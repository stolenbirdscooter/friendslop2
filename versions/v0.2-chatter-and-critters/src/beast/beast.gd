class_name Beast
extends Node3D
## The Mossback. Server simulates behaviour; everyone animates legs/head/lure locally
## from the (interpolated) body state. Physics bodies follow the visuals so the crew can ride.

enum Act { IDLE, WALK, EAT, SNEEZE_IN, SNEEZE, SIT, BLOCKED, SHAKE }

signal stepped(pos: Vector3, strength: float)
signal sneezed(origin: Vector3)
signal shook
signal chomped(mouth: Vector3)
signal vocal(kind: String, pos: Vector3)

const STRIDE := 9.0
const WALK_SPEED := 3.2
const TROT_SPEED := 4.4
const SLOW_SPEED := 2.0
const MAX_TURN := deg_to_rad(11.0)
const LURE_MAX_YAW := deg_to_rad(50.0)
const POLE_LEN := 20.0
const POLE_PITCH := deg_to_rad(18.0)
const FOOT_ORDER := [2, 0, 3, 1]  # lateral-sequence walk: LH, LF, RH, RF

var world: World
var look_targets: Array = []
var beast_name := "Old Barnaby"
var temperament := "Sneezy"
var mods := {"pollen": 1.0, "hunger": 1.0, "itch": 1.0, "speed": 1.0, "turn": 1.0, "greed": 65.0, "feed": 1.0, "nap": 0.0}
const TEMPERAMENTS := {
	"Sneezy": {"pollen": 2.0, "blurb": "sneezes at the faintest flower"},
	"Greedy": {"hunger": 1.4, "greed": 85.0, "feed": 1.25, "blurb": "will walk a mile for a plumbob"},
	"Ticklish": {"itch": 1.7, "blurb": "can't stand a single thistlemite"},
	"Dozy": {"speed": 0.88, "nap": 1.0, "blurb": "naps whenever nobody's looking"},
	"Stubborn": {"turn": 0.7, "blurb": "turns like a cathedral"},
	"Nosy": {"greed": 80.0, "pollen": 1.3, "blurb": "has to sniff everything"},
}
var _nap_t := 40.0   # Node3Ds the beast may glance at (the crew)
var authority := true

# --- simulated state (server authoritative, replicated)
var ground_pos := Vector3.ZERO
var yaw := 0.0
var speed := 0.0
var turn_rate := 0.0
var phase := 0.0
var satiety := 70.0
var joy := 0.5
var pollen := 0.0
var itch := 0.0
var act: int = Act.IDLE
var act_t := 0.0
var lure_yaw := 0.0
var lure_down := 0.0
var lure_operator := 0
var mouth_open := 0.0

# server-only inputs
var whistle_pos := Vector3.ZERO
var whistle_time := -100.0
var fruit_target: Node3D = null
var _food_list: Array = []
var _blocked_turn := 1.0
var _idle_moo := 6.0
var _time := 0.0
var _last_fed := -100.0

# --- local visual state
var body: AnimatableBody3D
var head: AnimatableBody3D
var jaw: Node3D
var ears: Array[Node3D] = []
var eyes: Array[Node3D] = []
var lids: Array[Node3D] = []
var legs: Array = []   # each: {hip, thigh, shin, foot, body, planted, from, to, swing, t}
var tail_mi: MeshInstance3D
var swivel: Node3D
var rope_mi: MeshInstance3D
var decoy: Node3D
var _decoy_pos := Vector3.ZERO
var _hut_pos := Vector3.ZERO
var _decoy_vel := Vector3.ZERO
var _pitch := 0.0
var _roll := 0.0
var _height := 0.0
var _head_yaw := 0.0
var _head_pitch := 0.0
var _blink := 0.0
var _tail_sway := 0.0
var _snaps: Array = []   # client interpolation buffer [time, PackedFloat32Array]
var body_xf := Transform3D()
var _prev_body_xf := Transform3D()
var platform_yaw_delta := 0.0

