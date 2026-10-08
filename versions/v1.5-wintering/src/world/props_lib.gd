class_name PropsLib
## Procedural meshes for world props. Built once, shared everywhere.

static var _cache := {}

static func get_mesh(key: String) -> Mesh:
	if _cache.has(key):
		return _cache[key]
	var m: Mesh
	var parts := key.split(":")
	match parts[0]:
		"tree":
			m = _tree(int(parts[1]), int(parts[2]), int(parts[3]) if parts.size() > 3 else 0)
		"rock":
			m = _rock(int(parts[1]))
		"grass":
			m = _grass_clump()
		"flowers":
			m = _flower_clump(int(parts[1]))
		"plumbob":
			m = _plumbob()
		"mite":
			m = _mite()
		"ks_teacup", "ks_acorn", "ks_crown", "ks_feather", "ks_shell", "ks_lampshade":
			m = keepsake_mesh(parts[0])
		"thistle":
			m = _thistle_clump()
		"magpie":
			m = magpie_body()
		"magpie_wing":
			m = magpie_wing(float(parts[1]))
		"nest":
			m = nest_mesh()
		"gourdle":
			m = _gourdle()
		"sweetroot":
			m = _sweetroot()
		"waystone":
			m = _waystone()
		"bell":
			m = Geo.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.9, 0.05), Vector2(0.75, 0.3), Vector2(0.55, 0.9), Vector2(0.5, 1.4), Vector2(0.25, 1.6), Vector2(0.0, 1.62)]), 16, Color("b0803e"))
	_cache[key] = m
	return m

static func _shade_fn(base: Color, top: Color, under: Color, radius: float) -> Callable:
	return func(p: Vector3) -> Color:
		var t := clampf(p.y / radius * 0.5 + 0.5, 0.0, 1.0)
		var c := under.lerp(base, smoothstep(0.0, 0.5, t))
		return c.lerp(top, smoothstep(0.55, 1.0, t))

## [base, top, under] canopy colours for a tree variant in a biome.
static func canopy(variant: int, biome: int) -> Array:
	var table := {
		0: [[G.MOSS, G.MEADOW, G.MOSS_DARK], [G.MOSS, G.MEADOW, G.MOSS_DARK], [G.MOSS_DARK, G.TEAL, G.MOSS_DARK], [G.MEADOW_DRY, G.BUTTER, G.MOSS]],
		1: [[Color("8c9a4c"), Color("b8bb6a"), Color("5f6b35")], [Color("a6ad5a"), Color("c9c77a"), Color("6a7040")], [G.MOSS_DARK, G.TEAL, G.MOSS_DARK], [G.BUTTER, Color("f4e3a0"), G.MEADOW_DRY]],
		2: [[Color("5f8f6a"), Color("86b37f"), Color("3e6250")], [Color("7fae6a"), Color("a6c98a"), Color("4f7a50")], [G.TEAL, Color("5f9e8f"), Color("2f5a52")], [Color("c9d48a"), Color("e6ebb0"), Color("8fa86a")]],
		3: [[G.TERRACOTTA, G.MARIGOLD, Color("7a3b2e")], [Color("d08a3a"), G.BUTTER, Color("8a5a2e")], [Color("8a5a3a"), Color("b8743f"), Color("5a3a2a")], [G.MARIGOLD, G.BUTTER, G.TERRACOTTA]],
		4: [[Color("7f9a8a"), G.PAPER, Color("4f665c")], [Color("a9b8a0"), G.PAPER, Color("6f8270")], [Color("5f7f74"), G.PAPER, Color("3a524a")], [G.PAPER_DARK, G.PAPER, Color("a9b0a0")]],
	}
	return table[clampi(biome, 0, 4)][variant]

