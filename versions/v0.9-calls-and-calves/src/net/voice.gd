extends Node
## Voice - proximity voice chat (autoload "Voice").
##
## Capture : AudioStreamMicrophone -> muted bus "Mic" (AudioEffectCapture) -> mono -> 16 kHz
##           -> noise gate / VAD (hysteresis, 260 ms hangover, 80 ms pre-roll) -> mu-law 8 bit
##           -> 20 ms frames, 2 per packet -> unreliable_ordered RPC on channel 2 to everyone.
## Playback: per remote peer a jitter buffer feeds an AudioStreamGenerator (16 kHz) played by an
##           AudioStreamPlayer3D that Voice creates under the node passed to attach_speaker().
##
##   Voice.attach_speaker(peer_id, player_node3d)   # once per remote player node
##   Voice.level(peer_id)                           # 0..1 loudness for mouth animation
##   Voice.speaking_changed                          # (peer_id, speaking) for UI icons
##   Voice.set_test_source(true)                    # synthetic voice instead of the microphone
##
## Nothing happens in solo / offline sessions. Without a microphone (headless, no device,
## input disabled) the node stays quiet and `mic_status` says why.

signal speaking_changed(peer_id: int, speaking: bool)

## Master switch for sending (mute yourself with `false`).
var enabled := true
## If true, only transmit while the "talk" input action (default: T) is held.
var push_to_talk := false
## Linear gain applied to the microphone before the gate and encoder.
var input_gain := 1.0
## Volume trim for all remote voices (dB).
var output_volume_db := 0.0:
	set(value):
		output_volume_db = value
		for rx: Rx in _rx.values():
			if rx.player != null and is_instance_valid(rx.player):
				rx.player.volume_db = value

## "idle", "starting", "ok", "no_signal" (device opened but delivers nothing), "input_disabled"
## (audio/driver/enable_input is off). Informational only; Voice never prints about it.
var mic_status := "idle"
## Running counters (tx_packets, tx_bytes, rx_packets, rx_bytes, rx_rejected).
var stats := {"tx_packets": 0, "tx_bytes": 0, "rx_packets": 0, "rx_bytes": 0, "rx_rejected": 0}

# ------------------------------------------------------------------ constants
const RATE := 16000
const RATE_F := 16000.0
const FRAME := 320                    # 20 ms
const FRAMES_PER_PACKET := 2          # 40 ms per packet
const MAX_FRAMES_PER_PACKET := 8
const HEADER := 3                     # u16 first-frame sequence (LE) + u8 flags (bit0 = talkspurt start)
const CHANNEL := 2
const BUS_MIC := &"Mic"
const BUS_VOICE := &"Voice"
const ACTION_TALK := &"talk"

# Gate / VAD (levels are RMS of a 20 ms frame, full scale = 1.0)
const OPEN_MIN := 0.012
const CLOSE_MIN := 0.007
const HANG_FRAMES := 13               # 260 ms
const PTT_HANG_FRAMES := 4
const PREROLL_FRAMES := 4

# Playback (all in 16 kHz samples)
const PREBUFFER := 1280               # 80 ms before (re)starting playback
const ONSET_EXTRA := 640              # extra hold at the start of a talkspurt (pre-roll burst)
const LOOKAHEAD := 960                # keep ~60 ms in the generator (grows if the audio thread mixes in big blocks)
const MAX_LOOKAHEAD := 3840
const MAX_PRE_EXTRA := 2240           # adaptive extra prebuffer after underruns (jittery links)
const MAX_BUFFER := 4800              # 300 ms hard cap
const TRIM_TO := 2240                 # when over the cap, keep the newest 140 ms
const GEN_LENGTH := 0.5
const SPEAK_TIMEOUT_MS := 300
const MAX_CONCEAL_FRAMES := 5

