class_name RouteMap
extends Control
## The crew's map of the migration, drawn like a plate in a field guide: watercolour biome
## bands, inked lake shores and woods, the waystone tree with every road (taken or not), the
## beast's actual trail, and little marks where the journal's moments happened.
## Water and woods are sampled once per run on a worker thread (from a private Terrain copy).

const ASPECT := 2.0         # pages are about twice as wide as tall
const MAX_SAMPLES := 70000
const PAD := 70.0           # metres of margin around the planned route
const MARKS := {
	"found_": "star", "robbed": "feather", "snatched": "feather", "nest": "nest", "nest_beast": "nest",
	"gulp": "gulp", "ford": "wave", "brambles": "thorn", "calf_joined": "heart", "night": "tent",
	"shake": "zig", "sneeze": "spray", "fling_crew": "arc", "rescue": "ring", "enchanted": "note",
}

var game: Game
var reveal := 1.0           # 0..1 of the trail inked (the end page animates it)
var interactive := false    # hover a mark to read its journal line
var _rot := 0.0             # world (x, z) bearing that points right on the page
var _start := Vector2.ZERO  # world (x, z) of the first camp; map space is relative to it
var _lo := Vector2.ZERO     # planned bounds, map space (metres)
var _hi := Vector2.ONE
var _bands: Array = []      # [radius m, wash colour, edge colour, name] innermost first
var _grid_lo := Vector2.ZERO
var _grid_n := Vector2i.ZERO
var _cell := 12.0           # metres per water/woods sample (grows with the route's size)
var _water_tex: ImageTexture
var _shore := PackedVector2Array()   # map-space segment pairs
var _woods: Array = []      # [map pos, biome, size]
var _task := -1
var _sampled: Dictionary = {}
var _xf_scale := 1.0
var _xf_off := Vector2.ZERO
var _marks: Array = []      # [screen pos, glyph, journal index, trail metres]
var _hover := -1
var _redraw_t := 0.0
var _rng_seed := 0

func setup(p_game: Game) -> void:
	game = p_game
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := game.world.terrain
	_start = Vector2(game._start_pos.x, game._start_pos.z)
	_rng_seed = game.seed_v
	# lay the page out along the migration: the average bearing to the last waystones points right
	var dirs := Vector2.ZERO
	for n in game.wtree:
		if int(n.level) == Game.WAYSTONES - 1:
			dirs += (Vector2(n.pos.x, n.pos.z) - _start).normalized()
	_rot = dirs.angle() if dirs.length() > 0.01 else 0.0
	_lo = Vector2(INF, INF)
	_hi = -_lo
	for p in [Vector2.ZERO] + _node_points():
		_lo = _lo.min(p)
		_hi = _hi.max(p)
	_lo -= Vector2(PAD, PAD)
	_hi += Vector2(PAD, PAD)
	# widen (or heighten) to the page's shape so the sampled ground fills it
	var ext := _hi - _lo
	if ext.x < ext.y * ASPECT:
		var grow := (ext.y * ASPECT - ext.x) * 0.5
		_lo.x -= grow
		_hi.x += grow
	else:
		var grow := (ext.x / ASPECT - ext.y) * 0.5
		_lo.y -= grow
		_hi.y += grow
	ext = _hi - _lo
	_cell = maxf(12.0, sqrt(ext.x * ext.y / MAX_SAMPLES))
	# biome rings, found by walking out along the page's axis
	var axis := Vector2.RIGHT.rotated(_rot)
	var cur := t.biome_index(_start.x, _start.y)
	var r := 0.0
	while r < _hi.x + 400.0:
		r += 6.0
		var w := _start + axis * r
		var b := t.biome_index(w.x, w.y)
		if b != cur:
			_add_band(r, cur)
			cur = b
	_add_band(1.0e5, cur)
	# water and woods: sampled off the main thread
	_grid_lo = _lo
	_grid_n = Vector2i(ceili(ext.x / _cell) + 1, ceili(ext.y / _cell) + 1)
	var copy := t.clone_for_thread()
	_task = WorkerThreadPool.add_task(_sample.bind(copy, _grid_lo, _grid_n, _rot, _start, _cell), false, "route map")

