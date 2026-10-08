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

func _raw_height(x: float, z: float) -> float:
	var b := n_base.get_noise_2d(x, z)
	var m := n_mid.get_noise_2d(x, z)
	var h := b * 17.0 + m * 4.0 + n_detail.get_noise_2d(x, z) * 0.35
	var l := n_lake.get_noise_2d(x, z)
	if l > 0.42:
		var k := minf((l - 0.42) * 7.0, 1.0)
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
	var c := G.MEADOW.lerp(G.MEADOW_DRY, smoothstep(0.55, 0.85, t))
	c = c.lerp(G.MEADOW_DEEP, smoothstep(0.05, 0.35, g) * 0.8)
	var f := n_flower.get_noise_2d(x, z)
	c = c.lerp(G.MEADOW.lightened(0.12), smoothstep(0.35, 0.6, f) * 0.35)
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
			var tree_p := smoothstep(0.0, 0.4, grove) * 0.75 + 0.015
			if near_flat:
				tree_p *= 0.1
			if roll < tree_p:
				var variant := 0
				var v := rng.randf()
				if h > 9.0 and v < 0.6:
					variant = 2  # spire
				elif v < 0.38:
					variant = 1  # fruit tree
				elif v < 0.5:
					variant = 3  # birch
				trees.append({
					"pos": Vector3(p.x, h, p.y), "variant": variant, "rot": rng.randf() * TAU,
					"scale": rng.randf_range(0.8, 1.3), "fruit": variant == 1, "id": trees.size(),
				})
				continue
			if rockm > 0.32 and roll < 0.45 and not near_flat:
				var big := rockm > 0.5 and rng.randf() < 0.3
				rocks.append({
					"pos": Vector3(p.x, h, p.y), "size": rng.randf_range(4.0, 7.0) if big else rng.randf_range(0.6, 2.2),
					"rot": rng.randf() * TAU, "variant": rng.randi() % 4, "big": big,
				})
				continue
			if flower > 0.25 and roll < 0.9:
				flowers.append({"pos": Vector3(p.x, h, p.y), "density": smoothstep(0.25, 0.6, flower), "seed": rng.randi()})
	var d := {"trees": trees, "rocks": rocks, "flowers": flowers}
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

## Flower density around a point (beast sneezes in flower fields).
func pollen_at(x: float, z: float) -> float:
	return clampf(n_flower.get_noise_2d(x, z) * 2.0 - 0.4, 0.0, 1.0)