# ------------------------------------------------------------------ state
class Rx extends RefCounted:
	var id := 0
	var node: Node3D
	var player: AudioStreamPlayer3D
	var pb: AudioStreamGeneratorPlayback
	var cap := 0
	var look := LOOKAHEAD
	var pre_extra := 0
	var adapt_ms := 0
	var prev_inflight := 0
	var q := PackedFloat32Array()
	var qh := 0
	var started := false
	var need := PREBUFFER
	var expect := -1
	var underrun_pending := false
	var last_pkt_ms := 0
	var speaking := false
	var lvl := 0.0
	var lvl_target := 0.0
	var lvl_until := 0.0
	var lvl_events: Array[Vector3] = []   # (due time s, rms, duration s)
	# stats
	var packets := 0
	var bytes := 0
	var underruns := 0
	var underrun_log: Array[float] = []   # seconds since the first packet, for diagnostics
	var first_pkt_ms := 0
	var dropped_old := 0
	var dropped_overflow := 0
	var concealed := 0
	var sumsq := 0.0
	var nsamp := 0
	var buffered := 0
	var dbg := PackedFloat32Array()

var _rx: Dictionary = {}              # peer id -> Rx
var _net_ok := false
var _gc_t := 0.0

# codec
var _enc_pos := PackedByteArray()
var _enc_neg := PackedByteArray()
var _dec := PackedFloat32Array()

# capture
var _cap: AudioEffectCapture
var _mic_player: AudioStreamPlayer
var _mic_running := false
var _mic_blocked := false
var _mic_off_t := 0.0
var _mic_age := 0.0
var _mic_got_frames := false
var _test_source := false
var _test_voice: TestVoice
var _test_acc := 0.0

# sender pipeline
var _in_buf := PackedFloat32Array()
var _rs_step := 0.0
var _rs_acc := 0.0
var _rs_need := 0.0
var _lp_b := Vector3.ZERO            # biquad low-pass (b0, b1, a1) ahead of the resampler; b2 = b0, a2 below
var _lp_a2 := 0.0
var _lp_x1 := 0.0
var _lp_x2 := 0.0
var _lp_y1 := 0.0
var _lp_y2 := 0.0
var _floor := 0.003
var _gate := false
var _hang := 0
var _open_run := 0
var _pre: Array[PackedFloat32Array] = []
var _pending: Array[PackedFloat32Array] = []
var _spurt_start := true
var _seq := 0
var _lvl_local := 0.0
var _speaking_local := false

# debugging (used by the test harness)
var _dbg_keep := false
var _dbg_sent := PackedFloat32Array()

# ------------------------------------------------------------------ lifecycle
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_codec_tables()
	_ensure_input_action()
	_ensure_buses()
	multiplayer.peer_disconnected.connect(_on_peer_gone)
	_test_voice = TestVoice.new()

func _exit_tree() -> void:
	_stop_mic()

func _ensure_input_action() -> void:
	if InputMap.has_action(ACTION_TALK):
		return
	InputMap.add_action(ACTION_TALK)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_T
	InputMap.action_add_event(ACTION_TALK, ev)

func _ensure_bus(bus_name: StringName) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, String(bus_name))
		AudioServer.set_bus_send(idx, &"Master")
	return idx

func _find_effect(idx: int, cls: String) -> AudioEffect:
	for e in AudioServer.get_bus_effect_count(idx):
		var fx := AudioServer.get_bus_effect(idx, e)
		if fx != null and fx.get_class() == cls:
			return fx
	return null

func _ensure_buses() -> void:
	# "Mic": capture only. Muted, so the microphone is never heard locally.
	var mic := _ensure_bus(BUS_MIC)
	AudioServer.set_bus_mute(mic, true)
	_cap = _find_effect(mic, "AudioEffectCapture") as AudioEffectCapture
	if _cap == null:
		_cap = AudioEffectCapture.new()
		_cap.buffer_length = 0.3
		AudioServer.add_bus_effect(mic, _cap, 0)
	# "Voice": remote players, warm and slightly leveled.
	var voice := _ensure_bus(BUS_VOICE)
	if _find_effect(voice, "AudioEffectLowPassFilter") == null:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 6000.0
		lp.db = AudioEffectFilter.FILTER_12DB
		AudioServer.add_bus_effect(voice, lp)
	if _find_effect(voice, "AudioEffectCompressor") == null:
		var comp := AudioEffectCompressor.new()
		comp.threshold = -16.0
		comp.ratio = 2.5
		comp.attack_us = 1500.0
		comp.release_ms = 200.0
		comp.gain = 2.0
		AudioServer.add_bus_effect(voice, comp)

