extends Node
## Sfx - Mossback's procedural sound bank and player pools (autoload "Sfx").
##
## Every sound is synthesized once at startup into a 16-bit mono AudioStreamWAV
## (no audio files). Playback goes through small player pools so callers can
## fire-and-forget:
##   Sfx.play("jump")                          non-positional one-shot
##   Sfx.play("beast_step", Vector3(...))      3D one-shot
##   Sfx.play_attached("creak", some_node3d)   3D player parented to a node
##   Sfx.set_ambience(wind, night)             wind loop / crickets / day birds
##   Sfx.set_listener_hint(pos)                where random bird chirps happen

const SR: int = 22050
const SRF: float = 22050.0
const ISR: float = 1.0 / 22050.0
const SEED_BASE: int = 0x4D4F5353 # "MOSS"

const POOL_3D: int = 24
const POOL_2D: int = 8

const BUS_MASTER: StringName = &"Master"
const BUS_SFX: StringName = &"SFX"
const BUS_AMB: StringName = &"Ambience"
const BUS_UI: StringName = &"UI"

## Wind loop recipe levels (relative gains of its three bands).
const WIND_BODY: float = 6.0
const WIND_AIR: float = 1.5
const WIND_RUMBLE: float = 1.2

## Ambience mix trims (dB) on top of the baked loop levels.
const WIND_TRIM_DB: float = -1.0
const CRICKET_TRIM_DB: float = 0.0
const AMB_SMOOTH_S: float = 1.4

## Per-sound 3D attenuation: Vector2(unit_size, max_distance) in metres.
## Godot's inverse-square model is 0 dB at unit_size and -12 dB per doubling after.
const SPATIAL_DEFAULT: Vector2 = Vector2(3.0, 40.0)
const SPATIAL: Dictionary = {
	"beast_step": Vector2(25.0, 250.0),
	"beast_moan": Vector2(30.0, 280.0),
	"beast_happy": Vector2(26.0, 250.0),
	"beast_grumble": Vector2(22.0, 220.0),
	"beast_sneeze_in": Vector2(25.0, 250.0),
	"beast_sneeze": Vector2(30.0, 280.0),
	"beast_chomp": Vector2(22.0, 220.0),
	"beast_gulp": Vector2(20.0, 200.0),
	"step_soft": Vector2(2.0, 25.0),
	"jump": Vector2(3.0, 40.0),
	"land": Vector2(3.0, 40.0),
	"splat": Vector2(4.0, 45.0),
	"pickup": Vector2(3.0, 35.0),
	"throw": Vector2(4.0, 45.0),
	"bonk": Vector2(5.0, 55.0),
	"fruit_drop": Vector2(3.5, 40.0),
	"whistle": Vector2(10.0, 100.0),
	"bell": Vector2(14.0, 140.0),
	"creak": Vector2(4.0, 40.0),
	"rustle": Vector2(4.0, 40.0),
	"munch": Vector2(3.0, 30.0),
	"spit": Vector2(3.0, 40.0),
	"tumble": Vector2(3.5, 45.0),
	"chirp": Vector2(12.0, 90.0),
}

# Vowel formants (F1, F2, F3 in Hz), a touch low for big/deep voices.
const V_OO: Vector3 = Vector3(300.0, 870.0, 2240.0)
const V_OH: Vector3 = Vector3(450.0, 800.0, 2500.0)
const V_AA: Vector3 = Vector3(700.0, 1100.0, 2450.0)
const V_UH: Vector3 = Vector3(520.0, 1190.0, 2390.0)
const V_MM: Vector3 = Vector3(250.0, 1000.0, 2200.0)

## Milliseconds spent synthesizing everything in _ready (for profiling).
var generation_ms: float = 0.0

var _streams: Dictionary = {} # String -> AudioStreamWAV | Array[AudioStreamWAV]
var _info: Dictionary = {} # String -> {unit, max, bus, vary}
var _warned: Dictionary = {}
var _rt_rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _root3d: Node3D
var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _stamp3d: PackedInt64Array = PackedInt64Array()
var _stamp2d: PackedInt64Array = PackedInt64Array()
var _serial: int = 0

var _wind_player: AudioStreamPlayer
var _cricket_player: AudioStreamPlayer
var _wind_target: float = 0.3
var _night_target: float = 0.0
var _wind_cur: float = 0.3
var _night_cur: float = 0.0
var _hint: Vector3 = Vector3.ZERO
var _bird_timer: float = 3.0

# Synthesis-rate state (see the "Rate note" below): _div is 1 (22.05 kHz) or 2 (11.025 kHz).
var _div: int = 1
var _rate: float = 22050.0
var _dt: float = 1.0 / 22050.0


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func play(sound: String, pos: Variant = null, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream: AudioStream = _resolve(sound)
	if stream == null:
		return
	var info: Dictionary = _info[sound]
	var p: float = _final_pitch(info, pitch)
	if pos is Vector3:
		var where: Vector3 = pos
		var idx: int = _acquire_3d()
		var pl: AudioStreamPlayer3D = _pool3d[idx]
		_apply_3d(pl, info, stream, vol_db, p)
		pl.global_position = where
		pl.play()
	else:
		var idx2: int = _acquire_2d()
		var pl2: AudioStreamPlayer = _pool2d[idx2]
		pl2.stream = stream
		pl2.bus = info["bus"]
		pl2.volume_db = vol_db
		pl2.pitch_scale = p
		pl2.play()


func play_attached(sound: String, node: Node3D, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	var stream: AudioStream = _resolve(sound)
	if stream == null:
		return
	var info: Dictionary = _info[sound]
	var pl: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	_apply_3d(pl, info, stream, vol_db, _final_pitch(info, pitch))
	pl.finished.connect(pl.queue_free)
	node.add_child(pl)
	pl.play()


func set_ambience(wind: float, night: float) -> void:
	_wind_target = clampf(wind, 0.0, 1.0)
	_night_target = clampf(night, 0.0, 1.0)


func set_listener_hint(pos: Vector3) -> void:
	_hint = pos


func has_sound(sound: String) -> bool:
	return _streams.has(sound)


## Extra helpers (used by tests and tools).
func get_sound_names() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for k: String in _streams.keys():
		out.append(k)
	out.sort()
	return out


func get_stream(sound: String) -> AudioStream:
	var s: Variant = _streams.get(sound)
	if s is Array:
		var arr: Array = s
		return arr[0]
	return s


func get_variants(sound: String) -> Array:
	var s: Variant = _streams.get(sound)
	if s is Array:
		return s
	if s == null:
		return []
	return [s]


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rt_rng.randomize()
	_setup_buses()
	var t0: int = Time.get_ticks_usec()
	_generate_all()
	generation_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	_build_pools()
	_build_loops()


func _process(delta: float) -> void:
	var k: float = 1.0 - exp(-delta / AMB_SMOOTH_S)
	_wind_cur += (_wind_target - _wind_cur) * k
	_night_cur += (_night_target - _night_cur) * k
	_update_loop(_wind_player, linear_to_db(lerpf(0.1, 1.0, _wind_cur)) + WIND_TRIM_DB, true)
	var cricket_lin: float = pow(_night_cur, 1.5)
	_update_loop(_cricket_player, linear_to_db(maxf(cricket_lin, 0.0001)) + CRICKET_TRIM_DB, cricket_lin > 0.01)
	# Daytime songbirds: random chirps around the listener, rarer at night / in strong wind.
	_bird_timer -= delta
	if _bird_timer <= 0.0:
		_bird_timer = _rt_rng.randf_range(2.2, 6.5)
		var chance: float = clampf(1.0 - _night_cur * 1.25, 0.0, 1.0) * (1.0 - 0.5 * _wind_cur)
		if _rt_rng.randf() < chance:
			var ang: float = _rt_rng.randf() * TAU
			var dist: float = _rt_rng.randf_range(10.0, 40.0)
			var spot: Vector3 = _hint + Vector3(cos(ang) * dist, _rt_rng.randf_range(2.0, 10.0), sin(ang) * dist)
			play("chirp", spot, _rt_rng.randf_range(-4.0, 1.0), _rt_rng.randf_range(0.85, 1.25))


func _update_loop(player: AudioStreamPlayer, db: float, audible: bool) -> void:
	if player == null:
		return
	if audible:
		player.volume_db = db
		if not player.playing:
			player.play()
	elif player.playing:
		player.stop()


# ---------------------------------------------------------------------------
# Buses, pools, playback plumbing
# ---------------------------------------------------------------------------

func _ensure_bus(bus_name: StringName) -> int:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, String(bus_name))
		AudioServer.set_bus_send(idx, BUS_MASTER)
	return idx


func _bus_has_effect(idx: int, kind: String) -> bool:
	for e in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, e).get_class() == kind:
			return true
	return false


