class_name TenderVisual
extends Node3D
## A Tender: pear-shaped felt body, floating mitts and boots, a hat. All procedural animation.

var color := G.MARIGOLD
var hat := "beanie"
var body_pivot: Node3D
var body_mi: MeshInstance3D
var hands: Array[Node3D] = []
var feet: Array[Node3D] = []
var pupils: Array[Node3D] = []
var eyes: Array[Node3D] = []
var hat_node: Node3D
var smile_mi: MeshInstance3D
var mouth_mi: MeshInstance3D
var talk := 0.0               # 0..1 voice loudness, drives the mouth

# animation inputs (set by Player every frame)
var move_speed := 0.0        # horizontal speed
var grounded := true
var vert_speed := 0.0
var tumbling := false
var spin := Vector3.ZERO     # tumble angular velocity
var carrying := false
var at_station := false
var whistling := 0.0
var waving := 0.0
var pointing := 0.0          # >0 while pointing at a ping
var squash := 0.0            # >0 squash, <0 stretch
var flattened := 0.0         # pancake after being stepped on
var look_dir := Vector3.FORWARD
var playing := 0.0           # >0 while thumbing the kalimba
var kalimba: Node3D

var _phase := 0.0
var _blink := 2.0
var _tumble_basis := Basis()
var _breath := 0.0

func build(p_color: Color, p_hat: String) -> void:
	color = p_color
	hat = p_hat
	for c in get_children():
		c.queue_free()
	hands.clear(); feet.clear(); pupils.clear(); eyes.clear()
	body_pivot = Node3D.new()
	body_pivot.position = Vector3(0, 0.12, 0)
	add_child(body_pivot)
	var prof := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.3, 0.02), Vector2(0.44, 0.16), Vector2(0.46, 0.34),
		Vector2(0.42, 0.56), Vector2(0.34, 0.78), Vector2(0.22, 0.94), Vector2(0.0, 1.0)])
	var fn_mesh := Geo.lathe(prof, 18, color)
	body_mi = Mats.mesh_instance(fn_mesh, Mats.toon(Color.WHITE, true, 0.04))
	body_pivot.add_child(body_mi)
	# felt belly patch
	# face
	for sx in [-1, 1]:
		var eye := Node3D.new()
		eye.position = Vector3(sx * 0.135, 0.71, -0.28)
		eye.rotation.y = -sx * 0.25
		body_pivot.add_child(eye)
		var white := Mats.mesh_instance(Geo.blob(Vector3(0.1, 0.125, 0.06), G.PAPER, 0.0, 3, 8, 10))
		eye.add_child(white)
		var pupil := Mats.mesh_instance(Geo.sphere(0.064, G.INK, 10, 8))
		pupil.position = Vector3(0, 0.0, -0.04)
		var glint := Mats.mesh_instance(Geo.sphere(0.018, G.PAPER, 5, 4), Mats.toon(G.PAPER, false))
		glint.position = Vector3(0.022, 0.026, -0.055)
		pupil.add_child(glint)
		eye.add_child(pupil)
		pupils.append(pupil)
		eyes.append(eye)
	var nose := Mats.mesh_instance(Geo.sphere(0.06, color.darkened(0.2).lerp(G.ROSE, 0.6), 8, 6))
	nose.position = Vector3(0, 0.615, -0.365)
	body_pivot.add_child(nose)
	var smile := PackedVector3Array()
	var sr := PackedFloat32Array()
	for k in 7:
		var a := lerpf(-0.75, 0.75, k / 6.0)
		smile.append(Vector3(sin(a) * 0.075, 0.545 - cos(a) * 0.03, -0.345 - cos(a) * 0.01))
		sr.append(0.011)
	smile_mi = Mats.mesh_instance(Geo.tube(smile, sr, G.INK, 4), Mats.toon(Color.WHITE, false))
	body_pivot.add_child(smile_mi)
	# open mouth for talking: a dark oval with a rosy tongue
	var mouth_parts: Array = [[Geo.blob(Vector3(0.06, 0.05, 0.02), G.INK, 0.0, 6, 6, 10), Transform3D()], [Geo.blob(Vector3(0.04, 0.02, 0.012), G.ROSE, 0.0, 7, 4, 8), Transform3D(Basis(), Vector3(0, -0.025, -0.012))]]
	mouth_mi = Mats.mesh_instance(Geo.merge(mouth_parts), Mats.toon(Color.WHITE, false))
	mouth_mi.position = Vector3(0, 0.535, -0.355)
	mouth_mi.scale = Vector3(1, 0.05, 1)
	mouth_mi.visible = false
	body_pivot.add_child(mouth_mi)
	for sx in [-1, 1]:
		var cheek := Mats.mesh_instance(Geo.blob(Vector3(0.05, 0.03, 0.02), G.ROSE, 0.0, 4, 5, 8), Mats.toon(Color.WHITE, false))
		cheek.position = Vector3(sx * 0.235, 0.575, -0.31)
		cheek.rotation.y = sx * 0.6
		body_pivot.add_child(cheek)
	# mitts and boots float free (no limbs)
	var mitt_mesh := Geo.blob(Vector3(0.11, 0.1, 0.1), color.darkened(0.35), 0.05, 7, 7, 10)
	for sx in [-1, 1]:
		var h := Node3D.new()
		add_child(h)
		h.add_child(Mats.mesh_instance(mitt_mesh))
		hands.append(h)
	var boot_mesh := Geo.blob(Vector3(0.12, 0.08, 0.17), G.BARK, 0.04, 8, 6, 10)
	for sx in [-1, 1]:
		var f := Node3D.new()
		add_child(f)
		var bm := Mats.mesh_instance(boot_mesh)
		bm.position = Vector3(0, 0.06, -0.03)
		f.add_child(bm)
		feet.append(f)
	kalimba = Node3D.new()
	kalimba.position = Vector3(0, 0.56, -0.44)
	kalimba.rotation = Vector3(0.9, 0, 0)
	kalimba.visible = false
	body_pivot.add_child(kalimba)
	var kparts: Array = [[Geo.box(Vector3(0.3, 0.07, 0.22), G.WOOD), Transform3D()]]
	for k in 7:
		var len_t := 0.16 - absf(k - 3) * 0.022
		kparts.append([Geo.box(Vector3(0.022, 0.012, len_t), G.STONE.lightened(0.3)), Transform3D(Basis(), Vector3(-0.105 + k * 0.035, 0.045, -0.11 + len_t * 0.5 - 0.02))])
	kparts.append([Geo.cylinder(0.035, 0.035, 0.012, G.INK, 8), Transform3D(Basis(), Vector3(0, 0.036, 0.06))])
	kalimba.add_child(Mats.mesh_instance(Geo.merge(kparts)))
	hat_node = _make_hat(hat)
	if hat_node:
		hat_node.position = Vector3(0, 0.93, 0)
		body_pivot.add_child(hat_node)