static func _tree(variant: int, seed_v: int, biome := 0) -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 977 + variant
	var parts: Array = []
	var pal := canopy(variant, biome)
	var cb: Color = pal[0]
	var ct: Color = pal[1]
	var cu: Color = pal[2]
	match variant:
		0:
			# Umbrella pine: tall leaning trunk that forks, flat wide crown of layered pads
			var h := rng.randf_range(6.5, 8.5)
			var lean := Vector3(rng.randf_range(-1.2, 1.2), 0, rng.randf_range(-1.2, 1.2))
			var pts := PackedVector3Array()
			var rad := PackedFloat32Array()
			for i in 6:
				var t := i / 5.0
				pts.append(Vector3(0, t * h, 0) + lean * pow(t, 1.5))
				rad.append(lerpf(0.5, 0.22, t))
			parts.append([Geo.tube(pts, rad, G.BARK, 7), Transform3D()])
			var top := pts[5]
			var forks := rng.randi_range(2, 3)
			for k in forks:
				var a := TAU * k / forks + rng.randf()
				var tip := top + Vector3(cos(a) * 1.6, rng.randf_range(0.6, 1.2), sin(a) * 1.6)
				parts.append([Geo.tube(PackedVector3Array([top - Vector3(0, 0.6, 0), (top + tip) * 0.5 + Vector3(0, 0.2, 0), tip]), PackedFloat32Array([0.2, 0.14, 0.1]), G.BARK, 5), Transform3D()])
				var r := rng.randf_range(2.2, 2.9)
				var col_fn := _shade_fn(cb, ct, cu.darkened(0.15), r * 0.45)
				parts.append([Geo.blob(Vector3(r, r * 0.42, r), cb, 0.16, seed_v + k, 9, 16, false, col_fn), Transform3D(Basis(), tip + Vector3(0, 0.3, 0))])
			var r2 := rng.randf_range(2.4, 3.0)
			var col_fn2 := _shade_fn(cb, ct.lightened(0.04), cu.darkened(0.15), r2 * 0.45)
			parts.append([Geo.blob(Vector3(r2, r2 * 0.45, r2), cb, 0.16, seed_v + 9, 9, 16, false, col_fn2), Transform3D(Basis(), top + Vector3(0, 1.4, 0))])
		1:
			# Plumbob tree: short, round and generous, fruit tucked into the crown
			var h := rng.randf_range(3.6, 4.6)
			var pts := PackedVector3Array()
			var rad := PackedFloat32Array()
			var lean := Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
			for i in 5:
				var t := i / 4.0
				pts.append(Vector3(0, t * h, 0) + lean * sin(t * PI * 0.7))
				rad.append(lerpf(0.55, 0.3, t))
			parts.append([Geo.tube(pts, rad, G.BARK.lightened(0.08), 7), Transform3D()])
			var top := pts[4]
			var puffs: Array = []
			var n := rng.randi_range(3, 4)
			for k in n:
				var r := rng.randf_range(1.7, 2.3)
				var off := Vector3(rng.randf_range(-1.3, 1.3), rng.randf_range(0.0, 1.0), rng.randf_range(-1.3, 1.3))
				if k == 0:
					off = Vector3(0, 0.9, 0)
				var rr := Vector3(r, r * 0.85, r)
				var col_fn := _shade_fn(cb, ct, cu, r)
				parts.append([Geo.blob(rr, cb, 0.12, seed_v + k, 11, 16, false, col_fn), Transform3D(Basis(), top + off)])
				puffs.append([top + off, rr])
			for k in rng.randi_range(7, 10):
				var puff: Array = puffs[rng.randi() % puffs.size()]
				var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 0.4), rng.randf_range(-1, 1)).normalized()
				var p: Vector3 = puff[0] + dir * (puff[1] as Vector3) * 0.93
				parts.append([Geo.sphere(0.3, G.TERRACOTTA if k % 3 else G.MARIGOLD, 8, 6), Transform3D(Basis(), p)])
		2:
			# Spire: stacked cones
			var h := rng.randf_range(8.0, 11.0)
			parts.append([Geo.cylinder(0.25, 0.4, h * 0.4, G.BARK, 6), Transform3D(Basis(), Vector3(0, h * 0.2, 0))])
			var tiers := 4
			for i in tiers:
				var t := float(i) / tiers
				var w := lerpf(2.6, 0.9, t)
				var y := h * 0.25 + t * h * 0.7
				var prof := PackedVector2Array([Vector2(0.0, 0.0), Vector2(w, 0.0), Vector2(w * 0.9, 0.35), Vector2(0.0, h * 0.32)])
				var col := cb.lerp(ct if biome != 4 else cb.lightened(0.1), 0.15 + 0.1 * i)
				var tier_basis := Basis(Vector3.UP, rng.randf() * TAU)
				parts.append([Geo.lathe(prof, 9, col, Vector2.ONE, 0.12, seed_v + i), Transform3D(tier_basis, Vector3(0, y, 0))])
				if biome == 4:
					# a cap of snow on each tier
					var snow := PackedVector2Array([Vector2(w * 0.55, h * 0.16), Vector2(w * 0.4, h * 0.2), Vector2(0.0, h * 0.33)])
					parts.append([Geo.lathe(snow, 9, G.PAPER, Vector2.ONE, 0.15, seed_v + i + 50), Transform3D(tier_basis, Vector3(0, y + 0.05, 0))])
		3:
			# Paperbark: thin pale trunk, golden canopy
			var h := rng.randf_range(6.0, 8.0)
			var pts := PackedVector3Array([Vector3(0, 0, 0), Vector3(0.2, h * 0.5, 0.1), Vector3(-0.1, h, 0)])
			parts.append([Geo.tube(pts, PackedFloat32Array([0.28, 0.2, 0.14]), G.PAPER, 6), Transform3D()])
			for k in 3:
				var r := rng.randf_range(1.2, 1.8)
				var off := Vector3(rng.randf_range(-0.9, 0.9), h - 0.8 + k * 0.7, rng.randf_range(-0.9, 0.9))
				var col_fn := _shade_fn(cb, ct, cu, r)
				parts.append([Geo.blob(Vector3(r, r * 1.1, r), cb, 0.2, seed_v + k, 7, 9, false, col_fn), Transform3D(Basis(), off)])
	return Geo.merge(parts)