func _setup_buses() -> void:
	var sfx_idx: int = _ensure_bus(BUS_SFX)
	_ensure_bus(BUS_AMB)
	_ensure_bus(BUS_UI)
	if not _bus_has_effect(sfx_idx, "AudioEffectReverb"):
		var rev: AudioEffectReverb = AudioEffectReverb.new()
		rev.room_size = 0.6
		rev.damping = 0.65
		rev.spread = 1.0
		rev.predelay_msec = 35.0
		rev.predelay_feedback = 0.2
		rev.hipass = 0.08
		rev.dry = 1.0
		rev.wet = 0.12
		AudioServer.add_bus_effect(sfx_idx, rev)
	var master_idx: int = AudioServer.get_bus_index(BUS_MASTER)
	if master_idx >= 0 and not _bus_has_effect(master_idx, "AudioEffectHardLimiter"):
		var lim: AudioEffectHardLimiter = AudioEffectHardLimiter.new()
		lim.pre_gain_db = 0.0
		lim.ceiling_db = -1.0
		lim.release = 0.1
		AudioServer.add_bus_effect(master_idx, lim)


func _build_pools() -> void:
	_root3d = Node3D.new()
	_root3d.name = "Voices3D"
	add_child(_root3d)
	for _i in POOL_3D:
		var p3: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		p3.max_polyphony = 1
		_root3d.add_child(p3)
		_pool3d.append(p3)
		_stamp3d.append(0)
	for _i in POOL_2D:
		var p2: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(p2)
		_pool2d.append(p2)
		_stamp2d.append(0)


func _build_loops() -> void:
	_wind_player = AudioStreamPlayer.new()
	_wind_player.stream = _streams["amb_wind"]
	_wind_player.bus = BUS_AMB
	_wind_player.volume_db = -60.0
	add_child(_wind_player)
	_cricket_player = AudioStreamPlayer.new()
	_cricket_player.stream = _streams["amb_crickets"]
	_cricket_player.bus = BUS_AMB
	_cricket_player.volume_db = -60.0
	add_child(_cricket_player)


func _acquire_3d() -> int:
	var idx: int = -1
	var oldest: int = 0
	for i in _pool3d.size():
		if not _pool3d[i].playing:
			idx = i
			break
		if _stamp3d[i] < _stamp3d[oldest]:
			oldest = i
	if idx < 0:
		idx = oldest
		_pool3d[idx].stop()
	_serial += 1
	_stamp3d[idx] = _serial
	return idx


func _acquire_2d() -> int:
	var idx: int = -1
	var oldest: int = 0
	for i in _pool2d.size():
		if not _pool2d[i].playing:
			idx = i
			break
		if _stamp2d[i] < _stamp2d[oldest]:
			oldest = i
	if idx < 0:
		idx = oldest
		_pool2d[idx].stop()
	_serial += 1
	_stamp2d[idx] = _serial
	return idx


func _apply_3d(pl: AudioStreamPlayer3D, info: Dictionary, stream: AudioStream, vol_db: float, pitch: float) -> void:
	pl.stream = stream
	pl.bus = info["bus"]
	pl.volume_db = vol_db
	pl.pitch_scale = pitch
	pl.unit_size = info["unit"]
	pl.max_distance = info["max"]
	pl.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE


func _final_pitch(info: Dictionary, pitch: float) -> float:
	var p: float = pitch
	if info["vary"]:
		p *= 1.0 + _rt_rng.randf_range(-0.04, 0.04)
	return maxf(p, 0.05)


func _resolve(sound: String) -> AudioStream:
	var s: Variant = _streams.get(sound)
	if s == null:
		if not _warned.has(sound):
			_warned[sound] = true
			push_warning("Sfx: unknown sound '%s'" % sound)
		return null
	if s is Array:
		var arr: Array = s
		return arr[_rt_rng.randi() % arr.size()]
	return s


func _register(sound: String, stream: Variant) -> void:
	_streams[sound] = stream
	var sp: Vector2 = SPATIAL.get(sound, SPATIAL_DEFAULT)
	var bus: StringName = BUS_SFX
	if sound.begins_with("ui_"):
		bus = BUS_UI
	elif sound.begins_with("amb_") or sound == "chirp":
		bus = BUS_AMB
	_info[sound] = {"unit": sp.x, "max": sp.y, "bus": bus, "vary": not sound.begins_with("ui_")}


# ---------------------------------------------------------------------------
# Synthesis: the sound bank
#
# Rate note: generators that only contain low-frequency material start with
# _set_div(2) and are synthesized at 11.025 kHz; _wav()/_wav_loop() then
# upsample them 2x (4-tap interpolation) to the stream's 22.05 kHz and reset the
# divisor. Everything else is synthesized directly at 22.05 kHz.
# ---------------------------------------------------------------------------

func _generate_all() -> void:
	_register("beast_step", _gen_beast_step())
	_register("beast_moan", _gen_beast_moan())
	_register("beast_happy", _gen_beast_happy())
	_register("beast_grumble", _gen_beast_grumble())
	_register("beast_sneeze_in", _gen_beast_sneeze_in())
	_register("beast_sneeze", _gen_beast_sneeze())
	_register("beast_chomp", _gen_beast_chomp())
	_register("beast_gulp", _gen_beast_gulp())
	_register("step_soft", _gen_step_soft())
	_register("jump", _gen_jump())
	_register("land", _gen_land())
	_register("splat", _gen_splat())
	_register("pickup", _gen_pickup())
	_register("throw", _gen_throw())
	_register("bonk", _gen_bonk())
	_register("fruit_drop", _gen_fruit_drop())
	_register("whistle", _gen_whistle())
	_register("bell", _gen_bell())
	_register("creak", _gen_creak())
	_register("rustle", _gen_rustle())
	_register("munch", _gen_munch())
	_register("ui_click", _gen_ui_click())
	_register("ui_hover", _gen_ui_hover())
	_register("chirp", [_gen_chirp(0), _gen_chirp(1), _gen_chirp(2)])
	_register("spit", _gen_spit())
	_register("tumble", _gen_tumble())
	_register("amb_wind", _gen_wind())
	_register("amb_crickets", _gen_crickets())


func _gen_beast_step() -> AudioStreamWAV:
	_set_div(2)
	var rng: RandomNumberGenerator = _rng("beast_step")
	var n: int = _n(1.4)
	# Sub sweep 70 -> 28 Hz, soft-saturated so small speakers still get the thump.
	var f: PackedFloat32Array = _curve(n, PackedFloat32Array([0.0, 70.0, 0.6, 28.0, 1.4, 26.0]), true)
	var out: PackedFloat32Array = _osc_sine(f)
	_apply_exp(out, 0.012, 0.24)
	_sat(out, 3.0)
	# Toe-down: a second, softer settling thump.
	_add(out, _hit(0.9, 52.0, 30.0, 0.15, 0.2, 0.01), 0.2, 0.4)
	# Low-passed body thump (80 ms).
	var thump: PackedFloat32Array = _lp(_white(_n(0.1), rng), 250.0, 2)
	_apply_exp(thump, 0.004, 0.045)
	_add_pk(out, thump, 0.0, 2.5)
	# Faint gravel crunch (2-4 kHz, 150 ms).
	var gravel: PackedFloat32Array = _bp(_white(_n(0.15), rng), 3000.0, 0.9)
	_apply_exp(gravel, 0.004, 0.045)
	_add_pk(out, gravel, 0.03, 0.12)
	return _wav(out, -3.0, 6.0, 20.0)


func _gen_beast_moan() -> AudioStreamWAV:
	_set_div(2)
	var rng: RandomNumberGenerator = _rng("beast_moan")
	var n: int = _n(2.6)
	var f0: PackedFloat32Array = _curve(n, PackedFloat32Array([0.0, 54.0, 0.55, 58.0, 1.25, 69.0, 1.75, 65.0, 2.6, 51.0]))
	_vib(f0, 4.0, 0.02, 0.5)
	# "oo" -> "aa" -> "oo" through three vocal formants.
	var keys: Array = [0.0, V_OO, 0.45, V_OO, 1.1, V_AA, 1.8, V_AA, 2.6, V_OO]
	var voiced: PackedFloat32Array = _voice(rng, f0, keys, Vector3(1.0, 0.65, 0.3), Vector3(3.0, 4.0, 6.0), 0.35, 1800.0, 0.92)
	var body: PackedFloat32Array = _stack(f0, PackedFloat32Array([1.0, 0.6, 0.35, 0.2, 0.1]))
	var out: PackedFloat32Array = _zeros(n)
	_add_pk(out, voiced, 0.0, 1.0)
	_add_pk(out, body, 0.0, 0.7)
	# Breathy layer: a puff at the start and a sigh at the end.
	var puff: PackedFloat32Array = _bp(_white(_n(0.6), rng), 700.0, 1.2)
	_apply_exp(puff, 0.01, 0.2)
	_add_pk(out, puff, 0.0, 0.14)
	var sigh: PackedFloat32Array = _bp(_white(_n(0.6), rng), 600.0, 1.2)
	_mulc(sigh, _cv(sigh.size(), PackedFloat32Array([0.0, 0.0, 0.25, 1.0, 0.6, 0.0]), false, true))
	_add_pk(out, sigh, 2.0, 0.1)
	_mulc(out, _cv(n, PackedFloat32Array([0.0, 0.0, 0.32, 0.85, 0.6, 1.0, 1.9, 0.9, 2.6, 0.0]), false, true))
	out = _lp(out, 3200.0)
	return _wav(out, -4.0, 8.0, 40.0)


