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
# the flinger on the back (operator-driven; yaw/charge ride in the snapshot)
const FL_AIM_CENTER := deg_to_rad(90.0)   # it sits on the left flank: aim swings forward, out left, and back
const FL_MAX_YAW := deg_to_rad(120.0)
const FL_ELEV := deg_to_rad(50.0)
var fl_yaw := 0.0
var fl_charge := 0.0
var fl_operator := 0
# serenade: kalimba notes near its head make it blissful (0..1, server-owned)
var serenade := 0.0
var _note_peers := {}   # server: peer -> [time, last note]
var _hum_t := 0.0
var balk := false        # refusing to wade into deep water (replicated)
# who it likes best (server tallies affection; the favourite's peer id is replicated)
var affection := {}
var favourite := 0
var _fav_call_t := -100.0
var _nuzzle := 0.0       # local head animation
# rope ladders on each flank: lowered by someone aboard, they roll themselves up again
const LADDER_Z := -3.0
const LADDER_X := 9.7
const LADDER_TOP := 15.8
const LADDER_BOTTOM := 1.2
var ladder_t: Array[float] = [0.0, 0.0]   # server: seconds left down (replicated as 0/1)
var ladder_by: Array[int] = [0, 0]
var _ladder_nodes: Array[Node3D] = []
# snow settles on its back in the wintering hollow (0..1, set by Game from the biome)
var snow := 0.0
var _snow_nodes: Array[Node3D] = []
var _balk_moan := 0.0

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
var fl_body: AnimatableBody3D
var fl_arm: Node3D
var _fl_pos := Vector3.ZERO
var _fl_fire_t := 100.0
var _celebrate := 0.0
var shelf: Array[String] = []
var _shelf_node: Node3D
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
	lantern.position = hut_pos + Vector3(0, 3.35, 0.0)   # hangs from the ridge, above head height
	lantern.name = "Lantern"
	body.add_child(lantern)
	var lamp := Mats.mesh_instance(Geo.sphere(0.22, Color.WHITE, 8, 6), Mats.glow(G.MARIGOLD, 1.5))
	lamp.position = lantern.position
	body.add_child(lamp)
	var cord := Mats.mesh_instance(Geo.cylinder(0.02, 0.02, 0.6, G.INK, 4))
	cord.position = lantern.position + Vector3(0, 0.5, 0)
	body.add_child(cord)
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
	# keepsake shelves along the back wall inside the cottage
	for k in 2:
		var board := Mats.mesh_instance(Geo.merge([
			[Geo.box(Vector3(3.7, 0.08, 0.42), G.WOOD), Transform3D()],
			[Geo.box(Vector3(0.08, 0.25, 0.3), G.BARK), Transform3D(Basis(), Vector3(-1.6, -0.15, 0.05))],
			[Geo.box(Vector3(0.08, 0.25, 0.3), G.BARK), Transform3D(Basis(), Vector3(1.6, -0.15, 0.05))]]))
		board.position = BeastBuild.SHELF + Vector3(0, k * 0.62, 0)
		hut.add_child(board)
	_shelf_node = Node3D.new()
	_shelf_node.position = BeastBuild.SHELF
	hut.add_child(_shelf_node)
	_build_flinger()
	_build_ladders()
	_build_snow(hut)
	# tail (visual mesh rebuilt as it sways; collision fixed ramp)
	tail_mi = MeshInstance3D.new()
	tail_mi.material_override = Mats.toon(Color.WHITE, true, 0.06)
	body.add_child(tail_mi)
	_rebuild_tail(0.0)
	# tail ramp: one smooth strip along the tail's back (separate boxes left ledges at the joints)
	var tp := BeastBuild.tail_points(0.0)
	var tr := BeastBuild.tail_radii()
	var faces := PackedVector3Array()
	for i in tp.size() - 1:
		var a0 := tp[i] + Vector3(-1.3, tr[i] * 0.9, 0)
		var a1 := tp[i] + Vector3(1.3, tr[i] * 0.9, 0)
		var b0 := tp[i + 1] + Vector3(-1.3, tr[i + 1] * 0.9, 0)
		var b1 := tp[i + 1] + Vector3(1.3, tr[i + 1] * 0.9, 0)
		faces.append_array([a0, b0, b1, a0, b1, a1])
	# and run it down into the grass behind the tip, so you can simply walk on
	var tip_top := tp[tp.size() - 1] + Vector3(0, tr[tr.size() - 1] * 0.9, 0)
	var ground_end := Vector3(0, -0.6, tip_top.z + 3.5)
	faces.append_array([tip_top + Vector3(-1.3, 0, 0), ground_end + Vector3(-1.6, 0, 0), ground_end + Vector3(1.6, 0, 0), tip_top + Vector3(-1.3, 0, 0), ground_end + Vector3(1.6, 0, 0), tip_top + Vector3(1.3, 0, 0)])
	# carry the strip a little onto the back so there's no lip where tail meets shell
	var root_top := BeastBuild.top_point(0.0, BeastBuild.TAIL_ROOT.z - 1.5)
	var r0 := tp[0] + Vector3(0, tr[0] * 0.9, 0)
	faces.append_array([Vector3(-1.3, root_top.y, root_top.z), r0 + Vector3(-1.3, 0, 0), r0 + Vector3(1.3, 0, 0), Vector3(-1.3, root_top.y, root_top.z), r0 + Vector3(1.3, 0, 0), Vector3(1.3, root_top.y, root_top.z)])
	var ramp := ConcavePolygonShape3D.new()
	ramp.set_faces(faces)
	ramp.backface_collision = true
	var ramp_cs := CollisionShape3D.new()
	ramp_cs.shape = ramp
	body.add_child(ramp_cs)
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