## Name, coat and temperament from a seed (same on every peer).
func roll_personality(seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 7 + 3
	var titles := ["Old", "Big", "Auntie", "Uncle", "Sir", "Dame", "Little", "Lord", "Granny", "Captain"]
	var names := ["Barnaby", "Gertrude", "Wobbleton", "Mumble", "Puddle", "Fernsby", "Clover", "Bramble", "Turnip", "Marrow", "Pudding", "Biscuit", "Hollyhock", "Thimble", "Bumble", "Parsnip", "Dumpling", "Mossimus"]
	beast_name = "%s %s" % [titles[rng.randi() % titles.size()], names[rng.randi() % names.size()]]
	var keys := TEMPERAMENTS.keys()
	temperament = keys[rng.randi() % keys.size()]
	var t: Dictionary = TEMPERAMENTS[temperament]
	for k in t:
		if mods.has(k):
			mods[k] = t[k]
	var coat: Array = BeastBuild.COATS[rng.randi() % BeastBuild.COATS.size()]
	BeastBuild.fur = coat[1]
	BeastBuild.fur_light = coat[2]
	BeastBuild.fur_dark = coat[3]

func temperament_blurb() -> String:
	return TEMPERAMENTS[temperament].blurb

func setup(p_world: World, start: Vector3, start_yaw: float) -> void:
	world = p_world
	ground_pos = start
	ground_pos.y = world.terrain.height(start.x, start.z)
	yaw = start_yaw
	_build()
	_update_body_transform(0.0, true)
	for i in 4:
		var leg: Dictionary = legs[i]
		var hip_w: Vector3 = body_xf * (BeastBuild.HIPS[i] as Vector3)
		leg.planted = _ground_at(hip_w)
		leg.from = leg.planted
		leg.to = leg.planted
	_decoy_pos = _pole_tip_global() + Vector3.DOWN * 2.0
	_update_visuals(0.0)

## After teleporting: settle body and feet instantly.
func setup_snap() -> void:
	_update_body_transform(0.0, true)
	for i in 4:
		var leg: Dictionary = legs[i]
		var p := _ground_at(body_xf * (BeastBuild.HIPS[i] as Vector3))
		leg.planted = p
		leg.from = p
		leg.to = p
		leg.pos = p

# ---------------------------------------------------------------- build
func _build() -> void:
	body = AnimatableBody3D.new()
	body.name = "Body"
	body.sync_to_physics = true
	body.collision_layer = G.BEAST_LAYER | G.WORLD_LAYER
	body.collision_mask = 0
	add_child(body)
	var shell_cs := CollisionShape3D.new()
	shell_cs.shape = BeastBuild.shell_collision()
	body.add_child(shell_cs)
	body.add_child(Mats.mesh_instance(BeastBuild.shell_mesh(), Mats.toon(Color.WHITE, true, 0.06)))
	var fringe := MultiMeshInstance3D.new()
	fringe.multimesh = BeastBuild.fringe_multimesh()
	fringe.material_override = Mats.foliage(0.04, 2.0)
	body.add_child(fringe)
	_build_garden()
	# hut
	var hut_pos := BeastBuild.top_point(BeastBuild.HUT.x, BeastBuild.HUT.z) + Vector3(0, 0.55, 0)
	var hut := Node3D.new()
	hut.name = "Hut"
	hut.position = hut_pos
	body.add_child(hut)
	hut.add_child(Mats.mesh_instance(BeastBuild.hut_mesh()))
	for pair in BeastBuild.hut_shapes():
		var cs := CollisionShape3D.new()
		cs.shape = pair[0]
		cs.transform = Transform3D((pair[1] as Transform3D).basis, hut_pos + (pair[1] as Transform3D).origin)
		body.add_child(cs)
	var lantern := OmniLight3D.new()
	lantern.light_color = Color("ffc070")
	lantern.light_energy = 0.0
	lantern.omni_range = 9.0
	lantern.position = hut_pos + Vector3(0, 2.0, -1.6)
	lantern.name = "Lantern"
	body.add_child(lantern)
	var lamp := Mats.mesh_instance(Geo.sphere(0.22, Color.WHITE, 8, 6), Mats.glow(G.MARIGOLD, 1.5))
	lamp.position = lantern.position
	body.add_child(lamp)
	# gangplank up to the roof, and the lookout's spyglass on the ridge
	hut.add_child(Mats.mesh_instance(BeastBuild.ramp_mesh()))
	var rs: Array = BeastBuild.ramp_shape()
	var rcs := CollisionShape3D.new()
	rcs.shape = rs[0]
	rcs.transform = Transform3D((rs[1] as Transform3D).basis, hut_pos + (rs[1] as Transform3D).origin)
	body.add_child(rcs)
	var spy := Mats.mesh_instance(BeastBuild.spyglass_mesh())
	spy.position = BeastBuild.SPYGLASS
	spy.name = "Spyglass"
	hut.add_child(spy)
	_hut_pos = hut_pos
	# tail (visual mesh rebuilt as it sways; collision fixed ramp)
	tail_mi = MeshInstance3D.new()
	tail_mi.material_override = Mats.toon(Color.WHITE, true, 0.06)
	body.add_child(tail_mi)
	_rebuild_tail(0.0)
	var tp := BeastBuild.tail_points(0.0)
	var tr := BeastBuild.tail_radii()
	for i in tp.size() - 1:
		var a := tp[i]
		var b := tp[i + 1]
		var mid := (a + b) * 0.5
		var dir := (b - a)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2.6, 0.6, dir.length() + 0.5)
		cs.shape = box
		var basis := Basis.looking_at(dir.normalized(), Vector3.UP)
		cs.transform = Transform3D(basis, mid + Vector3(0, (tr[i] + tr[i + 1]) * 0.5 - 0.35, 0))
		body.add_child(cs)
	# lure
	var post_pos := BeastBuild.top_point(BeastBuild.LURE_POST.x, BeastBuild.LURE_POST.z)
	var post := Mats.mesh_instance(Geo.cylinder(0.22, 0.32, 2.6, G.BARK, 7))
	post.position = post_pos + Vector3(0, 1.1, 0)
	body.add_child(post)
	var post_cs := CollisionShape3D.new()
	var post_shape := CylinderShape3D.new()
	post_shape.radius = 0.3
	post_shape.height = 2.6
	post_cs.shape = post_shape
	post_cs.position = post.position
	body.add_child(post_cs)
	swivel = Node3D.new()
	swivel.position = post_pos + Vector3(0, 2.4, 0)
	body.add_child(swivel)
	var cap := Mats.mesh_instance(Geo.cylinder(0.4, 0.4, 0.35, G.TERRACOTTA, 9))
	swivel.add_child(cap)
	var pole_pts := PackedVector3Array()
	var pole_r := PackedFloat32Array()
	for i in 6:
		var t := i / 5.0
		pole_pts.append(Vector3(0, sin(POLE_PITCH) * POLE_LEN * t + sin(t * PI) * 0.6, -cos(POLE_PITCH) * POLE_LEN * t))
		pole_r.append(lerpf(0.2, 0.08, t))
	var pole := Mats.mesh_instance(Geo.tube(pole_pts, pole_r, G.WOOD_LIGHT, 6))
	swivel.add_child(pole)
	# counterweight + handle bar behind the post
	var handle := Mats.mesh_instance(Geo.cylinder(0.07, 0.07, 1.6, G.BARK, 5))
	handle.rotation = Vector3(0, 0, PI * 0.5)
	handle.position = Vector3(0, -0.9, 1.2)
	swivel.add_child(handle)
	var arm := Mats.mesh_instance(Geo.box(Vector3(0.14, 0.14, 1.3), G.BARK))
	arm.position = Vector3(0, -0.5, 0.65)
	arm.rotation = Vector3(0.5, 0, 0)
	swivel.add_child(arm)
	for sx in [-1, 1]:
		var grip := Mats.mesh_instance(Geo.sphere(0.13, G.TERRACOTTA, 8, 6))
		grip.position = Vector3(sx * 0.8, -0.9, 1.2)
		swivel.add_child(grip)
	rope_mi = MeshInstance3D.new()
	rope_mi.material_override = Mats.toon(G.PAPER_DARK)
	add_child(rope_mi)
	decoy = Node3D.new()
	add_child(decoy)
	var root_mi := Mats.mesh_instance(PropsLib.get_mesh("sweetroot"))
	root_mi.scale = Vector3.ONE * 1.4
	decoy.add_child(root_mi)
	# head
	head = AnimatableBody3D.new()
	head.name = "Head"
	head.sync_to_physics = true
	head.collision_layer = G.BEAST_LAYER | G.WORLD_LAYER
	head.collision_mask = 0
	add_child(head)
	var hs := CollisionShape3D.new()
	var hsh := SphereShape3D.new()
	hsh.radius = 3.5
	hs.shape = hsh
	head.add_child(hs)
	var ms := CollisionShape3D.new()
	var msh := SphereShape3D.new()
	msh.radius = 2.2
	ms.shape = msh
	ms.position = Vector3(0, -1.3, -2.9)
	head.add_child(ms)
	head.add_child(Mats.mesh_instance(BeastBuild.head_mesh(), Mats.toon(Color.WHITE, true, 0.06)))
	jaw = Node3D.new()
	jaw.position = Vector3(0, -1.9, 0.4)
	head.add_child(jaw)
	jaw.add_child(Mats.mesh_instance(BeastBuild.jaw_mesh()))
	for sx in [-1, 1]:
		var eye := Node3D.new()
		eye.position = Vector3(sx * 2.75, 0.9, -2.6)
		eye.rotation = Vector3(0, sx * 0.55, 0)
		head.add_child(eye)
		eye.add_child(Mats.mesh_instance(Geo.sphere(0.78, G.PAPER, 14, 10)))
		var pupil := Mats.mesh_instance(Geo.sphere(0.46, G.INK, 10, 8))
		pupil.position = Vector3(0, -0.05, -0.48)
		pupil.name = "Pupil"
		eye.add_child(pupil)
		var glint := Mats.mesh_instance(Geo.sphere(0.12, G.PAPER, 6, 4), Mats.glow(G.PAPER, 0.6))
		glint.position = Vector3(0.12, 0.12, -0.88)
		eye.add_child(glint)
		var lid := Node3D.new()
		eye.add_child(lid)
		var lid_mi := Mats.mesh_instance(Geo.blob(Vector3(0.9, 0.9, 0.9), BeastBuild.fur, 0.0, 5, 8, 12))
		lid.add_child(lid_mi)
		# keep only a cap: scale the lid sphere into a dome sitting on top
		lid_mi.scale = Vector3(1.0, 0.62, 1.0)
		lid_mi.position = Vector3(0, 0.42, 0)
		eyes.append(eye)
		lids.append(lid)
		var ear := Node3D.new()
		ear.position = Vector3(sx * 3.6, 1.8, 0.8)
		head.add_child(ear)
		var ear_mi := Mats.mesh_instance(BeastBuild.ear_mesh())
		ear_mi.position = Vector3(sx * 1.4, -0.6, 0)
		ear_mi.rotation = Vector3(0, 0, sx * 1.15)
		ear.add_child(ear_mi)
		ears.append(ear)
	# legs
	var thigh_mesh := BeastBuild.leg_segment_mesh(1.55, 2.1, BeastBuild.fur)
	var shin_mesh := BeastBuild.leg_segment_mesh(1.45, 1.6, BeastBuild.fur.darkened(0.08))
	var foot_mesh := BeastBuild.foot_mesh()
	for i in 4:
		var thigh := Mats.mesh_instance(thigh_mesh)
		var shin := Mats.mesh_instance(shin_mesh)
		var foot := Mats.mesh_instance(foot_mesh)
		add_child(thigh)
		add_child(shin)
		add_child(foot)
		var lb := AnimatableBody3D.new()
		lb.sync_to_physics = true
		lb.collision_layer = G.BEAST_LAYER
		lb.collision_mask = 0
		var lcs := CollisionShape3D.new()
		var cap_s := CapsuleShape3D.new()
		cap_s.radius = 1.5
		cap_s.height = 6.0
		lcs.shape = cap_s
		lb.add_child(lcs)
		add_child(lb)
		legs.append({"thigh": thigh, "shin": shin, "foot": foot, "body": lb,
			"planted": Vector3.ZERO, "from": Vector3.ZERO, "to": Vector3.ZERO, "swing": false, "t": 0.0, "pos": Vector3.ZERO})