func _gen_beast_happy() -> AudioStreamWAV:
	_set_div(2)
	var rng: RandomNumberGenerator = _rng("beast_happy")
	var n: int = _n(1.4)
	# "mmmMM?" - closed-mouth hum that lifts at the end.
	var f0: PackedFloat32Array = _curve(n, PackedFloat32Array([0.0, 59.0, 0.5, 62.0, 0.62, 66.0, 0.76, 75.0, 1.15, 90.0, 1.4, 86.0]))
	_vib(f0, 5.0, 0.012, 0.3)
	var keys: Array = [0.0, V_MM, 0.6, V_MM, 0.75, Vector3(330.0, 1050.0, 2250.0), 1.4, Vector3(300.0, 1000.0, 2200.0)]
	var voiced: PackedFloat32Array = _voice(rng, f0, keys, Vector3(1.0, 0.1, 0.03), Vector3(5.0, 5.0, 6.0), 0.08, 1100.0, 1.0)
	var body: PackedFloat32Array = _stack(f0, PackedFloat32Array([1.0, 0.5, 0.25, 0.1]))
	var out: PackedFloat32Array = _zeros(n)
	_add_pk(out, voiced, 0.0, 0.8)
	_add_pk(out, body, 0.0, 1.0)
	_mulc(out, _cv(n, PackedFloat32Array([0.0, 0.0, 0.08, 0.8, 0.3, 0.9, 0.52, 0.7, 0.6, 0.15, 0.68, 0.15, 0.78, 1.0, 1.1, 0.85, 1.4, 0.0]), false, true))
	out = _lp(out, 1600.0)
	return _wav(out, -5.0, 8.0, 40.0)


func _gen_beast_grumble() -> AudioStreamWAV:
	_set_div(2)
	var rng: RandomNumberGenerator = _rng("beast_grumble")
	var n: int = _n(1.8)
	var dt: float = _dt
	var noise: PackedFloat32Array = _white(n, rng)
	# Irregular slow LFO (three unrelated sines) shaping the rumble.
	var lfo: PackedFloat32Array = _zeros(n)
	for i in n:
		var t: float = float(i) * dt
		var x: float = 0.55 * sin(TAU * 1.3 * t + 1.0) + 0.35 * sin(TAU * 2.9 * t + 2.2) + 0.28 * sin(TAU * 4.7 * t + 0.3)
		var m: float = clampf(0.5 + 0.55 * x, 0.0, 1.0)
		lfo[i] = m * m
	var rumble: PackedFloat32Array = _lp(noise, 210.0, 2)
	_mul(rumble, lfo)
	var out: PackedFloat32Array = _zeros(n)
	_add_pk(out, rumble, 0.0, 1.0)
	# "Gloop" band riding the same LFO.
	var gloop: PackedFloat32Array = _bpc(noise, _cv(n, PackedFloat32Array([0.0, 300.0, 0.6, 520.0, 1.2, 340.0, 1.8, 450.0])), 3.0)
	_mul(gloop, lfo)
	_add_pk(out, gloop, 0.0, 0.4)
	# Wobbly ~40 Hz gurgles.
	for _g in 4:
		var st: float = rng.randf_range(0.05, 1.35)
		var gn: int = _n(rng.randf_range(0.18, 0.34))
		var f_a: float = rng.randf_range(48.0, 70.0)
		var f_b: float = f_a * rng.randf_range(0.55, 0.75)
		var gb: PackedFloat32Array = _zeros(gn)
		var ph: float = 0.0
		for i in gn:
			var u: float = float(i) / float(gn)
			var fr: float = lerpf(f_a, f_b, u) * (1.0 + 0.16 * sin(TAU * (16.0 + 6.0 * u) * float(i) * dt))
			ph += fr * dt
			gb[i] = sin(TAU * ph) * sin(PI * u)
		_sat(gb, 3.0)
		_add_pk(out, gb, st, 0.6)
	_mulc(out, _cv(n, PackedFloat32Array([0.0, 0.0, 0.15, 1.0, 1.3, 1.0, 1.8, 0.0])))
	out = _lp(out, 1200.0)
	return _wav(out, -4.0, 10.0, 40.0)


func _gen_beast_sneeze_in() -> AudioStreamWAV:
	_set_div(2)
	var rng: RandomNumberGenerator = _rng("beast_sneeze_in")
	var n: int = _n(1.2)
	var dt: float = _dt
	var noise: PackedFloat32Array = _white(n, rng)
	# Rising band center 400 -> 1600 Hz in two swells ("ahh-AHH").
	var fc: PackedFloat32Array = _cv(n, PackedFloat32Array([0.0, 400.0, 0.5, 1450.0, 0.55, 560.0, 1.2, 1750.0]), true)
	var fc2: PackedFloat32Array = fc.duplicate()
	for k in fc2.size():
		fc2[k] = fc[k] * 1.9
	var out: PackedFloat32Array = _zeros(n)
	_add_pk(out, _bpc(noise, fc, 2.2), 0.0, 1.0)
	_add_pk(out, _bpc(noise, fc2, 3.0), 0.0, 0.5)
	# Wheeze: a narrow, slightly whistly component.
	_add_pk(out, _bpc(noise, fc, 9.0), 0.0, 0.3)
	for i in n:
		var t: float = float(i) * dt
		var s1: float = 0.0
		if t > 0.02 and t < 0.52:
			s1 = sin(PI * (t - 0.02) / 0.5)
		var s2: float = 0.0
		if t > 0.56 and t < 1.18:
			s2 = sin(PI * (t - 0.56) / 0.62)
		out[i] *= (0.5 * s1 * s1 + s2 * s2) * (0.88 + 0.12 * sin(TAU * 24.0 * t))
	return _wav(out, -7.0, 10.0, 30.0)


func _gen_beast_sneeze() -> AudioStreamWAV:
	var rng: RandomNumberGenerator = _rng("beast_sneeze")
	var n: int = _n(1.0)
	var out: PackedFloat32Array = _zeros(n)
	# "ch": burst of hissy noise.
	var ch: PackedFloat32Array = _bp(_hp(_white(_n(0.14), rng), 1200.0), 3200.0, 0.9)
	_apply_exp(ch, 0.004, 0.035)
	_add_pk(out, ch, 0.0, 0.7)
	# "oo": explosive voiced vowel, pitch dropping.
	var vn: int = _n(0.75)
	var f0: PackedFloat32Array = _curve(vn, PackedFloat32Array([0.0, 105.0, 0.6, 70.0, 0.75, 66.0]), true)
	var keys: Array = [0.0, V_OH, 0.15, V_OO, 0.75, V_OO]
	var oo: PackedFloat32Array = _voice(rng, f0, keys, Vector3(1.0, 0.7, 0.3), Vector3(3.0, 4.0, 6.0), 0.3, 2000.0, 0.95)
	_apply_exp(oo, 0.02, 0.2)
	_add_pk(out, oo, 0.07, 1.0)
	# Low thump under the burst.
	_add(out, _hit(0.3, 95.0, 38.0, 0.06, 0.1, 0.004), 0.06, 0.55)
	# Breathy exhale tail.
	var tail: PackedFloat32Array = _bp(_white(_n(0.7), rng), 900.0, 1.2)
	_apply_exp(tail, 0.03, 0.25)
	_add_pk(out, tail, 0.2, 0.12)
	return _wav(out, -3.0, 5.0, 40.0)


func _gen_beast_chomp() -> AudioStreamWAV:
	var rng: RandomNumberGenerator = _rng("beast_chomp")
	var n: int = _n(0.5)
	var out: PackedFloat32Array = _zeros(n)
	var starts: Array = [0.01, 0.22]
	var sizes: Array = [1.0, 0.85]
	for k in 2:
		var t0: float = starts[k]
		var sz: float = sizes[k]
		var gr: PackedFloat32Array = _grains(n, rng, t0, 9, 0.06, 2.0, 9.0, 0.3)
		gr = _hp(_bp(gr, 2100.0, 0.7), 500.0)
		_add_pk(out, gr, 0.0, 0.8 * sz)
		_add(out, _hit(0.18, 135.0, 55.0, 0.025, 0.05, 0.003), t0, 0.9 * sz)
	return _wav(out, -4.0, 5.0, 25.0)


