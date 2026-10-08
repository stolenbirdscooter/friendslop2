extends Node
## Music - Mossback's generative, adaptive folk-ensemble score (autoload "Music").
##
## No audio files: a small travelling band (kalimba, nylon-ish pluck, breathy
## wooden flute, bowed drone, frame drum, wood block) is synthesized once at
## startup into 16-bit mono AudioStreamWAVs, and a seeded composer sequences it
## at runtime so the music comes and goes - phrases of 40-90 s, then 20-60 s of
## near silence - rather than looping as wallpaper.
##
##   Music.set_mood("travel")     "dawn" | "travel" | "tense" | "night" | "arrived" | "silent"
##   Music.stinger("waystone")    "waystone" | "day_lost" | "sneeze" | "won" | "fed"
##   Music.set_volume_db(-3.0)    Music bus volume
##   Music.enabled = false        hard mute (stops everything)
##
## Mood changes take effect on the next bar line (old notes ring out, the drone
## crossfades). Stingers play immediately, in the current key, over a short duck.
##
## Design notes
##  * Composer (inner class) is pure data: it turns a mood + seed into Ev events
##    one bar at a time and never touches audio, so it can be tested offline.
##  * AudioStreamPolyphonic has no scheduled start, so the sequencer keeps a
##    lookahead queue on an accumulated clock and fires events from _process;
##    jitter is at most one frame (plus a few ms of seeded humanization).
##  * Everything is deterministic: same seed + same mood sequence = same music.

signal event_fired(ev: Ev)

const SR: int = 22050
const SRF: float = 22050.0
const SR_LO: int = 11025
const SRL: float = 11025.0

const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"

const SEED_BASE: int = 0x4D555349 # "MUSI"
const LOOKAHEAD: float = 0.45 # seconds of composed-but-unplayed music
const MAX_STEP: float = 0.1 # clock never advances more than this per frame (hitch guard)
const POLY_MAIN: int = 40
const POLY_STING: int = 16

const MOODS: PackedStringArray = ["dawn", "travel", "tense", "night", "arrived", "silent"]
const STINGERS: PackedStringArray = ["waystone", "day_lost", "sneeze", "won", "fed"]

enum Inst { KALIMBA, PLUCK, FLUTE, DRONE, DRUM, BLOCK, PLUCK_MUTE }
enum Kind { NOTE, DRONE_SET, DRONE_STOP }

const INST_NAMES: PackedStringArray = ["kalimba", "pluck", "flute", "drone", "drum", "block", "pluck_mute"]
## Per-instrument trim (dB) on top of RMS-normalized samples and per-event levels.
const INST_DB: PackedFloat32Array = [-3.5, -5.0, -4.5, -9.0, -5.5, -9.5, -6.0]
const STING_DB: float = 2.0
## Extra level per stinger (dB) so each reads clearly over the music.
const STING_TRIM: Dictionary = {"waystone": 1.0, "day_lost": 4.0, "sneeze": 3.5, "won": 1.0, "fed": 5.0}
const DUCK_DB: float = -4.5

## Rendered sample roots (MIDI). Playback pitch-shifts at most ~6 semitones.
const KAL_ROOTS: PackedInt32Array = [62, 74, 86]
const PLK_ROOTS: PackedInt32Array = [50, 60, 70]
const PLM_ROOTS: PackedInt32Array = [50, 60]
const FLT_ROOTS: PackedInt32Array = [57, 69, 79]
const DRN_ROOTS: PackedInt32Array = [39, 46]
const DRN_CYCLES: PackedInt32Array = [156, 232] # integer cycles per 2 s loop cell (even)
const DRN_LEN: int = 22050 # samples at SR_LO = 2.0 s
const FLT_LEN_S: float = 0.7
const FLT_LEN_M: float = 1.9
const FLT_LEN_L: float = 3.4

## Milliseconds spent synthesizing the sample bank in _ready.
var generation_ms: float = 0.0
## True while stepping offline / headless tests: events are emitted but no audio is played.
var debug_dry: bool = false

var enabled: bool = true:
	set(value):
		if value == enabled:
			return
		enabled = value
		if not enabled:
			_silence_now()
		else:
			_clock_reset()

var _vol_db: float = 0.0
var _mood: String = "silent"
var _warned: Dictionary = {}
var _ready_ok: bool = false
var _clock: float = 0.0
var _queue: Array[Ev] = []
var _composer: Composer = Composer.new(SEED_BASE)
var _bank: Dictionary = {}
var _noise: PackedFloat32Array = PackedFloat32Array()
var _sting_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _last_sting: Dictionary = {}

var _main_player: AudioStreamPlayer
var _sting_player: AudioStreamPlayer
var _main_pb: AudioStreamPlaybackPolyphonic
var _sting_pb: AudioStreamPlaybackPolyphonic
var _drones: Array[DroneV] = []
var _glides: Array[Glide] = []
var _duck_cur: float = 0.0
var _duck_hold_until: float = -1.0


# ---------------------------------------------------------------------------
# Small data classes
# ---------------------------------------------------------------------------

## One scheduled musical event on the music clock (seconds).
class Ev extends RefCounted:
	var t: float = 0.0
	var kind: int = 0 # Kind
	var inst: int = 0 # Inst
	var midi: float = 60.0 # drum / block: semitone offset instead
	var db: float = 0.0
	var dur: float = 1.0 # flute length class; drone fade seconds
	var bend: float = 0.0 # semitones glided over bend_t after the onset
	var bend_t: float = 0.0
	var voice: int = 0 # drum: 0 thump, 1 tap
	var sting: bool = false

	static func note(t_: float, inst_: int, midi_: float, db_: float, dur_: float) -> Ev:
		var e: Ev = Ev.new()
		e.t = t_
		e.inst = inst_
		e.midi = midi_
		e.db = db_
		e.dur = dur_
		return e

	static func drone_set(t_: float, midi_: float, db_: float, fade: float) -> Ev:
		var e: Ev = Ev.new()
		e.t = t_
		e.kind = Kind.DRONE_SET
		e.inst = Inst.DRONE
		e.midi = midi_
		e.db = db_
		e.dur = fade
		return e

	static func drone_stop(t_: float, fade: float) -> Ev:
		var e: Ev = Ev.new()
		e.t = t_
		e.kind = Kind.DRONE_STOP
		e.inst = Inst.DRONE
		e.dur = fade
		return e


class Sample extends RefCounted:
	var stream: AudioStreamWAV
	var base_hz: float = 1.0
	var rate: int = 22050
	var looped: bool = false
	var frames: int = 0


class DroneV extends RefCounted:
	var id: int = -1
	var gain: float = 0.0
	var target: float = 1.0
	var rate: float = 0.5
	var db: float = 0.0


class Glide extends RefCounted:
	var pb: AudioStreamPlaybackPolyphonic
	var id: int = -1
	var t0: float = 0.0
	var dur: float = 0.3
	var p0: float = 1.0
	var p1: float = 1.0


class Theory extends RefCounted:
	static func hz(m: float) -> float:
		return 440.0 * pow(2.0, (m - 69.0) / 12.0)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func set_mood(mood: String) -> void:
	if not MOODS.has(mood):
		_warn_once("mood:" + mood, "Music.set_mood: unknown mood '%s' (expected one of %s)" % [mood, ", ".join(MOODS)])
		return
	_mood = mood
	_composer.request(mood)


func get_mood() -> String:
	return _mood


func stinger(sting_name: String) -> void:
	if not STINGERS.has(sting_name):
		_warn_once("sting:" + sting_name, "Music.stinger: unknown stinger '%s' (expected one of %s)" % [sting_name, ", ".join(STINGERS)])
		return
	if not enabled or not _ready_ok:
		return
	var min_gap: float = 0.12 if sting_name == "fed" else 0.3
	var last: float = _last_sting.get(sting_name, -100.0)
	if _clock - last < min_gap:
		return
	_last_sting[sting_name] = _clock
	var evs: Array[Ev] = _build_stinger(sting_name)
	var span: float = 0.0
	for e: Ev in evs:
		span = maxf(span, e.t)
		e.t += _clock
		e.sting = true
		_queue.append(e)
	_queue.sort_custom(_ev_before)
	_duck_hold_until = maxf(_duck_hold_until, _clock + span + 0.7)


func set_volume_db(db: float) -> void:
	_vol_db = clampf(db, -80.0, 6.0)
	var idx: int = AudioServer.get_bus_index(BUS_MUSIC)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, _vol_db)


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sting_rng.seed = SEED_BASE ^ 0x57
	_setup_bus()
	var t0: int = Time.get_ticks_usec()
	_build_bank()
	generation_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	_build_players()
	_ready_ok = true
	_composer.request(_mood)


func _process(delta: float) -> void:
	_step(delta)


