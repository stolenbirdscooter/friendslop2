class_name Fruit
extends RigidBody3D
## Food for the Mossback. Server-simulated; clients show interpolated, frozen copies.

const KINDS := {
	"plumbob": {"value": 12.0, "mass": 1.0, "radius": 0.3, "heavy": false},
	"gourdle": {"value": 30.0, "mass": 4.0, "radius": 0.45, "heavy": true},
	"mite": {"value": 0.0, "mass": 0.5, "radius": 0.27, "heavy": false, "pest": true},
}

var id := 0
var kind := "plumbob"
var held_by := 0          # peer id holding it, 0 = free
var value := 12.0
var heavy := false
var _target_pos := Vector3.ZERO
var _target_rot := Quaternion.IDENTITY
var _last_bonk := 0.0
var server_side := true
var pest := false
var game: Node
var on_beast := false
var ground_t := 0.0
var _wander := Vector2.ZERO
var _wander_t := 0.0
var _mesh: MeshInstance3D
var _prev_pos := Vector3.ZERO
var _hop := 0.0
var stun := 0.0

func setup(p_id: int, p_kind: String, is_server: bool) -> void:
	id = p_id
	kind = p_kind
	name = "F%d" % id
	server_side = is_server
	var k: Dictionary = KINDS[kind]
	value = k.value
	heavy = k.heavy
	pest = k.get("pest", false)
	mass = k.mass
	collision_layer = G.PROP_LAYER
	collision_mask = G.WORLD_LAYER | G.BEAST_LAYER | G.PROP_LAYER | G.PLAYER_LAYER
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = k.radius
	cs.shape = sp
	add_child(cs)
	var mi := Mats.mesh_instance(PropsLib.get_mesh(kind))
	add_child(mi)
	_mesh = mi
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.8
	physics_material_override = pm
	angular_damp = 1.5
	linear_damp = 0.15
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 2
	if not is_server:
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

## Server: knock this prop around (stuns crawling pests so physics can take over).
func fling(impulse: Vector3) -> void:
	freeze = false
	sleeping = false
	stun = 1.6
	apply_central_impulse(impulse * mass)

func set_remote_state(p: Vector3, q: Quaternion, holder: int) -> void:
	_target_pos = p
	_target_rot = q
	held_by = holder

func _process(dt: float) -> void:
	if not pest:
		return
	# little hop-scurry animation from actual motion (works on every peer)
	var v := (global_position - _prev_pos) / maxf(dt, 0.001)
	_prev_pos = global_position
	var moving := clampf(Vector2(v.x, v.z).length() * 0.2, 0.0, 1.0) if held_by == 0 else 1.0
	_hop += dt * 16.0
	_mesh.position.y = absf(sin(_hop)) * 0.08 * moving
	_mesh.rotation.z = sin(_hop * 0.5) * 0.25 * moving

func _physics_process(dt: float) -> void:
	if held_by != 0:
		return  # Game positions held fruit in the holder's mitts
	if pest and server_side and game:
		_pest_tick(dt)
	if not server_side:
		global_position = global_position.lerp(_target_pos, G.damp(14.0, dt))
		quaternion = quaternion.slerp(_target_rot, G.damp(14.0, dt))
	elif global_position.y < Terrain.WATER_LEVEL - 30.0:
		global_position.y = 50.0  # fell through the world; drop it back in

## Server: thistlemites crawl over the shell towards the moss, nibbling (Game counts them for itch).
func _pest_tick(dt: float) -> void:
	var b: Beast = game.beast
	if stun > 0.0:
		stun -= dt
		on_beast = false
		return
	var lp := b.body_xf.affine_inverse() * global_position
	var top := BeastBuild.back_height(lp.x, lp.z)
	on_beast = not is_inf(top) and absf(lp.y - top) < 0.9
	if on_beast:
		ground_t = 0.0
		_wander_t -= dt
		if _wander_t <= 0.0:
			_wander_t = randf_range(1.0, 3.0)
			_wander = Vector2(randf_range(-4, 4), randf_range(-6, 6))
		var to := Vector2(_wander.x - lp.x, _wander.y - lp.z)
		var dir := to.normalized() * 1.1 if to.length() > 0.5 else Vector2.ZERO
		var next_local := Vector3(lp.x + dir.x * dt, 0, lp.z + dir.y * dt)
		next_local.y = BeastBuild.back_height(next_local.x, next_local.z)
		if is_inf(next_local.y):
			next_local = Vector3(lp.x, top, lp.z)
		var target := b.body_xf * (next_local + Vector3(0, 0.27, 0))
		linear_velocity = (target - global_position) / dt
		angular_velocity = Vector3.ZERO
		if dir.length() > 0.1:
			var fwd := (b.body_xf.basis * Vector3(dir.x, 0, dir.y)).normalized()
			global_basis = Basis.looking_at(fwd, b.body_xf.basis.y)
	else:
		# fallen off: scurry away from the beast, then vanish into the grass
		ground_t += dt
		if ground_t > 1.0 and ground_t < 1.1:
			var away := (global_position - b.ground_pos)
			away.y = 0
			apply_central_impulse(away.normalized() * 2.0 + Vector3.UP * 1.5)
		if ground_t > 7.0:
			game.despawn_prop(id)