func _gen_beast_gulp() -> AudioStreamWAV:
	var rng: RandomNumberGenerator = _rng("beast_gulp")
	var n: int = _n(0.5)
	var out: PackedFloat32Array = _zeros(n)
	# Downward bubble 300 -> 90 Hz, with a smaller echo bubble.
	_add(out, _hit(0.34, 300.0, 90.0, 0.09, 0.12, 0.008), 0.0, 1.0)
	_add(out, _hit(0.2, 240.0, 110.0, 0.06, 0.07, 0.006), 0.2, 0.4)
	# "g" click, then the "k" pop with a little blip.
	var g: PackedFloat32Array = _bp(_white(_n(0.03), rng), 900.0, 5.0)
	_apply_exp(g, 0.001, 0.006)
	_add_pk(out, g, 0.0, 0.4)
	var k: PackedFloat32Array = _bp(_white(_n(0.05), rng), 1400.0, 4.0)
	_apply_exp(k, 0.001, 0.01)
	_add_pk(out, k, 0.33, 0.5)
	_add(out, _hit(0.08, 220.0, 130.0, 0.02, 0.025, 0.002), 0.33, 0.5)
	return _wav(out, -6.0, 5.0, 25.0)


func _gen_step_soft() -> AudioStreamWAV:
	var rng: RandomNumberGenerator = _rng("step_soft")
	var n: int = _n(0.12)
	var out: PackedFloat32Array = _lp(_white(n, rng), 1400.0, 2)
	_apply_exp(out, 0.002, 0.022)
	out = _norm(out, 1.0)
	_add(out, _hit(0.1, 110.0, 70.0, 0.02, 0.025, 0.002), 0.0, 0.5)
	var swish: PackedFloat32Array = _bp(_white(n, rng), 4000.0, 1.0)
	_apply_exp(swish, 0.004, 0.03)
	_add_pk(out, swish, 0.0, 0.08)
	return _wav(out, -17.0, 5.0, 25.0)


func _gen_jump() -> AudioStreamWAV:
	var rng: RandomNumberGenerator = _rng("jump")
	var n: int = _n(0.18)
	var f0: PackedFloat32Array = _curve(n, PackedFloat32Array([0.0, 340.0, 0.12, 450.0, 0.18, 440.0]))
	var keys: Array = [0.0, Vector3(400.0, 1100.0, 2400.0), 0.1, V_UH, 0.18, V_UH]
	var v: PackedFloat32Array = _voice(rng, f0, keys, Vector3(1.0, 0.7, 0.3), Vector3(4.0, 5.0, 6.0), 0.0, 3500.0, 1.0)
	_mulc(v, _cv(n, PackedFloat32Array([0.0, 0.0, 0.012, 1.0, 0.09, 0.8, 0.15, 0.3, 0.18, 0.0])))
	var out: PackedFloat32Array = _zeros(n)
	_add_pk(out, v, 0.0, 1.0)
	# Air: the "h" at the start and a tiny "p" at the end.
	var air: PackedFloat32Array = _hp(_white(n, rng), 1800.0)
	_apply_exp(air, 0.004, 0.03)
	_add_pk(out, air, 0.0, 0.3)
	var pf: PackedFloat32Array = _hp(_white(_n(0.03), rng), 1500.0)
	_apply_exp(pf, 0.002, 0.008)
	_add_pk(out, pf, 0.145, 0.1)
	return _wav(out, -9.0, 5.0, 25.0)


func _gen_land() -> AudioStreamWAV:
	var rng: RandomNumberGenerator = _rng("land")
	var n: int = _n(0.2)
	var out: PackedFloat32Array = _hit(0.2, 110.0, 55.0, 0.035, 0.05, 0.003)
	var nz: PackedFloat32Array = _lp(_white(n, rng), 500.0, 2)
	_apply_exp(nz, 0.003, 0.02)
	_add_pk(out, nz, 0.0, 0.5)
	return _wav(out, -11.0, 5.0, 30.0)


func _gen_splat() -> AudioStreamWAV:
	var rng: RandomNumberGenerator = _rng("splat")
	var n: int = _n(0.45)
	var dt: float = _dt
	var out: PackedFloat32Array = _zeros(n)
	_add(out, _hit(0.3, 120.0, 45.0, 0.04, 0.07, 0.003), 0.0, 1.0)
	var nz: PackedFloat32Array = _lp(_white(_n(0.1), rng), 350.0, 2)
	_apply_exp(nz, 0.002, 0.03)
	_add_pk(out, nz, 0.0, 0.6)
	# Squelch: resonant band sweeping down with a wet ripple.
	var sn: int = _n(0.32)
	var sq: PackedFloat32Array = _bpc(_white(sn, rng), _cv(sn, PackedFloat32Array([0.0, 1800.0, 0.05, 1500.0, 0.3, 300.0]), true), 6.0)
	_apply_exp(sq, 0.004, 0.1)
	for i in sn:
		sq[i] *= 0.6 + 0.4 * sin(TAU * 38.0 * float(i) * dt)
	_add_pk(out, sq, 0.03, 0.7)
	# Little wet bubbles.
	_add(out, _hit(0.06, 520.0, 760.0, 0.02, 0.02, 0.002), 0.12, 0.3)
	_add(out, _hit(0.06, 430.0, 640.0, 0.02, 0.02, 0.002), 0.2, 0.28)
	_add(out, _hit(0.06, 600.0, 880.0, 0.02, 0.02, 0.002), 0.29, 0.25)
	return _wav(out, -7.0, 5.0, 30.0)


func _gen_pickup() -> AudioStreamWAV:
	var out: PackedFloat32Array = _hit(0.12, 500.0, 900.0, 0.03, 0.05, 0.003)
	_add(out, _hit(0.12, 1000.0, 1800.0, 0.03, 0.035, 0.003), 0.0, 0.18)
	return _wav(out, -10.0, 5.0, 25.0)


func _gen_throw() -> AudioStreamWAV:
	var rng: RandomNumberGenerator = _rng("throw")
	var n: int = _n(0.35)
	var noise: PackedFloat32Array = _white(n, rng)
	var fc: PackedFloat32Array = _cv(n, PackedFloat32Array([0.0, 400.0, 0.14, 1800.0, 0.35, 600.0]), true)
	var out: PackedFloat32Array = _zeros(n)
	_add_pk(out, _bpc(noise, fc, 1.6), 0.0, 1.0)
	_add_pk(out, _bp(noise, 250.0, 1.0), 0.0, 0.3)
	for i in n:
		var s: float = sin(PI * float(i) / float(n))
		out[i] *= s * s
	return _wav(out, -10.0, 8.0, 30.0)


func _gen_bonk() -> AudioStreamWAV:
	var rng: RandomNumberGenerator = _rng("bonk")
	var out: PackedFloat32Array = _hit(0.35, 690.0, 600.0, 0.03, 0.07, 0.0008)
	_add(out, _hit(0.35, 1750.0, 1520.0, 0.03, 0.04, 0.0008), 0.0, 0.6)
	_add(out, _hit(0.2, 330.0, 290.0, 0.03, 0.05, 0.001), 0.0, 0.45)
	var click: PackedFloat32Array = _bp(_white(_n(0.02), rng), 2500.0, 1.5)
	_apply_exp(click, 0.0005, 0.004)
	_add_pk(out, click, 0.0, 0.4)
	out = _lp(out, 6500.0)
	return _wav(out, -6.0, 5.0, 40.0)


func _gen_fruit_drop() -> AudioStreamWAV:
	var rng: RandomNumberGenerator = _rng("fruit_drop")
	var n: int = _n(0.25)
	var out: PackedFloat32Array = _hit(0.25, 150.0, 68.0, 0.03, 0.06, 0.003)
	var nz: PackedFloat32Array = _lp(_white(n, rng), 600.0, 2)
	_apply_exp(nz, 0.003, 0.03)
	_add_pk(out, nz, 0.0, 0.5)
	var leaf: PackedFloat32Array = _hp(_white(_n(0.1), rng), 3000.0)
	_apply_exp(leaf, 0.01, 0.03)
	_add_pk(out, leaf, 0.03, 0.06)
	return _wav(out, -12.0, 5.0, 40.0)


func _gen_whistle() -> AudioStreamWAV:
	var rng: RandomNumberGenerator = _rng("whistle")
	var n: int = _n(0.8)
	var dt: float = _dt
	# Two notes a major third apart (880 -> 1109 Hz), scooping up into each.
	var f: PackedFloat32Array = _curve(n, PackedFloat32Array([0.0, 805.0, 0.05, 880.0, 0.33, 880.0, 0.37, 985.0, 0.43, 1109.0, 0.8, 1100.0]))
	_vib(f, 5.5, 0.006, 0.12)
	var out: PackedFloat32Array = _zeros(n)
	var ph: float = 0.0
	for i in n:
		ph += f[i] * dt
		var w: float = TAU * ph
		out[i] = sin(w) + 0.06 * sin(2.0 * w) + 0.02 * sin(3.0 * w)
	# Breath hiss riding an octave above the note.
	var breath_fc: PackedFloat32Array = _decim(f)
	for k in breath_fc.size():
		breath_fc[k] *= 2.0
	_add_pk(out, _bpc(_white(n, rng), breath_fc, 6.0), 0.0, 0.07)
	_mulc(out, _cv(n, PackedFloat32Array([0.0, 0.0, 0.03, 0.9, 0.1, 1.0, 0.31, 0.9, 0.345, 0.0, 0.37, 0.2, 0.4, 0.85, 0.5, 1.0, 0.7, 0.8, 0.8, 0.0]), false, true))
	return _wav(out, -8.0, 8.0, 40.0)