func _build_snow(hut: Node3D) -> void:
	# drifts on the moss: soft, flattened white blobs scattered over the back
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Geo.blob(Vector3(1.0, 0.22, 1.0), G.PAPER, 0.25, 121, 5, 9)
	var pts := BeastBuild.garden_points(70, 131, 0.8)
	mm.instance_count = pts.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 132
	for i in pts.size():
		var sc := rng.randf_range(0.8, 2.2)
		mm.set_instance_transform(i, pts[i].scaled_local(Vector3(sc, 1.0, sc * rng.randf_range(0.7, 1.3))))
	var drifts := MultiMeshInstance3D.new()
	drifts.multimesh = mm
	drifts.material_override = Mats.toon(Color.WHITE, true, 0.12)
	body.add_child(drifts)
	_snow_nodes.append(drifts)
	# a snow cap on each roof slope, and on the ridge
	var cap := Node3D.new()
	hut.add_child(cap)
	for sx in [-1, 1]:
		var b := Basis(Vector3.FORWARD, sx * 0.62)
		var slab := Mats.mesh_instance(Geo.blob(Vector3(1.45, 0.14, 2.6), G.PAPER, 0.08, 133 + sx, 4, 10))
		slab.transform = Transform3D(b, Vector3(sx * 4.2 * 0.27, 2.6 + 1.0, 0) + b * Vector3(0, 0.12, 0))
		cap.add_child(slab)
	_snow_nodes.append(cap)
	for n in _snow_nodes:
		n.visible = false

func _update_snow(dt: float) -> void:
	var on := snow > 0.02
	for n in _snow_nodes:
		n.visible = on
		if on:
			n.scale = Vector3(1.0, clampf(snow, 0.05, 1.0), 1.0)

func _build_ladders() -> void:
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var post_base := BeastBuild.top_point(side * 6.6, LADDER_Z)
		var parts: Array = [
			[Geo.cylinder(0.14, 0.18, LADDER_TOP - post_base.y + 0.9, G.BARK, 6), Transform3D(Basis(), Vector3(side * 6.6, (post_base.y + LADDER_TOP + 0.9) * 0.5, LADDER_Z))],
			[Geo.box(Vector3(3.4, 0.22, 0.26), G.WOOD), Transform3D(Basis(), Vector3(side * 8.2, LADDER_TOP + 0.75, LADDER_Z))],
			[Geo.cylinder(0.32, 0.32, 1.0, G.PAPER_DARK, 8), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(side * LADDER_X, LADDER_TOP + 0.4, LADDER_Z))],
		]
		body.add_child(Mats.mesh_instance(Geo.merge(parts)))
		var lad := Node3D.new()
		lad.position = Vector3(side * LADDER_X, LADDER_TOP + 0.3, LADDER_Z)
		lad.scale = Vector3(1, 0.04, 1)
		body.add_child(lad)
		var length := LADDER_TOP + 0.3 - LADDER_BOTTOM
		var lp: Array = []
		for sx in [-0.35, 0.35]:
			lp.append([Geo.cylinder(0.035, 0.035, length, G.PAPER_DARK, 4), Transform3D(Basis(), Vector3(0, -length * 0.5, sx))])
		var n := int(length / 0.45)
		for k in n:
			lp.append([Geo.box(Vector3(0.09, 0.07, 0.78), G.WOOD_LIGHT), Transform3D(Basis(), Vector3(0, -0.4 - k * 0.45, 0))])
		lad.add_child(Mats.mesh_instance(Geo.merge(lp)))
		_ladder_nodes.append(lad)