static func _rock(variant: int) -> Mesh:
	var fn := func(p: Vector3) -> Color:
		var up := p.normalized().y
		var c := G.STONE.lerp(G.STONE_DARK, smoothstep(0.0, -0.6, up))
		return c.lerp(G.MOSS, smoothstep(0.82, 0.95, up + sin(p.x * 3.0) * 0.05))
	return Geo.blob(Vector3(1.0, 0.7, 0.9), G.STONE, 0.32, 40 + variant, 6, 8, true, fn)

static func _grass_clump() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	st.set_color(Color.WHITE)
	for b in 7:
		var a := rng.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.25)
		var h := rng.randf_range(0.45, 0.9)
		var w := 0.07
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.1, 0.3)
		var side := Vector3(-sin(a + 1.2), 0, cos(a + 1.2)) * w
		var p0 := base - side
		var p1 := base + side
		var p2 := base + lean * 0.5 + Vector3(0, h * 0.55, 0) + side * 0.6
		var p3 := base + lean * 0.5 + Vector3(0, h * 0.55, 0) - side * 0.6
		var tip := base + lean + Vector3(0, h, 0)
		st.set_normal(Vector3.UP)
		for v in [p0, p1, p2, p0, p2, p3, p3, p2, tip]:
			st.add_vertex(v)
	return st.commit()

static func _flower_clump(col_idx: int) -> Mesh:
	var cols := [G.BUTTER, G.ROSE, G.PAPER, G.PLUM.lightened(0.25), G.SKY.lightened(0.1)]
	var col: Color = cols[col_idx % cols.size()]
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + col_idx
	var parts: Array = []
	for k in 5:
		var p := Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
		var h := rng.randf_range(0.22, 0.45)
		parts.append([Geo.cylinder(0.02, 0.025, h, G.MOSS_DARK, 4), Transform3D(Basis(), p + Vector3(0, h * 0.5, 0))])
		for pi in 5:
			var a := TAU * pi / 5.0 + k
			var petal := Geo.blob(Vector3(0.13, 0.035, 0.08), col, 0.0, k, 4, 6)
			parts.append([petal, Transform3D(Basis(Vector3.UP, -a), p + Vector3(cos(a) * 0.11, h, sin(a) * 0.11))])
		parts.append([Geo.sphere(0.05, G.MARIGOLD if col != G.BUTTER else G.TERRACOTTA, 6, 4), Transform3D(Basis(), p + Vector3(0, h + 0.02, 0))])
	return Geo.merge(parts)

