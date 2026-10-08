class_name BeastBuild
## Builds the Mossback's body from math. Local space: forward = -Z, up = +Y, origin on the ground.
## The shell is a superellipsoid with a hump; `back_height()` gives the exact top surface.

const C := Vector3(0, 11.0, 0)          # torso centre
const R := Vector3(8.6, 5.6, 13.8)      # torso radii
const E1 := 0.62                         # vertical squareness (<1 = flatter top)
const E2 := 0.92                         # horizontal squareness
const HIPS := [Vector3(-5.4, 8.0, -7.8), Vector3(5.4, 8.0, -7.8), Vector3(-5.4, 8.0, 7.6), Vector3(5.4, 8.0, 7.6)]
const NECK := Vector3(0, 11.0, -12.0)
const HEAD_OFFSET := Vector3(0, -1.6, -7.0)  # from neck pivot to head centre
const MOUTH_LOCAL := Vector3(0, -2.4, -4.4)  # mouth relative to head centre
const LURE_POST := Vector3(0, 0, -8.6)       # x/z on the back; y from back_height
const HUT := Vector3(0, 0, 4.6)
const TAIL_ROOT := Vector3(0, 0, 10.2)

# coat colours for the current beast (set before building)
static var fur := Color("8f7d6b")
static var fur_light := Color("c2ad8f")
static var fur_dark := Color("5e4f45")

const COATS := [
	["chestnut", Color("8f7d6b"), Color("c2ad8f"), Color("5e4f45")],
	["slate", Color("7a7f8c"), Color("b9bcc2"), Color("4c505c")],
	["cream", Color("b8a585"), Color("e6d8b8"), Color("7f6f58")],
	["rust", Color("a0664a"), Color("d6a27c"), Color("6a3f2e")],
	["dusk", Color("6f6a86"), Color("a9a3be"), Color("47435a")],
]

static func _hump(x: float, z: float) -> float:
	return 1.3 * exp(-pow(z - 1.5, 2) / 70.0 - x * x / 45.0)

static func _f(d: Vector3) -> float:
	var x := absf(d.x / R.x)
	var y := absf(d.y / R.y)
	var z := absf(d.z / R.z)
	return pow(pow(x, 2.0 / E2) + pow(z, 2.0 / E2), E2 / E1) + pow(y, 2.0 / E1)

static func shell_point(dir: Vector3) -> Vector3:
	var r := pow(_f(dir), -E1 / 2.0)
	var p := C + dir * r
	if p.y > C.y:
		p.y += _hump(p.x, p.z) * smoothstep(0.0, R.y, p.y - C.y)
	return p

## Exact top-of-shell height at local (x, z); returns -INF if outside the footprint.
static func back_height(x: float, z: float) -> float:
	var X := absf(x / R.x)
	var Z := absf(z / R.z)
	var s := pow(pow(X, 2.0 / E2) + pow(Z, 2.0 / E2), E2 / E1)
	if s >= 1.0:
		return -INF
	var y := C.y + R.y * pow(1.0 - s, E1 / 2.0)
	return y + _hump(x, z) * smoothstep(0.0, R.y, y - C.y)

static func top_point(x: float, z: float) -> Vector3:
	return Vector3(x, back_height(x, z), z)

static func _shell_color(p: Vector3, n: Vector3, noise: FastNoiseLite) -> Color:
	var nn := noise.get_noise_3dv(p * 0.35)
	var moss_k := smoothstep(0.42, 0.62, n.y + nn * 0.18)
	var belly_k := smoothstep(-0.2, -0.6, n.y)
	var c := fur.lerp(fur_light, belly_k)
	c = c.lerp(fur_dark, smoothstep(0.15, 0.4, nn) * 0.5 * (1.0 - moss_k))
	var moss := G.MOSS.lerp(G.MOSS_DARK, smoothstep(-0.2, 0.4, nn)).lerp(G.MEADOW, smoothstep(0.35, 0.6, -nn) * 0.6)
	return c.lerp(moss, moss_k)