func _exit_tree() -> void:
	# Drop playback references so the engine can free them cleanly at shutdown.
	_drones.clear()
	_glides.clear()
	_main_pb = null
	_sting_pb = null


## One tick of the sequencer. _process calls this; tests may call it directly
## (with set_process(false)) to simulate time faster than real time.
func _step(delta: float) -> void:
	if not _ready_ok or not enabled:
		return
	_clock += minf(delta, MAX_STEP)
	var horizon: float = _clock + LOOKAHEAD
	var guard: int = 0
	var added: bool = false
	while _composer.wants_bar(horizon) and guard < 6:
		var evs: Array[Ev] = _composer.gen_bar(_clock)
		for e: Ev in evs:
			_queue.append(e)
			added = true
		guard += 1
	if added:
		_queue.sort_custom(_ev_before)
	while not _queue.is_empty() and _queue[0].t <= _clock:
		_fire(_queue.pop_front())
	if not debug_dry:
		_keep_players_alive()
		_update_drones(delta)
		_update_glides()
		_update_duck(delta)


static func _ev_before(a: Ev, b: Ev) -> bool:
	return a.t < b.t


func _clock_reset() -> void:
	_queue.clear()
	_composer.request(_mood)


func _silence_now() -> void:
	_queue.clear()
	_glides.clear()
	for v: DroneV in _drones:
		v.target = 0.0
		v.rate = 8.0
	if _main_player != null:
		_main_player.stop()
		_main_player.play()
		_main_pb = _main_player.get_stream_playback() as AudioStreamPlaybackPolyphonic
	if _sting_player != null:
		_sting_player.stop()
		_sting_player.play()
		_sting_pb = _sting_player.get_stream_playback() as AudioStreamPlaybackPolyphonic
	_drones.clear()
	_composer.silence()


func _warn_once(key: String, msg: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(msg)


# ---------------------------------------------------------------------------
# Bus and players
# ---------------------------------------------------------------------------

func _setup_bus() -> void:
	var idx: int = AudioServer.get_bus_index(BUS_MUSIC)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, String(BUS_MUSIC))
		AudioServer.set_bus_send(idx, BUS_MASTER)
		var rev: AudioEffectReverb = AudioEffectReverb.new()
		rev.room_size = 0.6
		rev.damping = 0.6
		rev.spread = 1.0
		rev.predelay_msec = 32.0
		rev.predelay_feedback = 0.25
		rev.hipass = 0.1
		rev.dry = 1.0
		rev.wet = 0.25
		AudioServer.add_bus_effect(idx, rev)
		var comp: AudioEffectCompressor = AudioEffectCompressor.new()
		comp.threshold = -16.0
		comp.ratio = 2.2
		comp.attack_us = 30000.0
		comp.release_ms = 400.0
		comp.gain = 1.0
		comp.mix = 1.0
		AudioServer.add_bus_effect(idx, comp)
		var lim: AudioEffectLimiter = AudioEffectLimiter.new()
		lim.threshold_db = -3.0
		lim.ceiling_db = -1.0
		AudioServer.add_bus_effect(idx, lim)
	AudioServer.set_bus_volume_db(idx, _vol_db)


func _build_players() -> void:
	_main_player = _make_player(POLY_MAIN)
	_sting_player = _make_player(POLY_STING)
	_main_pb = _main_player.get_stream_playback() as AudioStreamPlaybackPolyphonic
	_sting_pb = _sting_player.get_stream_playback() as AudioStreamPlaybackPolyphonic


func _make_player(poly: int) -> AudioStreamPlayer:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	var s: AudioStreamPolyphonic = AudioStreamPolyphonic.new()
	s.polyphony = poly
	p.stream = s
	p.bus = BUS_MUSIC
	add_child(p)
	p.play()
	return p


func _keep_players_alive() -> void:
	# If the engine ever stops a player (device change), restart it.
	if _main_player != null and not _main_player.playing:
		_main_player.play()
		_main_pb = _main_player.get_stream_playback() as AudioStreamPlaybackPolyphonic
		_drones.clear()
	if _sting_player != null and not _sting_player.playing:
		_sting_player.play()
		_sting_pb = _sting_player.get_stream_playback() as AudioStreamPlaybackPolyphonic


# ---------------------------------------------------------------------------
# Event playback
# ---------------------------------------------------------------------------

func _fire(e: Ev) -> void:
	event_fired.emit(e)
	if debug_dry or _main_pb == null:
		return
	match e.kind:
		Kind.NOTE:
			_play_note(e)
		Kind.DRONE_SET:
			_drone_set(e)
		Kind.DRONE_STOP:
			_drone_stop(e.dur)


## How an event is voiced: {sample: Sample, pitch: float, db: float}.
## Shared by live playback and the offline test renderer.
func voice_for(e: Ev) -> Dictionary:
	var key: String = ""
	match e.inst:
		Inst.KALIMBA:
			key = "kal_%d" % _nearest_root(KAL_ROOTS, e.midi)
		Inst.PLUCK:
			key = "plk_%d" % _nearest_root(PLK_ROOTS, e.midi)
		Inst.PLUCK_MUTE:
			key = "plm_%d" % _nearest_root(PLM_ROOTS, e.midi)
		Inst.FLUTE:
			var cls: String = "S"
			if e.dur > FLT_LEN_M - 0.05:
				cls = "L"
			elif e.dur > FLT_LEN_S + 0.2:
				cls = "M"
			key = "flt_%d_%s" % [_nearest_root(FLT_ROOTS, e.midi), cls]
		Inst.DRONE:
			key = "drn_%d" % _nearest_root(DRN_ROOTS, e.midi)
		Inst.DRUM:
			key = "drm_thump" if e.voice == 0 else "drm_tap"
		_:
			key = "blk"
	var s: Sample = _bank.get(key) as Sample
	var pitch: float = 1.0
	if s != null:
		if e.inst == Inst.DRUM or e.inst == Inst.BLOCK:
			pitch = pow(2.0, e.midi / 12.0)
		else:
			pitch = Theory.hz(e.midi) / s.base_hz
	return {
		"sample": s,
		"pitch": clampf(pitch, 0.25, 4.0),
		"db": INST_DB[e.inst] + e.db + (STING_DB if e.sting else 0.0),
	}


static func _nearest_root(roots: PackedInt32Array, midi: float) -> int:
	var best: int = roots[0]
	var bd: float = 1.0e9
	for r in roots:
		var d: float = absf(midi - float(r))
		if d < bd:
			bd = d
			best = r
	return best


func _play_note(e: Ev) -> void:
	var vp: Dictionary = voice_for(e)
	var s: Sample = vp["sample"] as Sample
	if s == null:
		return
	var pb: AudioStreamPlaybackPolyphonic = _sting_pb if e.sting else _main_pb
	var pitch: float = vp["pitch"]
	var db: float = vp["db"]
	var id: int = pb.play_stream(s.stream, 0.0, db, pitch, AudioServer.PLAYBACK_TYPE_DEFAULT, BUS_MUSIC)
	if id < 0 or absf(e.bend) < 0.001:
		return
	var g: Glide = Glide.new()
	g.pb = pb
	g.id = id
	g.t0 = _clock
	g.dur = maxf(e.bend_t, 0.05)
	g.p0 = pitch
	g.p1 = clampf(pitch * pow(2.0, e.bend / 12.0), 0.25, 4.0)
	_glides.append(g)


func _drone_set(e: Ev) -> void:
	var fade: float = maxf(e.dur, 0.2)
	for v: DroneV in _drones:
		v.target = 0.0
		v.rate = 1.0 / fade
	var vp: Dictionary = voice_for(e)
	var s: Sample = vp["sample"] as Sample
	if s == null:
		return
	var nv: DroneV = DroneV.new()
	nv.id = _main_pb.play_stream(s.stream, 0.0, -80.0, vp["pitch"], AudioServer.PLAYBACK_TYPE_DEFAULT, BUS_MUSIC)
	if nv.id < 0:
		return
	nv.db = vp["db"]
	nv.rate = 1.0 / fade
	_drones.append(nv)


func _drone_stop(fade: float) -> void:
	for v: DroneV in _drones:
		v.target = 0.0
		v.rate = 1.0 / maxf(fade, 0.2)


func _update_drones(delta: float) -> void:
	var i: int = _drones.size() - 1
	while i >= 0:
		var v: DroneV = _drones[i]
		var d: float = clampf(v.target - v.gain, -v.rate * delta, v.rate * delta)
		v.gain += d
		if v.gain <= 0.0001 and v.target <= 0.0:
			_main_pb.stop_stream(v.id)
			_drones.remove_at(i)
		else:
			var amp: float = sin(clampf(v.gain, 0.0, 1.0) * PI * 0.5)
			_main_pb.set_stream_volume(v.id, v.db + linear_to_db(maxf(amp, 0.0001)))
		i -= 1