static func _plumbob() -> Mesh:
	var fn := func(p: Vector3) -> Color:
		return G.TERRACOTTA.lerp(G.MARIGOLD, smoothstep(-0.1, 0.25, p.y))
	var body := Geo.blob(Vector3(0.3, 0.27, 0.3), G.TERRACOTTA, 0.06, 3, 8, 12, false, fn)
	var stem := Geo.cylinder(0.02, 0.03, 0.14, G.BARK, 5)
	var leaf := Geo.blob(Vector3(0.12, 0.02, 0.06), G.MOSS, 0.0, 1, 3, 6)
	return Geo.merge([[body, Transform3D()], [stem, Transform3D(Basis(), Vector3(0, 0.3, 0))], [leaf, Transform3D(Basis(Vector3.FORWARD, 0.4), Vector3(0.1, 0.33, 0))]])

static func _gourdle() -> Mesh:
	var prof := PackedVector2Array([Vector2(0.0, -0.45), Vector2(0.3, -0.42), Vector2(0.45, -0.25), Vector2(0.44, -0.02), Vector2(0.3, 0.12), Vector2(0.22, 0.22), Vector2(0.28, 0.36), Vector2(0.2, 0.5), Vector2(0.0, 0.54)])
	var body := Geo.lathe(prof, 14, G.BUTTER, Vector2.ONE, 0.04, 5)
	var stem := Geo.cylinder(0.03, 0.05, 0.2, G.MOSS_DARK, 5)
	return Geo.merge([[body, Transform3D()], [stem, Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0, 0.6, 0))]])

static func _sweetroot() -> Mesh:
	var prof := PackedVector2Array([Vector2(0.0, -1.4), Vector2(0.12, -1.1), Vector2(0.35, -0.5), Vector2(0.55, 0.0), Vector2(0.5, 0.25), Vector2(0.2, 0.4), Vector2(0.0, 0.42)])
	var body := Geo.lathe(prof, 12, G.PLUM.lightened(0.15), Vector2.ONE, 0.05, 9)
	var parts: Array = [[body, Transform3D()]]
	for k in 5:
		var a := TAU * k / 5.0
		var leaf := Geo.blob(Vector3(0.12, 0.6, 0.05), G.MOSS, 0.05, k, 4, 6)
		parts.append([leaf, Transform3D(Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), 0.45), Vector3(cos(a) * 0.15, 0.85, sin(a) * 0.15))])
	return Geo.merge(parts)

static func _waystone() -> Mesh:
	# Three leaning menhirs meeting overhead, painted bands, a stone base.
	var parts: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	parts.append([Geo.blob(Vector3(7.5, 1.2, 7.5), G.STONE, 0.12, 1, 6, 14, true), Transform3D(Basis(), Vector3(0, 0.0, 0))])
	for i in 3:
		var a := TAU * i / 3.0 + 0.3
		var base := Vector3(cos(a), 0, sin(a)) * 5.5
		var top := Vector3(0, 15.0, 0)
		var dir := (top - base)
		var len_v := dir.length()
		var prof := PackedVector2Array([Vector2(1.5, 0.0), Vector2(1.7, len_v * 0.3), Vector2(1.3, len_v * 0.75), Vector2(0.6, len_v), Vector2(0.0, len_v + 0.3)])
		var stone := Geo.lathe(prof, 7, G.STONE, Vector2(1.0, 0.7), 0.1, 70 + i)
		var b := Basis(Quaternion(Vector3.UP, dir.normalized()))
		parts.append([stone, Transform3D(b, base)])
		# painted bands
		for k in 2:
			var y := len_v * (0.35 + k * 0.12)
			var r := lerpf(1.72, 1.4, (y / len_v)) * 1.03
			var band := Geo.lathe(PackedVector2Array([Vector2(r, 0.0), Vector2(r, 0.45)]), 7, G.TERRACOTTA if k == 0 else G.INK.lightened(0.15), Vector2(1.0, 0.7))
			parts.append([band, Transform3D(b, base + b.y * y)])
	return Geo.merge(parts)

