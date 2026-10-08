class_name Fx
extends Node3D
## Cartoon puffs: dust, pollen, leaves, splashes. One CPU-animated MultiMesh, opaque + inked.

const MAX := 320

var _mm: MultiMesh
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _grow := PackedFloat32Array()
var _grav := PackedFloat32Array()
var _spin := PackedFloat32Array()
var _next := 0

func _ready() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = Geo.blob(Vector3.ONE, Color.WHITE, 0.22, 5, 6, 9)
	_mm.instance_count = MAX
	for arr in [_pos, _vel]:
		arr.resize(MAX)
	for arr in [_age, _life, _size, _grow, _grav, _spin]:
		arr.resize(MAX)
	for i in MAX:
		_life[i] = 0.0
		_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.material_override = Mats.toon(Color.WHITE, true, 0.15)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 2000.0
	add_child(mmi)

## Spawn `count` puffs around `pos`.
func puff(pos: Vector3, count: int, color: Color, size := 0.6, speed := 2.0, up := 1.0, life := 1.2, gravity := -0.5, spread := 0.5) -> void:
	for k in count:
		var i := _next
		_next = (_next + 1) % MAX
		var d := Vector3(randf_range(-1, 1), randf_range(-0.2, 1) * up, randf_range(-1, 1)).normalized()
		_pos[i] = pos + Vector3(randf_range(-1, 1), randf_range(0, 1), randf_range(-1, 1)) * spread
		_vel[i] = d * speed * randf_range(0.6, 1.2)
		_age[i] = 0.0
		_life[i] = life * randf_range(0.75, 1.25)
		_size[i] = size * randf_range(0.7, 1.3)
		_grow[i] = randf_range(0.3, 0.9)
		_grav[i] = gravity
		_spin[i] = randf_range(-3, 3)
		var c := color.lerp(Color.WHITE, randf_range(0.0, 0.18))
		_mm.set_instance_color(i, c)

func _process(dt: float) -> void:
	for i in MAX:
		if _life[i] <= 0.0:
			continue
		_age[i] += dt
		var t := _age[i] / _life[i]
		if t >= 1.0:
			_life[i] = 0.0
			_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), _pos[i]))
			continue
		_vel[i] = _vel[i] * (1.0 - G.damp(2.5, dt)) + Vector3(0, _grav[i] * dt, 0)
		_pos[i] += _vel[i] * dt
		# grow, then shrink away (pop) - reads like hand-drawn smoke
		var s := _size[i] * (1.0 + _grow[i] * t) * (1.0 - smoothstep(0.65, 1.0, t))
		var b := Basis(Vector3.UP, _spin[i] * _age[i]).scaled(Vector3(s, s * 0.85, s))
		_mm.set_instance_transform(i, Transform3D(b, _pos[i]))