static func shell_mesh(rings := 40, segs := 56) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = 3
	noise.frequency = 0.5
	var pts: Array[PackedVector3Array] = []
	for i in rings + 1:
		var phi := PI * float(i) / rings
		var row := PackedVector3Array()
		for s in segs + 1:
			var th := TAU * float(s % segs) / segs
			var d := Vector3(sin(phi) * cos(th), -cos(phi), sin(phi) * sin(th))
			row.append(shell_point(d))
		pts.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rings:
		for s in segs:
			var a := pts[i][s]; var b := pts[i][s + 1]; var c := pts[i + 1][s + 1]; var d := pts[i + 1][s]
			for p in [a, c, b, a, d, c]:
				var n := ((p as Vector3) - C).normalized()
				st.set_color(_shell_color(p, n, noise))
				st.add_vertex(p)
	st.generate_normals()
	return st.commit()

static func shell_collision() -> ConcavePolygonShape3D:
	var rings := 18
	var segs := 28
	var pts: Array[PackedVector3Array] = []
	for i in rings + 1:
		var phi := PI * float(i) / rings
		var row := PackedVector3Array()
		for s in segs + 1:
			var th := TAU * float(s % segs) / segs
			row.append(shell_point(Vector3(sin(phi) * cos(th), -cos(phi), sin(phi) * sin(th))))
		pts.append(row)
	var faces := PackedVector3Array()
	for i in rings:
		for s in segs:
			var a := pts[i][s]; var b := pts[i][s + 1]; var c := pts[i + 1][s + 1]; var d := pts[i + 1][s]
			faces.append_array([a, c, b, a, d, c])
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	return shape

## Shaggy fringe: drooping tufts around the shell's skirt.
static func fringe_multimesh() -> MultiMesh:
	# a lock of shaggy hair: narrow at the root, a little belly, a pointed curling tip
	var tuft := Geo.lathe(PackedVector2Array([Vector2(0.0, 0.1), Vector2(0.3, -0.1), Vector2(0.34, -0.9), Vector2(0.24, -1.9), Vector2(0.1, -2.7), Vector2(0.0, -3.0)]), 6, Color.WHITE, Vector2(1.0, 0.55), 0.08, 3)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = tuft
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	for row in 4:
		var n := 150 - row * 20
		for k in n:
			var th := TAU * (float(k) + rng.randf() * 0.6) / n
			var phi := lerpf(PI * 0.6, PI * 0.45, float(row) / 3.0) + rng.randf_range(-0.05, 0.05)
			var d := Vector3(sin(phi) * cos(th), -cos(phi), sin(phi) * sin(th))
			var p := shell_point(d)
			var out := Vector3(p.x, 0, p.z).normalized()
			var s := rng.randf_range(0.45, 0.75) * (1.0 + 0.1 * row)
			var b := Basis(Vector3.UP, atan2(out.x, out.z)) * Basis(Vector3.RIGHT, -rng.randf_range(0.05, 0.3)) * Basis(Vector3.FORWARD, rng.randf_range(-0.15, 0.15))
			xfs.append(Transform3D(b.scaled(Vector3(s, s * rng.randf_range(0.9, 1.4), s)), p - out * 0.2))
			var c := fur.lerp(fur_light, rng.randf() * 0.45).lerp(fur_dark, rng.randf() * 0.35)
			if row == 3:
				c = c.lerp(G.MOSS_DARK, 0.5)
			cols.append(c)
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_color(i, cols[i])
	return mm