static func _mite() -> Mesh:
	# a thistlemite: a burr-ball of purple spines with two big eyes and a tuft
	var parts: Array = []
	var fn := func(p: Vector3) -> Color:
		return G.PLUM.lerp(G.ROSE, smoothstep(-0.1, 0.25, p.y) * 0.6)
	parts.append([Geo.blob(Vector3(0.26, 0.22, 0.26), G.PLUM, 0.22, 61, 7, 10, true, fn), Transform3D()])
	var rng := RandomNumberGenerator.new()
	rng.seed = 62
	for k in 16:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 1), rng.randf_range(-1, 1)).normalized()
		if d.z < -0.5 and d.y < 0.5:
			continue
		var spike := Geo.lathe(PackedVector2Array([Vector2(0.05, 0.0), Vector2(0.0, 0.16)]), 4, G.PLUM.darkened(0.3))
		parts.append([spike, Transform3D(Basis(Quaternion(Vector3.UP, d)), d * 0.2)])
	for sx in [-1, 1]:
		parts.append([Geo.sphere(0.085, G.PAPER, 8, 6), Transform3D(Basis(), Vector3(sx * 0.09, 0.08, -0.2))])
		parts.append([Geo.sphere(0.045, G.INK, 6, 4), Transform3D(Basis(), Vector3(sx * 0.095, 0.075, -0.27))])
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			parts.append([Geo.cylinder(0.02, 0.02, 0.16, G.INK, 4), Transform3D(Basis(Vector3.FORWARD, sx * 0.5), Vector3(sx * 0.15, -0.2, sz * 0.1))])
	return Geo.merge(parts)

static func _thistle_clump() -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 300
	var parts: Array = []
	for k in 6:
		var p := Vector3(rng.randf_range(-0.7, 0.7), 0, rng.randf_range(-0.7, 0.7))
		var h := rng.randf_range(0.7, 1.3)
		parts.append([Geo.cylinder(0.025, 0.035, h, G.MOSS_DARK.lerp(G.TEAL, 0.3), 4), Transform3D(Basis(Vector3.FORWARD, rng.randf_range(-0.15, 0.15)), p + Vector3(0, h * 0.5, 0))])
		var head := Geo.lathe(PackedVector2Array([Vector2(0.0, -0.08), Vector2(0.11, -0.02), Vector2(0.1, 0.08), Vector2(0.14, 0.14), Vector2(0.0, 0.2)]), 7, G.PLUM.lightened(0.15), Vector2.ONE, 0.25, k)
		parts.append([head, Transform3D(Basis(), p + Vector3(0, h, 0))])
		for l in 2:
			var leaf := Geo.blob(Vector3(0.18, 0.02, 0.05), G.MOSS_DARK, 0.3, k * 3 + l, 3, 6)
			parts.append([leaf, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p + Vector3(0, h * (0.3 + l * 0.25), 0))])
	return Geo.merge(parts)

# ---------------------------------------------------------------- keepsakes (they double as hats)
const KEEPSAKES := {
	"ks_teacup": {"name": "a chipped teacup", "hat": "teacup"},
	"ks_acorn": {"name": "a giant acorn", "hat": "acorn"},
	"ks_crown": {"name": "a paper crown", "hat": "crown"},
	"ks_feather": {"name": "a heron feather", "hat": "feather"},
	"ks_shell": {"name": "an empty snail shell", "hat": "shell"},
	"ks_lampshade": {"name": "a lampshade", "hat": "lampshade"},
}

