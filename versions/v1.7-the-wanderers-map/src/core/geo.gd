class_name Geo
## Procedural mesh helpers. Everything in Mossback is built from these.

## Revolve a profile (x = radius, y = height), bottom to top, around Y.
## `squash` scales X/Z of the result (Vector2(x, z)).
static func lathe(profile: PackedVector2Array, segments: int, color: Color, squash := Vector2.ONE, wobble := 0.0, seed_v := 0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	var noise := FastNoiseLite.new()
	noise.seed = seed_v
	noise.frequency = 1.3
	for p in profile:
		var ring := PackedVector3Array()
		for s in segments + 1:
			var a := TAU * float(s % segments) / segments
			var r := p.x
			if wobble > 0.0 and r > 0.001:
				r *= 1.0 + wobble * noise.get_noise_3d(cos(a) * 2.0, p.y * 2.0, sin(a) * 2.0)
			ring.append(Vector3(cos(a) * r * squash.x, p.y, sin(a) * r * squash.y))
		rings.append(ring)
	st.set_color(color)
	for i in rings.size() - 1:
		var r0 := rings[i]
		var r1 := rings[i + 1]
		for s in segments:
			_quad(st, r0[s], r0[s + 1], r1[s + 1], r1[s])
	st.generate_normals()
	return st.commit()

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	# CCW when viewed from outside (Godot front faces are clockwise -> we emit a,c,b order)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
	st.add_vertex(a); st.add_vertex(d); st.add_vertex(c)

## Lumpy ellipsoid. `flat` = true gives faceted (hard) shading, good for rocks.
static func blob(radii: Vector3, color: Color, lump := 0.15, seed_v := 0, rings := 10, segs := 14, flat := false, color_fn: Callable = Callable()) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = seed_v
	noise.frequency = 0.9
	var pts: Array[PackedVector3Array] = []
	for i in rings + 1:
		var v := float(i) / rings
		var phi := PI * v
		var row := PackedVector3Array()
		for s in segs + 1:
			var th := TAU * float(s % segs) / segs
			var n := Vector3(sin(phi) * cos(th), -cos(phi), sin(phi) * sin(th))
			var k := 1.0 + lump * noise.get_noise_3dv(n * 1.7)
			row.append(n * radii * k)
		pts.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if flat:
		st.set_smooth_group(-1)
	for i in rings:
		for s in segs:
			var a := pts[i][s]; var b := pts[i][s + 1]; var c := pts[i + 1][s + 1]; var d := pts[i + 1][s]
			if color_fn.is_valid():
				for p in [a, c, b, a, d, c]:
					st.set_color(color_fn.call(p))
					st.add_vertex(p)
			else:
				st.set_color(color)
				_quad(st, a, b, c, d)
	st.generate_normals()
	return st.commit()

## Merge several meshes (each with a transform) into one ArrayMesh surface.
## Inputs: Array of [Mesh, Transform3D]. All surfaces must be triangles with colors.
static func merge(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		var m: Mesh = part[0]
		var xf: Transform3D = part[1]
		for si in m.get_surface_count():
			# append_from drops the triangles of non-indexed parts once anything indexed is in
			# the mix (primitive meshes are indexed, SurfaceTool-built ones aren't): index them first
			var idx: Variant = m.surface_get_arrays(si)[Mesh.ARRAY_INDEX]
			if idx == null or (idx as PackedInt32Array).is_empty():
				var t := SurfaceTool.new()
				t.create_from(m, si)
				t.index()
				st.append_from(t.commit(), 0, xf)
			else:
				st.append_from(m, si, xf)
	return st.commit()

## A triangle in the XY plane extruded along Z (gables, wedges). Flat shaded.
static func prism(a: Vector2, b: Vector2, c: Vector2, depth: float, color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(color)
	var z0 := -depth * 0.5
	var z1 := depth * 0.5
	var f := [Vector3(a.x, a.y, z1), Vector3(b.x, b.y, z1), Vector3(c.x, c.y, z1)]
	var k := [Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z0), Vector3(c.x, c.y, z0)]
	st.add_vertex(f[0]); st.add_vertex(f[2]); st.add_vertex(f[1])
	st.add_vertex(k[0]); st.add_vertex(k[1]); st.add_vertex(k[2])
	for i in 3:
		var j := (i + 1) % 3
		_quad(st, f[i], k[i], k[j], f[j])
	st.generate_normals()
	return st.commit()

## Simple coloured box (flat shaded).
static func box(size: Vector3, color: Color) -> ArrayMesh:
	var bm := BoxMesh.new()
	bm.size = size
	return recolor(bm, color)

static func cylinder(r_top: float, r_bottom: float, h: float, color: Color, segs := 10) -> ArrayMesh:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bottom
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	return recolor(cm, color)

static func sphere(r: float, color: Color, segs := 12, rings := 8) -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = segs
	sm.rings = rings
	return recolor(sm, color)

## Copy a primitive mesh into an ArrayMesh with vertex colours baked in.
static func recolor(m: Mesh, color: Color) -> ArrayMesh:
	var arrays := m.surface_get_arrays(0)
	var n: int = arrays[Mesh.ARRAY_VERTEX].size()
	var cols := PackedColorArray()
	cols.resize(n)
	cols.fill(color)
	arrays[Mesh.ARRAY_COLOR] = cols
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am

## A tube along a list of points with per-point radius (for tails, trunks, ropes).
static func tube(points: PackedVector3Array, radii: PackedFloat32Array, color: Color, segs := 8) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(color)
	var rings: Array[PackedVector3Array] = []
	var prev_side := Vector3.RIGHT
	for i in points.size():
		var fwd: Vector3
		if i == 0:
			fwd = (points[1] - points[0]).normalized()
		elif i == points.size() - 1:
			fwd = (points[i] - points[i - 1]).normalized()
		else:
			fwd = (points[i + 1] - points[i - 1]).normalized()
		var side := fwd.cross(Vector3.UP)
		if side.length() < 0.01:
			side = prev_side
		side = side.normalized()
		prev_side = side
		var up := side.cross(fwd).normalized()
		var ring := PackedVector3Array()
		for s in segs + 1:
			var a := TAU * float(s % segs) / segs
			ring.append(points[i] + (side * cos(a) + up * sin(a)) * radii[i])
		rings.append(ring)
	for i in rings.size() - 1:
		for s in segs:
			_quad(st, rings[i][s], rings[i][s + 1], rings[i + 1][s + 1], rings[i + 1][s])
	st.generate_normals()
	return st.commit()