# ------------------------------------------------------------------ public API
func attach_speaker(peer_id: int, node: Node3D) -> void:
	if peer_id == multiplayer.get_unique_id():
		return   # never play your own voice back
	var rx := _get_rx(peer_id)
	_clear_sink(rx)
	if node == null or not is_instance_valid(node):
		return
	var gen := AudioStreamGenerator.new()
	gen.mix_rate_mode = AudioStreamGenerator.MIX_RATE_CUSTOM
	gen.mix_rate = RATE_F
	gen.buffer_length = GEN_LENGTH
	var p := AudioStreamPlayer3D.new()
	p.stream = gen
	p.bus = BUS_VOICE
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.unit_size = 6.0
	p.max_distance = 45.0
	p.attenuation_filter_cutoff_hz = 4000.0
	p.attenuation_filter_db = -12.0
	p.volume_db = output_volume_db
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	node.add_child(p)
	rx.node = node
	rx.player = p

func detach_speaker(peer_id: int) -> void:
	var rx: Rx = _rx.get(peer_id)
	if rx != null:
		_clear_sink(rx)

## Smoothed 0..1 loudness (mouth animation). Local peer: gated microphone level.
func level(peer_id: int) -> float:
	if peer_id == multiplayer.get_unique_id():
		return _lvl_local
	var rx: Rx = _rx.get(peer_id)
	return rx.lvl if rx != null else 0.0

func is_speaking(peer_id: int) -> bool:
	if peer_id == multiplayer.get_unique_id():
		return _speaking_local
	var rx: Rx = _rx.get(peer_id)
	return rx.speaking if rx != null else false

## Replace the microphone with a synthetic voice (talks ~1.6 s, pauses ~1.4 s, repeating).
func set_test_source(on: bool) -> void:
	if on == _test_source:
		return
	_test_source = on
	_reset_sender()
	if on:
		_stop_mic()
		_test_voice = TestVoice.new()
		_test_acc = 0.0

## Snapshot of per-peer receive state and counters (for debugging / tests).
func debug_info() -> Dictionary:
	var peers := {}
	for id in _rx:
		var rx: Rx = _rx[id]
		peers[id] = {
			"packets": rx.packets, "bytes": rx.bytes, "underruns": rx.underruns,
			"dropped_old": rx.dropped_old, "dropped_overflow": rx.dropped_overflow,
			"concealed_frames": rx.concealed, "buffered_ms": rx.buffered * 1000.0 / RATE_F,
			"started": rx.started, "speaking": rx.speaking, "level": rx.lvl,
			"rms": sqrt(rx.sumsq / maxf(1.0, float(rx.nsamp))), "has_sink": rx.player != null,
			"samples": rx.nsamp, "lookahead_ms": rx.look * 1000.0 / RATE_F, "prebuffer_ms": (PREBUFFER + rx.pre_extra) * 1000.0 / RATE_F, "underrun_log": rx.underrun_log,
		}
	return {"stats": stats.duplicate(), "mic_status": mic_status, "net_ok": _net_ok,
		"local_level": _lvl_local, "floor": _floor, "peers": peers}

# ------------------------------------------------------------------ per-frame
func _process(delta: float) -> void:
	_net_ok = _net_active()
	_tick_mic(delta)
	_tick_capture(delta)
	var now_ms := Time.get_ticks_msec()
	var now_s := Time.get_ticks_usec() * 1e-6
	for id in _rx.keys():
		var rx: Rx = _rx.get(id)
		if rx != null:
			_tick_rx(rx, delta, now_ms, now_s)
	_gc_t += delta
	if _gc_t >= 0.5:
		_gc_t = 0.0
		_prune()

func _net_active() -> bool:
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return false
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	return Net.players.has(multiplayer.get_unique_id())

# ------------------------------------------------------------------ microphone
func _tick_mic(delta: float) -> void:
	var want := enabled and _net_ok and not _test_source
	if want:
		_mic_off_t = 0.0
		if _mic_player == null and not _mic_blocked:
			_start_mic()
		if _mic_player != null and mic_status == "starting":
			_mic_age += delta
			if _mic_got_frames:
				mic_status = "ok"
			elif _mic_age > 2.0:
				mic_status = "no_signal"
		elif _mic_player != null and mic_status == "no_signal" and _mic_got_frames:
			mic_status = "ok"
	else:
		if _mic_player != null:
			_mic_off_t += delta
			if _mic_off_t > 2.0:
				_stop_mic()
		if not _net_ok:
			_mic_blocked = false