## Points on the walkable moss plateau, for planting grass etc.
static func garden_points(count: int, seed_v: int, min_up := 0.75) -> Array[Transform3D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var out: Array[Transform3D] = []
	var tries := 0
	while out.size() < count and tries < count * 6:
		tries += 1
		var x := rng.randf_range(-R.x, R.x) * 0.85
		var z := rng.randf_range(-R.z, R.z) * 0.85
		var y := back_height(x, z)
		if y == -INF:
			continue
		var e := 0.4
		var hx0 := back_height(x - e, z); var hx1 := back_height(x + e, z)
		var hz0 := back_height(x, z - e); var hz1 := back_height(x, z + e)
		if is_inf(hx0) or is_inf(hx1) or is_inf(hz0) or is_inf(hz1):
			continue
		var n := Vector3(hx0 - hx1, 2.0 * e, hz0 - hz1).normalized()
		if n.y < min_up:
			continue
		# keep the hut and lure post areas clear
		if Vector2(x - HUT.x, z - HUT.z).length() < 3.2 or Vector2(x, z - LURE_POST.z).length() < 1.6:
			continue
		var b := Basis(Quaternion(Vector3.UP, n)) * Basis(Vector3.UP, rng.randf() * TAU)
		out.append(Transform3D(b, Vector3(x, y - 0.05, z)))
	return out

static func hut_mesh() -> ArrayMesh:
	var parts: Array = []
	var w := 4.2
	var d := 3.6
	var h := 2.6
	# floor deck sits flat; legs reach down to the shell
	parts.append([Geo.box(Vector3(w + 0.6, 0.25, d + 1.4), G.WOOD), Transform3D(Basis(), Vector3(0, 0.0, -0.3))])
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			parts.append([Geo.cylinder(0.12, 0.14, 1.6, G.BARK, 5), Transform3D(Basis(), Vector3(sx * w * 0.45, -0.8, sz * d * 0.45))])
	# walls (back + sides), each with plank stripes
	parts.append([Geo.box(Vector3(w, h, 0.2), G.WOOD_LIGHT), Transform3D(Basis(), Vector3(0, h * 0.5, d * 0.5))])
	for sx in [-1, 1]:
		parts.append([Geo.box(Vector3(0.2, h, d), G.WOOD_LIGHT), Transform3D(Basis(), Vector3(sx * w * 0.5, h * 0.5, 0))])
		for k in 3:
			parts.append([Geo.box(Vector3(0.24, 0.07, d), G.WOOD), Transform3D(Basis(), Vector3(sx * w * 0.5, 0.6 + k * 0.7, 0))])
	# front wall halves with a doorway
	for sx in [-1, 1]:
		parts.append([Geo.box(Vector3(w * 0.3, h, 0.2), G.WOOD_LIGHT), Transform3D(Basis(), Vector3(sx * w * 0.35, h * 0.5, -d * 0.5))])
	parts.append([Geo.box(Vector3(w, 0.6, 0.2), G.WOOD_LIGHT), Transform3D(Basis(), Vector3(0, h - 0.3, -d * 0.5))])
	# round window on the back wall
	parts.append([Geo.cylinder(0.45, 0.45, 0.26, G.INK, 12), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, h * 0.6, d * 0.5))])
	parts.append([Geo.cylinder(0.55, 0.55, 0.22, G.WOOD, 12), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, h * 0.6, d * 0.5 + 0.03))])
	# crooked pitched roof
	var roof_len := d + 1.4
	for sx in [-1, 1]:
		var b := Basis(Vector3.FORWARD, sx * 0.62)
		parts.append([Geo.box(Vector3(w * 0.68, 0.22, roof_len), G.TERRACOTTA), Transform3D(b, Vector3(sx * w * 0.27, h + 0.85, 0))])
		for k in 4:
			parts.append([Geo.box(Vector3(w * 0.7, 0.08, 0.12), G.TERRACOTTA.darkened(0.25)), Transform3D(b, Vector3(sx * w * 0.27, h + 0.98, -roof_len * 0.4 + k * roof_len * 0.27))])
	parts.append([Geo.box(Vector3(0.3, 0.3, roof_len + 0.1), G.BARK), Transform3D(Basis(), Vector3(0, h + 1.55, 0))])
	# stone chimney
	parts.append([Geo.cylinder(0.38, 0.45, 1.8, G.STONE, 7), Transform3D(Basis(), Vector3(1.1, h + 1.5, 0.9))])
	parts.append([Geo.cylinder(0.48, 0.48, 0.25, G.STONE_DARK, 7), Transform3D(Basis(), Vector3(1.1, h + 2.4, 0.9))])
	# a little pennant pole
	parts.append([Geo.cylinder(0.04, 0.05, 2.0, G.BARK, 4), Transform3D(Basis(), Vector3(-1.4, h + 2.2, 1.2))])
	parts.append([Geo.box(Vector3(0.05, 0.45, 0.8), G.MARIGOLD), Transform3D(Basis(), Vector3(-1.4, h + 2.9, 1.6))])
	return Geo.merge(parts)