func _add_band(radius: float, biome: int) -> void:
	var def: Dictionary = Terrain.BIOMES[biome]
	var base: Color = def.base
	_bands.append([radius, G.PAPER.lerp(base, 0.5), base.darkened(0.12), String(def.name)])

func _node_points() -> Array:
	var out: Array = []
	for n in game.wtree:
		out.append(to_map(n.pos))
	return out

## World position -> map space (metres, page-aligned).
func to_map(w: Vector3) -> Vector2:
	return (Vector2(w.x, w.z) - _start).rotated(-_rot)

func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

## Worker thread: water depth field, its shoreline (marching squares) and wood glyphs.
func _sample(t: Terrain, lo: Vector2, n: Vector2i, rot: float, start: Vector2, cell: float) -> void:
	var depth := PackedFloat32Array()
	depth.resize(n.x * n.y)
	var img := Image.create(n.x, n.y, false, Image.FORMAT_RGBA8)
	var wash := G.WATER.lightened(0.25)
	var woods: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = _rng_seed
	for j in n.y:
		for i in n.x:
			var m := lo + Vector2(i, j) * cell
			var w := start + m.rotated(rot)
			var h := t.height(w.x, w.y)
			var d := Terrain.WATER_LEVEL - 0.15 - h
			depth[j * n.x + i] = d
			if d > 0.0:
				var edge := clampf(minf(minf(i, n.x - 1 - i), minf(j, n.y - 1 - j)) / 6.0, 0.0, 1.0)
				img.set_pixel(i, j, Color(wash, clampf(0.4 + d * 0.05, 0.0, 0.6) * edge))
			else:
				img.set_pixel(i, j, Color(wash, 0.0))
				if i % 3 == 0 and j % 3 == 0 and d < -0.6:
					var bio := t.biome_index(w.x, w.y)
					var grove := t.n_grove.get_noise_2d(w.x, w.y)
					var p: float = (smoothstep(0.0, 0.4, grove) * 0.75 + 0.015) * float(Terrain.BIOMES[bio].density)
					if p > 0.42:
						var jit := Vector2(rng.randf_range(-1.2, 1.2), rng.randf_range(-1.2, 1.2)) * cell
						woods.append([m + jit, bio, clampf(p, 0.5, 1.2)])
	var segs := PackedVector2Array()
	for j in n.y - 1:
		for i in n.x - 1:
			var v := [depth[j * n.x + i], depth[j * n.x + i + 1], depth[(j + 1) * n.x + i + 1], depth[(j + 1) * n.x + i]]
			var inside := 0
			for k in 4:
				if float(v[k]) > 0.0:
					inside += 1
			if inside == 0 or inside == 4 or i < 3 or j < 3 or i > n.x - 5 or j > n.y - 5:
				continue
			var c := [lo + Vector2(i, j) * cell, lo + Vector2(i + 1, j) * cell, lo + Vector2(i + 1, j + 1) * cell, lo + Vector2(i, j + 1) * cell]
			var pts: Array = []
			for k in 4:
				var a: float = v[k]
				var b: float = v[(k + 1) % 4]
				if (a > 0.0) != (b > 0.0):
					pts.append((c[k] as Vector2).lerp(c[(k + 1) % 4], a / (a - b)))
			for k in range(0, pts.size() - 1, 2):
				segs.append(pts[k])
				segs.append(pts[k + 1])
	_sampled = {"img": img, "segs": segs, "woods": woods}