func _start_mic() -> void:
	_mic_got_frames = false
	_mic_age = 0.0
	if not bool(ProjectSettings.get_setting("audio/driver/enable_input", false)):
		mic_status = "input_disabled"
		_mic_blocked = true
		return
	if OS.has_feature("android"):
		OS.request_permission("RECORD_AUDIO")
	_ensure_buses()
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = BUS_MIC
	add_child(_mic_player)
	_mic_player.play()
	if _cap != null:
		_cap.clear_buffer()
	_mic_running = true
	mic_status = "starting"

func _stop_mic() -> void:
	if _mic_player != null:
		if is_instance_valid(_mic_player):
			_mic_player.stop()
			_mic_player.queue_free()
		_mic_player = null
	if _mic_running:
		_mic_running = false
		if _cap != null:
			_cap.clear_buffer()
	if mic_status != "input_disabled":
		mic_status = "idle"

# ------------------------------------------------------------------ capture + encode
func _reset_sender() -> void:
	_in_buf.clear()
	_pre.clear()
	_pending.clear()
	_rs_step = 0.0
	_gate = false
	_hang = 0
	_open_run = 0
	_spurt_start = true
	if _speaking_local:
		_speaking_local = false
		speaking_changed.emit(multiplayer.get_unique_id(), false)

func _tick_capture(delta: float) -> void:
	var run := enabled and (_mic_running or _test_source)
	if not run:
		if _gate or _speaking_local or not _in_buf.is_empty():
			_reset_sender()
		_lvl_local = move_toward(_lvl_local, 0.0, delta * 4.0)
		return
	if _test_source:
		_test_acc = minf(_test_acc + delta * RATE_F, RATE_F * 0.25)
		var n := int(_test_acc)
		_test_acc -= float(n)
		if n > 0:
			_in_buf.append_array(_test_voice.gen(n))
	elif _cap != null:
		var avail := _cap.get_frames_available()
		if avail > 0:
			_mic_got_frames = true
			var frames := _cap.get_buffer(mini(avail, 48000))
			_ingest_stereo(frames, AudioServer.get_mix_rate())
	var h := 0
	var total := _in_buf.size()
	while total - h >= FRAME:
		_on_frame(_in_buf.slice(h, h + FRAME))
		h += FRAME
	if h > 0:
		_in_buf = _in_buf.slice(h)

## Downmix to mono, low-pass (7 kHz biquad), then resample in_rate -> 16 kHz by area averaging.
## The whole chain is stateful so it can be fed arbitrary chunk sizes.
func _ingest_stereo(frames: PackedVector2Array, in_rate: float) -> void:
	if in_rate < 4000.0:
		in_rate = 44100.0
	var step := in_rate / RATE_F
	if absf(step - _rs_step) > 0.0001:
		_rs_step = step
		_rs_need = step
		_rs_acc = 0.0
		var w0 := TAU * minf(7000.0, in_rate * 0.45) / in_rate
		var alpha := sin(w0) / (2.0 * 0.7071)
		var c := cos(w0)
		var a0 := 1.0 + alpha
		_lp_b = Vector3((1.0 - c) * 0.5 / a0, (1.0 - c) / a0, -2.0 * c / a0)
		_lp_a2 = (1.0 - alpha) / a0
		_lp_x1 = 0.0
		_lp_x2 = 0.0
		_lp_y1 = 0.0
		_lp_y2 = 0.0
	var inv := 1.0 / step
	var g := input_gain * 0.5
	var b0 := _lp_b.x
	var b1 := _lp_b.y
	var a1 := _lp_b.z
	var a2 := _lp_a2
	var x1 := _lp_x1
	var x2 := _lp_x2
	var y1 := _lp_y1
	var y2 := _lp_y2
	var acc := _rs_acc
	var need := _rs_need
	var out := PackedFloat32Array()
	for v: Vector2 in frames:
		var x := (v.x + v.y) * g
		var s := b0 * (x + x2) + b1 * x1 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = s
		var w := 1.0
		while w >= need:
			acc += s * need
			out.append(acc * inv)
			w -= need
			acc = 0.0
			need = step
		if w > 0.0:
			acc += s * w
			need -= w
	_lp_x1 = x1
	_lp_x2 = x2
	_lp_y1 = y1
	_lp_y2 = y2
	_rs_acc = acc
	_rs_need = need
	_in_buf.append_array(out)