func ladder_down(i: int) -> bool:
	return ladder_t[i] > 0.0

## A point on the hanging ladder at beast-local height h.
func ladder_point(i: int, h: float) -> Vector3:
	return body_xf * Vector3((-1.0 if i == 0 else 1.0) * (LADDER_X + 0.45), h, LADDER_Z)

func ladder_anchor_global(i: int) -> Vector3:
	var side := -1.0 if i == 0 else 1.0
	return body_xf * BeastBuild.top_point(side * 6.6, LADDER_Z)

## Where a climber steps off at the top.
func ladder_landing_global(i: int) -> Vector3:
	var x := (-1.0 if i == 0 else 1.0) * 5.6
	return body_xf * Vector3(x, BeastBuild.back_height(x, LADDER_Z) + 0.4, LADDER_Z)

func _build_flinger() -> void:
	# its own kinematic body, so the turntable can turn without rebuilding the shell's shape
	_fl_pos = BeastBuild.top_point(BeastBuild.FLINGER.x, BeastBuild.FLINGER.z) + Vector3(0, -0.1, 0)
	fl_body = AnimatableBody3D.new()
	fl_body.name = "Flinger"
	fl_body.sync_to_physics = true
	fl_body.collision_layer = G.BEAST_LAYER | G.WORLD_LAYER
	fl_body.collision_mask = 0
	add_child(fl_body)
	var parts := PropsLib.flinger_parts()
	fl_body.add_child(Mats.mesh_instance(parts.base))
	fl_arm = Node3D.new()
	fl_arm.position = PropsLib.FL_AXLE
	fl_body.add_child(fl_arm)
	fl_arm.add_child(Mats.mesh_instance(parts.arm))
	var disc := CollisionShape3D.new()
	var dsh := CylinderShape3D.new()
	dsh.radius = 1.65
	dsh.height = 1.0
	disc.shape = dsh
	fl_body.add_child(disc)
	var bowl := CollisionShape3D.new()
	bowl.shape = PropsLib.bowl_collision()
	bowl.position = PropsLib.FL_BOWL
	fl_body.add_child(bowl)
	for sx in [-0.75, 0.75]:
		var post := CollisionShape3D.new()
		var psh := BoxShape3D.new()
		psh.size = Vector3(0.26, 2.0, 0.26)
		post.shape = psh
		post.position = Vector3(sx, 1.35, -2.0)
		fl_body.add_child(post)

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

var _tuft_mi: MeshInstance3D
func _rebuild_tail(sway: float) -> void:
	# the tube is rebuilt as it sways; the tuft is a fixed mesh that rides the tip
	var pts := BeastBuild.tail_points(sway)
	tail_mi.mesh = Geo.tube(pts, BeastBuild.tail_radii(), BeastBuild.fur, 12)
	if _tuft_mi == null:
		_tuft_mi = Mats.mesh_instance(Geo.blob(Vector3(1.4, 1.1, 1.8), BeastBuild.fur_dark, 0.25, 77, 8, 10), Mats.toon(Color.WHITE, true, 0.06))
		body.add_child(_tuft_mi)
	_tuft_mi.position = pts[pts.size() - 1] + Vector3(0, 0.3, 0.8)

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

## Keep an aim (beast-relative yaw) inside the flinger's arc, which never points over the cottage.
static func clamp_fl_yaw(rel: float) -> float:
	return clampf(wrapf(rel - FL_AIM_CENTER, -PI, PI), -FL_MAX_YAW, FL_MAX_YAW) + FL_AIM_CENTER

func flinger_xf() -> Transform3D:
	return body_xf * Transform3D(Basis(Vector3.UP, fl_yaw), _fl_pos)