func _build_garden() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = PropsLib.get_mesh("grass")
	var xfs := BeastBuild.garden_points(900, 5, 0.55)
	mm.instance_count = xfs.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in xfs.size():
		var s := rng.randf_range(0.35, 0.7)
		mm.set_instance_transform(i, xfs[i].scaled_local(Vector3(s * 1.3, s, s * 1.3)))
		mm.set_instance_custom_data(i, G.MOSS.lerp(G.MEADOW, rng.randf()).lightened(0.1))
	var gi := MultiMeshInstance3D.new()
	gi.multimesh = mm
	gi.material_override = world.grass_mat if world else null
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(gi)
	# flowers & a few mossy stones on the back
	for k in 3:
		var fm := MultiMesh.new()
		fm.transform_format = MultiMesh.TRANSFORM_3D
		fm.mesh = PropsLib.get_mesh("flowers:%d" % [0, 1, 3][k])
		var pts := BeastBuild.garden_points(26, 70 + k, 0.7)
		fm.instance_count = pts.size()
		for i in pts.size():
			fm.set_instance_transform(i, pts[i])
		var fi := MultiMeshInstance3D.new()
		fi.multimesh = fm
		fi.material_override = Mats.foliage(0.04, 0.7)
		body.add_child(fi)
	for xf in BeastBuild.garden_points(6, 99, 0.8):
		var rock := Mats.mesh_instance(PropsLib.get_mesh("rock:%d" % (randi() % 4)))
		rock.transform = xf.scaled_local(Vector3.ONE * randf_range(0.5, 0.9))
		body.add_child(rock)