func _on_frame(fr: PackedFloat32Array) -> void:
	var ss := 0.0
	for s: float in fr:
		ss += s * s
	var rms := sqrt(ss / float(FRAME))
	var ptt := push_to_talk
	var pressed := ptt and Input.is_action_pressed(ACTION_TALK)
	if not _gate:
		# Track the ambient noise floor only while the gate is closed.
		var open_thr := maxf(OPEN_MIN, _floor * 3.5)
		_floor = clampf(lerpf(_floor, rms, 0.3 if rms < _floor else 0.02), 0.0005, 0.03)
		var trigger := pressed if ptt else rms >= open_thr
		_open_run = _open_run + 1 if trigger else 0
		_pre.append(fr)
		var keep := 1 if ptt else PREROLL_FRAMES
		while _pre.size() > keep:
			_pre.pop_front()
		if _open_run >= (1 if ptt else 2):
			_open_gate(PTT_HANG_FRAMES if ptt else HANG_FRAMES)
	else:
		var close_thr := maxf(CLOSE_MIN, _floor * 2.0)
		var loud := pressed if ptt else rms >= close_thr
		if loud:
			_hang = PTT_HANG_FRAMES if ptt else HANG_FRAMES
		else:
			_hang -= 1
		if _hang < 0:
			_close_gate()
		else:
			_pending.append(fr)
			_flush(false)
	var target := clampf(rms * 5.0, 0.0, 1.0) if _gate else 0.0
	_lvl_local += (target - _lvl_local) * (0.6 if target > _lvl_local else 0.18)

func _open_gate(hang: int) -> void:
	_gate = true
	_hang = hang
	_open_run = 0
	_pending.append_array(_pre)
	_pre.clear()
	_spurt_start = true
	if not _speaking_local:
		_speaking_local = true
		speaking_changed.emit(multiplayer.get_unique_id(), true)
	_flush(false)

func _close_gate() -> void:
	_gate = false
	_hang = 0
	_open_run = 0
	_flush(true)
	if _speaking_local:
		_speaking_local = false
		speaking_changed.emit(multiplayer.get_unique_id(), false)

func _flush(force: bool) -> void:
	while _pending.size() >= FRAMES_PER_PACKET or (force and not _pending.is_empty()):
		var n := mini(FRAMES_PER_PACKET, _pending.size())
		var pkt := PackedByteArray()
		pkt.resize(HEADER + n * FRAME)
		pkt[0] = _seq & 0xFF
		pkt[1] = (_seq >> 8) & 0xFF
		pkt[2] = 1 if _spurt_start else 0
		_spurt_start = false
		var ofs := HEADER
		for i in n:
			var f: PackedFloat32Array = _pending[i]
			_encode_into(pkt, ofs, f)
			ofs += FRAME
			if _dbg_keep:
				_dbg_sent.append_array(f)
		for i in n:
			_pending.pop_front()
		_seq = (_seq + n) & 0xFFFF
		_send(pkt)

func _send(pkt: PackedByteArray) -> void:
	if not _net_ok or multiplayer.get_peers().is_empty():
		return
	_voice_rx.rpc(pkt)
	stats.tx_packets += 1
	stats.tx_bytes += pkt.size()