func _update_glides() -> void:
	var i: int = _glides.size() - 1
	while i >= 0:
		var g: Glide = _glides[i]
		var k: float = clampf((_clock - g.t0) / g.dur, 0.0, 1.0)
		g.pb.set_stream_pitch_scale(g.id, lerpf(g.p0, g.p1, k * k * (3.0 - 2.0 * k)))
		if k >= 1.0:
			_glides.remove_at(i)
		i -= 1


func _update_duck(delta: float) -> void:
	var holding: bool = _clock < _duck_hold_until
	var target: float = DUCK_DB if holding else 0.0
	var tau: float = 0.08 if holding else 0.9
	_duck_cur += (target - _duck_cur) * (1.0 - exp(-delta / tau))
	if _main_player != null:
		_main_player.volume_db = _duck_cur


# ---------------------------------------------------------------------------
# Stingers (short phrases in the current key)
# ---------------------------------------------------------------------------

func _build_stinger(sting_name: String) -> Array[Ev]:
	var tk: float = float(57 + posmod(_composer.tonic - 57, 12)) # tonic in 57..68
	var out: Array[Ev] = []
	match sting_name:
		"waystone":
			var arp: PackedInt32Array = [0, 4, 7, 12, 16]
			for i in arp.size():
				out.append(Ev.note(0.12 * float(i), Inst.KALIMBA, tk + float(arp[i]), -5.0 + 1.0 * float(i), 1.0))
			out.append(Ev.note(0.68, Inst.PLUCK, tk - 12.0, -4.0, 1.0))
			out.append(Ev.note(0.72, Inst.PLUCK, tk - 5.0, -5.0, 1.0))
			out.append(Ev.note(0.76, Inst.PLUCK, tk + 4.0, -6.0, 1.0))
			out.append(Ev.note(0.70, Inst.KALIMBA, tk + 19.0, -4.0, 1.0))
			out.append(Ev.note(0.74, Inst.KALIMBA, tk + 12.0, -4.5, 1.0))
			out.append(Ev.note(0.55, Inst.FLUTE, tk + 4.0, -4.0, 3.3))
			out.append(Ev.note(0.62, Inst.FLUTE, tk + 12.0, -5.0, 3.3))
		"day_lost":
			var steps: PackedFloat32Array = [12.0, 10.0, 7.0, 3.0, 0.0]
			var times: PackedFloat32Array = [0.0, 0.42, 0.84, 1.3, 1.8]
			for i in steps.size():
				out.append(Ev.note(times[i], Inst.KALIMBA, tk + steps[i], -4.5 - 0.5 * float(i), 1.0))
			out.append(Ev.note(1.75, Inst.FLUTE, tk, -4.0, 1.8))
			out.append(Ev.note(1.8, Inst.PLUCK, tk - 12.0, -6.0, 1.0))
		"sneeze":
			out.append(Ev.note(0.0, Inst.BLOCK, 4.0, -5.0, 0.2))
			var bloop: PackedFloat32Array = [19.0, 14.0, 9.0]
			for i in bloop.size():
				var e: Ev = Ev.note(0.05 + 0.11 * float(i), Inst.KALIMBA, tk + bloop[i], -4.0 - float(i), 1.0)
				if i == 2:
					e.bend = -2.5
					e.bend_t = 0.28
				out.append(e)
		"won":
			# I - IV - V - I with a rising kalimba line, held chord of flutes at the end.
			var mel: PackedFloat32Array = [12.0, 16.0, 17.0, 21.0, 19.0, 23.0]
			var mt: PackedFloat32Array = [0.0, 0.45, 0.9, 1.35, 1.8, 2.25]
			for i in mel.size():
				out.append(Ev.note(mt[i], Inst.KALIMBA, tk + mel[i], -5.0 + 0.4 * float(i), 1.0))
			var chords: Array = [[0.0, -12.0, -5.0, 4.0], [0.9, -7.0, 0.0, 9.0], [1.8, -5.0, 2.0, 7.0]]
			for c: Array in chords:
				var ct: float = float(c[0]) * 1.0
				for j in range(1, 4):
					out.append(Ev.note(ct + 0.03 * float(j), Inst.PLUCK, tk + float(c[j]), -5.5, 1.0))
			out.append(Ev.note(2.9, Inst.PLUCK, tk - 12.0, -3.5, 1.0))
			out.append(Ev.note(2.93, Inst.PLUCK, tk - 5.0, -4.5, 1.0))
			out.append(Ev.note(2.96, Inst.PLUCK, tk + 4.0, -5.0, 1.0))
			out.append(Ev.note(2.99, Inst.PLUCK, tk + 12.0, -5.5, 1.0))
			out.append(Ev.note(2.9, Inst.KALIMBA, tk + 24.0, -4.5, 1.0))
			out.append(Ev.note(3.0, Inst.KALIMBA, tk + 16.0, -5.5, 1.0))
			out.append(Ev.note(2.85, Inst.FLUTE, tk + 4.0, -4.0, 3.3))
			out.append(Ev.note(2.9, Inst.FLUTE, tk + 12.0, -4.0, 3.3))
			out.append(Ev.note(2.95, Inst.FLUTE, tk + 7.0, -5.0, 3.3))
			out.append(Ev.note(2.9, Inst.DRUM, 0.0, -4.0, 0.3))
			out.append(Ev.note(0.0, Inst.DRUM, 0.0, -7.0, 0.3))
			out.append(Ev.note(0.9, Inst.DRUM, 0.0, -8.0, 0.3))
			out.append(Ev.note(1.8, Inst.DRUM, 0.0, -8.0, 0.3))
		"fed":
			var pairs: Array = [[12.0, 19.0], [16.0, 21.0], [14.0, 19.0], [12.0, 16.0]]
			var pr: Array = pairs[_sting_rng.randi() % pairs.size()]
			out.append(Ev.note(0.0, Inst.KALIMBA, tk + float(pr[0]), -7.0, 1.0))
			out.append(Ev.note(0.09, Inst.KALIMBA, tk + float(pr[1]), -6.0, 1.0))
	var trim: float = STING_TRIM.get(sting_name, 0.0)
	for e: Ev in out:
		e.db += trim
	return out


# ---------------------------------------------------------------------------
# Sample bank (offline synthesis at startup)
# ---------------------------------------------------------------------------

func _build_bank() -> void:
	_bank.clear()
	_noise = _make_noise(65536)
	for r in KAL_ROOTS:
		var dur: float = 2.35 - 0.028 * float(r - 62)
		var buf: PackedFloat32Array = _synth_kalimba(r, dur, _noise)
		_normalize(buf, SRF, 0.0, 0.4, 0.10, 0.9)
		_add_sample("kal_%d" % r, buf, SR, false, Theory.hz(float(r)))
	for r in PLK_ROOTS:
		var pk: Dictionary = _synth_pluck(r, 1.9 - 0.012 * float(r - 50), 1.5, 0.55, _noise)
		var pbuf: PackedFloat32Array = pk["buf"]
		_normalize(pbuf, SRF, 0.0, 0.4, 0.10, 0.9)
		_add_sample("plk_%d" % r, pbuf, SR, false, pk["hz"])
	for r in PLM_ROOTS:
		var pm: Dictionary = _synth_pluck(r, 0.75, 0.33, 0.3, _noise)
		var mbuf: PackedFloat32Array = pm["buf"]
		_normalize(mbuf, SRF, 0.0, 0.2, 0.10, 0.9)
		_add_sample("plm_%d" % r, mbuf, SR, false, pm["hz"])
	for r in FLT_ROOTS:
		var lens: PackedFloat32Array = [FLT_LEN_S, FLT_LEN_M, FLT_LEN_L]
		var tags: PackedStringArray = ["S", "M", "L"]
		for li in lens.size():
			var fb: PackedFloat32Array = _synth_flute(r, lens[li], _noise)
			_normalize(fb, SRL, 0.14, minf(0.45, lens[li] * 0.6), 0.10, 0.9)
			_add_sample("flt_%d_%s" % [r, tags[li]], fb, SR_LO, false, Theory.hz(float(r)))
	for di in DRN_ROOTS.size():
		var dbuf: PackedFloat32Array = _synth_drone(DRN_CYCLES[di], _noise)
		_normalize(dbuf, SRL, 0.0, 2.0, 0.10, 0.9)
		_add_sample("drn_%d" % DRN_ROOTS[di], dbuf, SR_LO, true, float(DRN_CYCLES[di]) * 0.5)
	var th: PackedFloat32Array = _synth_thump(_noise)
	_normalize(th, SRF, 0.0, 0.25, 0.10, 0.9)
	_add_sample("drm_thump", th, SR, false, 1.0)
	var tp: PackedFloat32Array = _synth_tap(_noise)
	_normalize(tp, SRF, 0.0, 0.12, 0.10, 0.9)
	_add_sample("drm_tap", tp, SR, false, 1.0)
	var bl: PackedFloat32Array = _synth_block(_noise)
	_normalize(bl, SRF, 0.0, 0.12, 0.10, 0.9)
	_add_sample("blk", bl, SR, false, 1.0)