func _rebuild_tail(sway: float) -> void:
	var pts := BeastBuild.tail_points(sway)
	var mesh := Geo.tube(pts, BeastBuild.tail_radii(), BeastBuild.fur, 12)
	var tuft := Geo.blob(Vector3(1.4, 1.1, 1.8), BeastBuild.fur_dark, 0.25, 77, 8, 10)
	tail_mi.mesh = Geo.merge([[mesh, Transform3D()], [tuft, Transform3D(Basis(), pts[pts.size() - 1] + Vector3(0, 0.3, 0.8))]])

# ---------------------------------------------------------------- helpers
func _ground_at(p: Vector3) -> Vector3:
	return Vector3(p.x, world.terrain.height(p.x, p.z), p.z)

func forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))

func head_global() -> Transform3D:
	return head.global_transform

func mouth_global() -> Vector3:
	return head.global_transform * BeastBuild.MOUTH_LOCAL

func lure_handle_global() -> Vector3:
	return swivel.global_transform * Vector3(0, -2.4, 1.9)

func lure_stand_global() -> Vector3:
	var off := Basis(Vector3.UP, lure_yaw * LURE_MAX_YAW) * Vector3(0, 0, 2.3)
	var x := BeastBuild.LURE_POST.x + off.x
	var z := BeastBuild.LURE_POST.z + off.z
	return body_xf * Vector3(x, BeastBuild.back_height(x, z) + 0.05, z)

## If a point (world) has sunk inside the shell, return the surface point above it; else the point.
func surface_rescue(p: Vector3) -> Vector3:
	var lp := body_xf.affine_inverse() * p
	var top := BeastBuild.back_height(lp.x, lp.z)
	if is_inf(top):
		return p
	if lp.y < top - 0.3 and lp.y > BeastBuild.C.y - 1.0:
		return body_xf * Vector3(lp.x, top + 0.1, lp.z)
	return p

func _pole_tip_global() -> Vector3:
	return swivel.global_transform * Vector3(0, sin(POLE_PITCH) * POLE_LEN, -cos(POLE_PITCH) * POLE_LEN)

func spyglass_global() -> Vector3:
	return body_xf * (_hut_pos + BeastBuild.SPYGLASS)

func spyglass_stand_global() -> Vector3:
	return body_xf * (_hut_pos + BeastBuild.SPYGLASS + Vector3(0.0, -0.55, 0.7))

func decoy_global() -> Vector3:
	return _decoy_pos

func is_walking() -> bool:
	return speed > 0.3

