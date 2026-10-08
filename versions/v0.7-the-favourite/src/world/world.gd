class_name World
extends Node3D
## Streams terrain chunks + scatter around focus points. Visual only, except
## collision for chunks near anything that needs to stand on the ground.

const VIEW_R := 7
const DETAIL_R := 1
const FLOWER_R := 2

var terrain: Terrain
var chunks := {}            # Vector2i -> Dictionary {node, lod, detail, collider}
var focus := Vector3.ZERO   # camera / local player
var collision_points: Array[Vector3] = []
var water: MeshInstance3D
var grass_mat: ShaderMaterial
var _queue: Array[Vector2i] = []
var _timer := 0.0
var _hidden_trees := {}     # "cx,cz,id" -> true
var _terrain_mat: ShaderMaterial

func setup(seed_v: int) -> void:
	terrain = Terrain.new(seed_v)
	grass_mat = ShaderMaterial.new()
	grass_mat.shader = preload("res://shaders/grass.gdshader")
	_terrain_mat = Mats.toon(Color.WHITE, true, 0.09)
	water = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1400, 1400)
	pm.subdivide_depth = 0
	pm.subdivide_width = 0
	water.mesh = pm
	var wm := ShaderMaterial.new()
	wm.shader = preload("res://shaders/water.gdshader")
	water.material_override = wm
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)

func _process(dt: float) -> void:
	if terrain == null:
		return
	water.global_position = Vector3(snappedf(focus.x, 32.0), Terrain.WATER_LEVEL, snappedf(focus.z, 32.0))
	_timer -= dt
	if _timer <= 0.0:
		_timer = 0.3
		_refresh()
	var budget := 2
	while budget > 0 and not _queue.is_empty():
		var c: Vector2i = _queue.pop_front()
		_build_or_update(c)
		budget -= 1

## Build everything around `focus` synchronously (used at load).
func warm_up() -> void:
	_refresh()
	while not _queue.is_empty():
		_build_or_update(_queue.pop_front())

func _desired_lod(c: Vector2i, fc: Vector2i) -> int:
	var d := maxi(absi(c.x - fc.x), absi(c.y - fc.y))
	if d > VIEW_R:
		return -1
	if d <= 1:
		return 32
	if d <= 3:
		return 16
	return 8

func _refresh() -> void:
	var fc := Terrain.chunk_of(focus)
	var want := {}
	for dx in range(-VIEW_R, VIEW_R + 1):
		for dz in range(-VIEW_R, VIEW_R + 1):
			var c := fc + Vector2i(dx, dz)
			want[c] = true
	# drop far chunks
	for c in chunks.keys():
		if not want.has(c):
			chunks[c].node.queue_free()
			chunks.erase(c)
	var todo: Array[Vector2i] = []
	for c in want.keys():
		var lod := _desired_lod(c, fc)
		var need_col := _needs_collision(c)
		var d := maxi(absi(c.x - fc.x), absi(c.y - fc.y))
		if not chunks.has(c):
			todo.append(c)
		else:
			var ch: Dictionary = chunks[c]
			if ch.lod != lod or ch.collider != need_col or ch.detail != (d <= DETAIL_R) or ch.flowers != (d <= FLOWER_R):
				todo.append(c)
	todo.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - fc).length_squared() < (b - fc).length_squared())
	_queue = todo

## True once the ground under p has a collider (props far from everyone wait for it).
func has_collision_at(p: Vector3) -> bool:
	var ch: Dictionary = chunks.get(Terrain.chunk_of(p), {})
	return ch.get("collider", false)

func _needs_collision(c: Vector2i) -> bool:
	var center := Vector3((c.x + 0.5) * Terrain.CHUNK, 0, (c.y + 0.5) * Terrain.CHUNK)
	for p in collision_points:
		if absf(p.x - center.x) < Terrain.CHUNK * 1.1 and absf(p.z - center.z) < Terrain.CHUNK * 1.1:
			return true
	return false