# ------------------------------------------------------------------ receive
@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _voice_rx(pkt: PackedByteArray) -> void:
	var from := multiplayer.get_remote_sender_id()
	var size := pkt.size() - HEADER
	if from <= 0 or from == multiplayer.get_unique_id() or not Net.players.has(from) \
			or size < FRAME or size > MAX_FRAMES_PER_PACKET * FRAME or size % FRAME != 0:
		stats.rx_rejected += 1
		return
	var rx := _get_rx(from)
	@warning_ignore("integer_division")
	var frames := size / FRAME
	var seq := pkt[0] | (pkt[1] << 8)
	var flags := pkt[2]
	var spurt_start := (flags & 1) != 0
	var gap := 0
	if spurt_start:
		rx.expect = -1
	elif rx.expect >= 0:
		var d := (seq - rx.expect) & 0xFFFF
		if d >= 0x8000:
			rx.dropped_old += 1       # stale or duplicate
			return
		if d > 0 and d <= MAX_CONCEAL_FRAMES:
			gap = d
	rx.expect = (seq + frames) & 0xFFFF
	if not rx.started:
		rx.need = PREBUFFER + rx.pre_extra + (ONSET_EXTRA if spurt_start else 0)
		if rx.underrun_pending and not spurt_start:
			rx.underruns += 1
			rx.pre_extra = mini(rx.pre_extra + 320, MAX_PRE_EXTRA)
			rx.adapt_ms = Time.get_ticks_msec()
			rx.need = PREBUFFER + rx.pre_extra
			if rx.underrun_log.size() < 16:
				rx.underrun_log.append((Time.get_ticks_msec() - rx.first_pkt_ms) / 1000.0)
	rx.underrun_pending = false
	if gap > 0:
		rx.concealed += gap
		rx.q.resize(rx.q.size() + gap * FRAME)   # zero-filled
		if _dbg_keep:
			rx.dbg.resize(rx.dbg.size() + gap * FRAME)
	var pcm := _decode(pkt, HEADER, size)
	rx.q.append_array(pcm)
	if _dbg_keep:
		rx.dbg.append_array(pcm)
	rx.packets += 1
	rx.bytes += pkt.size()
	stats.rx_packets += 1
	stats.rx_bytes += pkt.size()
	rx.last_pkt_ms = Time.get_ticks_msec()
	if rx.first_pkt_ms == 0:
		rx.first_pkt_ms = rx.last_pkt_ms
	if not rx.speaking:
		rx.speaking = true
		speaking_changed.emit(from, true)

func _tick_rx(rx: Rx, delta: float, now_ms: int, now_s: float) -> void:
	var sink := false
	if rx.player != null:
		if is_instance_valid(rx.player) and is_instance_valid(rx.node):
			sink = _ensure_playback(rx)
		else:
			_clear_sink(rx)
	var avail := rx.q.size() - rx.qh
	var inflight := 0
	if sink:
		inflight = maxi(0, rx.cap - rx.pb.get_frames_available())
		# The audio thread drained everything we gave it while we still had more: it mixes in
		# bigger blocks than our lookahead (or the game hitched). Hold more in the generator.
		if rx.started and rx.prev_inflight > 0 and inflight == 0 and avail > 0:
			rx.look = mini(rx.look + 480, MAX_LOOKAHEAD)
		var extra := rx.look - LOOKAHEAD
		var total := avail + inflight
		if total > MAX_BUFFER + extra:
			var drop := mini(total - (TRIM_TO + extra), avail)
			if drop > 0:
				rx.qh += drop
				avail -= drop
				rx.dropped_overflow += drop
		if not rx.started and avail >= rx.need:
			rx.started = true
		if rx.started:
			var want := rx.look - inflight
			if want > 0 and avail > 0:
				var n := mini(want, avail)
				_push_chunk(rx, n, now_s + float(inflight) / RATE_F)
				avail -= n
				inflight += n
			if avail == 0 and inflight == 0:
				rx.started = false
				rx.underrun_pending = true
		rx.prev_inflight = inflight
	else:
		# Nothing to play through: consume instantly so level() still works.
		rx.started = false
		if avail > 0:
			_note_level(rx, rx.qh, avail, now_s)
			rx.qh += avail
			avail = 0
	rx.buffered = avail + inflight
	if rx.pre_extra > 0 and now_ms - rx.adapt_ms > 4000:
		rx.pre_extra = maxi(0, rx.pre_extra - 160)   # slowly relax once the link behaves
		rx.adapt_ms = now_ms
	if rx.qh >= rx.q.size():
		rx.q.clear()
		rx.qh = 0
	elif rx.qh > 8192:
		rx.q = rx.q.slice(rx.qh)
		rx.qh = 0
	# mouth-sync loudness
	while not rx.lvl_events.is_empty() and rx.lvl_events[0].x <= now_s:
		var ev: Vector3 = rx.lvl_events.pop_front()
		rx.lvl_target = clampf(ev.y * 5.0, 0.0, 1.0)
		rx.lvl_until = ev.x + ev.z
	if now_s > rx.lvl_until + 0.02:
		rx.lvl_target = 0.0
	var rate := 30.0 if rx.lvl_target > rx.lvl else 9.0
	rx.lvl += (rx.lvl_target - rx.lvl) * (1.0 - exp(-rate * delta))
	if rx.speaking and (not _net_ok or now_ms - rx.last_pkt_ms > SPEAK_TIMEOUT_MS):
		rx.speaking = false
		speaking_changed.emit(rx.id, false)