# ---------------------------------------------------------------- server sim
func server_tick(dt: float) -> void:
	_time += dt
	act_t += dt
	var hungry := satiety < 25.0
	var target_speed := 0.0
	var desired_turn := 0.0
	satiety = maxf(satiety - dt * (0.11 if speed > 0.3 else 0.045) * mods.hunger, 0.0)
	if mods.nap > 0.0 and act == Act.WALK and lure_down < 0.5:
		_nap_t -= dt
		if _nap_t <= 0.0:
			_nap_t = randf_range(50.0, 90.0)
			_set_act(Act.SIT)
			vocal.emit("moan", global_head())
	joy = move_toward(joy, clampf(satiety / 100.0, 0.0, 1.0), dt * 0.02)
	match act:
		Act.SIT:
			if satiety > 18.0 and (mods.nap == 0.0 or act_t > 8.0 or lure_down > 0.5):
				_set_act(Act.IDLE)
				vocal.emit("happy", global_head())
		Act.EAT:
			if act_t > 1.6:
				_set_act(Act.IDLE)
		Act.SNEEZE_IN:
			if act_t > 1.5:
				_set_act(Act.SNEEZE)
				sneezed.emit(mouth_global())
		Act.SNEEZE:
			if act_t > 1.0:
				_set_act(Act.IDLE)
		Act.SHAKE:
			if act_t > 2.6:
				_set_act(Act.IDLE)
		Act.BLOCKED:
			desired_turn = _blocked_turn * MAX_TURN
			target_speed = 0.6
			if act_t > 3.0:
				_set_act(Act.IDLE)
		_:
			if satiety <= 0.0:
				_set_act(Act.SIT)
				vocal.emit("grumble", global_head())
			else:
				# priorities: food on the ground > lure > whistle > idle
				var food := _find_food()
				if food:
					fruit_target = food
					var m := mouth_global()
					var to := food.global_position - ground_pos
					to.y = 0
					var to_mouth := food.global_position - m
					to_mouth.y = 0
					desired_turn = clampf(_angle_to(to) * 1.5, -MAX_TURN * 1.4, MAX_TURN * 1.4)
					target_speed = WALK_SPEED * 0.8 if to_mouth.length() > 8.0 else 1.0
					if to_mouth.length() < 3.4:
						_set_act(Act.EAT)
				elif lure_down > 0.5:
					fruit_target = null
					desired_turn = -lure_yaw * MAX_TURN * mods.turn
					target_speed = (SLOW_SPEED if hungry else (TROT_SPEED if joy > 0.75 and _time - _last_fed < 40.0 else WALK_SPEED)) * mods.speed
				elif _time - whistle_time < 5.0:
					var to := whistle_pos - ground_pos
					to.y = 0
					desired_turn = clampf(_angle_to(to) * 1.2, -MAX_TURN, MAX_TURN)
					target_speed = WALK_SPEED * 0.8 if to.length() > 16.0 else 0.0
				act = Act.WALK if target_speed > 0.1 else Act.IDLE
	# obstacles: big rocks block, trees get shoved
	if speed > 0.2 and act != Act.BLOCKED:
		var probe := ground_pos + forward() * 12.0
		for ob in world.terrain.obstacles_near(probe, 9.0):
			if ob.has("big"):
				_set_act(Act.BLOCKED)
				_blocked_turn = 1.0 if _angle_to(ob.pos - ground_pos) < 0.0 else -1.0
				vocal.emit("moan", global_head())
				speed *= 0.3
				break
	# itch -> a full-body wet-dog shake
	if itch >= 100.0 and act in [Act.IDLE, Act.WALK, Act.BLOCKED]:
		itch = 0.0
		_set_act(Act.SHAKE)
		shook.emit()
		vocal.emit("grumble", global_head())
	# pollen -> sneeze
	if speed > 0.5 and act == Act.WALK:
		var m := mouth_global()
		pollen += world.terrain.pollen_at(m.x, m.z) * dt * 0.09 * mods.pollen
		if pollen >= 1.0:
			pollen = 0.0
			_set_act(Act.SNEEZE_IN)
			vocal.emit("sneeze_in", global_head())
	if act in [Act.EAT, Act.SNEEZE_IN, Act.SNEEZE, Act.SIT, Act.SHAKE]:
		target_speed = 0.0
	speed = move_toward(speed, target_speed, dt * (0.9 if target_speed > speed else 1.6))
	turn_rate = move_toward(turn_rate, desired_turn, dt * 0.25)
	yaw = wrapf(yaw + turn_rate * dt * clampf(speed / 1.5, 0.35, 1.0) * (1.0 if speed > 0.05 or act == Act.BLOCKED else 0.0), -PI, PI)
	ground_pos += forward() * speed * dt
	ground_pos.y = world.terrain.height(ground_pos.x, ground_pos.z)
	_idle_moo -= dt
	if _idle_moo <= 0.0:
		_idle_moo = randf_range(14.0, 28.0)
		vocal.emit("grumble" if hungry else "moan", global_head())
	mouth_open = 1.0 if act in [Act.EAT, Act.SNEEZE_IN] else 0.0

func global_head() -> Vector3:
	return head.global_position if head else ground_pos

func _set_act(a: int) -> void:
	act = a
	act_t = 0.0

func _angle_to(dir: Vector3) -> float:
	var f := forward()
	return atan2(f.cross(dir).y, f.dot(dir))

func _find_food() -> Node3D:
	# a peckish beast is a distractible beast
	if satiety > mods.greed:
		return null
	var best: Node3D = null
	var best_d := 24.0
	var m := mouth_global()
	var f_dir := forward()
	for f in _food_list:
		if not is_instance_valid(f) or f.get("held_by") != 0:
			continue
		var to: Vector3 = f.global_position - m
		to.y = 0
		# must be ahead of the mouth (or right at it) and roughly in front
		if f_dir.dot(to) < -2.0 or (absf(_angle_to(f.global_position - ground_pos)) > deg_to_rad(60) and to.length() > 5.0):
			continue
		if f.global_position.y > world.terrain.height(f.global_position.x, f.global_position.z) + 2.0:
			continue  # only food lying on the ground
		var d := to.length()
		if d < best_d:
			best_d = d
			best = f
	return best