func _add_sample(key: String, buf: PackedFloat32Array, rate: int, looped: bool, base_hz: float) -> void:
	var s: Sample = Sample.new()
	s.stream = _to_wav(buf, rate, looped)
	s.base_hz = base_hz
	s.rate = rate
	s.looped = looped
	s.frames = buf.size()
	_bank[key] = s


static func _make_noise(n: int) -> PackedFloat32Array:
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = SEED_BASE
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = r.randf() * 2.0 - 1.0
	return out


## Damped sinusoid added into out (two-pole resonator: one multiply-add per partial).
static func _resonate(out: PackedFloat32Array, f: float, amp: float, tau: float, sr: float) -> void:
	if f >= sr * 0.45:
		return
	var w: float = TAU * f / sr
	var r: float = exp(-1.0 / (tau * sr))
	var c1: float = 2.0 * r * cos(w)
	var c2: float = -r * r
	var ya: float = 0.0
	var yb: float = amp * r * sin(w)
	for i in out.size():
		out[i] += ya
		var yc: float = c1 * yb + c2 * ya
		ya = yb
		yb = yc


## Scale so the RMS over [w0, w1] seconds hits target_rms, without exceeding max_peak.
static func _normalize(buf: PackedFloat32Array, sr: float, w0: float, w1: float, target_rms: float, max_peak: float) -> void:
	var n: int = buf.size()
	var a: int = clampi(int(w0 * sr), 0, n - 1)
	var b: int = clampi(int(w1 * sr), a + 1, n)
	var sq: float = 0.0
	for i in range(a, b):
		sq += buf[i] * buf[i]
	var rms: float = sqrt(sq / float(b - a))
	var pk: float = 0.0
	for i in n:
		var v: float = absf(buf[i])
		if v > pk:
			pk = v
	if rms < 1.0e-9 or pk < 1.0e-9:
		return
	var g: float = minf(target_rms / rms, max_peak / pk)
	for i in n:
		buf[i] *= g


static func _fade_tail(buf: PackedFloat32Array, n_fade: int) -> void:
	var n: int = buf.size()
	n_fade = mini(n_fade, n)
	for i in n_fade:
		var x: float = float(i) / float(n_fade)
		buf[n - 1 - i] *= 0.5 - 0.5 * cos(PI * x)


static func _fade_head(buf: PackedFloat32Array, n_fade: int) -> void:
	for i in mini(n_fade, buf.size()):
		buf[i] *= float(i) / float(n_fade)


static func _to_wav(buf: PackedFloat32Array, rate: int, looped: bool) -> AudioStreamWAV:
	var n: int = buf.size()
	var m: int = (n + 1) >> 1
	var ints: PackedInt32Array = PackedInt32Array()
	ints.resize(m)
	for k in m:
		var i0: int = k << 1
		var lo_s: int = int(clampf(buf[i0] * 32767.0, -32767.0, 32767.0)) & 0xFFFF
		var hi_s: int = 0
		if i0 + 1 < n:
			hi_s = int(clampf(buf[i0 + 1] * 32767.0, -32767.0, 32767.0)) & 0xFFFF
		ints[k] = lo_s | (hi_s << 16)
	var w: AudioStreamWAV = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = ints.to_byte_array()
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w


## Kalimba: a few inharmonic tine partials (fast decays on the upper ones), a
## tiny thumb click and a woody thump.
static func _synth_kalimba(root: int, dur: float, noise: PackedFloat32Array) -> PackedFloat32Array:
	var n: int = int(dur * SRF)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var f0: float = Theory.hz(float(root))
	var ts: float = clampf(1.0 - float(root - 62) * 0.016, 0.45, 1.1)
	_resonate(out, f0, 1.0, 0.62 * ts, SRF)
	_resonate(out, f0 * 2.004, 0.16, 0.30 * ts, SRF)
	_resonate(out, f0 * 4.02, 0.06, 0.15 * ts, SRF)
	_resonate(out, f0 * 6.27, 0.15, 0.065 * ts, SRF)
	_resonate(out, f0 * 9.2, 0.04, 0.035, SRF)
	var lp: float = 0.0
	var nl: int = int(0.06 * SRF)
	for i in nl:
		var t: float = float(i) / SRF
		var x: float = noise[3000 + i]
		lp += 0.12 * (x - lp)
		out[i] += 0.22 * exp(-t / 0.0035) * (x - lp) + 0.45 * exp(-t / 0.011) * lp
	_fade_head(out, 6)
	_fade_tail(out, int(0.3 * SRF))
	return out


## Karplus-Strong pluck with a softened (low-passed) excitation: nylon-ish.
## Returns {buf, hz}; hz is the real fundamental (delay lengths are integers).
static func _synth_pluck(root: int, dur: float, t60: float, bright: float, noise: PackedFloat32Array) -> Dictionary:
	var n: int = int(dur * SRF)
	var f0: float = Theory.hz(float(root))
	var dl: int = maxi(int(round(SRF / f0 - 0.5)), 4)
	var actual: float = SRF / (float(dl) + 0.5)
	var line: PackedFloat32Array = PackedFloat32Array()
	line.resize(dl)
	var lp: float = 0.0
	var mean: float = 0.0
	var off: int = 9000 + root * 97
	for i in dl:
		lp += bright * (noise[off + i] - lp)
		line[i] = lp
		mean += lp
	mean /= float(dl)
	for i in dl:
		line[i] -= mean
	var decay: float = exp(-6.9078 / (t60 * actual))
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var p: int = 0
	var prev: float = 0.0
	var body: float = 0.0
	for i in n:
		var cur: float = line[p]
		var nv: float = (cur + prev) * 0.5 * decay
		line[p] = nv
		prev = cur
		p += 1
		if p >= dl:
			p = 0
		body += 0.55 * (nv - body)
		out[i] = body
	var tl: float = 0.0
	for i in int(0.02 * SRF):
		tl += 0.1 * (noise[off + 400 + i] - tl)
		out[i] += 0.5 * tl * exp(-float(i) / (0.006 * SRF))
	# The excitation burst is far louder than the ringing string: tame it with a soft
	# clip (also warms the tone) so the sample has a sane crest factor.
	var pk: float = 0.0
	for i in n:
		pk = maxf(pk, absf(out[i]))
	var inv_pk: float = 1.0 / maxf(pk, 1.0e-6)
	var kk: float = 2.4
	var norm: float = 1.0 / tanh(kk)
	for i in n:
		out[i] = tanh(kk * out[i] * inv_pk) * norm
	_fade_head(out, 8)
	_fade_tail(out, int(0.25 * SRF))
	return {"buf": out, "hz": actual}


## Breathy wooden flute at SR_LO: sine + soft 2nd/3rd, delayed vibrato, band-passed
## breath noise and a little chiff on the attack. Release is baked in.
static func _synth_flute(root: int, dur: float, noise: PackedFloat32Array) -> PackedFloat32Array:
	var n: int = int(dur * SRL)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var f0: float = Theory.hz(float(root))
	var inv: float = 1.0 / SRL
	var att: float = 0.085
	var rel: float = minf(0.3, dur * 0.35)
	var ph: float = 0.0
	var vph: float = 0.0
	var vstep: float = TAU * 5.0 * inv
	var wstep: float = TAU * f0 * inv
	var lpa: float = 0.0
	var lpb: float = 0.0
	var noff: int = root * 211 + int(dur * 100.0)
	for i in n:
		var t: float = float(i) * inv
		var env: float = 1.0
		if t < att:
			var x: float = t / att
			env = x * x * (3.0 - 2.0 * x)
		var tr: float = dur - t
		if tr < rel:
			var y: float = tr / rel
			env *= y * y * (3.0 - 2.0 * y)
		var vib: float = clampf((t - 0.22) / 0.5, 0.0, 1.0)
		vph += vstep
		var vs: float = sin(vph)
		ph += wstep * (1.0 + 0.0055 * vib * vs)
		var s: float = sin(ph)
		var c: float = cos(ph)
		var tone: float = s + 0.2 * (2.0 * s * c) + 0.06 * (s * (3.0 - 4.0 * s * s))
		var nz: float = noise[(noff + i) & 65535]
		lpa += 0.55 * (nz - lpa)
		lpb += 0.10 * (nz - lpb)
		var br: float = lpa - lpb
		var breath: float = 0.26 + 0.35 * exp(-t / 0.035)
		out[i] = env * (tone * (1.0 + 0.05 * vib * vs) + breath * br)
	return out