## Collision boxes for the hut: [BoxShape3D, Transform3D] pairs in hut-local space.
static func hut_shapes() -> Array:
	var w := 4.2
	var d := 3.6
	var h := 2.6
	var out: Array = []
	var add := func(size: Vector3, xf: Transform3D) -> void:
		var b := BoxShape3D.new()
		b.size = size
		out.append([b, xf])
	add.call(Vector3(w + 0.6, 0.25, d + 1.4), Transform3D(Basis(), Vector3(0, 0, -0.3)))
	add.call(Vector3(w, h, 0.2), Transform3D(Basis(), Vector3(0, h * 0.5, d * 0.5)))
	for sx in [-1, 1]:
		add.call(Vector3(0.2, h, d), Transform3D(Basis(), Vector3(sx * w * 0.5, h * 0.5, 0)))
		add.call(Vector3(w * 0.3, h, 0.2), Transform3D(Basis(), Vector3(sx * w * 0.35, h * 0.5, -d * 0.5)))
		add.call(Vector3(w * 0.68, 0.22, d + 1.4), Transform3D(Basis(Vector3.FORWARD, sx * 0.62), Vector3(sx * w * 0.27, h + 0.85, 0)))
	return out

static func head_mesh() -> ArrayMesh:
	var fn := func(p: Vector3) -> Color:
		var c := fur.lerp(fur_light, smoothstep(0.0, -2.5, p.y))
		return c.lerp(G.MOSS, smoothstep(2.2, 3.2, p.y) * 0.7)
	var parts: Array = []
	parts.append([Geo.blob(Vector3(4.1, 3.5, 4.4), fur, 0.05, 21, 16, 22, false, fn), Transform3D()])
	# muzzle
	var mfn := func(p: Vector3) -> Color:
		return fur_light.lerp(G.ROSE.lerp(fur_light, 0.5), smoothstep(0.5, 1.6, -p.z) * 0.5)
	parts.append([Geo.blob(Vector3(3.1, 2.1, 2.7), fur_light, 0.04, 22, 12, 18, false, mfn), Transform3D(Basis(), Vector3(0, -1.3, -2.9))])
	# nostrils
	for sx in [-1, 1]:
		parts.append([Geo.sphere(0.32, G.INK, 8, 6), Transform3D(Basis().scaled(Vector3(1.0, 0.7, 0.6)), Vector3(sx * 0.95, -0.7, -5.4))])
	# horns
	for sx in [-1, 1]:
		var horn := Geo.lathe(PackedVector2Array([Vector2(0.55, 0.0), Vector2(0.5, 0.6), Vector2(0.32, 1.3), Vector2(0.0, 1.8)]), 8, G.PAPER_DARK)
		parts.append([horn, Transform3D(Basis(Vector3.FORWARD, -sx * 0.5) * Basis(Vector3.RIGHT, -0.35), Vector3(sx * 1.7, 2.9, 0.6))])
	return Geo.merge(parts)

static func jaw_mesh() -> ArrayMesh:
	var parts: Array = []
	parts.append([Geo.blob(Vector3(2.7, 1.0, 2.6), fur_light, 0.03, 23, 10, 16), Transform3D(Basis(), Vector3(0, -0.4, -2.0))])
	parts.append([Geo.blob(Vector3(2.2, 0.5, 2.1), G.PLUM.darkened(0.3), 0.0, 24, 6, 12), Transform3D(Basis(), Vector3(0, 0.35, -2.0))])
	parts.append([Geo.blob(Vector3(1.2, 0.35, 1.6), G.ROSE, 0.05, 25, 6, 10), Transform3D(Basis(), Vector3(0, 0.6, -2.3))])
	return Geo.merge(parts)

static func ear_mesh() -> ArrayMesh:
	var fn := func(p: Vector3) -> Color:
		return fur.lerp(G.ROSE, smoothstep(-0.1, -0.35, p.z) * 0.6)
	return Geo.blob(Vector3(0.8, 2.2, 0.35), fur, 0.06, 31, 8, 10, false, fn)

static func leg_segment_mesh(r0: float, r1: float, color: Color) -> ArrayMesh:
	# unit length along +Y, radius r0 at bottom, r1 at top
	var prof := PackedVector2Array([Vector2(0.0, -0.05), Vector2(r0 * 0.9, 0.0), Vector2(r0, 0.15), Vector2(lerpf(r0, r1, 0.6), 0.6), Vector2(r1, 0.95), Vector2(r1 * 0.8, 1.05), Vector2(0.0, 1.08)])
	return Geo.lathe(prof, 14, color, Vector2.ONE, 0.04, 17)