func set_food_list(list: Array) -> void:
	_food_list = list

func whistle(at: Vector3) -> void:
	whistle_pos = at
	whistle_time = _time

func feed(amount: float) -> void:
	amount *= mods.feed
	satiety = minf(satiety + amount, 100.0)
	joy = minf(joy + amount * 0.004, 1.0)
	_last_fed = _time
	if act != Act.SNEEZE_IN and act != Act.SNEEZE:
		_set_act(Act.EAT)
	act_t = 0.6
	chomped.emit(mouth_global())

# ---------------------------------------------------------------- replication
func get_snapshot() -> PackedFloat32Array:
	return PackedFloat32Array([ground_pos.x, ground_pos.y, ground_pos.z, yaw, speed, phase, satiety, joy,
		float(act), act_t, lure_yaw, lure_down, float(lure_operator), mouth_open, turn_rate, itch, pollen])

func push_snapshot(t: float, s: PackedFloat32Array) -> void:
	_snaps.append([t, s])
	while _snaps.size() > 8:
		_snaps.pop_front()

func _client_interp(now: float) -> void:
	if _snaps.size() == 0:
		return
	var render_t := now - 0.12
	var a: Array = _snaps[0]
	var b: Array = _snaps[_snaps.size() - 1]
	for i in _snaps.size() - 1:
		if _snaps[i][0] <= render_t and _snaps[i + 1][0] >= render_t:
			a = _snaps[i]
			b = _snaps[i + 1]
			break
	var sa: PackedFloat32Array = a[1]
	var sb: PackedFloat32Array = b[1]
	var k := 0.0
	if b[0] > a[0]:
		k = clampf((render_t - a[0]) / (b[0] - a[0]), 0.0, 1.2)
	ground_pos = Vector3(lerpf(sa[0], sb[0], k), lerpf(sa[1], sb[1], k), lerpf(sa[2], sb[2], k))
	yaw = lerp_angle(sa[3], sb[3], k)
	speed = lerpf(sa[4], sb[4], k)
	satiety = sb[6]
	joy = sb[7]
	var new_act := int(sb[8])
	if new_act != act:
		act = new_act
		act_t = 0.0
		if act == Act.SNEEZE:
			sneezed.emit(mouth_global())
		elif act == Act.SHAKE:
			shook.emit()
	itch = sb[15]
	pollen = sb[16]
	if lure_operator != multiplayer.get_unique_id():
		lure_yaw = lerpf(sa[10], sb[10], k)
		lure_down = lerpf(sa[11], sb[11], k)
	lure_operator = int(sb[12])
	mouth_open = sb[13]
	turn_rate = sb[14]

# ---------------------------------------------------------------- per-frame
func _physics_process(dt: float) -> void:
	if world == null:
		return
	if authority:
		server_tick(dt)
	else:
		act_t += dt
		_client_interp(Time.get_ticks_msec() / 1000.0)
	phase = fposmod(phase + (speed + absf(turn_rate) * 9.0 * (1.0 if speed < 0.5 else 0.0)) * dt / STRIDE, 1.0)
	_update_body_transform(dt, false)
	_update_visuals(dt)

func _update_body_transform(dt: float, snap: bool) -> void:
	var basis_yaw := Basis(Vector3.UP, yaw)
	var hs: Array[float] = []
	for i in 4:
		var hip: Vector3 = BeastBuild.HIPS[i]
		var w := ground_pos + basis_yaw * Vector3(hip.x, 0, hip.z)
		hs.append(world.terrain.height(w.x, w.z))
	var front := (hs[0] + hs[1]) * 0.5
	var back := (hs[2] + hs[3]) * 0.5
	var left := (hs[0] + hs[2]) * 0.5
	var right := (hs[1] + hs[3]) * 0.5
	var avg := (front + back) * 0.5
	var target_pitch := atan2(front - back, 15.4) * 0.8
	var target_roll := atan2(right - left, 10.8) * 0.6
	var sit := 1.0 if act == Act.SIT else 0.0
	var walk_k := clampf(speed / WALK_SPEED, 0.0, 1.3)
	var bob := sin(phase * TAU * 4.0) * 0.22 * walk_k
	var sway := sin(phase * TAU * 2.0) * deg_to_rad(1.6) * walk_k
	var target_h := maxf(avg, Terrain.WATER_LEVEL - 3.0) - 0.4 - sit * 4.2
	if act == Act.SNEEZE_IN:
		target_pitch -= deg_to_rad(4.0) * clampf(act_t, 0.0, 1.0)
	if act == Act.SNEEZE:
		target_pitch += deg_to_rad(5.0) * exp(-act_t * 4.0)
	if snap:
		_pitch = target_pitch
		_roll = target_roll
		_height = target_h
	else:
		_pitch = lerpf(_pitch, target_pitch, G.damp(2.0, dt))
		_roll = lerpf(_roll, target_roll, G.damp(2.0, dt))
		_height = lerpf(_height, target_h, G.damp(2.5 if sit == 0.0 else 0.8, dt))
	var shake_roll := 0.0
	if act == Act.SHAKE:
		var env := sin(clampf(act_t / 2.4, 0.0, 1.0) * PI)
		shake_roll = sin(act_t * 12.0) * 0.09 * env
	var basis := basis_yaw * Basis(Vector3.RIGHT, -_pitch) * Basis(Vector3.FORWARD, _roll + sway + shake_roll)
	_prev_body_xf = body_xf
	body_xf = Transform3D(basis, Vector3(ground_pos.x, _height + bob, ground_pos.z))
	body.global_transform = body_xf

