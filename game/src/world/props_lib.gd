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
			m = _tree(int(parts[1]), int(parts[2]))
		"rock":
			m = _rock(int(parts[1]))
		"grass":
			m = _grass_clump()
		"flowers":
			m = _flower_clump(int(parts[1]))
		"plumbob":
			m = _plumbob()
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

static func _tree(variant: int, seed_v: int) -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 977 + variant
	var parts: Array = []
	match variant:
		0, 1:
			# Puffwood / Plumbob tree: bent trunk + clustered canopy puffs
			var h := rng.randf_range(5.5, 7.5) if variant == 0 else rng.randf_range(4.0, 5.2)
			var lean := Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))
			var pts := PackedVector3Array()
			var rad := PackedFloat32Array()
			for i in 6:
				var t := i / 5.0
				pts.append(Vector3(0, t * h, 0) + lean * sin(t * PI * 0.7) + Vector3(0, 0, 0))
				rad.append(lerpf(0.55, 0.28, t))
			parts.append([Geo.tube(pts, rad, G.BARK, 7), Transform3D()])
			var top := pts[5]
			var canopy_base := G.MOSS if variant == 0 else G.MEADOW
			var n := rng.randi_range(3, 5)
			var puffs: Array = []
			for k in n:
				var r := rng.randf_range(1.6, 2.5) * (1.15 if variant == 1 else 1.0)
				var off := Vector3(rng.randf_range(-1.6, 1.6), rng.randf_range(-0.4, 1.2), rng.randf_range(-1.6, 1.6))
				if k == 0:
					off = Vector3(0, 0.6, 0)
				var rr := Vector3(r, r * 0.82, r)
				var col_fn := _shade_fn(canopy_base, canopy_base.lightened(0.18), G.MOSS_DARK.darkened(0.15), r)
				parts.append([Geo.blob(rr, canopy_base, 0.14, seed_v + k, 11, 16, false, col_fn), Transform3D(Basis(), top + off)])
				puffs.append([top + off, rr])
			if variant == 1:
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
				var col := G.MOSS_DARK.lerp(G.TEAL, 0.25 + 0.1 * i)
				parts.append([Geo.lathe(prof, 9, col, Vector2.ONE, 0.12, seed_v + i), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(0, y, 0))])
		3:
			# Paperbark: thin pale trunk, golden canopy
			var h := rng.randf_range(6.0, 8.0)
			var pts := PackedVector3Array([Vector3(0, 0, 0), Vector3(0.2, h * 0.5, 0.1), Vector3(-0.1, h, 0)])
			parts.append([Geo.tube(pts, PackedFloat32Array([0.28, 0.2, 0.14]), G.PAPER, 6), Transform3D()])
			for k in 3:
				var r := rng.randf_range(1.2, 1.8)
				var off := Vector3(rng.randf_range(-0.9, 0.9), h - 0.8 + k * 0.7, rng.randf_range(-0.9, 0.9))
				var col_fn := _shade_fn(G.MEADOW_DRY, G.BUTTER, G.MOSS, r)
				parts.append([Geo.blob(Vector3(r, r * 1.1, r), G.MEADOW_DRY, 0.2, seed_v + k, 7, 9, false, col_fn), Transform3D(Basis(), off)])
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
