class_name Terrain
extends RefCounted
## Deterministic world data from a seed: height, ground colour, scatter records.
## Pure data (no nodes) so the server can query it without building visuals.

const CHUNK := 64.0
const WATER_LEVEL := -1.6

var seed_v: int
var n_base := FastNoiseLite.new()
var n_mid := FastNoiseLite.new()
var n_detail := FastNoiseLite.new()
var n_lake := FastNoiseLite.new()
var n_grove := FastNoiseLite.new()
var n_rock := FastNoiseLite.new()
var n_flower := FastNoiseLite.new()
var n_tint := FastNoiseLite.new()
var n_thistle := FastNoiseLite.new()

## One biome per leg of the migration, blended near the waystones.
## trees = weights for [umbrella pine, plumbob tree, spire, paperbark]
const BIOMES := [
	{"name": "Clover Meadows", "base": Color("a3b55a"), "dry": Color("cdb96a"), "deep": Color("6f8f45"), "trees": [0.42, 0.38, 0.05, 0.15], "density": 1.0, "flowers": 1.4, "thistles": 0.4, "lakes": 0.0, "rocks": 1.0},
	{"name": "Gold Steppe", "base": Color("b9aa62"), "dry": Color("cfbd84"), "deep": Color("8f9a50"), "trees": [0.75, 0.22, 0.0, 0.03], "density": 0.5, "flowers": 0.5, "thistles": 1.8, "lakes": -0.08, "rocks": 1.4},
	{"name": "Mere Country", "base": Color("8fb06a"), "dry": Color("aabb7c"), "deep": Color("5d8a5a"), "trees": [0.15, 0.25, 0.2, 0.4], "density": 0.9, "flowers": 1.0, "thistles": 0.8, "lakes": 0.14, "rocks": 0.6},
	{"name": "Ember Woods", "base": Color("b39d5b"), "dry": Color("c9955a"), "deep": Color("86704a"), "trees": [0.35, 0.3, 0.1, 0.25], "density": 1.5, "flowers": 0.6, "thistles": 1.1, "lakes": 0.0, "rocks": 1.0},
	{"name": "Wintering Hollow", "base": Color("c3cbbd"), "dry": Color("dde2d6"), "deep": Color("9aab98"), "trees": [0.0, 0.05, 0.85, 0.1], "density": 0.7, "flowers": 0.2, "thistles": 0.0, "lakes": -0.04, "rocks": 1.8},
]

var route := PackedVector2Array()
var _chunk_data := {}  # Vector2i -> Dictionary
var _flatten: Array = []  # [Vector2 center, radius, height]

func _init(p_seed: int) -> void:
	seed_v = p_seed
	_cfg(n_base, 1, 0.0022, 4)
	_cfg(n_mid, 2, 0.011, 3)
	_cfg(n_detail, 3, 0.07, 1)
	_cfg(n_lake, 4, 0.0042, 2)
	_cfg(n_grove, 5, 0.0075, 2)
	_cfg(n_rock, 6, 0.012, 2)
	_cfg(n_flower, 7, 0.02, 2)
	_cfg(n_tint, 8, 0.03, 2)
	_cfg(n_thistle, 9, 0.016, 2)

func _cfg(n: FastNoiseLite, off: int, freq: float, oct: int) -> void:
	n.seed = seed_v * 31 + off
	n.frequency = freq
	n.fractal_octaves = oct
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

## Flatten a disc (used for waystone plateaus and the start meadow).
func add_flatten(center: Vector2, radius: float) -> void:
	var h := _raw_height(center.x, center.y)
	_flatten.append([center, radius, max(h, WATER_LEVEL + 1.2)])
	_chunk_data.clear()

## Route polyline: start then each waystone. Must be identical on every peer.
func set_route(points: PackedVector2Array) -> void:
	route = points
	_chunk_data.clear()