func _push_chunk(rx: Rx, n: int, due_s: float) -> void:
	var chunk := PackedVector2Array()
	chunk.resize(n)
	var q := rx.q
	var h := rx.qh
	var ss := 0.0
	for i in n:
		var s := q[h + i]
		chunk[i] = Vector2(s, s)
		ss += s * s
	rx.qh = h + n
	rx.pb.push_buffer(chunk)
	rx.sumsq += ss
	rx.nsamp += n
	rx.lvl_events.append(Vector3(due_s, sqrt(ss / float(n)), float(n) / RATE_F))

## Level bookkeeping for audio that is consumed immediately (no speaker attached).
func _note_level(rx: Rx, from_idx: int, n: int, now_s: float) -> void:
	var ss := 0.0
	for i in n:
		var s := rx.q[from_idx + i]
		ss += s * s
	rx.sumsq += ss
	rx.nsamp += n
	rx.lvl_events.append(Vector3(now_s, sqrt(ss / float(n)), float(n) / RATE_F))

func _ensure_playback(rx: Rx) -> bool:
	var p := rx.player
	if not p.is_inside_tree():
		rx.pb = null
		return false
	if rx.pb != null and p.playing:
		return true
	if not p.playing:
		p.play()
	var pb := p.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		rx.pb = null
		return false
	rx.pb = pb
	rx.cap = pb.get_frames_available()
	rx.started = false
	return true

# ------------------------------------------------------------------ receivers
func _get_rx(peer_id: int) -> Rx:
	var rx: Rx = _rx.get(peer_id)
	if rx == null:
		rx = Rx.new()
		rx.id = peer_id
		_rx[peer_id] = rx
	return rx

func _clear_sink(rx: Rx) -> void:
	if rx.player != null and is_instance_valid(rx.player):
		rx.player.stop()
		rx.player.queue_free()
	rx.player = null
	rx.node = null
	rx.pb = null
	rx.started = false
	rx.q.clear()
	rx.qh = 0

func _drop_rx(peer_id: int) -> void:
	var rx: Rx = _rx.get(peer_id)
	if rx == null:
		return
	_clear_sink(rx)
	_rx.erase(peer_id)
	if rx.speaking:
		rx.speaking = false
		speaking_changed.emit(peer_id, false)

func _on_peer_gone(peer_id: int) -> void:
	_drop_rx(peer_id)

func _prune() -> void:
	for id in _rx.keys():
		var rx: Rx = _rx[id]
		if rx.player != null and not (is_instance_valid(rx.player) and is_instance_valid(rx.node)):
			_clear_sink(rx)
		if rx.player == null and not Net.players.has(id):
			_drop_rx(id)

# ------------------------------------------------------------------ mu-law (G.711)
func _build_codec_tables() -> void:
	var mags := PackedInt32Array()
	mags.resize(128)
	for k in 128:
		mags[k] = ((((k & 15) << 3) + 0x84) << (k >> 4)) - 0x84
	_dec.resize(256)
	for b in 256:
		var positive := b >= 128
		var k := (255 - b) if positive else (127 - b)
		var v := float(mags[k]) / 32768.0
		_dec[b] = v if positive else -v
	_enc_pos.resize(32768)
	_enc_neg.resize(32768)
	var lo := 0
	for k in 128:
		var hi := 32768 if k == 127 else (mags[k] + mags[k + 1] + 1) >> 1
		var cp := 255 - k
		var cn := 127 - k
		for m in range(lo, hi):
			_enc_pos[m] = cp
			_enc_neg[m] = cn
		lo = hi