func _update_visuals(dt: float) -> void:
	_update_legs(dt)
	_update_head(dt)
	_update_lure(dt)
	_tail_sway = lerpf(_tail_sway, -turn_rate * 18.0 + sin(phase * TAU) * 1.2 * clampf(speed, 0.0, 1.0) + sin(Time.get_ticks_msec() * 0.0007) * 0.8, G.damp(2.0, dt))
	if Engine.get_physics_frames() % 4 == 0:
		_rebuild_tail(_tail_sway)
	var lantern: OmniLight3D = body.get_node("Lantern")
	lantern.light_energy = lerpf(lantern.light_energy, 1.8 if _is_dark() else 0.0, G.damp(1.0, dt))

var dark := false
func _is_dark() -> bool:
	return dark

func _update_legs(dt: float) -> void:
	var walk_k := clampf(speed / WALK_SPEED, 0.0, 1.0)
	for n in 4:
		var i: int = FOOT_ORDER[n]
		var leg: Dictionary = legs[i]
		var hip_local: Vector3 = BeastBuild.HIPS[i]
		var hip_w := body_xf * hip_local
		# swing window for this foot within the gait cycle
		var lp := fposmod(phase - n * 0.25, 1.0)
		var in_swing := lp < 0.24 and (speed > 0.15 or absf(turn_rate) > 0.02)
		var rest := _ground_at(ground_pos + Basis(Vector3.UP, yaw) * Vector3(hip_local.x * 1.02, 0, hip_local.z))
		if in_swing and not leg.swing:
			leg.swing = true
			leg.from = leg.planted
			var ahead := forward() * STRIDE * 0.5 * maxf(walk_k, 0.3)
			var rot_off := Basis(Vector3.UP, turn_rate * 1.5) * (rest - ground_pos) + ground_pos - rest
			leg.to = _ground_at(rest + ahead + rot_off)
		if leg.swing:
			var t := clampf(lp / 0.24, 0.0, 1.0)
			if not in_swing:
				t = 1.0
			var p: Vector3 = (leg.from as Vector3).lerp(leg.to, t * t * (3.0 - 2.0 * t))
			p.y += sin(t * PI) * 2.2
			leg.pos = p
			if t >= 1.0:
				leg.swing = false
				leg.planted = leg.to
				leg.pos = leg.to
				stepped.emit(leg.to, clampf(0.4 + walk_k, 0.4, 1.3))
		else:
			# feet stay planted; if we drifted badly (teleport/sitting), resettle
			if (leg.planted as Vector3).distance_to(rest) > STRIDE * 1.4:
				leg.planted = rest
			leg.pos = leg.planted
			leg.pos.y = world.terrain.height(leg.pos.x, leg.pos.z)
		_pose_leg(leg, hip_w, leg.pos)

func _pose_leg(leg: Dictionary, hip: Vector3, foot: Vector3) -> void:
	var l1 := 4.4
	var l2 := 4.4
	var ankle := foot + Vector3(0, 1.0, 0)
	var to := ankle - hip
	var d := clampf(to.length(), 0.5, l1 + l2 - 0.01)
	var dir := to.normalized()
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var bend := forward()
	bend = (bend - dir * bend.dot(dir)).normalized()
	var knee := hip + dir * a + bend * h
	ankle = hip + dir * d
	_place_segment(leg.thigh, knee, hip, 1.0)
	_place_segment(leg.shin, ankle, knee, 1.0)
	var fb := Basis(Vector3.UP, yaw)
	(leg.foot as MeshInstance3D).global_transform = Transform3D(fb, foot + Vector3(0, -0.15, 0))
	var lb: AnimatableBody3D = leg.body
	lb.global_transform = Transform3D(_seg_basis(ankle, knee), (ankle + knee) * 0.5 + Vector3(0, -0.6, 0))

func _seg_basis(from: Vector3, to: Vector3) -> Basis:
	var up := (to - from).normalized()
	var side := up.cross(forward())
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var fwd := side.cross(up).normalized()
	return Basis(side, up, fwd).orthonormalized()

func _place_segment(mi: MeshInstance3D, from: Vector3, to: Vector3, width: float) -> void:
	var len_v := from.distance_to(to)
	var b := _seg_basis(from, to)
	mi.global_transform = Transform3D(b.scaled_local(Vector3(width, len_v, width)), from)

