class_name Fruit
extends RigidBody3D
## Food for the Mossback. Server-simulated; clients show interpolated, frozen copies.

const KINDS := {
	"plumbob": {"value": 12.0, "mass": 1.0, "radius": 0.3, "heavy": false},
	"gourdle": {"value": 30.0, "mass": 4.0, "radius": 0.45, "heavy": true},
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

func setup(p_id: int, p_kind: String, is_server: bool) -> void:
	id = p_id
	kind = p_kind
	name = "F%d" % id
	server_side = is_server
	var k: Dictionary = KINDS[kind]
	value = k.value
	heavy = k.heavy
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

func set_remote_state(p: Vector3, q: Quaternion, holder: int) -> void:
	_target_pos = p
	_target_rot = q
	held_by = holder

func _physics_process(dt: float) -> void:
	if held_by != 0:
		return  # Game positions held fruit in the holder's mitts
	if not server_side:
		global_position = global_position.lerp(_target_pos, G.damp(14.0, dt))
		quaternion = quaternion.slerp(_target_rot, G.damp(14.0, dt))
	elif global_position.y < Terrain.WATER_LEVEL - 30.0:
		global_position.y = 50.0  # fell through the world; drop it back in