## Progress along the route in legs (0..route.size()-1) for the nearest route point.
func route_progress(x: float, z: float) -> float:
	if route.size() < 2:
		return 0.0
	var p := Vector2(x, z)
	var best := INF
	var best_u := 0.0
	for i in route.size() - 1:
		var a := route[i]
		var b := route[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var d := p.distance_squared_to(a + ab * t)
		if d < best:
			best = d
			best_u = i + t
	return best_u

## [biome_a, biome_b, blend]
func biome_at(x: float, z: float) -> Array:
	var u := route_progress(x, z)
	var i := mini(int(u), BIOMES.size() - 1)
	var f := u - floorf(u)
	if i >= route.size() - 2 and f > 0.75:
		return [i, BIOMES.size() - 1, smoothstep(0.75, 1.0, f)]
	return [i, mini(i + 1, BIOMES.size() - 1), smoothstep(0.82, 1.0, f)]

func biome_value(x: float, z: float, key: String) -> float:
	var b := biome_at(x, z)
	return lerpf(BIOMES[b[0]][key], BIOMES[b[1]][key], b[2])

func biome_index(x: float, z: float) -> int:
	var b := biome_at(x, z)
	return b[1] if b[2] > 0.5 else b[0]

func _raw_height(x: float, z: float) -> float:
	var b := n_base.get_noise_2d(x, z)
	var m := n_mid.get_noise_2d(x, z)
	var h := b * 17.0 + m * 4.0 + n_detail.get_noise_2d(x, z) * 0.35
	var l := n_lake.get_noise_2d(x, z)
	var lake_t := 0.42
	if route.size() >= 2:
		lake_t -= biome_value(x, z, "lakes")
	if l > lake_t:
		var k := minf((l - lake_t) * 7.0, 1.0)
		h = lerpf(h, WATER_LEVEL - 2.6, k * k * (3.0 - 2.0 * k))
	return h

func height(x: float, z: float) -> float:
	var h := _raw_height(x, z)
	for f in _flatten:
		var d: float = Vector2(x, z).distance_to(f[0])
		var r: float = f[1]
		if d < r * 1.6:
			var k := clampf((r * 1.6 - d) / (r * 0.6), 0.0, 1.0)
			k = k * k * (3.0 - 2.0 * k)
			h = lerpf(h, f[2], k)
	return h

func normal(x: float, z: float) -> Vector3:
	var e := 1.0
	var hx := height(x + e, z) - height(x - e, z)
	var hz := height(x, z + e) - height(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()

func is_water(x: float, z: float) -> bool:
	return height(x, z) < WATER_LEVEL - 0.15

func ground_color(x: float, z: float, h: float, n: Vector3) -> Color:
	var t := n_tint.get_noise_2d(x, z) * 0.5 + 0.5
	var g := n_grove.get_noise_2d(x, z)
	var bi := biome_at(x, z)
	var ba: Dictionary = BIOMES[bi[0]]
	var bb: Dictionary = BIOMES[bi[1]]
	var k: float = bi[2]
	var base: Color = (ba.base as Color).lerp(bb.base, k)
	var dry: Color = (ba.dry as Color).lerp(bb.dry, k)
	var deep: Color = (ba.deep as Color).lerp(bb.deep, k)
	var c := base.lerp(dry, smoothstep(0.55, 0.85, t))
	c = c.lerp(deep, smoothstep(0.05, 0.35, g) * 0.8)
	var f := n_flower.get_noise_2d(x, z)
	c = c.lerp(base.lightened(0.12), smoothstep(0.35, 0.6, f) * 0.35)
	var slope := 1.0 - n.y
	c = c.lerp(G.SOIL, smoothstep(0.12, 0.3, slope))
	c = c.lerp(G.STONE, smoothstep(0.3, 0.45, slope))
	var shore := smoothstep(WATER_LEVEL + 1.3, WATER_LEVEL + 0.2, h)
	c = c.lerp(G.PAPER_DARK, shore)
	c = c.lerp(G.TEAL.darkened(0.2), smoothstep(WATER_LEVEL - 0.1, WATER_LEVEL - 1.5, h))
	return c

## Scatter records for a chunk, generated once and cached.
## kinds: "tree" (variant, fruit), "rock" (size), "flowers" (patch), "bush"
func chunk_data(c: Vector2i) -> Dictionary:
	if _chunk_data.has(c):
		return _chunk_data[c]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(c.x, c.y, seed_v))
	var trees: Array = []
	var rocks: Array = []
	var flowers: Array = []
	var thistles: Array = []
	var origin := Vector2(c.x * CHUNK, c.y * CHUNK)
	var step := 7.0
	var cells := int(CHUNK / step)
	for i in cells:
		for j in cells:
			var p := origin + Vector2((i + rng.randf()) * step, (j + rng.randf()) * step)
			var h := height(p.x, p.y)
			if h < WATER_LEVEL + 0.4:
				continue
			var near_flat := false
			for f in _flatten:
				if p.distance_to(f[0]) < f[1] * 0.8:
					near_flat = true
			var grove := n_grove.get_noise_2d(p.x, p.y)
			var rockm := n_rock.get_noise_2d(p.x, p.y)
			var flower := n_flower.get_noise_2d(p.x, p.y)
			var roll := rng.randf()
			var bio := biome_index(p.x, p.y)
			var bdef: Dictionary = BIOMES[bio]
			var tree_p: float = (smoothstep(0.0, 0.4, grove) * 0.75 + 0.015) * bdef.density
			if near_flat:
				tree_p *= 0.1
			if roll < tree_p:
				var variant := 0
				var v := rng.randf()
				var w: Array = bdef.trees
				var acc := 0.0
				for vi in 4:
					acc += w[vi]
					if v <= acc:
						variant = vi
						break
				if h > 11.0 and rng.randf() < 0.4:
					variant = 2  # spires on the high ground
				trees.append({
					"pos": Vector3(p.x, h, p.y), "variant": variant, "rot": rng.randf() * TAU, "biome": bio,
					"scale": rng.randf_range(0.8, 1.3), "fruit": variant == 1, "id": trees.size(),
				})
				continue
			if rockm > 0.32 and roll < 0.45 * bdef.rocks and not near_flat:
				var big := rockm > 0.5 and rng.randf() < 0.3
				rocks.append({
					"pos": Vector3(p.x, h, p.y), "size": rng.randf_range(4.0, 7.0) if big else rng.randf_range(0.6, 2.2),
					"rot": rng.randf() * TAU, "variant": rng.randi() % 4, "big": big,
				})
				continue
			var th := thistle_at(p.x, p.y)
			if th > 0.05 and roll < 0.95 and not near_flat:
				thistles.append({"pos": Vector3(p.x, h, p.y), "density": th, "seed": rng.randi()})
				continue
			if flower > 0.25 and roll < 0.9 * bdef.flowers:
				flowers.append({"pos": Vector3(p.x, h, p.y), "density": smoothstep(0.25, 0.6, flower), "seed": rng.randi()})
	var d := {"trees": trees, "rocks": rocks, "flowers": flowers, "thistles": thistles}
	_chunk_data[c] = d
	return d

static func chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK))

## Obstacles near a point (for the beast). Returns trees + big rocks.
func obstacles_near(p: Vector3, radius: float) -> Array:
	var out: Array = []
	var c := chunk_of(p)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var d := chunk_data(c + Vector2i(dx, dz))
			for t in d.trees:
				if Vector2(t.pos.x - p.x, t.pos.z - p.z).length() < radius:
					out.append(t)
			for r in d.rocks:
				if r.big and Vector2(r.pos.x - p.x, r.pos.z - p.z).length() < radius + r.size:
					out.append(r)
	return out

## Thistle density (thistlemites hitch rides from these patches).
func thistle_at(x: float, z: float) -> float:
	var m := biome_value(x, z, "thistles") if route.size() >= 2 else 1.0
	return clampf((n_thistle.get_noise_2d(x, z) - 0.38) * 3.0 * m, 0.0, 1.0)

## Flower density around a point (beast sneezes in flower fields).
func pollen_at(x: float, z: float) -> float:
	var m := biome_value(x, z, "flowers") if route.size() >= 2 else 1.0
	return clampf((n_flower.get_noise_2d(x, z) * 2.0 - 0.4) * m, 0.0, 1.0)