func _build_or_update(c: Vector2i) -> void:
	var fc := Terrain.chunk_of(focus)
	var lod := _desired_lod(c, fc)
	if lod < 0:
		return
	var d := maxi(absi(c.x - fc.x), absi(c.y - fc.y))
	var detail := d <= DETAIL_R
	var flowers := d <= FLOWER_R
	var need_col := _needs_collision(c)
	var ch: Dictionary = chunks.get(c, {})
	if ch.is_empty():
		var node := Node3D.new()
		node.name = "C%d_%d" % [c.x, c.y]
		add_child(node)
		ch = {"node": node, "lod": -1, "detail": false, "flowers": false, "collider": false}
		chunks[c] = ch
		_build_scatter(c, node)
	var node: Node3D = ch.node
	if ch.lod != lod:
		var old := node.get_node_or_null("Ground")
		if old:
			old.free()
		var mi := MeshInstance3D.new()
		mi.name = "Ground"
		mi.mesh = _ground_mesh(c, lod)
		mi.material_override = _terrain_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if lod < 32 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		node.add_child(mi)
		ch.lod = lod
	if ch.detail != detail:
		var old := node.get_node_or_null("Grass")
		if old:
			old.free()
		if detail:
			node.add_child(_build_grass(c))
		ch.detail = detail
	if ch.flowers != flowers:
		var old := node.get_node_or_null("Flowers")
		if old:
			old.free()
		if flowers:
			node.add_child(_build_flowers(c))
		ch.flowers = flowers
	if ch.collider != need_col:
		var old := node.get_node_or_null("Body")
		if old:
			old.free()
		if need_col:
			node.add_child(_build_collision(c))
		ch.collider = need_col

func _ground_mesh(c: Vector2i, seg: int) -> ArrayMesh:
	var size := Terrain.CHUNK
	var stp := size / seg
	var ox := c.x * size
	var oz := c.y * size
	var n := seg + 3
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	for j in n:
		for i in n:
			hs[j * n + i] = terrain.height(ox + (i - 1) * stp, oz + (j - 1) * stp)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var row := seg + 1
	for j in row:
		for i in row:
			var gi := i + 1
			var gj := j + 1
			var h := hs[gj * n + gi]
			var nx := hs[gj * n + gi - 1] - hs[gj * n + gi + 1]
			var nz := hs[(gj - 1) * n + gi] - hs[(gj + 1) * n + gi]
			var nrm := Vector3(nx, 2.0 * stp, nz).normalized()
			var x := ox + i * stp
			var z := oz + j * stp
			verts.append(Vector3(i * stp, h, j * stp))
			norms.append(nrm)
			cols.append(terrain.ground_color(x, z, h, nrm))
	for j in seg:
		for i in seg:
			var a := j * row + i
			var b := a + 1
			var cc := a + row
			var dd := cc + 1
			idx.append_array([a, b, dd, a, dd, cc])
	# skirts to hide LOD cracks
	var edge_lists: Array[PackedInt32Array] = []
	var top := PackedInt32Array(); var bottom := PackedInt32Array(); var left := PackedInt32Array(); var right := PackedInt32Array()
	for i in row:
		top.append(i)
		bottom.append(row * (row - 1) + i)
		left.append(i * row)
		right.append(i * row + row - 1)
	edge_lists = [top, bottom, left, right]
	for e in edge_lists:
		var base := verts.size()
		for k in e:
			var v := verts[k]
			verts.append(v - Vector3(0, 3.0, 0))
			norms.append(norms[k])
			cols.append(cols[k])
		for k in e.size() - 1:
			var t0 := e[k]; var t1 := e[k + 1]
			var b0 := base + k; var b1 := base + k + 1
			idx.append_array([t0, b0, t1, t1, b0, b1, t0, t1, b0, t1, b1, b0])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am