## Where the operator stands: behind the bowl, on the shell, swinging round with the aim.
func flinger_stand_global() -> Vector3:
	var off := Basis(Vector3.UP, fl_yaw) * Vector3(0, 0, 2.55)
	var x := _fl_pos.x + off.x
	var z := _fl_pos.z + off.z
	return body_xf * Vector3(x, BeastBuild.back_height(x, z) + 0.05, z)

func flinger_dir() -> Vector3:
	return flinger_xf().basis * Vector3(0, sin(FL_ELEV), -cos(FL_ELEV))

func flinger_release_global() -> Vector3:
	return flinger_xf() * Vector3(0, 3.0, -2.5)

## World velocity a launch of this power gives a prop (players scale it for their heavier gravity).
func flinger_velocity(power: float) -> Vector3:
	return flinger_dir() * lerpf(10.0, 27.0, clampf(power, 0.0, 1.0)) + forward() * speed

func in_bowl(p: Vector3) -> bool:
	var lp := flinger_xf().affine_inverse() * p - PropsLib.FL_BOWL
	return Vector2(lp.x, lp.z).length() < 1.25 and lp.y > -0.4 and lp.y < 1.9

func fire_flinger_anim() -> void:
	_fl_fire_t = 0.0

func in_hut(p: Vector3) -> bool:
	var lp := body_xf.affine_inverse() * p - _hut_pos
	return absf(lp.x) < 2.0 and lp.y > -0.5 and lp.y < 2.5 and absf(lp.z) < 1.7

func hut_door_global() -> Vector3:
	return body_xf * (_hut_pos + Vector3(0, 0.3, -2.2))

func add_to_shelf(kind: String) -> void:
	var i := shelf.size()
	shelf.append(kind)
	var mi := Mats.mesh_instance(PropsLib.get_mesh(kind), Mats.glow(Color.WHITE, 0.25))
	mi.position = Vector3(-1.45 + 0.58 * (i % 6), 0.04 + 0.62 * float(i / 6), -0.02)
	mi.rotation.y = randf_range(-0.5, 0.5)
	_shelf_node.add_child(mi)

func set_shelf(list: Array) -> void:
	if list.size() == shelf.size():
		return
	for c in _shelf_node.get_children():
		c.queue_free()
	shelf.clear()
	for k in list:
		add_to_shelf(k)

## Local flourish when a waystone is reached: head up, a long happy bellow.
func celebrate() -> void:
	_celebrate = 3.4