func _encode_into(out: PackedByteArray, ofs: int, f: PackedFloat32Array) -> void:
	var pos := _enc_pos
	var neg := _enc_neg
	for i in f.size():
		var v := int(clampf(f[i], -1.0, 1.0) * 32767.0)
		out[ofs + i] = pos[v] if v >= 0 else neg[-v]

func _decode(pkt: PackedByteArray, ofs: int, count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(count)
	var d := _dec
	for i in count:
		out[i] = d[pkt[ofs + i]]
	return out

## Encode mono 16 kHz floats into mu-law bytes (public for tests / tools).
func encode_pcm(pcm: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(pcm.size())
	_encode_into(out, 0, pcm)
	return out

## Decode mu-law bytes back to floats (public for tests / tools).
func decode_pcm(data: PackedByteArray) -> PackedFloat32Array:
	return _decode(data, 0, data.size())

# ------------------------------------------------------------------ synthetic test voice
## Formant-ish buzz: sawtooth glottal source through three resonators, shaped into syllables.
class TestVoice extends RefCounted:
	const CYCLE := 3.0
	const GAIN := 0.22
	# [start s, duration s, vowel index]
	const SYLLABLES := [[0.00, 0.22, 0], [0.28, 0.20, 1], [0.55, 0.30, 2], [0.97, 0.22, 3], [1.24, 0.36, 4]]
	const VOWELS := [Vector3(730.0, 1090.0, 2440.0), Vector3(530.0, 1840.0, 2480.0),
		Vector3(270.0, 2290.0, 3010.0), Vector3(570.0, 840.0, 2410.0), Vector3(300.0, 870.0, 2240.0)]
	const BW := Vector3(90.0, 110.0, 160.0)

	var _n := 0
	var _phase := 0.0
	var _f := Vector3(730.0, 1090.0, 2440.0)
	var _b1 := Vector3.ZERO
	var _b2 := Vector3.ZERO
	var _a0 := Vector3.ZERO
	var _y1 := Vector3.ZERO
	var _y2 := Vector3.ZERO
	var _rng := RandomNumberGenerator.new()

	func _init() -> void:
		_rng.seed = 1234
		_coefs()

	func _coefs() -> void:
		var fs := 16000.0
		var r := Vector3(exp(-PI * BW.x / fs), exp(-PI * BW.y / fs), exp(-PI * BW.z / fs))
		_b1 = Vector3(2.0 * r.x * cos(TAU * _f.x / fs), 2.0 * r.y * cos(TAU * _f.y / fs), 2.0 * r.z * cos(TAU * _f.z / fs))
		_b2 = Vector3(-r.x * r.x, -r.y * r.y, -r.z * r.z)
		_a0 = Vector3(1.0 - r.x, 1.0 - r.y, 1.0 - r.z)

	func gen(count: int) -> PackedFloat32Array:
		var out := PackedFloat32Array()
		out.resize(count)
		for i in count:
			var t := float(_n) / 16000.0
			_n += 1
			var ct := fposmod(t, CYCLE)
			var env := 0.0
			for syl: Array in SYLLABLES:
				var u: float = (ct - float(syl[0])) / float(syl[1])
				if u >= 0.0 and u < 1.0:
					env = pow(sin(PI * u), 0.6)
					_f = _f.lerp(VOWELS[int(syl[2])], 0.002)
					break
			if (_n & 31) == 0:
				_coefs()
			var f0 := 118.0 + 18.0 * sin(TAU * 0.8 * t)
			_phase += f0 / 16000.0
			if _phase >= 1.0:
				_phase -= 1.0
			var x := (2.0 * _phase - 1.0) + (_rng.randf() - 0.5) * 0.06
			var y := Vector3(
				_a0.x * x + _b1.x * _y1.x + _b2.x * _y2.x,
				_a0.y * x + _b1.y * _y1.y + _b2.y * _y2.y,
				_a0.z * x + _b1.z * _y1.z + _b2.z * _y2.z)
			_y2 = _y1
			_y1 = y
			out[i] = clampf((y.x + 0.55 * y.y + 0.3 * y.z) * env * GAIN, -1.0, 1.0)
		return out