## Bowed drone loop cell at SR_LO: root + fifth, three detuned saws (+-0.5 Hz chorus),
## two-pole low-pass, slow bow-pressure swell. All voices are whole cycles per cell,
## so it loops seamlessly (k must be even).
static func _synth_drone(k: int, noise: PackedFloat32Array) -> PackedFloat32Array:
	var cell: int = DRN_LEN
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(cell)
	var f0: float = float(k) * 0.5
	var cutoff: float = clampf(f0 * 8.0, 500.0, 1100.0)
	var a: float = 1.0 - exp(-TAU * cutoff / SRL)
	var kf: int = k + (k >> 1)
	var inv_l: float = 1.0 / float(cell)
	var warm: int = 400
	var y1: float = 0.0
	var y2: float = 0.0
	# Fixed phase offsets keep the saw edges from lining up (softer chorus beating).
	var o0: int = 3217
	var o1: int = 9181
	var o2: int = 14903
	var o3: int = 6029
	var o4: int = 17747
	for j in range(-warm, cell):
		var i: int = j if j >= 0 else j + cell
		var p0: float = float((i * (k - 1) + o0) % cell) * inv_l
		var p1: float = float((i * k + o1) % cell) * inv_l
		var p2: float = float((i * (k + 1) + o2) % cell) * inv_l
		var q0: float = float((i * kf + o3) % cell) * inv_l
		var q1: float = float((i * (kf + 1) + o4) % cell) * inv_l
		# Centre voice full, detuned sides lighter: a gentle chorus swell, not full phasing.
		var x: float = 1.0 * (2.0 * p1 - 1.0) + 0.35 * ((2.0 * p0 - 1.0) + (2.0 * p2 - 1.0))
		x += 0.3 * (2.0 * q0 - 1.0) + 0.1 * (2.0 * q1 - 1.0)
		x += 0.04 * noise[(5000 + i) & 65535]
		y1 += a * (x - y1)
		y2 += a * (y1 - y2)
		if j >= 0:
			var ph: float = TAU * float(i) * inv_l
			out[j] = y2 * (1.0 + 0.1 * sin(ph) + 0.05 * sin(3.0 * ph + 1.3))
	return out


static func _synth_thump(noise: PackedFloat32Array) -> PackedFloat32Array:
	var n: int = int(0.5 * SRF)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var ph: float = 0.0
	var lp: float = 0.0
	for i in n:
		var t: float = float(i) / SRF
		ph += TAU * (58.0 + 85.0 * exp(-t / 0.035)) / SRF
		var body: float = sin(ph) * exp(-t / 0.13) + 0.25 * sin(ph * 1.59) * exp(-t / 0.05)
		lp += 0.3 * (noise[7000 + i] - lp)
		out[i] = body + 0.5 * lp * exp(-t / 0.014)
	_fade_head(out, 20)
	_fade_tail(out, int(0.1 * SRF))
	return out


static func _synth_tap(noise: PackedFloat32Array) -> PackedFloat32Array:
	var n: int = int(0.28 * SRF)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var ph: float = 0.0
	var lp: float = 0.0
	for i in n:
		var t: float = float(i) / SRF
		ph += TAU * (165.0 + 90.0 * exp(-t / 0.012)) / SRF
		lp += 0.55 * (noise[12000 + i] - lp)
		out[i] = sin(ph) * exp(-t / 0.05) + 0.7 * (noise[12000 + i] - lp) * exp(-t / 0.012) + 0.35 * lp * exp(-t / 0.02)
	_fade_head(out, 12)
	_fade_tail(out, int(0.06 * SRF))
	return out


static func _synth_block(noise: PackedFloat32Array) -> PackedFloat32Array:
	var n: int = int(0.3 * SRF)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	_resonate(out, 880.0, 1.0, 0.035, SRF)
	_resonate(out, 880.0 * 2.76, 0.5, 0.015, SRF)
	_resonate(out, 880.0 * 5.4, 0.2, 0.006, SRF)
	for i in int(0.01 * SRF):
		out[i] += 0.3 * noise[20000 + i] * exp(-float(i) / (0.0025 * SRF))
	_fade_head(out, 4)
	_fade_tail(out, int(0.08 * SRF))
	return out


# ---------------------------------------------------------------------------
# Composer: mood + seed -> bar-by-bar events (pure data, no audio)
# ---------------------------------------------------------------------------