## A loose copy of a hat (a magpie's loot).
static func hat_for(kind: String, col: Color) -> Node3D:
	var tv := TenderVisual.new()
	tv.color = col
	var h := tv._make_hat(kind)
	tv.free()
	if h:
		h.scale = Vector3.ONE * 0.62
	return h

func _make_hat(kind: String) -> Node3D:
	var n := Node3D.new()
	var accent := color.darkened(0.45).lerp(G.INK, 0.2)
	match kind:
		"beanie":
			var dome := Geo.lathe(PackedVector2Array([Vector2(0.3, -0.12), Vector2(0.31, 0.0), Vector2(0.27, 0.12), Vector2(0.15, 0.22), Vector2(0.0, 0.25)]), 14, G.PAPER)
			n.add_child(Mats.mesh_instance(dome))
			var brim := Geo.lathe(PackedVector2Array([Vector2(0.31, -0.16), Vector2(0.33, -0.1), Vector2(0.32, -0.03)]), 14, accent)
			n.add_child(Mats.mesh_instance(brim))
			var pom := Mats.mesh_instance(Geo.blob(Vector3(0.1, 0.1, 0.1), accent, 0.3, 9, 6, 8))
			pom.position = Vector3(0, 0.29, 0)
			n.add_child(pom)
		"cone":
			var c := Geo.lathe(PackedVector2Array([Vector2(0.3, -0.1), Vector2(0.24, 0.15), Vector2(0.12, 0.42), Vector2(0.02, 0.62), Vector2(0.0, 0.64)]), 12, G.TEAL if color != G.TEAL else G.PLUM)
			var mi := Mats.mesh_instance(c)
			mi.rotation = Vector3(0.25, 0, 0.15)
			n.add_child(mi)
			var band := Geo.lathe(PackedVector2Array([Vector2(0.31, -0.11), Vector2(0.3, -0.02)]), 12, G.MARIGOLD)
			n.add_child(Mats.mesh_instance(band))
		"bucket":
			var b := Geo.lathe(PackedVector2Array([Vector2(0.46, -0.1), Vector2(0.44, -0.07), Vector2(0.3, -0.03), Vector2(0.27, 0.14), Vector2(0.2, 0.2), Vector2(0.0, 0.21)]), 16, G.MEADOW_DRY)
			n.add_child(Mats.mesh_instance(b))
		"sprout":
			var stem := Mats.mesh_instance(Geo.cylinder(0.02, 0.025, 0.25, G.MOSS_DARK, 5))
			stem.position = Vector3(0, 0.12, 0)
			n.add_child(stem)
			for sx in [-1, 1]:
				var leaf := Mats.mesh_instance(Geo.blob(Vector3(0.14, 0.03, 0.07), G.MOSS, 0.0, 10, 4, 8))
				leaf.position = Vector3(sx * 0.12, 0.25, 0)
				leaf.rotation = Vector3(0, 0, sx * 0.4)
				n.add_child(leaf)
		"beret":
			var disc := Mats.mesh_instance(Geo.blob(Vector3(0.36, 0.08, 0.34), G.TERRACOTTA if color != G.TERRACOTTA else G.PLUM, 0.04, 11, 6, 14))
			disc.position = Vector3(0.05, 0.02, 0)
			disc.rotation = Vector3(0, 0, -0.25)
			n.add_child(disc)
			var nub := Mats.mesh_instance(Geo.cylinder(0.015, 0.025, 0.08, G.INK, 4))
			nub.position = Vector3(0.05, 0.1, 0)
			n.add_child(nub)
		"teacup", "acorn", "crown", "feather", "shell", "lampshade":
			var mi := Mats.mesh_instance(PropsLib.keepsake_mesh("ks_" + kind))
			match kind:
				"teacup":   # worn upside down, saucer on top
					mi.transform = Transform3D(Basis(Vector3.RIGHT, PI).scaled(Vector3.ONE * 1.25), Vector3(0, 0.3, 0))
				"acorn":
					mi.transform = Transform3D(Basis(Vector3.FORWARD, 0.15).scaled(Vector3.ONE * 1.3), Vector3(0, 0.12, 0))
				"crown":
					mi.transform = Transform3D(Basis(Vector3.FORWARD, -0.12).scaled(Vector3.ONE * 1.3), Vector3(0, -0.06, 0))
				"feather":
					mi.transform = Transform3D(Basis(Vector3.FORWARD, -0.35), Vector3(0.12, 0.02, 0.08))
				"shell":
					mi.transform = Transform3D(Basis().scaled(Vector3.ONE * 1.35), Vector3(0, -0.06, 0.02))
				"lampshade":
					mi.transform = Transform3D(Basis().scaled(Vector3.ONE * 1.15), Vector3(0, -0.14, 0))
			n.add_child(mi)
		_:
			n.free()
			return null
	return n