func _build_scatter(c: Vector2i, node: Node3D) -> void:
	node.position = Vector3(c.x * Terrain.CHUNK, 0, c.y * Terrain.CHUNK)
	var data := terrain.chunk_data(c)
	var groups := {}
	for t in data.trees:
		var key := "tree:%d:%d:%d" % [t.variant, int(t.rot * 10.0) % 3, t.get("biome", 0)]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(t)
	for r in data.rocks:
		var key := "rock:%d" % r.variant
		if not groups.has(key):
			groups[key] = []
		groups[key].append(r)
	var scat := Node3D.new()
	scat.name = "Scatter"
	node.add_child(scat)
	for key in groups:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = PropsLib.get_mesh(key)
		var list: Array = groups[key]
		mm.instance_count = list.size()
		for k in list.size():
			var it: Dictionary = list[k]
			var s: float = it.get("scale", 1.0)
			if key.begins_with("rock"):
				s = it.size
			var b := Basis(Vector3.UP, it.rot).scaled(Vector3(s, s, s))
			var p: Vector3 = it.pos - node.position
			if key.begins_with("rock"):
				p.y -= s * 0.25
			else:
				p.y -= 0.2
			mm.set_instance_transform(k, Transform3D(b, p))
			it["mm"] = mm
			it["mm_index"] = k
			it["mm_xf"] = Transform3D(b, p)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = key.replace(":", "_")
		if key.begins_with("tree"):
			var v := int(key.split(":")[1])
			mmi.material_override = Mats.foliage(0.06 if v != 2 else 0.03, 8.0)
		else:
			mmi.material_override = Mats.toon(Color.WHITE, true, 0.03)
		scat.add_child(mmi)