static func keepsake_mesh(kind: String) -> Mesh:
	var parts: Array = []
	match kind:
		"ks_teacup":
			parts.append([Geo.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.16, 0.0), Vector2(0.22, 0.08), Vector2(0.26, 0.24), Vector2(0.24, 0.26), Vector2(0.2, 0.1), Vector2(0.0, 0.06)]), 14, G.PAPER), Transform3D()])
			parts.append([Geo.lathe(PackedVector2Array([Vector2(0.255, 0.17), Vector2(0.262, 0.21)]), 14, G.ROSE), Transform3D()])
			var hp := PackedVector3Array()
			var hr := PackedFloat32Array()
			for k in 7:
				var a := lerpf(-1.4, 1.4, k / 6.0)
				hp.append(Vector3(0.25 + cos(a) * 0.08, 0.14 + sin(a) * 0.08, 0))
				hr.append(0.022)
			parts.append([Geo.tube(hp, hr, G.PAPER, 5), Transform3D()])
			parts.append([Geo.lathe(PackedVector2Array([Vector2(0.0, -0.02), Vector2(0.34, -0.02), Vector2(0.36, 0.01), Vector2(0.0, 0.0)]), 16, G.SKY.lightened(0.3)), Transform3D()])
		"ks_acorn":
			parts.append([Geo.blob(Vector3(0.2, 0.24, 0.2), G.WOOD_LIGHT, 0.04, 81, 8, 12), Transform3D(Basis(), Vector3(0, 0.0, 0))])
			parts.append([Geo.lathe(PackedVector2Array([Vector2(0.0, 0.06), Vector2(0.23, 0.08), Vector2(0.25, 0.16), Vector2(0.18, 0.24), Vector2(0.0, 0.26)]), 12, G.BARK, Vector2.ONE, 0.12, 82), Transform3D()])
			parts.append([Geo.cylinder(0.02, 0.03, 0.1, G.BARK.darkened(0.2), 4), Transform3D(Basis(Vector3.FORWARD, 0.3), Vector3(0.01, 0.3, 0))])
		"ks_crown":
			parts.append([Geo.lathe(PackedVector2Array([Vector2(0.24, 0.0), Vector2(0.25, 0.12)]), 14, G.BUTTER), Transform3D()])
			for k in 7:
				var a := TAU * k / 7.0
				var spike := Geo.lathe(PackedVector2Array([Vector2(0.06, 0.0), Vector2(0.0, 0.14)]), 4, G.BUTTER)
				parts.append([spike, Transform3D(Basis(), Vector3(cos(a) * 0.235, 0.11, sin(a) * 0.235))])
				parts.append([Geo.sphere(0.025, [G.ROSE, G.TEAL, G.TERRACOTTA][k % 3], 5, 4), Transform3D(Basis(), Vector3(cos(a) * 0.255, 0.05, sin(a) * 0.255))])
		"ks_feather":
			var pts := PackedVector3Array()
			var rad := PackedFloat32Array()
			for k in 8:
				var t := k / 7.0
				pts.append(Vector3(0, t * 0.75, sin(t * 2.4) * 0.12))
				rad.append(sin(t * PI) * 0.07 + 0.01)
			parts.append([Geo.tube(pts, rad, G.SKY.darkened(0.15), 6), Transform3D(Basis().scaled(Vector3(1.0, 1.0, 0.3)))])
			parts.append([Geo.cylinder(0.008, 0.012, 0.85, G.PAPER, 4), Transform3D(Basis(), Vector3(0, 0.38, 0.05))])
		"ks_shell":
			for k in 9:
				var t := k / 8.0
				var a := t * TAU * 1.5
				var r := lerpf(0.2, 0.05, t)
				parts.append([Geo.sphere(r, G.TERRACOTTA if k % 2 == 0 else G.PAPER_DARK, 8, 6), Transform3D(Basis(), Vector3(cos(a) * (0.2 - t * 0.15), 0.12 + t * 0.12, sin(a) * (0.2 - t * 0.15)))])
		"ks_lampshade":
			parts.append([Geo.lathe(PackedVector2Array([Vector2(0.32, 0.0), Vector2(0.18, 0.3), Vector2(0.17, 0.31)]), 14, G.MARIGOLD), Transform3D()])
			for k in 14:
				var a := TAU * k / 14.0
				parts.append([Geo.sphere(0.03, G.TERRACOTTA, 4, 3), Transform3D(Basis(), Vector3(cos(a) * 0.32, -0.04, sin(a) * 0.32))])
	return Geo.merge(parts)