## Server: a crew member played a kalimba note within earshot.
func hear_note(peer: int, note: int) -> void:
	var rec: Array = _note_peers.get(peer, [-100.0, -1])
	var w := 1.0
	if _time - float(rec[0]) < 0.14:
		w *= 0.3   # mashing isn't music
	if note == int(rec[1]):
		w *= 0.5   # neither is one note over and over
	_note_peers[peer] = [_time, note]
	var band := 0
	for k in _note_peers:
		if _time - float(_note_peers[k][0]) < 3.0:
			band += 1
	serenade = minf(serenade + 0.05 * w * (1.0 + 0.6 * (band - 1)), 1.0)

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
	serenade = maxf(serenade - dt * 0.05, 0.0)
	for i in 2:
		ladder_t[i] = maxf(ladder_t[i] - dt, 0.0)
	if ground_pos.y < Terrain.WATER_LEVEL - 1.2:
		_last_wet = _time
	var enchanted := serenade > 0.55
	satiety = maxf(satiety - dt * (0.11 if speed > 0.3 else 0.045) * mods.hunger * (1.0 - 0.5 * serenade), 0.0)
	if enchanted:
		_hum_t -= dt
		if _hum_t <= 0.0:
			_hum_t = randf_range(4.0, 7.0)
			vocal.emit("hum", global_head())
	if mods.nap > 0.0 and act == Act.WALK and lure_down < 0.5:
		_nap_t -= dt
		if _nap_t <= 0.0:
			_nap_t = randf_range(50.0, 90.0)
			_set_act(Act.SIT)
			vocal.emit("moan", global_head())
	joy = move_toward(joy, clampf(satiety / 100.0 + serenade * 0.5, 0.0, 1.0), dt * (0.02 + 0.06 * serenade))
	match act:
		Act.SIT:
			if satiety > 18.0 and (mods.nap == 0.0 or act_t > 8.0 or lure_down > 0.5 or enchanted):
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
				var chasing := food != null
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
						_set_act(Act.EAT)   # Game snuffles the food up while the head is down
				elif _time - _fav_call_t < 6.0:
					# its favourite called: it comes, lure or no lure
					var to := whistle_pos - ground_pos
					to.y = 0
					desired_turn = clampf(_angle_to(to) * 1.4, -MAX_TURN * 1.3, MAX_TURN * 1.3)
					target_speed = WALK_SPEED * 0.95 if to.length() > 14.0 else 0.0
				elif lure_down > 0.5:
					fruit_target = null
					desired_turn = -lure_yaw * MAX_TURN * mods.turn
					target_speed = (SLOW_SPEED if hungry else (TROT_SPEED if (joy > 0.75 and _time - _last_fed < 40.0) or enchanted else WALK_SPEED)) * mods.speed
				elif _time - whistle_time < 5.0:
					var to := whistle_pos - ground_pos
					to.y = 0
					desired_turn = clampf(_angle_to(to) * 1.2, -MAX_TURN, MAX_TURN)
					target_speed = WALK_SPEED * 0.8 if to.length() > 16.0 else 0.0
				# deep water: it won't wade in unless enchanted or tempted by food
				balk = false
				if target_speed > 0.1 and not chasing and serenade <= 0.55 and _deep_ahead():
					target_speed = 0.0
					balk = true
					_balk_moan -= dt
					if _balk_moan <= 0.0:
						_balk_moan = 8.0
						vocal.emit("moan", global_head())
				if act != Act.EAT:   # (the food branch may have just started eating)
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
	if act not in [Act.IDLE, Act.WALK]:
		balk = false
	yaw = wrapf(yaw + turn_rate * dt * clampf(speed / 1.5, 0.35, 1.0) * (1.0 if speed > 0.05 or act == Act.BLOCKED or balk else 0.0), -PI, PI)
	ground_pos += forward() * speed * dt
	ground_pos.y = world.terrain.height(ground_pos.x, ground_pos.z)
	_idle_moo -= dt
	if _idle_moo <= 0.0:
		_idle_moo = randf_range(14.0, 28.0)
		vocal.emit("grumble" if hungry else "moan", global_head())
	mouth_open = 1.0 if act in [Act.EAT, Act.SNEEZE_IN] else 0.0

var _last_wet := -100.0
func _deep_ahead() -> bool:
	var t := world.terrain
	if _time - _last_wet < 25.0:
		return false   # already soaked: one more channel makes no difference
	var probe := ground_pos + forward() * 15.0
	return t.height(probe.x, probe.z) < Terrain.WATER_LEVEL - 1.8

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
	var best_d := 30.0
	var m := mouth_global()
	var f_dir := forward()
	for f in _food_list:
		if not is_instance_valid(f) or f.get("held_by") != 0:
			continue
		var to: Vector3 = f.global_position - m
		to.y = 0
		# must be ahead of the mouth (or right at it) and roughly in front
		if f_dir.dot(to) < -4.5 or (absf(_angle_to(f.global_position - ground_pos)) > deg_to_rad(60) and to.length() > 5.0):
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

func whistle(at: Vector3, from_favourite := false) -> void:
	whistle_pos = at
	whistle_time = _time
	if from_favourite and at.distance_to(ground_pos) < 90.0:
		_fav_call_t = _time

## Server: someone was kind to it. Returns the new favourite if it just changed, else 0.
func befriend(peer: int, amount: float) -> int:
	if peer <= 0:
		return 0
	affection[peer] = float(affection.get(peer, 0.0)) + amount
	var best := 0
	var best_v := 0.0
	var second := 0.0
	for k in affection:
		var v: float = affection[k]
		if v > best_v:
			second = best_v
			best_v = v
			best = k
		elif v > second:
			second = v
	if best != favourite and best_v >= 14.0 and best_v - second >= 4.0:
		favourite = best
		return best
	return 0

func nuzzle() -> void:
	_nuzzle = 2.2

var _wave := 0.0
func wave_back() -> void:
	_wave = 1.6

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
		float(act), act_t, lure_yaw, lure_down, float(lure_operator), mouth_open, turn_rate, itch, pollen,
		fl_yaw, fl_charge, float(fl_operator), serenade, 1.0 if balk else 0.0, float(favourite),
		ladder_t[0], ladder_t[1]])

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
	if sb.size() > 20:
		if fl_operator != multiplayer.get_unique_id() or int(sb[19]) != fl_operator:
			fl_yaw = lerpf(sa[17], sb[17], k)
			fl_charge = sb[18]
		fl_operator = int(sb[19])
		serenade = sb[20]
	if sb.size() > 21:
		balk = sb[21] > 0.5
	if sb.size() > 22:
		favourite = int(sb[22])
	if sb.size() > 24:
		ladder_t[0] = sb[23]
		ladder_t[1] = sb[24]

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
	if fl_body:
		fl_body.global_transform = flinger_xf()