static func foot_mesh() -> ArrayMesh:
	var parts: Array = []
	var fn := func(p: Vector3) -> Color:
		return fur_dark.lerp(fur, smoothstep(-0.3, 0.6, p.y))
	parts.append([Geo.blob(Vector3(2.0, 1.0, 2.3), fur_dark, 0.06, 41, 8, 14, false, fn), Transform3D(Basis(), Vector3(0, 0.55, -0.2))])
	for k in 3:
		var x := (k - 1) * 0.95
		parts.append([Geo.blob(Vector3(0.5, 0.42, 0.42), G.PAPER_DARK, 0.0, 42 + k, 5, 8), Transform3D(Basis(), Vector3(x, 0.35, -2.15 + absf(x) * 0.25))])
	return Geo.merge(parts)

static func tail_points(sway: float) -> PackedVector3Array:
	var root := top_point(TAIL_ROOT.x, TAIL_ROOT.z)
	var pts := PackedVector3Array()
	var n := 9
	for i in n:
		var t := float(i) / (n - 1)
		var z := root.z + t * 19.0
		var y := lerpf(root.y - 0.4, 0.9, pow(t, 0.75))
		var x := sin(t * PI * 0.9) * sway * t
		pts.append(Vector3(x, y, z))
	return pts

static func tail_radii() -> PackedFloat32Array:
	var r := PackedFloat32Array()
	for i in 9:
		var t := float(i) / 8.0
		r.append(lerpf(2.3, 0.7, pow(t, 0.8)))
	return r

# ---------------------------------------------------------------- lookout: gangplank + spyglass
const RAMP_FROM := Vector3(2.75, -0.65, -3.4)   # hut-local: runs along the cottage's side
const RAMP_TO := Vector3(2.75, 2.98, 1.9)
const SPYGLASS := Vector3(0.0, 4.55, -1.4)    # hut-local, on the ridge

static func ramp_mesh() -> ArrayMesh:
	var dir := RAMP_TO - RAMP_FROM
	var l := dir.length()
	var parts: Array = []
	var b := Basis.looking_at(dir.normalized(), Vector3.UP)
	parts.append([Geo.box(Vector3(1.2, 0.12, l), G.WOOD_LIGHT), Transform3D(b, (RAMP_FROM + RAMP_TO) * 0.5)])
	for k in 7:
		var t := (k + 0.5) / 7.0
		parts.append([Geo.box(Vector3(1.2, 0.08, 0.1), G.WOOD), Transform3D(b, RAMP_FROM.lerp(RAMP_TO, t) + b.y * 0.08)])
	# rope handrail posts
	for side in [-1, 1]:
		for t in [0.05, 0.95]:
			var p: Vector3 = RAMP_FROM.lerp(RAMP_TO, t) + b.x * 0.6 * side
			parts.append([Geo.cylinder(0.04, 0.05, 0.8, G.BARK, 4), Transform3D(Basis(), p + Vector3(0, 0.4, 0))])
	return Geo.merge(parts)

static func ramp_shape() -> Array:
	var dir := RAMP_TO - RAMP_FROM
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 0.2, dir.length() + 0.3)
	return [box, Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), (RAMP_FROM + RAMP_TO) * 0.5)]

static func spyglass_mesh() -> ArrayMesh:
	var parts: Array = []
	for k in 3:
		var a := TAU * k / 3.0
		var foot := Vector3(cos(a) * 0.35, -0.75, sin(a) * 0.35)
		parts.append([Geo.tube(PackedVector3Array([foot, Vector3(0, 0, 0)]), PackedFloat32Array([0.03, 0.03]), G.BARK, 4), Transform3D()])
	var tube := Geo.lathe(PackedVector2Array([Vector2(0.07, -0.5), Vector2(0.075, 0.0), Vector2(0.06, 0.05), Vector2(0.06, 0.45), Vector2(0.09, 0.5), Vector2(0.09, 0.6)]), 10, Color("b0803e"))
	parts.append([tube, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5 + 0.1), Vector3(0, 0.08, 0))])
	return Geo.merge(parts)