## A torsion-spoon catapult. Turntable-local: aim is -Z, the bowl rests on the yaw axis
## so turning never moves it; the arm pivots on a rope skein at the front posts.
const FL_AXLE := Vector3(0, 0.62, -2.0)
const FL_BOWL := Vector3(0, 0.6, 0.0)
static func flinger_parts() -> Dictionary:
	var base := Geo.merge([
		# a mossy cairn of stones props the turntable level on the sloping back
		[Geo.blob(Vector3(1.75, 0.75, 1.7), G.STONE, 0.22, 41, 7, 10, true), Transform3D(Basis(), Vector3(0, -1.35, 0))],
		[Geo.blob(Vector3(1.5, 0.6, 1.45), G.STONE_DARK.lerp(G.STONE, 0.5), 0.2, 42, 6, 9, true), Transform3D(Basis(Vector3.UP, 0.7), Vector3(0.1, -0.55, 0))],
		[Geo.blob(Vector3(1.3, 0.25, 1.3), G.MOSS, 0.25, 43, 5, 10), Transform3D(Basis(), Vector3(0, -0.12, 0))],
		[Geo.cylinder(1.6, 1.62, 0.22, G.WOOD_LIGHT, 18), Transform3D(Basis(), Vector3(0, 0.39, 0))],
		[Geo.cylinder(1.25, 1.25, 0.24, G.WOOD, 18), Transform3D(Basis(), Vector3(0, 0.18, 0))],
		[Geo.box(Vector3(0.26, 0.22, 2.5), G.BARK), Transform3D(Basis(), Vector3(-0.75, 0.42, -1.05))],
		[Geo.box(Vector3(0.26, 0.22, 2.5), G.BARK), Transform3D(Basis(), Vector3(0.75, 0.42, -1.05))],
		[Geo.box(Vector3(0.26, 2.0, 0.26), G.BARK), Transform3D(Basis(), Vector3(-0.75, 1.35, -2.0))],
		[Geo.box(Vector3(0.26, 2.0, 0.26), G.BARK), Transform3D(Basis(), Vector3(0.75, 1.35, -2.0))],
		[Geo.cylinder(0.11, 0.11, 1.9, G.BARK, 6), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 2.2, -2.3))],
		[Geo.blob(Vector3(0.32, 0.2, 0.2), G.TERRACOTTA, 0.1, 31, 6, 8), Transform3D(Basis(), Vector3(0, 2.2, -2.2))],
		[Geo.cylinder(0.3, 0.3, 1.3, G.PAPER_DARK, 10), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), FL_AXLE)],
		[Geo.cylinder(0.32, 0.32, 0.1, G.TERRACOTTA, 10), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), FL_AXLE + Vector3(-0.4, 0, 0))],
		[Geo.cylinder(0.32, 0.32, 0.1, G.TERRACOTTA, 10), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), FL_AXLE + Vector3(0.4, 0, 0))],
		[Geo.box(Vector3(0.6, 0.12, 0.6), G.BARK), Transform3D(Basis(), Vector3(0, 0.55, 0))],
	])
	# arm-local: pivot at the origin, the spoon runs back (+Z) to its bowl
	var arm := Geo.merge([
		[Geo.box(Vector3(0.3, 0.2, 2.1), G.WOOD_LIGHT), Transform3D(Basis(), Vector3(0, 0.0, 1.0))],
		[Geo.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.6, 0.04), Vector2(0.95, 0.25), Vector2(1.1, 0.55), Vector2(1.0, 0.58), Vector2(0.85, 0.3), Vector2(0.5, 0.12), Vector2(0.0, 0.1)]), 16, G.WOOD_LIGHT), Transform3D(Basis(), FL_BOWL - FL_AXLE)],
	])
	return {"base": base, "arm": arm}