func _gen_bell() -> AudioStreamWAV:
	_set_div(2)
	var rng: RandomNumberGenerator = _rng("bell")
	var n: int = _n(4.5)
	var dt: float = _dt
	var out: PackedFloat32Array = _zeros(n)
	var fund: float = 180.0
	# [ratio, amplitude, decay tau (s)] - inharmonic bronze partials, plus detuned
	# twins on a few of them so the ring slowly beats.
	var partials: Array = [
		[0.5, 0.55, 2.4], [1.0, 1.0, 2.0], [1.004, 0.5, 1.8], [1.19, 0.5, 1.5], [1.56, 0.35, 1.2],
		[2.0, 0.35, 1.0], [2.003, 0.2, 0.9], [2.66, 0.18, 0.6], [3.01, 0.12, 0.45],
		[4.07, 0.2, 0.5], [5.43, 0.12, 0.35], [6.8, 0.07, 0.25],
	]
	for p: Array in partials:
		var freq: float = fund * float(p[0])
		var amp: float = float(p[1])
		var r: float = exp(-dt / float(p[2])) # per-sample decay
		var pn: int = mini(n, int(float(p[2]) * 6.2 * _rate)) # stop once ~-54 dB down
		var w: float = TAU * freq * dt
		var phase0: float = rng.randf() * TAU
		# Damped resonator: y[i+2] = 2 r cos(w) y[i+1] - r^2 y[i] gives amp * r^i * sin(w i + phase0).
		var c1: float = 2.0 * r * cos(w)
		var c2: float = r * r
		var y0: float = amp * sin(phase0)
		var y1: float = amp * r * sin(w + phase0)
		for i in pn:
			out[i] += y0
			var y2: float = c1 * y1 - c2 * y0
			y0 = y1
			y1 = y2
	# Shared 4 ms mallet attack.
	var na: int = int(0.004 * _rate)
	for i in na:
		out[i] *= 0.5 - 0.5 * cos(PI * float(i) / float(na))
	# Soft mallet strike.
	var strike: PackedFloat32Array = _bp(_white(_n(0.06), rng), 1800.0, 1.0)
	_apply_exp(strike, 0.001, 0.012)
	_add_pk(out, strike, 0.0, 0.6)
	return _wav(out, -5.0, 5.0, 700.0)


func _gen_creak() -> AudioStreamWAV:
	var rng: RandomNumberGenerator = _rng("creak")
	var n: int = _n(0.6)
	var dt: float = _dt
	# Stick-slip pulse train, 80-140 Hz with jitter.
	var rate_pts: PackedFloat32Array = PackedFloat32Array()
	var t: float = 0.0
	while t <= 0.6:
		rate_pts.append(t)
		rate_pts.append(rng.randf_range(80.0, 140.0))
		t += 0.06
	var rate: PackedFloat32Array = _curve(n, rate_pts)
	var pulses: PackedFloat32Array = _zeros(n)
	var ph: float = 0.0
	var jit: float = 0.0
	for i in n:
		ph += rate[i] * (1.0 + jit) * dt
		if ph >= 1.0:
			ph -= 1.0
			jit = rng.randf_range(-0.18, 0.18)
			var a: float = rng.randf_range(0.5, 1.0)
			pulses[i] = a
			if i + 1 < n:
				pulses[i + 1] = -0.5 * a
	var fc: PackedFloat32Array = _cv(n, PackedFloat32Array([0.0, 620.0, 0.2, 760.0, 0.4, 700.0, 0.6, 820.0]))
	var out: PackedFloat32Array = _zeros(n)
	_add_pk(out, _bpc(pulses, fc, 7.0), 0.0, 1.0)
	_add_pk(out, _bp(pulses, 1500.0, 8.0), 0.0, 0.35)
	_add_pk(out, _bp(_white(n, rng), 700.0, 5.0), 0.0, 0.08)
	_mulc(out, _cv(n, PackedFloat32Array([0.0, 0.0, 0.06, 0.8, 0.15, 1.0, 0.45, 0.9, 0.6, 0.0])))
	out = _lp(out, 4000.0)
	return _wav(out, -10.0, 8.0, 40.0)


func _gen_rustle() -> AudioStreamWAV:
	var rng: RandomNumberGenerator = _rng("rustle")
	var n: int = _n(0.7)
	var gr: PackedFloat32Array = _zeros(n)
	var placed: int = 0
	while placed < 75:
		var t: float = rng.randf() * 0.66
		# More leaves in the middle of the shake.
		var dens: float = 0.3 + 0.7 * sin(PI * t / 0.66)
		if rng.randf() > dens:
			continue
		placed += 1
		var s: int = int(t * _rate)
		var glen: int = maxi(2, int(rng.randf_range(3.0, 14.0) * 0.001 * _rate))
		var amp: float = rng.randf_range(0.15, 1.0)
		for k in glen:
			var j: int = s + k
			if j >= n:
				break
			var w: float = 1.0 - float(k) / float(glen)
			gr[j] += (rng.randf() * 2.0 - 1.0) * amp * w * w
	var out: PackedFloat32Array = _hp(_lp(gr, 5500.0, 2), 1600.0)
	_mulc(out, _cv(n, PackedFloat32Array([0.0, 0.0, 0.05, 0.9, 0.45, 1.0, 0.7, 0.0])))
	return _wav(out, -12.0, 8.0, 40.0)


func _gen_munch() -> AudioStreamWAV:
	var rng: RandomNumberGenerator = _rng("munch")
	var n: int = _n(0.25)
	var out: PackedFloat32Array = _zeros(n)
	var starts: Array = [0.0, 0.085, 0.165]
	for k in 3:
		var t0: float = starts[k]
		var gr: PackedFloat32Array = _grains(n, rng, t0, 4, 0.02, 2.0, 6.0, 0.4)
		gr = _bp(gr, 2400.0, 0.9)
		_add_pk(out, gr, 0.0, 0.8)
		_add(out, _hit(0.05, 260.0, 170.0, 0.012, 0.02, 0.002), t0, 0.5)
	return _wav(out, -11.0, 5.0, 30.0)


func _gen_ui_click() -> AudioStreamWAV:
	var rng: RandomNumberGenerator = _rng("ui_click")
	var out: PackedFloat32Array = _hit(0.06, 1180.0, 980.0, 0.01, 0.012, 0.0006)
	_add(out, _hit(0.06, 2650.0, 2400.0, 0.01, 0.008, 0.0005), 0.0, 0.4)
	var click: PackedFloat32Array = _bp(_white(_n(0.01), rng), 2200.0, 1.2)
	_apply_exp(click, 0.0003, 0.002)
	_add_pk(out, click, 0.0, 0.25)
	return _wav(out, -13.0, 5.0, 15.0)


func _gen_ui_hover() -> AudioStreamWAV:
	var rng: RandomNumberGenerator = _rng("ui_hover")
	var n: int = _n(0.04)
	var out: PackedFloat32Array = _lp(_white(n, rng), 1600.0, 2)
	_apply_exp(out, 0.001, 0.007)
	out = _norm(out, 1.0)
	_add(out, _hit(0.04, 520.0, 440.0, 0.01, 0.01, 0.001), 0.0, 0.5)
	return _wav(out, -22.0, 5.0, 12.0)


func _gen_chirp(variant: int) -> AudioStreamWAV:
	var rng: RandomNumberGenerator = _rng("chirp_%d" % variant)
	var syllables: int = 3 + variant
	var out: PackedFloat32Array = _zeros(_n(0.9))
	var base: float = rng.randf_range(2000.0, 2800.0)
	var d_min: float = [0.08, 0.06, 0.045][variant]
	var d_max: float = [0.13, 0.1, 0.075][variant]
	var t: float = 0.015
	var t_end: float = t
	for _s in syllables:
		var kind: int = rng.randi_range(0, 4)
		var dur: float = rng.randf_range(d_min, d_max)
		var sn: int = _n(dur)
		var f_a: float = base * rng.randf_range(0.9, 1.1)
		var pts: PackedFloat32Array
		var ratio: float = 2.0
		match kind:
			0: # up-sweep "tweet"
				pts = PackedFloat32Array([0.0, f_a, dur, f_a * rng.randf_range(1.2, 1.4)])
			1: # down-sweep
				pts = PackedFloat32Array([0.0, f_a * 1.35, dur, f_a * rng.randf_range(0.8, 0.95)])
			2: # arch
				pts = PackedFloat32Array([0.0, f_a, dur * 0.5, f_a * 1.4, dur, f_a * 1.05])
			3: # trill: fast wobble on a held pitch
				pts = PackedFloat32Array([0.0, f_a * 1.1, dur, f_a * 1.15])
				ratio = 3.0
			_: # flat blip with a tiny drop
				pts = PackedFloat32Array([0.0, f_a * 1.2, dur, f_a * 1.12])
		var fc: PackedFloat32Array = _curve(sn, pts, true)
		if kind == 3:
			_vib(fc, 52.0, 0.09, 0.001)
		var idx: PackedFloat32Array = _curve(sn, PackedFloat32Array([0.0, 0.9, dur, 0.25]))
		var syl: PackedFloat32Array = _fm(fc, ratio, idx)
		for i in sn:
			var w: float = sin(PI * float(i) / float(sn))
			syl[i] *= sqrt(w) * w
		_add(out, syl, t, 1.0)
		t_end = t + dur
		t += dur + rng.randf_range(0.025, 0.065)
	out.resize(mini(out.size(), _n(t_end + 0.03)))
	return _wav(out, -13.0, 5.0, 25.0)