func _process(dt: float) -> void:
	if body_pivot == null:
		return
	var walk_k := clampf(move_speed / 4.5, 0.0, 1.6)
	if grounded and not tumbling:
		_phase += dt * (2.2 + move_speed * 1.6)
	_breath += dt
	squash = lerpf(squash, 0.0, G.damp(9.0, dt))
	flattened = maxf(flattened - dt * 0.6, 0.0)
	# body pose
	var bob := absf(sin(_phase)) * 0.07 * walk_k if grounded else 0.0
	var breathe := sin(_breath * 2.4) * 0.015
	var sy := 1.0 + breathe - squash * 0.25
	var sxz := 1.0 - breathe * 0.5 + squash * 0.18
	if not grounded and not tumbling:
		sy += clampf(vert_speed * 0.02, -0.08, 0.12)
		sxz -= clampf(vert_speed * 0.012, -0.05, 0.06)
	if flattened > 0.0:
		var f := minf(flattened, 1.0)
		sy = lerpf(sy, 0.22, f)
		sxz = lerpf(sxz, 1.7, f)
	if tumbling:
		_tumble_basis = Basis.from_euler(spin * dt) * _tumble_basis
		_tumble_basis = _tumble_basis.orthonormalized()
	else:
		_tumble_basis = _tumble_basis.slerp(Basis(), G.damp(10.0, dt))
	var lean := Basis(Vector3.RIGHT, -walk_k * 0.12)
	body_pivot.transform = Transform3D(_tumble_basis * lean * Basis().scaled(Vector3(sxz, sy, sxz)), Vector3(0, 0.12 + bob, 0))
	# feet
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var p := Vector3(side * 0.17, 0.0, 0.0)
		if tumbling:
			p = body_pivot.transform * Vector3(side * 0.25, -0.05, sin(_breath * 20.0 + i * 3.0) * 0.2)
		elif grounded:
			var ph := _phase + (PI if i == 1 else 0.0)
			p.z = -sin(ph) * 0.26 * walk_k
			p.y = maxf(cos(ph), 0.0) * 0.14 * walk_k
		else:
			p.y = 0.12 + (0.08 if i == 0 else -0.02)
			p.z = -0.12 if i == 0 else 0.1
		feet[i].position = feet[i].position.lerp(p, G.damp(25.0, dt))
	# hands
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var p := Vector3(side * 0.52, 0.42, 0.0)
		if tumbling:
			p = body_pivot.transform * Vector3(side * 0.6, 0.6 + sin(_breath * 23.0 + i) * 0.2, cos(_breath * 19.0 + i) * 0.2)
		elif carrying:
			p = Vector3(side * 0.34, 0.75, -0.48)
		elif at_station:
			p = Vector3(side * 0.42, 0.62, -0.5)
		elif playing > 0.0:
			p = Vector3(side * 0.17, 0.56 + absf(sin(_breath * 18.0 + i * 1.7)) * 0.04, -0.42)
		elif whistling > 0.0:
			p = Vector3(side * 0.12 + (0.0 if i == 0 else 0.4), 0.62 if i == 0 else 0.5, -0.4 if i == 0 else 0.0)
		elif pointing > 0.0 and i == 1:
			p = Vector3(0.3, 0.95, -0.7)
		elif waving > 0.0 and i == 1:
			p = Vector3(0.58, 1.15 + sin(_breath * 14.0) * 0.06, -0.05 + sin(_breath * 14.0) * 0.12)
		elif not grounded:
			p = Vector3(side * 0.62, 0.78 + vert_speed * 0.02, 0.0)
		else:
			var ph := _phase + (0.0 if i == 0 else PI)
			p.z = sin(ph) * 0.22 * walk_k
			p.y += absf(cos(ph)) * 0.04 * walk_k
		hands[i].position = hands[i].position.lerp(p, G.damp(18.0, dt))
	playing = maxf(playing - dt, 0.0)
	pointing = maxf(pointing - dt, 0.0)
	kalimba.visible = playing > 0.0 and not tumbling and not carrying
	# talking mouth (voice chat) - flaps with loudness, a little wobble so it looks spoken
	if mouth_mi:
		var open := clampf(talk * 2.2, 0.0, 1.0) * (0.75 + 0.25 * sin(_breath * 31.0))
		mouth_mi.visible = open > 0.06
		smile_mi.visible = not mouth_mi.visible
		mouth_mi.scale = Vector3(0.8 + open * 0.3, maxf(open, 0.05), 1.0)
	# eyes: blink, look
	_blink -= dt
	var lid := 1.0
	if _blink < 0.0:
		lid = 0.1
		if _blink < -0.12:
			_blink = randf_range(1.8, 5.0)
	if tumbling:
		lid = 1.25
	for e in eyes:
		e.scale = Vector3(1, lerpf(e.scale.y, lid, G.damp(30.0, dt)), 1)
	var ld := global_transform.basis.inverse() * look_dir
	var px := clampf(ld.x * 0.02, -0.02, 0.02)
	var py := clampf(ld.y * 0.02, -0.015, 0.02)
	for p in pupils:
		p.position = Vector3(px, py, -0.04)

func land(strength: float) -> void:
	squash = clampf(strength * 0.12, 0.2, 1.0)