func _update_head(dt: float) -> void:
	var target_yaw := 0.0
	var target_pitch := 0.0
	var walk_k := clampf(speed / WALK_SPEED, 0.0, 1.2)
	# look at the decoy when it's dangling in front
	var neck_w := body_xf * BeastBuild.NECK
	if lure_down > 0.3:
		var to := body_xf.basis.inverse() * (_decoy_pos - neck_w)
		target_yaw = clampf(atan2(-to.x, -to.z), -0.6, 0.6)
		target_pitch = clampf(atan2(to.y + 1.5, Vector2(to.x, to.z).length()), -0.3, 0.35)
	# idle curiosity: glance at the nearest Tender in front of the face
	if lure_down <= 0.3 and act in [Act.IDLE, Act.WALK]:
		var best := 30.0
		for n in look_targets:
			if not is_instance_valid(n) or not n.visible:
				continue
			var to := body_xf.basis.inverse() * ((n as Node3D).global_position - neck_w)
			var d := to.length()
			if to.z < -2.0 and d < best:
				best = d
				target_yaw = clampf(atan2(-to.x, -to.z), -0.7, 0.7)
				target_pitch = clampf(atan2(to.y + 2.0, Vector2(to.x, to.z).length()), -0.5, 0.4)
	match act:
		Act.EAT:
			target_pitch = -0.55 if act_t < 1.2 else -0.2
		Act.SNEEZE_IN:
			target_pitch = 0.45 * clampf(act_t / 1.2, 0.0, 1.0)
		Act.SNEEZE:
			target_pitch = -0.35
		Act.SIT:
			target_pitch = -0.25
		Act.SHAKE:
			target_yaw = sin(act_t * 19.0) * 0.5
			target_pitch = -0.1
		Act.IDLE:
			target_pitch = -0.4 if fmod(Time.get_ticks_msec() * 0.001, 17.0) > 11.0 else target_pitch * 0.5
	target_pitch += sin(phase * TAU * 4.0 + 0.8) * 0.035 * walk_k
	target_yaw += -turn_rate * 1.5
	var rate := 9.0 if act in [Act.SNEEZE, Act.SHAKE] else 2.2
	_head_yaw = lerpf(_head_yaw, target_yaw, G.damp(rate, dt))
	_head_pitch = lerpf(_head_pitch, target_pitch, G.damp(rate, dt))
	var hb := Basis(Vector3.UP, _head_yaw) * Basis(Vector3.RIGHT, _head_pitch)
	var hx := body_xf * Transform3D(hb, BeastBuild.NECK) * Transform3D(Basis(), BeastBuild.HEAD_OFFSET)
	head.global_transform = hx
	# jaw: chomp twice while eating, gape while sneezing in
	var jaw_open := 0.0
	if act == Act.EAT:
		jaw_open = absf(sin(act_t * 7.0)) * 0.45 if act_t < 1.3 else 0.0
	elif act == Act.SNEEZE_IN:
		jaw_open = 0.35 * clampf(act_t, 0.0, 1.0)
	elif act == Act.SNEEZE:
		jaw_open = 0.5 * exp(-act_t * 3.0)
	jaw.rotation.x = lerpf(jaw.rotation.x, -jaw_open, G.damp(14.0, dt))
	# eyes: pupils track the decoy, lids droop when hungry, blink
	_blink -= dt
	var blink_k := 0.0
	if _blink < 0.0:
		blink_k = 1.0
		if _blink < -0.14:
			_blink = randf_range(2.5, 6.0)
	var droop := lerpf(0.35, 0.05, clampf(satiety / 60.0, 0.0, 1.0))
	if act == Act.SNEEZE_IN:
		droop = 0.6
	for e in 2:
		var lid: Node3D = lids[e]
		lid.rotation.x = lerpf(lid.rotation.x, -(0.15 + droop + blink_k * 1.2), G.damp(20.0, dt))
	for e in ears.size():
		var ear: Node3D = ears[e]
		var sx := -1.0 if e == 0 else 1.0
		ear.rotation.z = sx * (sin(phase * TAU * 4.0 + e) * 0.12 * walk_k + (0.3 if act == Act.SNEEZE_IN else 0.0))

func _update_lure(dt: float) -> void:
	swivel.rotation.y = lure_yaw * LURE_MAX_YAW
	var tip := _pole_tip_global()
	var rope_len := lerpf(2.0, 13.0, lure_down)
	# pendulum: gravity + spring to rope length
	_decoy_vel.y -= 14.0 * dt
	_decoy_vel *= 1.0 - G.damp(0.9, dt)
	_decoy_pos += _decoy_vel * dt
	var off := _decoy_pos - tip
	var l := off.length()
	if l > rope_len or l < 0.01:
		var n := off.normalized() if l > 0.01 else Vector3.DOWN
		_decoy_pos = tip + n * rope_len
		_decoy_vel -= n * _decoy_vel.dot(n)
	if l < rope_len * 0.7:
		_decoy_pos = _decoy_pos.lerp(tip + Vector3.DOWN * rope_len, G.damp(3.0, dt))
	decoy.global_position = _decoy_pos
	decoy.global_rotation = Vector3(0, yaw + Time.get_ticks_msec() * 0.0004, (_decoy_pos.x - tip.x) * 0.05)
	var mid := (tip + _decoy_pos) * 0.5 + Vector3(0, -0.3, 0)
	rope_mi.mesh = Geo.tube(PackedVector3Array([tip, mid, _decoy_pos + Vector3(0, 0.55, 0)]), PackedFloat32Array([0.05, 0.05, 0.05]), Color.WHITE, 4)