func _gen_spit() -> AudioStreamWAV:
	var rng: RandomNumberGenerator = _rng("spit")
	var n: int = _n(0.4)
	var out: PackedFloat32Array = _zeros(n)
	# "p"
	var pp: PackedFloat32Array = _lp(_white(_n(0.04), rng), 900.0, 1)
	_apply_exp(pp, 0.001, 0.01)
	_add_pk(out, pp, 0.0, 0.45)
	_add(out, _hit(0.05, 180.0, 110.0, 0.015, 0.02, 0.002), 0.0, 0.3)
	# "t"
	var tt: PackedFloat32Array = _bp(_white(_n(0.03), rng), 3500.0, 1.2)
	_apply_exp(tt, 0.001, 0.006)
	_add_pk(out, tt, 0.03, 0.5)
	# "oo": whispered vowel with a faint voiced core, plus spray.
	var vn: int = _n(0.3)
	var f0: PackedFloat32Array = _curve(vn, PackedFloat32Array([0.0, 220.0, 0.3, 150.0]), true)
	var keys: Array = [0.0, V_OO, 0.3, V_OH]
	var oo: PackedFloat32Array = _voice(rng, f0, keys, Vector3(1.0, 0.7, 0.3), Vector3(3.0, 4.0, 6.0), 1.2, 3000.0, 1.0)
	_apply_exp(oo, 0.015, 0.09)
	_add_pk(out, oo, 0.05, 0.8)
	var spray: PackedFloat32Array = _hp(_white(_n(0.25), rng), 2000.0)
	_apply_exp(spray, 0.01, 0.08)
	_add_pk(out, spray, 0.04, 0.25)
	# Comic droplets.
	_add(out, _hit(0.05, 700.0, 1100.0, 0.015, 0.012, 0.002), 0.22, 0.22)
	_add(out, _hit(0.05, 600.0, 950.0, 0.015, 0.012, 0.002), 0.29, 0.18)
	return _wav(out, -9.0, 5.0, 40.0)


func _gen_tumble() -> AudioStreamWAV:
	var rng: RandomNumberGenerator = _rng("tumble")
	var n: int = _n(0.35)
	# "whoa": falling, wobbly, cartoon voice.
	var f0: PackedFloat32Array = _curve(n, PackedFloat32Array([0.0, 330.0, 0.35, 170.0]), true)
	_vib(f0, 9.0, 0.035, 0.1)
	var keys: Array = [0.0, V_OO, 0.1, V_OH, 0.35, V_AA]
	var v: PackedFloat32Array = _voice(rng, f0, keys, Vector3(1.0, 0.7, 0.3), Vector3(4.0, 5.0, 6.0), 0.04, 3200.0, 1.0)
	_mulc(v, _cv(n, PackedFloat32Array([0.0, 0.0, 0.015, 1.0, 0.25, 0.85, 0.35, 0.0])))
	return _wav(v, -8.0, 6.0, 50.0)


func _gen_wind() -> AudioStreamWAV:
	_set_div(2)
	var rng: RandomNumberGenerator = _rng("amb_wind")
	var loop_n: int = _n(6.0)
	var warm: int = _n(0.15)
	var total: int = warm + loop_n + _n(0.8)
	var dt: float = _dt
	# Gust shape / filter motion are periodic over the 6 s loop (control-rate arrays);
	# only the noise carrier is random, and the loop seam is crossfaded.
	var nb: int = (total >> 4) + 2
	var ampc: PackedFloat32Array = _zeros(nb)
	var fc1: PackedFloat32Array = _zeros(nb)
	var fc2: PackedFloat32Array = _zeros(nb)
	for k in nb:
		var t: float = float((k << 4) - warm) * dt
		var w: float = TAU * t / 6.0
		var g: float = clampf(0.5 + 0.3 * sin(w + 0.6) + 0.16 * sin(2.0 * w + 2.1) + 0.08 * sin(3.0 * w + 4.0), 0.0, 1.0)
		ampc[k] = 0.25 + 0.75 * g * g
		fc1[k] = 200.0 + 600.0 * g + 60.0 * sin(5.0 * w + 1.0)
		fc2[k] = 1700.0 + 700.0 * sin(2.0 * w + 0.5)
	var pink: PackedFloat32Array = _pink(total, rng)
	_mulc(pink, ampc) # gusts swell the carrier...
	var body: PackedFloat32Array = _svf(pink, fc1, 0.9, WIND_BODY) # ...and a bandpass that brightens with them
	var air: PackedFloat32Array = _svf(pink, fc2, 3.5, WIND_AIR) # leafy hiss
	var rumble: PackedFloat32Array = _lp(pink, 130.0)
	var raw: PackedFloat32Array = _zeros(total)
	for i in total:
		raw[i] = body[i] + air[i] + rumble[i] * WIND_RUMBLE
	return _wav_loop(_loopify(raw, warm, loop_n), -10.0)


func _gen_crickets() -> AudioStreamWAV:
	var rng: RandomNumberGenerator = _rng("amb_crickets")
	var n: int = _n(4.0)
	var dt: float = _dt
	var out: PackedFloat32Array = _zeros(n)
	# [carrier Hz, level, pulse period s]
	var voices: Array = [[4350.0, 1.0, 0.043], [4620.0, 0.75, 0.039], [4880.0, 0.55, 0.047], [4150.0, 0.45, 0.041]]
	for v: Array in voices:
		var fc: float = float(v[0])
		var level: float = float(v[1])
		var period: float = float(v[2])
		var t: float = rng.randf() * 0.5
		while t < 4.0:
			var pulses: int = rng.randi_range(3, 5)
			var amp_g: float = rng.randf_range(0.6, 1.0) * level
			for p in pulses:
				var start: int = int((t + float(p) * period) * _rate)
				var pn: int = int(rng.randf_range(0.016, 0.022) * _rate)
				var f: float = fc * rng.randf_range(0.99, 1.01)
				for i in pn:
					var w: float = sin(PI * float(i) / float(pn))
					# Wraps around the end so the loop is seamless.
					out[(start + i) % n] += sin(TAU * f * float(i) * dt) * w * w * amp_g
			t += float(pulses) * period + rng.randf_range(0.18, 0.45)
	return _wav_loop(out, -16.0)


# ---------------------------------------------------------------------------
# DSP helpers (whole-buffer, PackedFloat32Array in / out)
#
# "Control-rate" curves (_cv) hold one value per 16 samples; _mulc / _svf read
# them with the index (i >> 4). "Full-rate" curves (_curve) hold one per sample.
# ---------------------------------------------------------------------------

func _set_div(d: int) -> void:
	_div = d
	_rate = SRF / float(d)
	_dt = float(d) * ISR


func _rng(sound: String) -> RandomNumberGenerator:
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = sound.hash() ^ SEED_BASE
	return r


func _n(seconds: float) -> int:
	return maxi(1, int(round(seconds * _rate)))


func _zeros(n: int) -> PackedFloat32Array:
	var b: PackedFloat32Array = PackedFloat32Array()
	b.resize(n)
	return b


func _peak(b: PackedFloat32Array) -> float:
	var pk: float = 0.0
	for i in b.size():
		var v: float = absf(b[i])
		if v > pk:
			pk = v
	return pk


## Scale a buffer so its peak equals `target` (returns a new buffer).
func _norm(b: PackedFloat32Array, target: float) -> PackedFloat32Array:
	var g: float = target / maxf(_peak(b), 1e-9)
	var out: PackedFloat32Array = _zeros(b.size())
	for i in b.size():
		out[i] = b[i] * g
	return out


## dst += src * gain, with src starting `offset_s` seconds into dst (clipped to dst).
func _add(dst: PackedFloat32Array, src: PackedFloat32Array, offset_s: float, gain: float) -> void:
	var o: int = int(round(offset_s * _rate))
	var n: int = dst.size()
	for i in src.size():
		var j: int = o + i
		if j >= n:
			break
		if j >= 0:
			dst[j] += src[i] * gain