static func bowl_collision() -> ConcavePolygonShape3D:
	var prof := [Vector2(0.0, 0.1), Vector2(0.5, 0.12), Vector2(0.85, 0.3), Vector2(1.0, 0.58)]
	var faces := PackedVector3Array()
	var segs := 12
	for i in prof.size() - 1:
		for s in segs:
			var a0 := TAU * s / segs
			var a1 := TAU * (s + 1) / segs
			var p0: Vector2 = prof[i]
			var p1: Vector2 = prof[i + 1]
			var v00 := Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x)
			var v01 := Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
			var v10 := Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)
			var v11 := Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x)
			faces.append_array([v00, v10, v11, v00, v11, v01])
	var sh := ConcavePolygonShape3D.new()
	sh.set_faces(faces)
	sh.backface_collision = true
	return sh

# ---------------------------------------------------------------- magpies
const MAGPIE_BLACK := Color("35303f")
static func magpie_body() -> Mesh:
	var tail_pts := PackedVector3Array([Vector3(0, 0.03, 0.22), Vector3(0, 0.06, 0.5), Vector3(0, 0.1, 0.78)])
	return Geo.merge([
		[Geo.blob(Vector3(0.16, 0.15, 0.3), MAGPIE_BLACK, 0.05, 61, 8, 12), Transform3D()],
		[Geo.blob(Vector3(0.155, 0.11, 0.2), G.PAPER, 0.04, 62, 6, 10), Transform3D(Basis(), Vector3(0, -0.045, -0.02))],
		[Geo.blob(Vector3(0.12, 0.12, 0.13), MAGPIE_BLACK, 0.03, 63, 7, 10), Transform3D(Basis(), Vector3(0, 0.11, -0.3))],
		[Geo.cylinder(0.0, 0.035, 0.14, G.INK, 6), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.09, -0.46))],
		[Geo.sphere(0.035, G.PAPER, 6, 4), Transform3D(Basis(), Vector3(0.075, 0.15, -0.38))],
		[Geo.sphere(0.035, G.PAPER, 6, 4), Transform3D(Basis(), Vector3(-0.075, 0.15, -0.38))],
		[Geo.sphere(0.02, G.INK, 5, 4), Transform3D(Basis(), Vector3(0.09, 0.155, -0.4))],
		[Geo.sphere(0.02, G.INK, 5, 4), Transform3D(Basis(), Vector3(-0.09, 0.155, -0.4))],
		[Geo.tube(tail_pts, PackedFloat32Array([0.05, 0.065, 0.075]), G.TEAL.darkened(0.45), 5), Transform3D(Basis().scaled(Vector3(1.4, 0.45, 1.0)))],
	])

## One wing, pivoting at the shoulder (origin); `side` is -1 (left) or 1 (right).
static func magpie_wing(side: float) -> Mesh:
	return Geo.merge([
		[Geo.blob(Vector3(0.32, 0.03, 0.17), MAGPIE_BLACK, 0.06, 64, 5, 10), Transform3D(Basis(), Vector3(side * 0.3, 0, 0.04))],
		[Geo.blob(Vector3(0.11, 0.036, 0.09), G.PAPER, 0.04, 65, 4, 8), Transform3D(Basis(), Vector3(side * 0.16, 0.004, -0.02))],
		[Geo.blob(Vector3(0.14, 0.032, 0.1), G.TEAL.darkened(0.35), 0.05, 66, 4, 8), Transform3D(Basis(), Vector3(side * 0.5, 0.0, 0.1))],
	])

## A scruffy twig nest for a treetop.
static func nest_mesh() -> Mesh:
	var parts: Array = [[Geo.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.55, 0.05), Vector2(0.8, 0.3), Vector2(0.72, 0.42), Vector2(0.5, 0.22), Vector2(0.0, 0.15)]), 10, G.BARK, Vector2.ONE, 0.18, 67), Transform3D()]]
	var rng := RandomNumberGenerator.new()
	rng.seed = 68
	for k in 9:
		var a := rng.randf() * TAU
		parts.append([Geo.cylinder(0.025, 0.025, 1.1, G.WOOD.darkened(0.2), 4), Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.FORWARD, PI * 0.5 + rng.randf_range(-0.3, 0.3)), Vector3(cos(a) * 0.6, 0.3, sin(a) * 0.6))])
	return Geo.merge(parts)