func _update_visuals(dt: float) -> void:
	_update_legs(dt)
	_update_head(dt)
	_update_lure(dt)
	_update_flinger(dt)
	_update_snow(dt)
	for i in _ladder_nodes.size():
		var lad := _ladder_nodes[i]
		lad.scale.y = move_toward(lad.scale.y, 1.0 if ladder_t[i] > 0.0 else 0.04, dt * (1.5 if ladder_t[i] > 0.0 else 0.6))
		lad.rotation.x = sin(Time.get_ticks_msec() * 0.0011 + i) * 0.04 * lad.scale.y
	_celebrate = maxf(_celebrate - dt, 0.0)
	var now := Time.get_ticks_msec() * 0.001
	_tail_sway = lerpf(_tail_sway, -turn_rate * 18.0 + sin(phase * TAU) * 1.2 * clampf(speed, 0.0, 1.0) + sin(now * 0.7) * 0.8 + sin(now * 5.0) * 2.0 * serenade, G.damp(2.0, dt))
	if Engine.get_physics_frames() % 4 == 0:
		_rebuild_tail(_tail_sway)
	var lantern: OmniLight3D = body.get_node("Lantern")
	lantern.light_energy = lerpf(lantern.light_energy, 1.8 if _is_dark() else 0.45, G.damp(1.0, dt))

func _update_flinger(dt: float) -> void:
	if fl_arm == null:
		return
	_fl_fire_t += dt
	var t := _fl_fire_t
	var ang := 0.0
	if t < 0.12:
		ang = lerpf(-0.12, 1.75, (t / 0.12) * (t / 0.12))
	elif t < 0.6:
		ang = 1.75 + sin((t - 0.12) * 34.0) * 0.07 * (0.6 - t) / 0.48   # judders against the crossbar
	elif t < 2.1:
		ang = lerpf(1.75, 0.0, smoothstep(0.6, 2.1, t))
	else:
		ang = -0.12 * fl_charge + sin(Time.get_ticks_msec() * 0.04) * 0.012 * fl_charge
	fl_arm.rotation.x = -ang

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
			if n.get("peer_id") == favourite and favourite != 0:
				d *= 0.35   # it keeps an eye on its favourite
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
	var now := Time.get_ticks_msec() * 0.001
	if serenade > 0.05 and act in [Act.IDLE, Act.WALK]:
		# swaying along, chin up, eyes half-shut
		target_yaw += sin(now * 2.6) * 0.22 * serenade
		target_pitch += 0.14 * serenade
	if _celebrate > 0.0:
		target_pitch = 0.55 * clampf(_celebrate, 0.0, 1.0)
		target_yaw = sin(now * 3.0) * 0.15
	_wave = maxf(_wave - dt, 0.0)
	if _nuzzle > 0.0:
		_nuzzle -= dt
		# dip the snout, then a little upward boop
		target_pitch = -0.7 if _nuzzle > 0.9 else 0.35
		target_yaw *= 0.3
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
	if _celebrate > 0.0:
		jaw_open = 0.42 * clampf(_celebrate - 0.4, 0.0, 1.0)
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
	droop = lerpf(droop, 0.62, serenade * 0.85)
	for e in 2:
		var lid: Node3D = lids[e]
		lid.rotation.x = lerpf(lid.rotation.x, -(0.15 + droop + blink_k * 1.2), G.damp(20.0, dt))
	for e in ears.size():
		var ear: Node3D = ears[e]
		var sx := -1.0 if e == 0 else 1.0
		ear.rotation.z = sx * (sin(phase * TAU * 4.0 + e) * 0.12 * walk_k + (0.3 if act == Act.SNEEZE_IN else 0.0) + sin(now * 2.6 + e * 1.4) * 0.3 * serenade - 0.4 * minf(_celebrate, 1.0) + sin(now * 14.0 + e) * 0.45 * minf(_wave, 1.0))

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