func _build_grass(c: Vector2i) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c) + 11
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = PropsLib.get_mesh("grass")
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	var count := 1500
	var ox := c.x * Terrain.CHUNK
	var oz := c.y * Terrain.CHUNK
	for k in count:
		var lx := rng.randf() * Terrain.CHUNK
		var lz := rng.randf() * Terrain.CHUNK
		var h := terrain.height(ox + lx, oz + lz)
		if h < Terrain.WATER_LEVEL + 0.3:
			continue
		var n := terrain.normal(ox + lx, oz + lz)
		if n.y < 0.8:
			continue
		var s := rng.randf_range(0.7, 1.4)
		xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), Vector3(lx, h - 0.05, lz)))
		var gc := terrain.ground_color(ox + lx, oz + lz, h, n).lightened(rng.randf_range(0.05, 0.2))
		cols.append(gc)
	mm.instance_count = xfs.size()
	for k in xfs.size():
		mm.set_instance_transform(k, xfs[k])
		mm.set_instance_custom_data(k, cols[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Grass"
	mmi.multimesh = mm
	mmi.material_override = grass_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi

func _build_flowers(c: Vector2i) -> Node3D:
	var root := Node3D.new()
	root.name = "Flowers"
	var data := terrain.chunk_data(c)
	var by_col := {}
	var ox := c.x * Terrain.CHUNK
	var oz := c.y * Terrain.CHUNK
	var thistle_xf: Array = []
	for t in data.thistles:
		var trng := RandomNumberGenerator.new()
		trng.seed = t.seed
		for k in int(2 + t.density * 5):
			var tp: Vector3 = t.pos + Vector3(trng.randf_range(-3.5, 3.5), 0, trng.randf_range(-3.5, 3.5))
			tp.y = terrain.height(tp.x, tp.z)
			var ts := trng.randf_range(0.8, 1.3)
			thistle_xf.append(Transform3D(Basis(Vector3.UP, trng.randf() * TAU).scaled(Vector3(ts, ts, ts)), tp - Vector3(ox, 0, oz)))
	if not thistle_xf.is_empty():
		var tmm := MultiMesh.new()
		tmm.transform_format = MultiMesh.TRANSFORM_3D
		tmm.mesh = PropsLib.get_mesh("thistle")
		tmm.instance_count = thistle_xf.size()
		for k in thistle_xf.size():
			tmm.set_instance_transform(k, thistle_xf[k])
		var tmi := MultiMeshInstance3D.new()
		tmi.multimesh = tmm
		tmi.material_override = Mats.foliage(0.06, 1.2)
		tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(tmi)
	for f in data.flowers:
		var rng := RandomNumberGenerator.new()
		rng.seed = f.seed
		var n := int(6 + f.density * 14)
		var col := rng.randi() % 5
		for k in n:
			var p: Vector3 = f.pos + Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4))
			p.y = terrain.height(p.x, p.z)
			if p.y < Terrain.WATER_LEVEL + 0.3:
				continue
			var ci := col if rng.randf() < 0.75 else rng.randi() % 5
			if not by_col.has(ci):
				by_col[ci] = []
			by_col[ci].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p - Vector3(ox, 0, oz)))
	for ci in by_col:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = PropsLib.get_mesh("flowers:%d" % ci)
		var list: Array = by_col[ci]
		mm.instance_count = list.size()
		for k in list.size():
			mm.set_instance_transform(k, list[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = Mats.foliage(0.05, 0.7)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
	return root

func _build_collision(c: Vector2i) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = G.WORLD_LAYER
	var seg := 32
	var stp := Terrain.CHUNK / seg
	var hm := HeightMapShape3D.new()
	hm.map_width = seg + 1
	hm.map_depth = seg + 1
	var data := PackedFloat32Array()
	data.resize((seg + 1) * (seg + 1))
	var ox := c.x * Terrain.CHUNK
	var oz := c.y * Terrain.CHUNK
	for j in seg + 1:
		for i in seg + 1:
			data[j * (seg + 1) + i] = terrain.height(ox + i * stp, oz + j * stp)
	hm.map_data = data
	var cs := CollisionShape3D.new()
	cs.shape = hm
	cs.scale = Vector3(stp, 1.0, stp)
	cs.position = Vector3(Terrain.CHUNK * 0.5, 0, Terrain.CHUNK * 0.5)
	body.add_child(cs)
	var cd := terrain.chunk_data(c)
	for t in cd.trees:
		var tc := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.45 * t.scale
		cyl.height = 6.0
		tc.shape = cyl
		tc.position = t.pos - Vector3(ox, -3.0, oz)
		body.add_child(tc)
	for r in cd.rocks:
		var rc := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = r.size * 0.78
		rc.shape = sp
		rc.position = r.pos - Vector3(ox, r.size * 0.25, oz)
		body.add_child(rc)
	return body

## --- Tree interaction (shake/push). Visual: hide instance, play a wobble, restore.
func shake_tree(tree: Dictionary, strength := 1.0) -> void:
	if not tree.has("mm"):
		return
	var mm: MultiMesh = tree.mm
	var idx: int = tree.mm_index
	var xf: Transform3D = tree.mm_xf
	if not is_instance_valid(mm):
		return
	var key := "tree:%d:%d:%d" % [tree.variant, int(tree.rot * 10.0) % 3, tree.get("biome", 0)]
	var mi := MeshInstance3D.new()
	mi.mesh = PropsLib.get_mesh(key)
	mi.material_override = Mats.foliage(0.06, 8.0)
	add_child(mi)
	var c := Terrain.chunk_of(tree.pos)
	var base := Transform3D(xf.basis, xf.origin + Vector3(c.x * Terrain.CHUNK, 0, c.y * Terrain.CHUNK))
	mi.global_transform = base
	mm.set_instance_transform(idx, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), xf.origin))
	var tw := create_tween()
	var axis := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	tw.tween_method(func(t: float) -> void:
		if not is_instance_valid(mi):
			return
		var ang := sin(t * 18.0) * exp(-t * 2.2) * 0.22 * strength
		mi.global_transform = Transform3D(Basis(axis, ang) * base.basis, base.origin), 0.0, 2.2, 2.2)
	tw.tween_callback(func() -> void:
		if is_instance_valid(mm):
			mm.set_instance_transform(idx, xf)
		mi.queue_free())