func _process(dt: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if not _sampled.is_empty():
			_water_tex = ImageTexture.create_from_image(_sampled.img)
			_shore = _sampled.segs
			_woods = _sampled.woods
			_sampled = {}
		queue_redraw()
	if not is_visible_in_tree():
		return
	_redraw_t -= dt
	if reveal < 1.0 or _redraw_t <= 0.0:
		_redraw_t = 0.2
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not interactive or not (event is InputEventMouseMotion):
		return
	var mp: Vector2 = (event as InputEventMouseMotion).position
	var best := -1
	var best_d := 14.0
	for k in _marks.size():
		var d := mp.distance_to(_marks[k][0])
		if d < best_d:
			best_d = d
			best = k
	if best != _hover:
		_hover = best
		queue_redraw()

func _scr(m: Vector2) -> Vector2:
	return (m - _lo) * _xf_scale + _xf_off

# ---------------------------------------------------------------- drawing
func _draw() -> void:
	if game == null or game.wtree.is_empty():
		return
	var trail: PackedVector2Array = game.trail
	# frame what the crew knows: the road so far, the smokes ahead and one fork beyond
	var lo := Vector2(-PAD, -PAD)
	var hi := Vector2(PAD, PAD)
	var focus: Array = []
	for id in game.path:
		focus.append(int(id))
	if game.waystone_idx < Game.WAYSTONES:
		for id in game.option_ids():
			focus.append(int(id))
			for kid in game.wtree[int(id)].kids:
				focus.append(int(kid))
	for id in focus:
		var m := to_map(game.wtree[id].pos)
		lo = lo.min(m - Vector2(PAD, PAD))
		hi = hi.max(m + Vector2(PAD, PAD))
	for p in trail:
		var m := (p - _start).rotated(-_rot)
		lo = lo.min(m - Vector2(PAD, PAD))
		hi = hi.max(m + Vector2(PAD, PAD))
	var ext := hi - lo
	var inner := size - Vector2(36, 36)
	_xf_scale = minf(inner.x / ext.x, inner.y / ext.y)
	_xf_off = Vector2(18, 18) + (inner - ext * _xf_scale) * 0.5 + (lo - _lo) * -_xf_scale
	var s := _xf_scale
	# paper and watercolour bands (outermost first, each a wobbly disc)
	draw_rect(Rect2(Vector2.ZERO, size), G.PAPER)
	var c := _scr(Vector2.ZERO)
	for bi in range(_bands.size() - 1, -1, -1):
		var band: Array = _bands[bi]
		if bi == _bands.size() - 1:
			draw_rect(Rect2(Vector2.ZERO, size), band[1])
			continue
		var ring := _wobble_ring(c, float(band[0]) * s, bi)
		draw_colored_polygon(ring, band[1])
		draw_polyline(ring, Color(band[2], 0.55), 2.0, true)
	# water wash and inked shores
	if _water_tex:
		draw_texture_rect(_water_tex, Rect2(_scr(_grid_lo - Vector2(_cell, _cell) * 0.5), Vector2(_grid_n) * _cell * s), false)
	if _shore.size() >= 2:
		var sh := PackedVector2Array()
		sh.resize(_shore.size())
		for k in _shore.size():
			sh[k] = _scr(_shore[k])
		draw_multiline(sh, Color(G.TEAL.darkened(0.35), 0.85), 1.4)
	# woods
	for wd in _woods:
		_tree_glyph(_scr(wd[0]), int(wd[1]), float(wd[2]))
	# biome names along the bottom margin
	_band_labels(c, s)
	# the bramble hedge (cut bushes leave the gap)
	for k in range(0, game.brambles.size()):
		if game.bramble_hp[k] <= 0 or k % 2 == 1:
			continue
		var bp := _scr(to_map(game.brambles[k]))
		draw_line(bp + Vector2(-3, -3), bp + Vector2(3, 3), G.PLUM.darkened(0.2), 1.6)
		draw_line(bp + Vector2(-3, 3), bp + Vector2(3, -3), G.PLUM.darkened(0.2), 1.6)
	# roads: every branch dashed in its smoke colour, the far ones fainter
	var reached := {}
	for id in game.path:
		reached[int(id)] = true
	var opts := game.option_ids()
	for id in game.wtree.size():
		var n: Dictionary = game.wtree[id]
		var from := Vector2.ZERO if int(n.parent) < 0 else to_map(game.wtree[int(n.parent)].pos)
		var a := _scr(from)
		var b := _scr(to_map(n.pos))
		var known := int(n.level) <= game.waystone_idx
		var col: Color = game.smoke_color(id).darkened(0.25)
		col.a = 0.85 if known else 0.4
		draw_dashed_line(a, b, col, 2.0, 7.0)
		if String(n.trait) != "":
			_road_label(a, b, String(Game.TRAITS[n.trait].short), Color(G.INK, 0.8 if known else 0.4))
	# the trail actually walked
	_draw_trail(trail, s)
	# waystones
	for id in game.wtree.size():
		var p := _scr(to_map(game.wtree[id].pos))
		_cairn(p, reached.has(id), id in opts, game.smoke_color(id))
	_cairn_start(c)
	# nests the magpies still hold
	for key in game._nest_info:
		var info: Array = game._nest_info[key]
		_glyph("nest", _scr(to_map(info[0])), G.BARK)
		if int(info[1]) > 0:
			draw_string(G.font_body, _scr(to_map(info[0])) + Vector2(7, -5), "%d" % int(info[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, G.INK)
	# journal marks along the way
	_draw_marks(trail)
	# where everyone is now
	if reveal >= 1.0 and game.beast:
		_beast_glyph(_scr(to_map(game.beast.ground_pos)), game.beast.yaw)
		for p in game.players.values():
			var pl := p as Player
			if pl == null or not pl.visible:
				continue
			var pp := _scr(to_map(pl.global_position))
			draw_circle(pp, 3.5, G.crew_color(pl.color_idx))
			draw_arc(pp, 3.5, 0, TAU, 10, G.INK, 1.0, true)
			if pl == game.local_player:
				draw_string(G.font_body, pp + Vector2(6, -6), "you", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, G.INK)
	_cartouche()
	_scale_bar(s)
	_compass_rose(Vector2(size.x - 52, size.y - 56))
	draw_rect(Rect2(Vector2(6, 6), size - Vector2(12, 12)), G.INK, false, 2.5)
	draw_rect(Rect2(Vector2(11, 11), size - Vector2(22, 22)), Color(G.INK, 0.5), false, 1.0)
	if _hover >= 0 and _hover < _marks.size():
		_callout(_marks[_hover][0], int(_marks[_hover][2]))

func _wobble_ring(c: Vector2, r: float, k: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 160
	for i in n + 1:
		var a := TAU * i / n
		var rr := r + sin(a * 9.0 + k * 1.7) * 3.0 + sin(a * 23.0 + k) * 1.4
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	return pts

func _band_labels(c: Vector2, s: float) -> void:
	var y := size.y - 24.0
	var prev := 0.0
	for bi in _bands.size():
		var band: Array = _bands[bi]
		var r_out: float = minf(float(band[0]), prev + 900.0)
		var mid := (prev + r_out) * 0.5 * s
		prev = float(band[0])
		var dy := y - c.y
		if mid <= absf(dy):
			continue
		var x := c.x + sqrt(mid * mid - dy * dy)
		var txt := String(band[3]).to_upper()
		var w := G.font_display.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		if x - w * 0.5 < 24.0 or x + w * 0.5 > size.x - 110.0:
			continue
		draw_string(G.font_display, Vector2(x - w * 0.5, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color((band[2] as Color).darkened(0.45), 0.85))

func _road_label(a: Vector2, b: Vector2, txt: String, col: Color) -> void:
	var d := b - a
	var ang := d.angle()
	if ang > PI * 0.5 or ang < -PI * 0.5:
		ang += PI
	var mid := a.lerp(b, 0.55)
	var w := G.font_body.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_set_transform(mid, ang)
	draw_string(G.font_body, Vector2(-w * 0.5, -5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	draw_set_transform(Vector2.ZERO)

func _trail_length(trail: PackedVector2Array) -> float:
	var total := 0.0
	for k in range(1, trail.size()):
		total += trail[k].distance_to(trail[k - 1])
	return total

func _draw_trail(trail: PackedVector2Array, _s: float) -> void:
	if trail.size() < 2:
		return
	var total := _trail_length(trail)
	var budget := total * clampf(reveal, 0.0, 1.0)
	var pts := PackedVector2Array([_scr((trail[0] - _start).rotated(-_rot))])
	var run := 0.0
	for k in range(1, trail.size()):
		var seg := trail[k].distance_to(trail[k - 1])
		var a := (trail[k - 1] - _start).rotated(-_rot)
		var b := (trail[k] - _start).rotated(-_rot)
		if run + seg > budget:
			pts.append(_scr(a.lerp(b, clampf((budget - run) / maxf(seg, 0.001), 0.0, 1.0))))
			break
		pts.append(_scr(b))
		run += seg
	if pts.size() < 2:
		return
	draw_polyline(pts, Color(G.PAPER, 0.8), 5.0, true)
	draw_polyline(pts, G.INK, 2.2, true)
	if reveal < 1.0:
		# the nib
		var tip := pts[pts.size() - 1]
		draw_circle(tip, 3.0, G.INK)

func _draw_marks(trail: PackedVector2Array) -> void:
	_marks.clear()
	var total := _trail_length(trail)
	var cum := PackedFloat32Array([0.0])
	for k in range(1, trail.size()):
		cum.append(cum[k - 1] + trail[k].distance_to(trail[k - 1]))
	var placed: Array = []
	for ji in game.journal.size():
		var e: Array = game.journal[ji]
		if e.size() < 5:
			continue
		var kind := String(e[2])
		var glyph := ""
		for prefix in MARKS:
			if kind == prefix or (String(prefix).ends_with("_") and kind.begins_with(prefix)):
				glyph = MARKS[prefix]
				break
		if glyph == "":
			continue
		var wp := Vector2(float(e[3]), float(e[4]))
		# when along the trail did this happen? (for the inking animation)
		var at := 0.0
		var best := INF
		for k in trail.size():
			var d := trail[k].distance_squared_to(wp)
			if d < best:
				best = d
				at = cum[k]
		if total > 0.0 and at > total * reveal + 1.0:
			continue
		var sp := _scr((wp - _start).rotated(-_rot))
		# nudge marks apart so a busy spot stays readable
		for q in placed:
			if sp.distance_to(q) < 13.0:
				sp += Vector2(0, -14.0)
		placed.append(sp)
		var col: Color = {"star": G.MARIGOLD, "feather": G.ROSE, "heart": G.ROSE, "wave": G.TEAL, "thorn": G.PLUM, "tent": G.TERRACOTTA, "note": G.MINT}.get(glyph, G.INK)
		_glyph(glyph, sp, col)
		if glyph == "tent":
			draw_string(G.font_body, sp + Vector2(8, 4), "night %d" % int(e[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(G.INK, 0.75))
		_marks.append([sp, glyph, ji, at])

func _glyph(kind: String, p: Vector2, col: Color) -> void:
	var ink := G.INK
	match kind:
		"star":
			var pts := PackedVector2Array()
			for k in 10:
				var a := -PI * 0.5 + TAU * k / 10.0
				pts.append(p + Vector2(cos(a), sin(a)) * (6.5 if k % 2 == 0 else 2.8))
			draw_colored_polygon(pts, col)
			pts.append(pts[0])
			draw_polyline(pts, ink, 1.2, true)
		"feather":
			var pts := PackedVector2Array([p + Vector2(-5, 5), p + Vector2(-1, -2), p + Vector2(5, -6), p + Vector2(2, 1)])
			draw_colored_polygon(pts, col)
			draw_line(p + Vector2(-6, 6), p + Vector2(4, -5), ink, 1.2, true)
		"nest":
			draw_arc(p + Vector2(0, -2), 6.0, 0.15, PI - 0.15, 10, col, 3.0, true)
			draw_arc(p + Vector2(0, -2), 6.0, 0.15, PI - 0.15, 10, ink, 1.0, true)
			draw_line(p + Vector2(-6, -2), p + Vector2(6, -2), ink, 1.0)
		"gulp":
			draw_circle(p, 5.5, G.PAPER)
			draw_arc(p, 5.5, 0, TAU, 14, ink, 1.4, true)
			draw_circle(p + Vector2(0, 1), 2.0, ink)
		"wave":
			var pts := PackedVector2Array()
			for k in 9:
				pts.append(p + Vector2(-7 + k * 1.75, sin(k * 1.4) * 2.2))
			draw_polyline(pts, col.darkened(0.2), 2.2, true)
		"thorn":
			draw_line(p + Vector2(-5, -5), p + Vector2(5, 5), col, 2.0, true)
			draw_line(p + Vector2(-5, 5), p + Vector2(5, -5), col, 2.0, true)
			draw_line(p + Vector2(0, -6), p + Vector2(0, 6), ink, 1.0, true)
		"heart":
			draw_circle(p + Vector2(-2.4, -1.5), 3.0, col)
			draw_circle(p + Vector2(2.4, -1.5), 3.0, col)
			draw_colored_polygon(PackedVector2Array([p + Vector2(-5.2, -0.5), p + Vector2(5.2, -0.5), p + Vector2(0, 5.5)]), col)
		"tent":
			var pts := PackedVector2Array([p + Vector2(-6, 4), p + Vector2(0, -6), p + Vector2(6, 4)])
			draw_colored_polygon(pts, col)
			pts.append(pts[0])
			draw_polyline(pts, ink, 1.2, true)
			draw_line(p + Vector2(0, -6), p + Vector2(0, 4), ink, 1.0)
		"zig":
			draw_polyline(PackedVector2Array([p + Vector2(-6, 2), p + Vector2(-3, -3), p + Vector2(0, 2), p + Vector2(3, -3), p + Vector2(6, 2)]), ink, 1.6, true)
		"spray":
			for k in 5:
				var a := -PI * 0.8 + k * 0.4
				draw_line(p + Vector2(cos(a), sin(a)) * 2.0, p + Vector2(cos(a), sin(a)) * 6.5, ink, 1.2, true)
		"arc":
			draw_arc(p + Vector2(0, 3), 6.0, PI, TAU, 10, ink, 1.4, true)
			draw_line(p + Vector2(6, 3), p + Vector2(3, 0), ink, 1.4)
			draw_line(p + Vector2(6, 3), p + Vector2(8, -0.5), ink, 1.4)
		"ring":
			draw_arc(p, 5.0, 0, TAU, 14, G.TERRACOTTA, 3.0, true)
			draw_arc(p, 5.0, 0, TAU, 14, ink, 1.0, true)
		"note":
			draw_circle(p + Vector2(-2, 3), 2.6, col.darkened(0.3))
			draw_line(p + Vector2(0.4, 3), p + Vector2(0.4, -6), ink, 1.3)
			draw_line(p + Vector2(0.4, -6), p + Vector2(4, -4), ink, 1.3)

func _tree_glyph(p: Vector2, biome: int, k: float) -> void:
	var tint: Color = (Terrain.BIOMES[biome].deep as Color)
	if biome == 3:
		tint = G.TERRACOTTA.lerp(G.MARIGOLD, fposmod(p.x * 0.37, 1.0))
	var r := 2.6 * k
	if biome == 4:
		var pts := PackedVector2Array([p + Vector2(-r, 1), p + Vector2(0, -r * 2.4), p + Vector2(r, 1)])
		draw_colored_polygon(pts, tint.darkened(0.1))
		pts.append(pts[0])
		draw_polyline(pts, Color(G.INK, 0.7), 1.0, true)
	else:
		draw_line(p + Vector2(0, 1.5), p + Vector2(0, -r), Color(G.INK, 0.7), 1.0)
		draw_circle(p + Vector2(0, -r), r, tint)
		draw_arc(p + Vector2(0, -r), r, 0, TAU, 10, Color(G.INK, 0.7), 1.0, true)

func _cairn(p: Vector2, reached: bool, current: bool, smoke: Color) -> void:
	if current:
		for k in 3:
			draw_circle(p + Vector2(sin(k * 1.9) * 3.0, -14.0 - k * 6.0), 3.5 + k * 1.2, Color(smoke, 0.75))
	var fill := G.STONE.lightened(0.15) if reached or current else G.PAPER
	for k in 3:
		var cp := p + Vector2(0, -k * 4.0)
		var rx := 6.0 - k * 1.4
		var pts := PackedVector2Array()
		for i in 13:
			var a := TAU * i / 12.0
			pts.append(cp + Vector2(cos(a) * rx, sin(a) * 2.6))
		draw_colored_polygon(pts, fill)
		draw_polyline(pts, G.INK, 1.1, true)
	if reached:
		draw_line(p + Vector2(0, -10), p + Vector2(0, -20), G.INK, 1.2)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -20), p + Vector2(8, -17.5), p + Vector2(0, -15)]), G.MARIGOLD)

func _cairn_start(p: Vector2) -> void:
	draw_circle(p, 4.0, G.TERRACOTTA)
	draw_arc(p, 4.0, 0, TAU, 12, G.INK, 1.2, true)
	draw_string(G.font_body, p + Vector2(-20, 18), "set out", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(G.INK, 0.8))

func _beast_glyph(p: Vector2, yaw: float) -> void:
	# the Mossback from above: a furry oval with a moss saddle, nose toward its heading
	var fwd := Vector2(-sin(yaw), -cos(yaw)).rotated(-_rot)
	var ang := fwd.angle()
	draw_set_transform(p, ang)
	var body := PackedVector2Array()
	for i in 17:
		var a := TAU * i / 16.0
		body.append(Vector2(cos(a) * 9.0, sin(a) * 6.0))
	draw_colored_polygon(body, G.FUR)
	draw_polyline(body, G.INK, 1.4, true)
	draw_circle(Vector2(-1, 0), 3.6, G.MOSS)
	draw_circle(Vector2(10, 0), 3.2, G.FUR_LIGHT)
	draw_arc(Vector2(10, 0), 3.2, 0, TAU, 10, G.INK, 1.0, true)
	draw_set_transform(Vector2.ZERO)

func _cartouche() -> void:
	var title := "The Wanderings of %s" % (game.beast.beast_name if game.beast else "the Mossback")
	var sub := "as walked, day %d of %d" % [game.day, Game.DAYS]
	var w := maxf(G.font_display.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x, 160.0) + 28.0
	var r := Rect2(Vector2(22, 22), Vector2(w, 58))
	draw_rect(r, G.PAPER)
	draw_rect(r, G.INK, false, 1.5)
	draw_rect(r.grow(-3.0), Color(G.INK, 0.4), false, 1.0)
	draw_string(G.font_display, r.position + Vector2(14, 28), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, G.INK)
	draw_string(G.font_body, r.position + Vector2(14, 47), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, G.STONE_DARK)

func _scale_bar(s: float) -> void:
	var metres := 100.0
	for m in [100.0, 200.0, 250.0, 500.0, 1000.0]:
		metres = m
		if m * s >= 70.0:
			break
	var at := Vector2(26, size.y - 48)
	var px := metres * s
	draw_rect(Rect2(at, Vector2(px, 5)), G.PAPER)
	for k in 4:
		if k % 2 == 0:
			draw_rect(Rect2(at + Vector2(px * k / 4.0, 0), Vector2(px / 4.0, 5)), G.INK)
	draw_rect(Rect2(at, Vector2(px, 5)), G.INK, false, 1.0)
	draw_string(G.font_body, at + Vector2(0, -5), "%d paces" % int(metres), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, G.INK)

func _compass_rose(c: Vector2) -> void:
	var north := Vector2(0, -1).rotated(-_rot)
	draw_circle(c, 20.0, Color(G.PAPER, 0.9))
	draw_arc(c, 20.0, 0, TAU, 24, G.INK, 1.2, true)
	for k in 4:
		var d := north.rotated(PI * 0.5 * k)
		var side := d.orthogonal() * 3.5
		var len := 17.0 if k == 0 else 11.0
		draw_colored_polygon(PackedVector2Array([c + side, c + d * len, c - side]), G.TERRACOTTA if k == 0 else G.INK)
	var np := c + north * 30.0
	draw_string(G.font_display, np - Vector2(5, -6), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, G.INK)

func _callout(at: Vector2, ji: int) -> void:
	if ji >= game.journal.size():
		return
	var e: Array = game.journal[ji]
	var txt := "Day %d: %s" % [int(e[0]), String(e[1])]
	var w := minf(G.font_body.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 24.0, 380.0)
	var lines := ceili((G.font_body.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 24.0) / 380.0)
	var h := 14.0 + 20.0 * lines
	var pos := at + Vector2(14, -h - 8)
	pos.x = clampf(pos.x, 16.0, size.x - w - 16.0)
	pos.y = clampf(pos.y, 16.0, size.y - h - 16.0)
	var r := Rect2(pos, Vector2(w, h))
	draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(G.INK, 0.3))
	draw_rect(r, G.BUTTER)
	draw_rect(r, G.INK, false, 1.5)
	draw_multiline_string(G.font_body, r.position + Vector2(12, 22), txt, HORIZONTAL_ALIGNMENT_LEFT, w - 24.0, 15, -1, G.INK)