class Composer extends RefCounted:
	const PH_IDLE: int = 0
	const PH_PLAY: int = 1
	const PH_REST: int = 2
	const PH_DONE: int = 3

	const V_NONE: int = 0
	const V_UP2: int = 1
	const V_DOWN2: int = 2
	const V_UP4: int = 3
	const V_DISP: int = 4
	const V_INV: int = 5
	const V_OCT: int = 6
	const V_EMB: int = 7
	const V_FRAG1: int = 8
	const V_FRAG2: int = 9

	const MODES: Dictionary = {
		"ionian": [0, 2, 4, 5, 7, 9, 11],
		"mixolydian": [0, 2, 4, 5, 7, 9, 10],
		"dorian": [0, 2, 3, 5, 7, 9, 10],
		"aeolian": [0, 2, 3, 5, 7, 8, 10],
		"phrygian": [0, 1, 3, 5, 7, 8, 10],
	}
	## Chord-root degree progressions (one entry per chord slot).
	const PROGS: Dictionary = {
		"ionian": [[0, 3, 0, 4], [0, 4, 3, 0], [0, 5, 3, 4]],
		"mixolydian": [[0, 6, 3, 0], [0, 3, 6, 3], [0, 6, 0, 3]],
		"dorian": [[0, 3, 0, 6], [0, 6, 3, 0], [0, 3, 0, 4]],
		"aeolian": [[0, 6, 5, 6], [0, 5, 6, 0], [0, 3, 6, 0]],
		"phrygian": [[0, 1, 0, 6], [0, 6, 1, 0]],
	}
	## Melody scale degrees allowed per mode (indices into the 7-note mode).
	const ALLOWED: Dictionary = {
		"ionian": [0, 1, 2, 4, 5],
		"mixolydian": [0, 1, 2, 4, 5, 6],
		"dorian": [0, 2, 3, 4, 5, 6],
		"aeolian": [0, 2, 3, 4, 6],
		"phrygian": [0, 1, 2, 3, 4, 6],
	}
	## Rhythm cells in 8th-note steps (negative = rest); each sums to the bar length.
	const CELLS: Dictionary = {
		"slow4": [[4, 4], [6, 2], [-2, 2, 4], [2, 2, 4], [3, 1, 4], [4, -2, 2], [8], [2, 6], [-4, 4]],
		"mid4": [[2, 2, 4], [3, 1, 2, 2], [2, 2, 2, 2], [3, 1, 4], [2, 1, 1, 4], [1, 1, 2, 4], [2, 3, 3], [4, 2, 2], [3, 3, 2], [2, 2, -2, 2]],
		"busy4": [[2, 2, 2, 2], [1, 1, 2, 2, 2], [2, 1, 1, 2, 2], [3, 1, 3, 1], [2, 2, 3, 1], [1, 1, 1, 1, 2, 2]],
		"cad4": [[4, 4], [2, 2, 4], [3, 1, 4], [2, 6], [1, 1, 2, 4]],
		"slow3": [[6], [4, 2], [2, 4], [3, 3], [-2, 4], [2, 2, 2]],
		"mid3": [[2, 2, 2], [3, 1, 2], [2, 1, 1, 2], [4, 2], [3, 3], [2, 2, 1, 1], [1, 1, 2, 2]],
		"busy3": [[2, 2, 2], [1, 1, 2, 2], [2, 1, 1, 2], [1, 1, 1, 1, 2]],
		"cad3": [[6], [4, 2], [2, 4], [3, 3], [2, 2, 2]],
	}
	## Pluck patterns: 0 root, 1 third, 2 fifth, 3 octave, 4 third+oct, -1 rest.
	const PLUCK_4: Array = [[0, -1, 2, -1, 1, -1, 2, -1], [0, 1, 2, 3, 2, 1, 2, -1], [0, -1, -1, 2, 1, -1, 2, -1], [0, 2, 1, 2, 0, 2, 1, 2]]
	const PLUCK_3: Array = [[0, -1, 2, 1, 2, -1], [0, 1, 2, 1, 2, 1], [0, -1, 1, -1, 2, -1]]
	## Drum patterns: 1 thump, 2 soft thump, 3 tap, 4 wood block.
	const DRUM_4: Array = [[1, 0, 0, 0, 2, 0, 3, 0], [1, 0, 3, 0, 2, 0, 0, 4], [1, 0, 0, 4, 2, 0, 3, 0]]
	const DRUM_3: Array = [[1, 0, 3, 0, 3, 0], [1, 0, 0, 4, 2, 0]]
	const BEAT_4: Array = [[2, 0, 0, 2, 0, 0, 3, 0], [1, 0, 0, 2, 0, 0, 0, 3]]
	const BEAT_3: Array = [[1, 0, 2, 0, 0, 0], [1, 0, 0, 2, 0, 0]]
	const JIT: float = 0.012

	var seed_base: int = 0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var mood: String = "silent"
	var pending: String = "silent"
	var phase: int = PH_IDLE
	var next_t: float = 0.0
	var piece_n: int = 0
	var bar_i: int = 0
	var bars_left: int = 0
	var rest_left: int = 0
	var rest_first: bool = true
	var drone_on: bool = false
	var drone_root: int = -999

	# --- current piece ---
	var tonic: int = 62
	var mode_name: String = "dorian"
	var mode: PackedInt32Array = PackedInt32Array()
	var allowed: PackedInt32Array = PackedInt32Array()
	var bpm: float = 66.0
	var beats: int = 4
	var steps: int = 8
	var step_s: float = 0.45
	var bar_s: float = 3.6
	var prog: PackedInt32Array = PackedInt32Array()
	var chord_bars: int = 1
	var lo: int = 0
	var hi: int = 10
	var motif: Array = []
	var plan: Array = []
	var pl_a: PackedInt32Array = PackedInt32Array()
	var pl_b: PackedInt32Array = PackedInt32Array()
	var dr_pat: PackedInt32Array = PackedInt32Array()
	var keep_p: float = 0.9
	var echo_p: float = 0.0
	var counter_p: float = 0.0
	var twinkle_p: float = 0.0
	var drone_db: float = -4.0
	var drone_fade: float = 2.0
	var rest_lo: float = 20.0
	var rest_hi: float = 45.0
	var act_lo: float = 40.0
	var act_hi: float = 90.0
	var plan_kind: int = 0
	var last_d: int = 0

	func _init(seed_in: int) -> void:
		seed_base = seed_in

	func request(m: String) -> void:
		pending = m

	## Stop everything immediately (used when the Music node is disabled).
	func silence() -> void:
		phase = PH_IDLE
		mood = "silent"
		pending = "silent"
		drone_on = false
		drone_root = -999

	## True when gen_bar should be called now (a bar boundary falls inside the horizon).
	func wants_bar(horizon: float) -> bool:
		if phase == PH_PLAY or phase == PH_REST:
			return next_t < horizon
		return pending != mood

	## Compose the next bar (starting at next_t) and advance. `now` anchors the first bar.
	func gen_bar(now: float) -> Array[Ev]:
		var evs: Array[Ev] = []
		if pending != mood:
			if pending == "silent":
				if drone_on:
					evs.append(Ev.drone_stop(maxf(next_t, now), 2.2))
				drone_on = false
				mood = "silent"
				phase = PH_IDLE
				return evs
			mood = pending
			if next_t < now or phase == PH_IDLE or phase == PH_DONE:
				next_t = now + 0.05
			_start_piece()
		if phase == PH_IDLE or phase == PH_DONE:
			return evs
		var adv: float = bar_s
		if phase == PH_PLAY:
			_play_bar(evs, next_t)
		else:
			_rest_bar(evs, next_t)
		next_t += adv
		return evs

	# ------------------------------------------------------------------
	# Piece construction
	# ------------------------------------------------------------------

	func _pick(arr: Array) -> Variant:
		return arr[rng.randi() % arr.size()]

	func _pick_tonic(pool: Array) -> int:
		var t: int = _pick(pool)
		var tries: int = 0
		while t == tonic and tries < 6 and pool.size() > 1:
			t = _pick(pool)
			tries += 1
		return t

	func _start_piece() -> void:
		piece_n += 1
		rng.seed = hash([seed_base, mood, piece_n])
		_build_piece()
		var target_s: float = rng.randf_range(act_lo, act_hi)
		var four: float = 4.0 * bar_s
		var n_min: int = ceili(act_lo / four)
		var n_max: int = maxi(n_min, floori(act_hi / four))
		var n4: int = clampi(roundi(target_s / four), n_min, n_max)
		bars_left = 4 * n4
		if mood == "arrived":
			bars_left = 4
		bar_i = 0
		phase = PH_PLAY
		rest_first = true
		_gen_motif()
		_make_plan()

	func _set_mode(mname: String) -> void:
		mode_name = mname
		mode = PackedInt32Array(MODES[mname])
		allowed = PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
		for d: int in ALLOWED[mname]:
			allowed[d] = 1

	func _set_window(lo_m: int, hi_m: int) -> void:
		lo = 99
		hi = -99
		for d in range(-14, 29):
			var m: int = dmidi(d)
			if m >= lo_m and m <= hi_m:
				lo = mini(lo, d)
				hi = maxi(hi, d)

	func _meter(p3: float) -> void:
		beats = 3 if rng.randf() < p3 else 4
		steps = beats * 2
		step_s = 30.0 / bpm
		bar_s = float(beats) * 60.0 / bpm

	func _pick_prog() -> void:
		var pool: Array = PROGS[mode_name]
		prog = PackedInt32Array(_pick(pool) as Array)

	func _build_piece() -> void:
		twinkle_p = 0.0
		echo_p = 0.0
		counter_p = 0.0
		match mood:
			"dawn":
				tonic = _pick_tonic([62, 67, 65, 60, 69])
				_set_mode(_pick(["ionian", "mixolydian"]) as String)
				bpm = rng.randf_range(58.0, 65.0)
				_meter(0.0)
				_pick_prog()
				chord_bars = 2
				_set_window(64, 84)
				keep_p = 0.9
				echo_p = 0.5
				drone_db = -5.0
				drone_fade = 2.8
				act_lo = 40.0
				act_hi = 75.0
				rest_lo = 25.0
				rest_hi = 50.0
			"travel":
				tonic = _pick_tonic([62, 67, 69, 64, 60, 65])
				_set_mode(_pick(["mixolydian", "dorian", "ionian", "mixolydian"]) as String)
				bpm = rng.randf_range(68.0, 80.0)
				_meter(0.3)
				_pick_prog()
				chord_bars = 1
				_set_window(62, 81)
				keep_p = 0.93
				counter_p = 0.55
				drone_db = -5.0
				drone_fade = 1.8
				act_lo = 55.0
				act_hi = 90.0
				rest_lo = 20.0
				rest_hi = 45.0
				var pp: Array = PLUCK_4 if beats == 4 else PLUCK_3
				pl_a = PackedInt32Array(_pick(pp) as Array)
				pl_b = PackedInt32Array(_pick(pp) as Array)
				dr_pat = PackedInt32Array(_pick(DRUM_4 if beats == 4 else DRUM_3) as Array)
			"tense":
				tonic = _pick_tonic([62, 64, 69, 57, 59])
				_set_mode(_pick(["aeolian", "aeolian", "phrygian"]) as String)
				bpm = rng.randf_range(76.0, 84.0)
				_meter(0.0)
				_pick_prog()
				chord_bars = 2
				_set_window(60, 78)
				keep_p = 0.5
				drone_db = -1.5
				drone_fade = 1.6
				act_lo = 40.0
				act_hi = 75.0
				rest_lo = 10.0
				rest_hi = 25.0
				dr_pat = PackedInt32Array(_pick(BEAT_4) as Array)
			"night":
				tonic = _pick_tonic([62, 64, 69, 67, 57])
				_set_mode(_pick(["dorian", "aeolian"]) as String)
				bpm = rng.randf_range(54.0, 60.0)
				_meter(0.25)
				_pick_prog()
				chord_bars = 2
				_set_window(54, 71)
				keep_p = 0.85
				twinkle_p = 0.14
				drone_db = -2.5
				drone_fade = 3.5
				act_lo = 40.0
				act_hi = 70.0
				rest_lo = 32.0
				rest_hi = 54.0
			"arrived":
				tonic = _pick_tonic([60, 62, 65, 67])
				_set_mode(_pick(["ionian", "ionian", "mixolydian"]) as String)
				bpm = rng.randf_range(70.0, 76.0)
				_meter(0.0)
				prog = PackedInt32Array([0, 3, 4, 0] if mode_name == "ionian" else [0, 3, 6, 0])
				chord_bars = 1
				_set_window(62, 86)
				keep_p = 1.0
				drone_db = -4.0
				drone_fade = 1.2
				rest_lo = 4.0
				rest_hi = 4.0
				pl_a = PackedInt32Array([0, -1, 2, -1, 1, -1, 2, -1])

	# ------------------------------------------------------------------
	# Pitch helpers (scale degrees <-> MIDI)
	# ------------------------------------------------------------------

	func dmidi(d: int) -> int:
		var o: int = floori(float(d) / 7.0)
		return tonic + 12 * o + mode[d - o * 7]

	func _snap(d: int) -> int:
		var x: int = clampi(d, lo, hi)
		for off: int in [0, 1, -1, 2, -2, 3, -3]:
			var y: int = x + off
			if y >= lo and y <= hi and allowed[posmod(y, 7)] == 1:
				return y
		return x

	func _chord_tone_near(d: int, croot: int) -> int:
		for off: int in [0, 1, -1, 2, -2, 3, -3]:
			var y: int = d + off
			if y < lo or y > hi or allowed[posmod(y, 7)] == 0:
				continue
			var rel: int = posmod(y - croot, 7)
			if rel == 0 or rel == 2 or rel == 4:
				return y
		return _snap(d)

	func _degree_near(d: int, deg_mod: int) -> int:
		for off: int in [0, 1, -1, 2, -2, 3, -3, 4, -4]:
			var y: int = d + off
			if y >= lo and y <= hi and posmod(y - deg_mod, 7) == 0:
				return y
		return _snap(d)

	@warning_ignore("integer_division")
	func chord_root_at(bar: int) -> int:
		return prog[(bar / chord_bars) % prog.size()]

	func _fit(m: int, lo_m: int, hi_m: int) -> int:
		while m > hi_m:
			m -= 12
		while m < lo_m:
			m += 12
		return m

	func _bass_midi(croot: int) -> int:
		return _fit(dmidi(croot), 35, 47)

	func _strong(step: int) -> bool:
		return step == 0 or (beats == 4 and step == 4)

	func _jit(amount: float = JIT) -> float:
		return rng.randf() * amount

	# ------------------------------------------------------------------
	# Motif generation and variation
	# ------------------------------------------------------------------

	func _density() -> String:
		match mood:
			"dawn", "night":
				return "slow"
			"tense":
				return "busy"
		return "mid"

	func _walk_bar(cell: Array, d0: int, croot: int, target: int, free_start: bool, last_bar: bool) -> Array:
		var notes: Array = []
		var step: int = 0
		var d: int = d0
		var first: bool = free_start
		for dv: int in cell:
			if dv < 0:
				step -= dv
				continue
			if first:
				first = false
			else:
				var r: float = rng.randf()
				var mag: int = 4
				if r < 0.12:
					mag = 0
				elif r < 0.64:
					mag = 1
				elif r < 0.88:
					mag = 2
				elif r < 0.96:
					mag = 3
				var sgn: int = 1 if target > d else -1
				if target == d:
					sgn = 1 if rng.randf() < 0.5 else -1
				if rng.randf() < 0.3:
					sgn = -sgn
				d = _snap(d + sgn * mag)
				if _strong(step) and rng.randf() < 0.75:
					d = _chord_tone_near(d, croot)
			notes.append(Vector3i(step, dv, d))
			step += dv
		if last_bar and not notes.is_empty():
			var fin: Vector3i = notes[notes.size() - 1]
			var tgt: int = croot if rng.randf() < 0.75 else croot + 4
			var fd: int = _degree_near(fin.z, posmod(tgt, 7))
			notes[notes.size() - 1] = Vector3i(fin.x, steps - fin.x, fd)
		if not notes.is_empty():
			var l: Vector3i = notes[notes.size() - 1]
			last_d = l.z
		return notes

	func _transpose(notes: Array, k: int) -> Array:
		var out: Array = []
		for n: Vector3i in notes:
			out.append(Vector3i(n.x, n.y, _snap(n.z + k)))
		return out

	func _gen_motif() -> void:
		motif = []
		var dens: String = _density()
		var cells: Array = CELLS[dens + str(beats)]
		var cads: Array = CELLS["cad" + str(beats)]
		var cell_a: Array = _pick(cells) as Array
		var cell_b: Array = _pick(cells) as Array
		var cell_c: Array = _pick(cads) as Array
		var center: int = (lo + hi) >> 1
		var c0: int = chord_root_at(0)
		var d0: int = _chord_tone_near(center, c0)
		var b0: Array = _walk_bar(cell_a, d0, c0, center, true, false)
		var b1: Array = _walk_bar(cell_b, last_d, chord_root_at(1), center + 2, false, false)
		var shift: int = _pick([1, 2, -1]) as int
		var b2: Array = _transpose(b0, shift)
		if rng.randf() < 0.4 and not b2.is_empty():
			var l2: Vector3i = b2[b2.size() - 1]
			b2[b2.size() - 1] = Vector3i(l2.x, l2.y, _chord_tone_near(l2.z + 1, chord_root_at(2)))
		var lastn: Vector3i = b2[b2.size() - 1] if not b2.is_empty() else Vector3i(0, 1, d0)
		var b3: Array = _walk_bar(cell_c, lastn.z, chord_root_at(3), center, false, true)
		motif = [b0, b1, b2, b3]

	func _vary(notes: Array, v: int) -> Array:
		var out: Array = []
		match v:
			V_UP2:
				out = _transpose(notes, 2)
			V_DOWN2:
				out = _transpose(notes, -2)
			V_UP4:
				out = _transpose(notes, 4)
			V_OCT:
				for n: Vector3i in notes:
					var up: int = n.z + 7
					if up > hi:
						up = n.z - 7
					out.append(Vector3i(n.x, n.y, _snap(up)))
			V_DISP:
				for n: Vector3i in notes:
					var s: int = n.x + 1
					if s < steps:
						out.append(Vector3i(s, mini(n.y, steps - s), n.z))
			V_INV:
				if not notes.is_empty():
					var first: Vector3i = notes[0]
					for n: Vector3i in notes:
						out.append(Vector3i(n.x, n.y, _snap(2 * first.z - n.z)))
			V_EMB:
				var end_prev: int = -1
				for n: Vector3i in notes:
					if n.x >= 1 and n.x - 1 >= end_prev and n.y >= 2 and rng.randf() < 0.5:
						out.append(Vector3i(n.x - 1, 1, _snap(n.z - 1)))
					out.append(n)
					end_prev = n.x + n.y
			V_FRAG1:
				for n: Vector3i in notes:
					if n.x < (steps >> 1):
						out.append(n)
			V_FRAG2:
				for n: Vector3i in notes:
					if n.x >= (steps >> 1):
						out.append(n)
		if v == V_NONE or out.is_empty():
			out = notes.duplicate()
		return out

	func _make_plan() -> void:
		plan = []
		var va: Array = [V_UP2, V_UP4, V_OCT]
		var vb: Array = [V_DISP, V_INV, V_EMB, V_DOWN2]
		var vall: Array = va + vb
		var ik: int = Inst.KALIMBA
		var fl: int = Inst.FLUTE
		plan_kind = rng.randi() % 2
		for b in 8:
			var e: Dictionary = {"lead": ik, "src": b % 4, "v": V_NONE, "counter": false}
			var stm1: bool = b >= 4
			var cad: bool = b == 3 or b == 7
			match mood:
				"dawn":
					if stm1 and not cad:
						e["v"] = _pick(vall)
				"travel":
					if plan_kind == 0:
						if stm1 and b <= 5:
							e["lead"] = fl
							e["v"] = _pick(va)
						elif stm1 and b == 6:
							e["v"] = _pick(vb)
						e["counter"] = (b == 2 or b == 3 or b == 7) and e["lead"] == ik and rng.randf() < counter_p
					else:
						if b % 4 >= 2:
							e["lead"] = fl
						if stm1 and not cad:
							e["v"] = _pick(va if b % 4 < 2 else vb)
						e["counter"] = b == 1 and rng.randf() < counter_p * 0.5
				"tense":
					if stm1 and not cad:
						e["v"] = _pick([V_FRAG1, V_FRAG2, V_INV, V_DISP])
					elif not cad and rng.randf() < 0.4:
						e["v"] = V_FRAG1
				"night":
					e["lead"] = fl
					if stm1 and not cad:
						e["v"] = _pick([V_DOWN2, V_UP2, V_DISP])
			plan.append(e)

	# ------------------------------------------------------------------
	# Bars
	# ------------------------------------------------------------------

	func _play_bar(evs: Array[Ev], t0: float) -> void:
		var b: int = bar_i % 8
		var croot: int = chord_root_at(bar_i)
		var droot: int = _bass_midi(croot)
		if not drone_on or droot != drone_root:
			evs.append(Ev.drone_set(t0, float(droot), drone_db, drone_fade))
			drone_on = true
			drone_root = droot
		match mood:
			"dawn":
				_bar_dawn(evs, t0, b)
			"travel":
				_bar_travel(evs, t0, b, croot)
			"tense":
				_bar_tense(evs, t0, b, croot)
			"night":
				_bar_night(evs, t0, b)
			"arrived":
				_bar_arrived(evs, t0, bar_i)
		bar_i += 1
		bars_left -= 1
		if bar_i % 8 == 0 and bars_left > 0:
			_make_plan()
		if bars_left <= 0:
			phase = PH_REST
			rest_first = true
			var rest_s: float = rng.randf_range(rest_lo, rest_hi)
			rest_left = maxi(1, roundi(rest_s / bar_s))

	func _rest_bar(evs: Array[Ev], t0: float) -> void:
		if rest_first:
			rest_first = false
			if drone_on and mood != "tense":
				evs.append(Ev.drone_stop(t0, 4.0 if mood == "arrived" else 3.5))
				drone_on = false
		rest_left -= 1
		if rest_left <= 0:
			if mood == "arrived":
				phase = PH_DONE
			else:
				_start_piece()

	func _emit_melody(evs: Array[Ev], notes: Array, t0: float, inst: int, db: float, keep: float, lo_m: int, hi_m: int, echo: float) -> void:
		for n: Vector3i in notes:
			var strong: bool = _strong(n.x)
			if not strong and rng.randf() > keep:
				continue
			var m: int = _fit(dmidi(n.z), lo_m, hi_m)
			var acc: float = 1.2 if strong else 0.0
			var tt: float = t0 + float(n.x) * step_s + _jit()
			evs.append(Ev.note(tt, inst, float(m), db + acc + rng.randf_range(-1.5, 0.5), float(n.y) * step_s))
			if echo > 0.0 and n.y >= 3 and rng.randf() < echo and m + 12 <= hi_m:
				evs.append(Ev.note(tt + 3.0 * step_s + 0.02, inst, float(m + 12), db - 10.0, 1.0))

	func _bar_dawn(evs: Array[Ev], t0: float, b: int) -> void:
		var e: Dictionary = plan[b]
		var notes: Array = _vary(motif[e["src"]], e["v"])
		_emit_melody(evs, notes, t0, Inst.KALIMBA, -2.5, keep_p, 58, 90, echo_p)

	func _bar_night(evs: Array[Ev], t0: float, b: int) -> void:
		var e: Dictionary = plan[b]
		var notes: Array = _vary(motif[e["src"]], e["v"])
		_emit_melody(evs, notes, t0, Inst.FLUTE, -4.0, keep_p, 55, 74, 0.0)
		if rng.randf() < twinkle_p:
			var d: int = _chord_tone_near(hi + 7, chord_root_at(bar_i))
			var m: int = _fit(dmidi(d), 76, 90)
			evs.append(Ev.note(t0 + float(rng.randi() % steps) * step_s, Inst.KALIMBA, float(m), -12.0, 1.0))

	func _counter(evs: Array[Ev], t0: float, croot: int) -> void:
		var deg: int = croot + (4 if rng.randf() < 0.55 else 2)
		var m: int = _fit(dmidi(deg), 62, 77)
		var s0: int = 0 if rng.randf() < 0.6 else 2
		evs.append(Ev.note(t0 + float(s0) * step_s + _jit(), Inst.FLUTE, float(m), -9.0, float(steps - s0) * step_s))

	func _pluck_midi(croot: int, sel: int) -> int:
		var base: int = _fit(dmidi(croot), 47, 58)
		var third: int = posmod(dmidi(croot + 2) - dmidi(croot), 12)
		var fifth: int = posmod(dmidi(croot + 4) - dmidi(croot), 12)
		match sel:
			1:
				return base + third
			2:
				return base + fifth
			3:
				return base + 12
			4:
				return base + third + 12
		return base

	func _drums(evs: Array[Ev], t0: float, pat: PackedInt32Array, gain: float, fill: bool) -> void:
		for s in steps:
			var code: int = pat[s]
			if code == 0:
				continue
			var tt: float = t0 + float(s) * step_s + _jit(0.006)
			var e: Ev
			match code:
				1:
					e = Ev.note(tt, Inst.DRUM, 0.0, -2.0 + gain, 0.3)
				2:
					e = Ev.note(tt, Inst.DRUM, 0.0, -6.0 + gain, 0.3)
				3:
					e = Ev.note(tt, Inst.DRUM, 0.0, -8.0 + gain, 0.2)
					e.voice = 1
				_:
					e = Ev.note(tt, Inst.BLOCK, float(_pick([-2, 0, 3]) as int), -6.0 + gain, 0.2)
			evs.append(e)
		if fill:
			for k in 2:
				var tf: float = t0 + float(steps - 2 + k) * step_s + _jit(0.006)
				var f: Ev = Ev.note(tf, Inst.DRUM, 2.0 * float(k), -9.0 + gain + float(k), 0.2)
				f.voice = 1
				evs.append(f)

	func _bar_travel(evs: Array[Ev], t0: float, b: int, croot: int) -> void:
		var pat: PackedInt32Array = pl_a if b < 4 else pl_b
		for s in steps:
			var sel: int = pat[s]
			if sel < 0:
				continue
			if s != 0 and rng.randf() < 0.07:
				continue
			var m: int = _pluck_midi(croot, sel)
			var lvl: float = -2.0 if s == 0 else -5.5 + rng.randf_range(-1.0, 1.0)
			evs.append(Ev.note(t0 + float(s) * step_s + _jit(), Inst.PLUCK, float(m), lvl, 1.0))
		var e: Dictionary = plan[b]
		var notes: Array = _vary(motif[e["src"]], e["v"])
		if e["lead"] == Inst.FLUTE:
			_emit_melody(evs, notes, t0, Inst.FLUTE, -3.5, keep_p, 58, 80, 0.0)
		else:
			_emit_melody(evs, notes, t0, Inst.KALIMBA, -4.0, keep_p, 58, 90, 0.0)
		if e["counter"]:
			_counter(evs, t0, croot)
		_drums(evs, t0, dr_pat, 0.0, b % 4 == 3 and rng.randf() < 0.5)

	func _bar_tense(evs: Array[Ev], t0: float, b: int, croot: int) -> void:
		var base: int = _fit(dmidi(croot), 44, 55)
		var fifth: int = base + posmod(dmidi(croot + 4) - dmidi(croot), 12)
		for s in steps:
			if s != 0 and s % 2 == 1 and rng.randf() < 0.15:
				continue
			var m: int = base
			if b % 2 == 1 and s >= steps - 2:
				m = fifth if s == steps - 2 else base + 12
			var lvl: float = -2.0 if s == 0 else (-5.0 if s == (steps >> 1) else -7.5 + rng.randf_range(-1.0, 1.0))
			evs.append(Ev.note(t0 + float(s) * step_s + _jit(0.008), Inst.PLUCK_MUTE, float(m), lvl, 0.5))
		var e: Dictionary = plan[b]
		var notes: Array = _vary(motif[e["src"]], e["v"])
		_emit_melody(evs, notes, t0, Inst.KALIMBA, -7.0, keep_p, 60, 84, 0.0)
		_drums(evs, t0, dr_pat, -1.0, false)

	func _bar_arrived(evs: Array[Ev], t0: float, b: int) -> void:
		var r: int = prog[b]
		var arp: Array = [0, 2, 4, 7]
		if b < 3:
			for i in 4:
				var m: int = _fit(dmidi(r + int(arp[i])), 62, 88)
				evs.append(Ev.note(t0 + float(i * 2) * step_s + _jit(), Inst.KALIMBA, float(m), -4.5 + 0.5 * float(i), 1.0))
		else:
			var run: Array = [2, 4, 7, 9]
			for i in 4:
				var m2: int = _fit(dmidi(int(run[i])), 62, 88)
				evs.append(Ev.note(t0 + float(i) * step_s * 0.75 + _jit(0.008), Inst.KALIMBA, float(m2), -4.0 + 0.6 * float(i), 1.0))
		# flute melody (long notes, rising)
		var melody: Array = [[[0, 8, 4]], [[0, 4, 5], [4, 4, 7]], [[0, 5, 8], [5, 3, 6]], [[0, 8, 7]]]
		for n: Array in melody[b]:
			var fm: int = _fit(dmidi(int(n[2])), 60, 81)
			evs.append(Ev.note(t0 + float(int(n[0])) * step_s + _jit(), Inst.FLUTE, float(fm), -4.0, float(int(n[1])) * step_s))
		# pluck
		if b < 3:
			for s in steps:
				var sel: int = pl_a[s]
				if sel >= 0:
					evs.append(Ev.note(t0 + float(s) * step_s + _jit(), Inst.PLUCK, float(_pluck_midi(r, sel)), -2.5 if s == 0 else -6.0, 1.0))
		else:
			var chord: Array = [0, 2, 1, 3]
			for i in 4:
				evs.append(Ev.note(t0 + 0.035 * float(i), Inst.PLUCK, float(_pluck_midi(r, int(chord[i]))), -3.0 - 0.5 * float(i), 1.0))
		# frame drum
		var dpat: Array = [[1, 0, 0, 0, 0, 0, 0, 0], [1, 0, 0, 0, 3, 0, 0, 0], [1, 0, 0, 0, 2, 0, 3, 0], [1, 0, 0, 0, 0, 0, 0, 0]]
		_drums(evs, t0, PackedInt32Array(dpat[b]), 0.0, false)