## Like _add, but src is first scaled so its own peak is `peak` (balances noise layers).
func _add_pk(dst: PackedFloat32Array, src: PackedFloat32Array, offset_s: float, peak: float) -> void:
	_add(dst, src, offset_s, peak / maxf(_peak(src), 1e-9))


func _mul(a: PackedFloat32Array, b: PackedFloat32Array) -> void:
	for i in mini(a.size(), b.size()):
		a[i] *= b[i]


## a *= control-rate curve (linearly interpolated between control points).
func _mulc(b: PackedFloat32Array, cc: PackedFloat32Array) -> void:
	var n: int = b.size()
	for k in (n + 15) >> 4:
		var v: float = cc[k]
		var d: float = (cc[k + 1] - v) * 0.0625
		for i in range(k << 4, mini((k + 1) << 4, n)):
			b[i] *= v
			v += d


## Soft saturation (tanh) - adds harmonics so sub-bass reads on small speakers.
func _sat(b: PackedFloat32Array, drive: float) -> void:
	var inv: float = 1.0 / tanh(drive)
	for i in b.size():
		b[i] = tanh(b[i] * drive) * inv


func _white(n: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b: PackedFloat32Array = _zeros(n)
	for i in n:
		b[i] = rng.randf() * 2.0 - 1.0
	return b


## Pink-ish noise (Paul Kellet's 3-pole economy filter).
func _pink(n: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b: PackedFloat32Array = _zeros(n)
	var b0: float = 0.0
	var b1: float = 0.0
	var b2: float = 0.0
	for i in n:
		var w: float = rng.randf() * 2.0 - 1.0
		b0 = 0.99765 * b0 + w * 0.099046
		b1 = 0.963 * b1 + w * 0.2965164
		b2 = 0.57 * b2 + w * 1.0526913
		b[i] = (b0 + b1 + b2 + w * 0.1848) * 0.25
	return b


## Piecewise curve through (time s, value) pairs, one element per `stride` samples.
## `expo` interpolates geometrically (pitch), `smooth` eases each segment (envelopes).
func _curve_g(m: int, pts: PackedFloat32Array, expo: bool, smooth: bool, stride: int) -> PackedFloat32Array:
	var b: PackedFloat32Array = _zeros(m)
	var cnt: int = pts.size() >> 1
	if cnt == 0:
		return b
	var sc: float = _rate / float(stride)
	var first: int = clampi(int(pts[0] * sc), 0, m)
	for k in first:
		b[k] = pts[1]
	for j in cnt - 1:
		var v0: float = pts[j * 2 + 1]
		var v1: float = pts[j * 2 + 3]
		var i0: int = clampi(int(pts[j * 2] * sc), 0, m)
		var i1: int = clampi(int(pts[j * 2 + 2] * sc), 0, m)
		var span: float = float(maxi(1, i1 - i0))
		var ratio: float = v1 / v0 if expo else 1.0
		for k in range(i0, i1):
			var u: float = float(k - i0) / span
			if smooth:
				u = u * u * (3.0 - 2.0 * u)
			b[k] = v0 * pow(ratio, u) if expo else v0 + (v1 - v0) * u
	var last: int = clampi(int(pts[(cnt - 1) * 2] * sc), 0, m)
	for k in range(last, m):
		b[k] = pts[cnt * 2 - 1]
	return b


## Full-rate curve (one element per sample).
func _curve(n: int, pts: PackedFloat32Array, expo: bool = false) -> PackedFloat32Array:
	return _curve_g(n, pts, expo, false, 1)


## Control-rate curve (one element per 16 samples, plus guard elements) for an n-sample buffer.
func _cv(n: int, pts: PackedFloat32Array, expo: bool = false, smooth: bool = false) -> PackedFloat32Array:
	return _curve_g((n >> 4) + 2, pts, expo, smooth, 16)


## Control-rate copy of a full-rate curve.
func _decim(fc: PackedFloat32Array) -> PackedFloat32Array:
	var n: int = fc.size()
	var m: int = (n >> 4) + 2
	var out: PackedFloat32Array = _zeros(m)
	for k in m:
		out[k] = fc[mini(k << 4, n - 1)]
	return out


## b *= (half-cosine attack, then exp decay with time constant tau), in place.
func _apply_exp(b: PackedFloat32Array, attack: float, tau: float) -> void:
	var n: int = b.size()
	var na: int = mini(n, maxi(1, int(attack * _rate)))
	var k: float = exp(-_dt / tau)
	var e: float = 1.0
	for i in na:
		b[i] *= (0.5 - 0.5 * cos(PI * float(i) / float(na))) * e
		e *= k
	for i in range(na, n):
		b[i] *= e
		e *= k


## Pitched thud / blip: sine gliding exponentially f0 -> f1 (time constant
## `glide`), with a smooth attack and exp decay `tau`.
func _hit(dur: float, f0: float, f1: float, glide: float, tau: float, atk: float) -> PackedFloat32Array:
	var n: int = _n(dur)
	var dt: float = _dt
	var b: PackedFloat32Array = _zeros(n)
	var ph: float = 0.0
	var fe: float = f0 - f1
	var kf: float = exp(-dt / glide)
	var e: float = 1.0
	var ke: float = exp(-dt / tau)
	var na: int = maxi(1, int(atk * _rate))
	for i in mini(na, n):
		ph += (f1 + fe) * dt
		fe *= kf
		b[i] = sin(TAU * ph) * e * (0.5 - 0.5 * cos(PI * float(i) / float(na)))
		e *= ke
	for i in range(na, n):
		ph += (f1 + fe) * dt
		fe *= kf
		b[i] = sin(TAU * ph) * e
		e *= ke
	return b


## `count` short noise grains scattered in [t0, t0 + spread] seconds (crunches, leaves).
func _grains(n: int, rng: RandomNumberGenerator, t0: float, count: int, spread: float, min_ms: float, max_ms: float, min_amp: float) -> PackedFloat32Array:
	var b: PackedFloat32Array = _zeros(n)
	for _g in count:
		var s: int = int((t0 + rng.randf() * spread) * _rate)
		var glen: int = maxi(2, int(rng.randf_range(min_ms, max_ms) * 0.001 * _rate))
		var amp: float = rng.randf_range(min_amp, 1.0)
		for k in glen:
			var j: int = s + k
			if j >= n:
				break
			var w: float = 1.0 - float(k) / float(glen)
			b[j] += (rng.randf() * 2.0 - 1.0) * amp * w * w
	return b


# -- oscillators --

func _osc_sine(fc: PackedFloat32Array) -> PackedFloat32Array:
	var n: int = fc.size()
	var dt: float = _dt
	var b: PackedFloat32Array = _zeros(n)
	var ph: float = 0.0
	for i in n:
		ph += fc[i] * dt
		b[i] = sin(TAU * ph)
	return b


## Band-limited-ish sawtooth (polyBLEP).
func _saw(fc: PackedFloat32Array) -> PackedFloat32Array:
	var n: int = fc.size()
	var dtc: float = _dt
	var b: PackedFloat32Array = _zeros(n)
	var ph: float = 0.0
	for i in n:
		var dt: float = fc[i] * dtc
		ph += dt
		if ph >= 1.0:
			ph -= 1.0
		var v: float = 2.0 * ph - 1.0
		if ph < dt:
			var x: float = ph / dt
			v -= x + x - x * x - 1.0
		elif ph > 1.0 - dt:
			var y: float = (ph - 1.0) / dt
			v -= y * y + y + y + 1.0
		b[i] = v
	return b


## Sum of sine harmonics 1..N with the given amplitudes.
func _stack(fc: PackedFloat32Array, amps: PackedFloat32Array) -> PackedFloat32Array:
	var n: int = fc.size()
	var na: int = amps.size()
	var dt: float = _dt
	var b: PackedFloat32Array = _zeros(n)
	var ph: float = 0.0
	for i in n:
		ph += fc[i] * dt
		var w: float = TAU * ph
		var s: float = 0.0
		for h in na:
			s += amps[h] * sin(w * float(h + 1))
		b[i] = s
	return b


## FM operator: sin(carrier + index * sin(ratio * carrier)).
func _fm(fc: PackedFloat32Array, ratio: float, idx: PackedFloat32Array) -> PackedFloat32Array:
	var n: int = fc.size()
	var dt: float = _dt
	var b: PackedFloat32Array = _zeros(n)
	var ph: float = 0.0
	for i in n:
		ph += fc[i] * dt
		var w: float = TAU * ph
		b[i] = sin(w + idx[mini(i, idx.size() - 1)] * sin(ratio * w))
	return b


## In-place vibrato on a frequency curve; depth is fractional, onset in seconds.
func _vib(fc: PackedFloat32Array, rate: float, depth: float, onset: float) -> void:
	var dt: float = _dt
	for i in fc.size():
		var t: float = float(i) * dt
		fc[i] *= 1.0 + depth * sin(TAU * rate * t) * minf(1.0, t / onset)


# -- filters --

## State-variable bandpass (TPT form, peak gain 1 at the centre). `fc` is a
## control-rate cutoff curve (one value per 16 samples; a 1-element array is a
## constant), which makes sweeps cheap and click-free.
func _svf(b: PackedFloat32Array, fc: PackedFloat32Array, q: float, gain: float = 1.0) -> PackedFloat32Array:
	var n: int = b.size()
	var out: PackedFloat32Array = _zeros(n)
	var nc: int = fc.size()
	if nc == 0:
		return out
	var k: float = 1.0 / maxf(q, 0.05)
	var og: float = gain * k
	var wk: float = PI * _dt
	var fmax: float = 0.44 / _dt
	var ic1: float = 0.0
	var ic2: float = 0.0
	for blk in (n + 15) >> 4:
		var g: float = tan(clampf(fc[mini(blk, nc - 1)], 12.0, fmax) * wk)
		var a1: float = 1.0 / (1.0 + g * (g + k))
		var a2: float = g * a1
		var a3: float = g * a2
		for i in range(blk << 4, mini((blk + 1) << 4, n)):
			var v3: float = b[i] - ic2
			var v1: float = a1 * ic1 + a2 * v3
			var v2: float = ic2 + a2 * ic1 + a3 * v3
			ic1 = 2.0 * v1 - ic1
			ic2 = 2.0 * v2 - ic2
			out[i] = v1 * og
	return out


## Constant bandpass.
func _bp(b: PackedFloat32Array, fc: float, q: float) -> PackedFloat32Array:
	return _svf(b, PackedFloat32Array([fc]), q)


## Bandpass with a control-rate center-frequency curve.
func _bpc(b: PackedFloat32Array, fcc: PackedFloat32Array, q: float) -> PackedFloat32Array:
	return _svf(b, fcc, q)


## One-pole lowpass (`passes` cascaded = 6 dB/oct each).
func _lp(b: PackedFloat32Array, fc: float, passes: int = 1) -> PackedFloat32Array:
	var a: float = 1.0 - exp(-TAU * fc * _dt)
	var out: PackedFloat32Array = b.duplicate()
	for _p in passes:
		var y: float = 0.0
		for i in out.size():
			y += a * (out[i] - y)
			out[i] = y
	return out


## One-pole highpass (input minus its lowpass).
func _hp(b: PackedFloat32Array, fc: float) -> PackedFloat32Array:
	var a: float = 1.0 - exp(-TAU * fc * _dt)
	var out: PackedFloat32Array = _zeros(b.size())
	var y: float = 0.0
	for i in b.size():
		y += a * (b[i] - y)
		out[i] = b[i] - y
	return out


# -- voices --

## Three control-rate formant curves (Hz) from [time, Vector3 vowel, time, Vector3 vowel ...] keys.
func _vowel_curves(n: int, keys: Array, scale: float) -> Array:
	var p1: PackedFloat32Array = PackedFloat32Array()
	var p2: PackedFloat32Array = PackedFloat32Array()
	var p3: PackedFloat32Array = PackedFloat32Array()
	for j in range(0, keys.size(), 2):
		var t: float = keys[j]
		var v: Vector3 = keys[j + 1]
		p1.append(t)
		p1.append(v.x * scale)
		p2.append(t)
		p2.append(v.y * scale)
		p3.append(t)
		p3.append(v.z * scale)
	return [_cv(n, p1), _cv(n, p2), _cv(n, p3)]


## Run `src` through a bank of three bandpass formants.
func _formants(src: PackedFloat32Array, curves: Array, gains: Vector3, qs: Vector3) -> PackedFloat32Array:
	var out: PackedFloat32Array = _svf(src, curves[0], qs.x, gains.x)
	var b: PackedFloat32Array = _svf(src, curves[1], qs.y, gains.y)
	var c: PackedFloat32Array = _svf(src, curves[2], qs.z, gains.z)
	for i in out.size():
		out[i] += b[i] + c[i]
	return out


## Glottal-ish saw source (+ optional breath noise) through vowel formants.
func _voice(rng: RandomNumberGenerator, f0: PackedFloat32Array, keys: Array, gains: Vector3, qs: Vector3, breath: float, src_lp: float, scale: float) -> PackedFloat32Array:
	var n: int = f0.size()
	var src: PackedFloat32Array = _lp(_saw(f0), src_lp)
	if breath > 0.0:
		for i in n:
			src[i] += (rng.randf() * 2.0 - 1.0) * breath
	return _formants(src, _vowel_curves(n, keys, scale), gains, qs)


# -- output --

## Remove DC, normalise to `peak_db`, apply cosine fades (at least 5 ms), convert to 16-bit mono.
func _wav(buf: PackedFloat32Array, peak_db: float, fade_in_ms: float = 5.0, fade_out_ms: float = 10.0) -> AudioStreamWAV:
	return _encode(buf, peak_db, int(maxf(fade_in_ms, 5.0) * 0.001 * SRF), int(maxf(fade_out_ms, 5.0) * 0.001 * SRF), false)


## Same, but as a seamless forward loop (no fades).
func _wav_loop(buf: PackedFloat32Array, peak_db: float) -> AudioStreamWAV:
	return _encode(buf, peak_db, 0, 0, true)


func _encode(buf: PackedFloat32Array, peak_db: float, nfi_in: int, nfo_in: int, loop: bool) -> AudioStreamWAV:
	var y: PackedFloat32Array = buf
	if _div == 2:
		y = _upsample2(buf, loop)
	_set_div(1)
	var n: int = y.size()
	var nfi: int = mini(nfi_in, n >> 1)
	var nfo: int = mini(nfo_in, n >> 1)
	var mid_end: int = n - nfo
	# Fade weights (half-cosine); the DC estimate is weighted by them so the faded
	# signal has (near) zero mean.
	var wi: PackedFloat32Array = _zeros(nfi)
	for i in nfi:
		wi[i] = 0.5 - 0.5 * cos(PI * float(i) / float(nfi))
	var wo: PackedFloat32Array = _zeros(nfo)
	for j in nfo:
		wo[j] = 0.5 - 0.5 * cos(PI * float(nfo - 1 - j) / float(nfo))
	var sxw: float = 0.0
	var sw: float = float(n - nfi - nfo)
	var lo: float = 1e30
	var hi: float = -1e30
	for i in nfi:
		var v: float = y[i]
		sxw += v * wi[i]
		sw += wi[i]
		lo = minf(lo, v)
		hi = maxf(hi, v)
	for i in range(nfi, mid_end):
		var v: float = y[i]
		sxw += v
		if v < lo:
			lo = v
		if v > hi:
			hi = v
	for j in nfo:
		var v: float = y[mid_end + j]
		sxw += v * wo[j]
		sw += wo[j]
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var mean: float = sxw / maxf(sw, 1.0)
	var pk: float = maxf(hi - mean, mean - lo)
	var g: float = db_to_linear(minf(peak_db, -1.0)) / maxf(pk, 1e-9) * 32767.0
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(n * 2)
	for i in nfi:
		bytes.encode_s16(i << 1, int((y[i] - mean) * g * wi[i]))
	for i in range(nfi, mid_end):
		bytes.encode_s16(i << 1, int((y[i] - mean) * g))
	for j in nfo:
		bytes.encode_s16((mid_end + j) << 1, int((y[mid_end + j] - mean) * g * wo[j]))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	wav.mix_rate = SR
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav


## 2x upsample with a 4-point half-sample interpolator (-1, 9, 9, -1) / 16.
## With `circular`, the buffer is treated as circular (seamless loops).
func _upsample2(b: PackedFloat32Array, circular: bool) -> PackedFloat32Array:
	var n: int = b.size()
	var out: PackedFloat32Array = _zeros(n * 2)
	for i in range(1, n - 2):
		out[i << 1] = b[i]
		out[(i << 1) + 1] = (9.0 * (b[i] + b[i + 1]) - b[i - 1] - b[i + 2]) * 0.0625
	var edges: Array[int] = [0, n - 2, n - 1]
	for i: int in edges:
		var im1: int = (i - 1 + n) % n if circular else maxi(i - 1, 0)
		var ip1: int = (i + 1) % n if circular else mini(i + 1, n - 1)
		var ip2: int = (i + 2) % n if circular else mini(i + 2, n - 1)
		out[i << 1] = b[i]
		out[(i << 1) + 1] = (9.0 * (b[i] + b[ip1]) - b[im1] - b[ip2]) * 0.0625
	return out


## Turn `raw` (warm-up + loop + crossfade tail) into a seamless loop of `loop_n`
## samples: the tail is equal-power-crossfaded into the head.
func _loopify(raw: PackedFloat32Array, start: int, loop_n: int) -> PackedFloat32Array:
	var xf: int = raw.size() - start - loop_n
	var out: PackedFloat32Array = _zeros(loop_n)
	for i in loop_n:
		out[i] = raw[start + i]
	for i in xf:
		var u: float = (float(i) + 0.5) / float(xf)
		out[i] = raw[start + i] * sin(PI * 0.5 * u) + raw[start + loop_n + i] * cos(PI * 0.5 * u)
	return out
