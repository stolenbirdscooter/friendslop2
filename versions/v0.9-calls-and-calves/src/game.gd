class_name Game
extends Node3D
## One migration. Lives at /root/Main/Game on every peer so RPC paths match.
## Server owns: beast behaviour, fruit physics, day clock, waystones. Owners move their own Tender.

enum Phase { LOADING, TRAVEL, ARRIVED, NIGHT, WON, LOST }

const DAY_START := 0.265
const DAY_END := 0.78
const DAY_SECONDS := 540.0
const NIGHT_SECONDS := 10.0
const WAYSTONES := 4
const DAYS := 6
const ARRIVE_RADIUS := 26.0

signal toast(text: String)
signal big_message(title: String, sub: String)

var main: Node
var seed_v := 0
var world: World
var sky: SkyEnv
var beast: Beast
var hud: Hud
var fx: Fx
var players_node: Node3D
var props_node: Node3D
var players := {}
var ready_peers: Array = [1]   # peers whose world is built (receive streamed state)
var fruits := {}
var next_fruit_id := 1
var phase: int = Phase.LOADING
var day := 1
var waystone_idx := 0
var waystones: Array[Vector3] = []
var waystone_node: Node3D
var time_of_day := DAY_START
var phase_t := 0.0
var local_player: Player
var paused_menu := false
var _snap_t := 0.0
var _fruit_t := 0.0
var _state_t := 0.0
var _tree_t := 0.0
var _lure_send_t := 0.0
var _shaken := {}           # tree key -> time
var _fruit_left := {}       # tree key -> fruit remaining
var _gulped := {}           # peer -> spit time
var _start_pos := Vector3.ZERO
var _start_yaw := 0.0
var stats := {"fed": 0, "sneezes": 0, "gulps": 0, "pancakes": 0, "distance": 0.0, "shakes": 0, "mites": 0, "keepsakes": 0, "flings": 0}
var _mite_t := 0.0
var _last_beast_pos := Vector3.ZERO
var _biome_shown := -1
var _mood_t := 0.0
var _nibble_t := 0.0
var _keepsake_legs := {}    # server: legs whose keepsakes have been scattered
var _glint_t := 0.0
var _last_fling := -100.0
var river_leg := -1
var magpies := {}            # id -> Magpie
var _next_magpie := 1
var _magpie_t := 50.0
var _magpie_send_t := 0.0
var stolen_hats := {}        # peer -> true
var nests := {}              # server: key -> {"pos", "loot"}; everyone: _nest_info key -> [pos, count]
var _nest_info := {}
var _nest_nodes := {}
const NEST_HOLD := -9999
# the field journal: what actually happened, for the end-of-run page
var journal: Array = []        # [day, text]
var pstats := {}               # server (sent to all at the end): peer -> tallies
var _log_counts := {}
var _was_balk := false
var _balked_at := -100.0
var _enchanted_day := -1
var _gust_t := 12.0
var gust_dir := Vector3.ZERO
var gust_at := -100.0        # local time the current gust hits (telegraphed ~2 s ahead)
const PLAYER_FLING := 1.355  # sqrt(Tender gravity / prop gravity): same range as a plumbob

func _ready() -> void:
	name = "Game"

func ui_blocking() -> bool:
	return paused_menu or (hud != null and hud.is_blocking())

# ---------------------------------------------------------------- setup
func start_as_server(p_seed: int) -> void:
	_build(p_seed)
	phase = Phase.TRAVEL
	var leg := int(Args.arg("leg", "0"))
	if leg > 0 and leg < WAYSTONES:
		# dev: start partway along the route
		for i in leg:
			path.append(0 if i == 0 else wtree[path[-1]].kids[0])
			waystones.append(node_pos(path[-1]))
		waystone_idx = leg
		day = leg + 1
		var a := leg_from()
		var b := node_pos(option_ids()[0])
		var p := a.lerp(b, 0.55)
		beast.ground_pos = Vector3(p.x, world.terrain.height(p.x, p.z), p.z)
		beast.yaw = atan2(-(b.x - a.x), -(b.z - a.z))
		beast.setup_snap()
		_build_waystone()
	_spawn_start_fruit()
	_spawn_keepsakes(waystone_idx)
	jot("start", "Set out with %s, the %s one, who %s." % [beast.beast_name, beast.temperament.to_lower(), beast.temperament_blurb()])
	_sync_roster()

func start_as_client() -> void:
	_request_welcome.rpc_id(1)

@rpc("any_peer", "reliable")
func _request_welcome() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var fl := []
	for f in fruits.values():
		fl.append([f.id, f.kind, f.global_position, f.held_by])
	var st := _run_state()
	st["journal"] = journal
	_welcome.rpc_id(id, seed_v, st, fl, beast.get_snapshot())

@rpc("authority", "reliable")
func _welcome(p_seed: int, state: Dictionary, fl: Array, beast_snap: PackedFloat32Array) -> void:
	_build(p_seed)
	beast.authority = false
	_apply_run_state(state)
	beast.ground_pos = Vector3(beast_snap[0], beast_snap[1], beast_snap[2])
	beast.yaw = beast_snap[3]
	beast.push_snapshot(Time.get_ticks_msec() / 1000.0, beast_snap)
	for f in fl:
		_spawn_fruit_local(f[0], f[1], f[2], Vector3.ZERO)
		fruits[f[0]].held_by = f[3]
	_sync_roster()
	_client_ready.rpc_id(1)

@rpc("any_peer", "reliable")
func _client_ready() -> void:
	if multiplayer.is_server():
		var id := multiplayer.get_remote_sender_id()
		if id not in ready_peers:
			ready_peers.append(id)
		_ready_list.rpc(ready_peers)

@rpc("authority", "reliable")
func _ready_list(list: Array) -> void:
	ready_peers = list

## Send an RPC only to peers whose world exists (avoids node-not-found spam while joining).
func to_ready(obj: Object, method: StringName, args: Array) -> void:
	var me := multiplayer.get_unique_id()
	for id in ready_peers:
		if id != me:
			multiplayer.rpc(id, obj, method, args)

func _build(p_seed: int) -> void:
	var t0 := Time.get_ticks_msec()
	seed_v = p_seed
	sky = SkyEnv.new()
	add_child(sky)
	world = World.new()
	add_child(world)
	world.setup(seed_v)
	_plan_route()
	beast = Beast.new()
	beast.name = "Beast"
	add_child(beast)
	beast.authority = multiplayer.is_server()
	beast.roll_personality(seed_v)
	beast.setup(world, _start_pos, _start_yaw)
	beast.stepped.connect(_on_beast_step)
	beast.sneezed.connect(_on_beast_sneeze)
	if multiplayer.is_server():
		beast.vocal.connect(func(kind: String, pos: Vector3) -> void: _beast_sound.rpc(kind, pos))
		beast.chomped.connect(func(pos: Vector3) -> void: _beast_sound.rpc("chomp", pos))
	players_node = Node3D.new()
	players_node.name = "Players"
	add_child(players_node)
	props_node = Node3D.new()
	props_node.name = "Props"
	add_child(props_node)
	fx = Fx.new()
	add_child(fx)
	var amb := Ambient.new()
	add_child(amb)
	amb.setup(self)
	beast.shook.connect(_on_beast_shake)
	_build_waystone()
	world.focus = beast.ground_pos
	world.collision_points = [beast.ground_pos]
	world.warm_up()
	hud = Hud.new()
	hud.game = self
	add_child(hud)
	Net.roster_changed.connect(_sync_roster)
	phase = Phase.TRAVEL
	print("Game built in %d ms (seed %d)" % [Time.get_ticks_msec() - t0, seed_v])

## Roads past the first waystone fork in two; each branch has a character.
const TRAITS := {
	"windward": {"name": "the Windward Ridge", "short": "Windward Ridge", "blurb": "gales, but few mites", "len": 1.0},
	"magpie": {"name": "Magpie Woods", "short": "Magpie Woods", "blurb": "thieves, and an extra keepsake", "len": 1.0},
	"thistle": {"name": "the Thistle Moor", "short": "Thistle Moor", "blurb": "short, but crawling with mites", "len": 0.8},
	"meadow": {"name": "the Long Meadow", "short": "Long Meadow", "blurb": "long, calm and quiet", "len": 1.18},
}
const TRAIT_SMOKE := {"windward": Color("8fb8c9"), "magpie": Color("e08b7d"), "thistle": Color("9a6fb0"), "meadow": Color("8ccfa5")}
var wtree: Array = []   # {pos, level, parent, trait, kids}
var path: Array = []    # node ids reached, in order (waystones[] mirrors their positions)

func _plan_route() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var t := world.terrain
	# find a dry, flat-ish start
	var start := Vector3.ZERO
	for i in 60:
		var c := Vector3(rng.randf_range(-400, 400), 0, rng.randf_range(-400, 400))
		if t.height(c.x, c.z) > Terrain.WATER_LEVEL + 2.0 and t.normal(c.x, c.z).y > 0.93:
			start = c
			break
	_start_yaw = rng.randf() * TAU
	t.add_flatten(Vector2(start.x, start.z), 30.0)
	_start_pos = start
	wtree.clear()
	path.clear()
	waystones.clear()
	wtree.append({"pos": _place_waystone(rng, start, _start_yaw, 0, 1.0), "level": 0, "parent": -1, "trait": "", "kids": []})
	for lv in range(1, WAYSTONES):
		for id in range(wtree.size()):
			if wtree[id].level != lv - 1:
				continue
			var par: Dictionary = wtree[id]
			var from: Vector3 = start if par.parent < 0 else wtree[par.parent].pos
			var heading := atan2(-(par.pos.x - from.x), -(par.pos.z - from.z))
			var keys: Array = TRAITS.keys()
			var a: String = keys[rng.randi() % keys.size()]
			keys.erase(a)
			var b: String = keys[rng.randi() % keys.size()]
			for side in [1.0, -1.0]:
				var tr: String = a if side > 0.0 else b
				var h: float = heading + side * rng.randf_range(0.38, 0.6)
				var pos := _place_waystone(rng, par.pos, h, lv, TRAITS[tr].len)
				wtree.append({"pos": pos, "level": lv, "parent": id, "trait": tr, "kids": []})
				(par.kids as Array).append(wtree.size() - 1)
	for n in wtree:
		t.add_flatten(Vector2(n.pos.x, n.pos.z), 26.0)
	# biome bands: rings at each level's average distance from the start
	var c2 := Vector2(start.x, start.z)
	var edges := PackedFloat32Array()
	var angs: Array = []
	for lv in WAYSTONES:
		var sum := 0.0
		var cnt := 0
		var dirs := Vector2.ZERO
		for n in wtree:
			if n.level == lv:
				var v := Vector2(n.pos.x, n.pos.z) - c2
				sum += v.length()
				cnt += 1
				dirs += v.normalized()
		edges.append(sum / cnt)
		angs.append(dirs.angle())
	# every last waystone stands in the wintering hollow, however short its road was
	var nearest_last := INF
	for n in wtree:
		if n.level == WAYSTONES - 1:
			nearest_last = minf(nearest_last, Vector2(n.pos.x, n.pos.z).distance_to(Vector2(start.x, start.z)))
	edges[WAYSTONES - 1] = minf(edges[WAYSTONES - 1], nearest_last - 90.0)
	t.set_radial(c2, edges)
	# one ring of the route is cut by a river the beast won't wade without coaxing
	river_leg = 1 + rng.randi() % 2
	var mid: float = angs[river_leg]
	var span := 0.0
	for n in wtree:
		if n.level == river_leg or n.level == river_leg - 1:
			span = maxf(span, absf(wrapf((Vector2(n.pos.x, n.pos.z) - c2).angle() - mid, -PI, PI)))
	t.add_river_arc(c2, (edges[river_leg - 1] + edges[river_leg]) * 0.5, mid, span + 0.5, 11.0, rng.randf() * TAU)
	for n in wtree:
		n.pos.y = t.height(n.pos.x, n.pos.z)
	_start_pos.y = t.height(_start_pos.x, _start_pos.z)

func _place_waystone(rng: RandomNumberGenerator, from: Vector3, heading: float, lv: int, len_mult: float) -> Vector3:
	var t := world.terrain
	var best := Vector3.ZERO
	var best_score := -INF
	for k in 12:
		var h := heading + rng.randf_range(-0.25, 0.25)
		var dist := (rng.randf_range(430.0, 560.0) + lv * 40.0) * len_mult
		var c := from + Vector3(-sin(h), 0, -cos(h)) * dist
		var ht := t.height(c.x, c.z)
		var score := -absf(h - heading) - (100.0 if ht < Terrain.WATER_LEVEL + 1.5 else 0.0) + t.normal(c.x, c.z).y * 2.0
		if score > best_score:
			best_score = score
			best = c
	best.y = t.height(best.x, best.z)
	return best

## The waystone(s) the crew is heading for: one, or two at a fork.
func option_ids() -> Array:
	if waystone_idx >= WAYSTONES or wtree.is_empty():
		return []
	if path.size() > waystone_idx:
		return [path[waystone_idx]]
	if waystone_idx == 0:
		return [0]
	return wtree[path[waystone_idx - 1]].kids

func node_pos(id: int) -> Vector3:
	return wtree[id].pos

func smoke_color(id: int) -> Color:
	var tr: String = wtree[id].trait
	return TRAIT_SMOKE[tr] if tr != "" else G.MARIGOLD

func leg_from() -> Vector3:
	return _start_pos if waystone_idx == 0 or path.is_empty() else node_pos(path[mini(waystone_idx, path.size()) - 1])

## Which fork's road the beast is on (by bearing from the last waystone), "" before it commits.
func active_trait() -> String:
	var ops := option_ids()
	if ops.size() < 2:
		return wtree[ops[0]].trait if ops.size() == 1 and path.size() <= waystone_idx else ""
	var from := leg_from()
	var v := Vector2(beast.ground_pos.x - from.x, beast.ground_pos.z - from.z)
	if v.length() < 60.0:
		return ""
	var best := ""
	var bd := -2.0
	for id in ops:
		var o: Vector3 = node_pos(id)
		var d := v.normalized().dot(Vector2(o.x - from.x, o.z - from.z).normalized())
		if d > bd:
			bd = d
			best = wtree[id].trait
	return best

## "Left: ... Right: ..." as seen from the beast at the fork.
func fork_text() -> String:
	var ops := option_ids()
	if ops.size() < 2:
		return ""
	var from := leg_from()
	var avg := Vector3.ZERO
	for id in ops:
		avg += (node_pos(id) - from).normalized()
	var parts: Array = []
	for id in ops:
		var o: Vector3 = node_pos(id)
		var side := signf(avg.cross(o - from).y)
		var tr: Dictionary = TRAITS[wtree[id].trait]
		parts.append([side, "%s: %s (%s)" % ["left" if side > 0.0 else "right", tr.name, tr.blurb]])
	parts.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
	return "The road forks.  %s.   %s." % [String(parts[0][1]).left(1).to_upper() + String(parts[0][1]).substr(1), String(parts[1][1]).left(1).to_upper() + String(parts[1][1]).substr(1)]

func _build_waystone() -> void:
	if waystone_node:
		waystone_node.queue_free()
	waystone_node = Node3D.new()
	add_child(waystone_node)
	for id in option_ids():
		var wp := node_pos(id)
		var marker := Node3D.new()
		marker.position = Vector3(wp.x, world.terrain.height(wp.x, wp.z) - 0.4, wp.z)
		waystone_node.add_child(marker)
		_build_marker(marker, smoke_color(id))

func _build_marker(marker: Node3D, smoke_col: Color) -> void:
	marker.add_child(Mats.mesh_instance(PropsLib.get_mesh("waystone")))
	var bell := Mats.mesh_instance(PropsLib.get_mesh("bell"))
	bell.position = Vector3(0, 11.8, 0)
	bell.scale = Vector3.ONE * 1.6
	marker.add_child(bell)
	# signal smoke: opaque puffs rising (no transparency - the ink pass reads opaque only)
	var parts := GPUParticles3D.new()
	parts.amount = 70
	parts.lifetime = 14.0
	parts.preprocess = 14.0
	parts.visibility_aabb = AABB(Vector3(-60, -5, -60), Vector3(120, 260, 120))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 6.0
	pm.initial_velocity_min = 12.0
	pm.initial_velocity_max = 15.0
	pm.gravity = Vector3(0.9, 0.0, 0.3)
	pm.damping_min = 0.4
	pm.damping_max = 0.6
	pm.scale_min = 2.5
	pm.scale_max = 4.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(0.15, 1.0))
	curve.add_point(Vector2(1, 2.4))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.0
	parts.process_material = pm
	var puff := Geo.blob(Vector3.ONE, smoke_col, 0.25, 3, 6, 9)
	parts.draw_pass_1 = puff
	parts.material_override = Mats.toon(Color.WHITE, true, 0.2)
	parts.position = Vector3(0, 16, 0)
	marker.add_child(parts)

# ---------------------------------------------------------------- roster / players
func _sync_roster() -> void:
	if world == null:
		return
	for id in Net.players.keys():
		if not players.has(id):
			var p := Player.new()
			p.setup(self, id, Net.players[id])
			players_node.add_child(p)
			players[id] = p
			beast.look_targets.append(p)
			if p.is_local:
				local_player = p
				respawn_on_beast(p)
				p.cam_yaw = beast.yaw
			else:
				p.global_position = beast.body_xf * Vector3(0, 16, 4)
				Voice.attach_speaker(id, p)
		else:
			players[id].refresh_look(Net.players[id])
	ready_peers = ready_peers.filter(func(i: int) -> bool: return Net.players.has(i) or i == 1)
	for id in players.keys():
		if not Net.players.has(id):
			var p: Player = players[id]
			_release_everything_of(id)
			Voice.detach_speaker(id)
			p.queue_free()
			players.erase(id)

func get_player(id: int) -> Player:
	return players.get(id)

func respawn_on_beast(p: Player) -> void:
	var local := BeastBuild.top_point(randf_range(-2.0, 2.0), randf_range(-4.5, -2.5)) + Vector3(0, 1.0, 0)
	p.global_position = beast.body_xf * local
	p.velocity = Vector3.ZERO
	p.state = Player.St.NORMAL
	p.facing = beast.yaw
	p.visible = true

# ---------------------------------------------------------------- main loop
func _physics_process(dt: float) -> void:
	if world == null or phase == Phase.LOADING:
		return
	var focus := local_player.global_position if local_player else beast.ground_pos
	world.focus = focus
	var cps: Array[Vector3] = [beast.ground_pos, focus]
	for p in players.values():
		cps.append(p.global_position)
	if multiplayer.is_server():
		for f in fruits.values():
			if f.global_position.distance_to(beast.ground_pos) > 60.0:
				cps.append(f.global_position)
	world.collision_points = cps
	_update_held_fruit()
	if multiplayer.is_server():
		_server_tick(dt)
	else:
		if phase == Phase.TRAVEL:
			time_of_day += dt * (DAY_END - DAY_START) / DAY_SECONDS
	sky.time_of_day = time_of_day
	sky.mist = move_toward(sky.mist, 1.0 if weather == "mist" else 0.0, get_physics_process_delta_time() * 0.1)
	sky.apply()
	_mood_t -= get_physics_process_delta_time()
	if _mood_t <= 0.0:
		_mood_t = 1.0
		Music.set_mood(_pick_mood())
	var bi := world.terrain.biome_index(beast.ground_pos.x, beast.ground_pos.z)
	if bi != _biome_shown:
		if _biome_shown >= 0:
			big_message.emit(Terrain.BIOMES[bi].name, "")
			if multiplayer.is_server():
				jot("biome%d" % bi, "Crossed into %s." % Terrain.BIOMES[bi].name)
		_biome_shown = bi
	beast.dark = sky.night_amount() > 0.5
	var gusting := absf(Time.get_ticks_msec() / 1000.0 - gust_at) < 2.2
	Sfx.set_ambience(1.0 if gusting else (0.75 if weather == "gale" else 0.55), sky.night_amount())
	Sfx.set_listener_hint(focus)
	_update_grass_pushers()

func _process(dt: float) -> void:
	_glint_t -= dt
	if _glint_t <= 0.0 and local_player and fx:
		_glint_t = 0.9
		for f in fruits.values():
			if f.keepsake and f.held_by == 0 and f.global_position.distance_to(local_player.global_position) < 170.0:
				fx.puff(f.global_position + Vector3(0, 0.5, 0), 2, G.BUTTER, 0.14, 0.8, 1.8, 0.9, 0.0, 0.25)
	if local_player and local_player.post_mat and _flash > 0.0:
		_flash = maxf(_flash - dt * 1.5, 0.0)
		local_player.post_mat.set_shader_parameter("flash", _flash * 0.6)

var _flash := 0.0

func _update_grass_pushers() -> void:
	if world.grass_mat:
		world.grass_mat.set_shader_parameter("pusher0", beast.ground_pos)
		world.grass_mat.set_shader_parameter("pusher1", local_player.global_position if local_player else Vector3(0, -999, 0))

func _update_held_fruit() -> void:
	for f in fruits.values():
		if f.held_by < 0:
			var m: Magpie = magpies.get(-f.held_by)
			if m:
				f.global_position = m.beak_global()
				f.linear_velocity = Vector3.ZERO
				if multiplayer.is_server():
					f.freeze = true
			continue
		if f.held_by != 0:
			var p := get_player(f.held_by)
			if p:
				f.global_position = p.hand_point()
				f.linear_velocity = Vector3.ZERO
				if multiplayer.is_server():
					f.freeze = true

func _server_tick(dt: float) -> void:
	phase_t += dt
	var food: Array = []
	var mites_aboard := 0
	var mites := 0
	for f in fruits.values():
		if f.pest:
			mites += 1
			if f.on_beast and f.held_by == 0:
				mites_aboard += 1
		elif not f.keepsake:
			food.append(f)
	beast.set_food_list(food)
	if mites_aboard > 0:
		beast.itch = minf(beast.itch + mites_aboard * dt * 3.2 * beast.mods.itch * (1.0 - 0.5 * beast.serenade), 100.0)
		_nibble_t -= dt
		if _nibble_t <= 0.0:
			_nibble_t = randf_range(0.8, 2.0) / sqrt(float(mites_aboard))
			for f in fruits.values():
				if f.pest and f.on_beast and randf() < 0.5:
					_beast_sound.rpc("nibble", f.global_position)
					break
	else:
		beast.itch = maxf(beast.itch - dt * 2.5, 0.0)
	_spawn_mites(dt, mites)
	_tick_keepsakes()
	_tick_magpies(dt)
	_tick_journal(dt)
	_tick_calf(dt)
	if (weather == "gale" or active_trait() == "windward") and phase == Phase.TRAVEL:
		_gust_t -= dt
		if _gust_t <= 0.0:
			_gust_t = randf_range(16.0, 28.0)
			# mostly from the side: that's what knocks people off a back
			var side := beast.body_xf.basis.x * (1.0 if randf() < 0.5 else -1.0)
			var d := (side + beast.forward() * randf_range(-0.5, 0.5)).normalized()
			_gust.rpc(Vector3(d.x, 0, d.z))
	# sprinting Tenders punt thistlemites
	for f in fruits.values():
		if not f.pest or f.held_by != 0 or f.stun > 0.0:
			continue
		for pl in players.values():
			var v: Vector3 = pl.velocity if pl.is_local else pl._remote_vel
			var hv := Vector3(v.x, 0, v.z)  # CharacterBody velocity already excludes the platform's
			if hv.length() > 4.5 and pl.global_position.distance_to(f.global_position) < 1.0:
				f.fling(hv.normalized() * 9.0 + Vector3.UP * 5.0)
				_beast_sound.rpc("punt", f.global_position)
				break
	stats.distance += beast.ground_pos.distance_to(_last_beast_pos) if _last_beast_pos != Vector3.ZERO else 0.0
	_last_beast_pos = beast.ground_pos
	match phase:
		Phase.TRAVEL:
			time_of_day += dt * (DAY_END - DAY_START) / DAY_SECONDS
			for id in option_ids():
				var wp := node_pos(id)
				if path.size() == waystone_idx and Vector2(beast.ground_pos.x - wp.x, beast.ground_pos.z - wp.z).length() < ARRIVE_RADIUS:
					_reached.rpc(id)
					var tr: String = wtree[id].trait
					if tr != "":
						jot("road", "Came by way of %s." % TRAITS[tr].name)
					_set_phase(Phase.ARRIVED)
					break
			if time_of_day >= DAY_END and phase == Phase.TRAVEL:
				_set_phase(Phase.NIGHT)
		Phase.ARRIVED:
			beast.lure_down = move_toward(beast.lure_down, 0.0, dt)
			if phase_t > 9.0:
				waystone_idx += 1
				if waystone_idx >= WAYSTONES:
					_set_phase(Phase.WON)
				else:
					day += 1
					_next_dawn()
		Phase.NIGHT:
			time_of_day = lerpf(DAY_END, 1.0 + DAY_START, clampf(phase_t / NIGHT_SECONDS, 0.0, 1.0))
			beast.lure_down = 0.0
			if phase_t > NIGHT_SECONDS:
				day += 1
				if day > DAYS:
					_set_phase(Phase.LOST)
				else:
					_next_dawn()
	# mouth: eat fruit that reaches it, gulp careless Tenders
	var mouth := beast.mouth_global()
	for f in fruits.values():
		if f.held_by < 0:
			continue
		if f.keepsake:
			if f.held_by == 0 and f.stun <= 0.0 and f.global_position.distance_to(mouth) < 2.9:
				f.fling(beast.forward() * 7.0 + Vector3.UP * 6.0)
				_beast_sound.rpc("spit", mouth)
				_announce.rpc("The Mossback doesn't eat %s. It spat it out." % PropsLib.KEEPSAKES[f.kind].name)
			continue
		if f.global_position.distance_to(mouth) < 2.9 and beast.act != Beast.Act.SIT and beast.satiety < 99.5:
			var holder: int = f.held_by
			if f.pest:
				beast.pollen = 1.0
				_announce.rpc("The Mossback ate a thistlemite. Its nose tickles...")
				jot("mite_eaten", "It ate a thistlemite. It regretted it immediately.")
			else:
				beast.feed(f.value)
				stats.fed += 1
				tally(f.last_holder, "fed")
				if f.kind == "gourdle" and f.last_holder != 0:
					jot("gourdle", "%s fed it a whole gourdle. It hummed for a mile." % pname(f.last_holder))
			_remove_fruit.rpc(f.id)
			if holder != 0:
				_gulp(holder)
			break
	for id in _gulped.keys():
		if Time.get_ticks_msec() / 1000.0 > _gulped[id]:
			_gulped.erase(id)
			var fwd := beast.forward()
			var v := fwd * randf_range(9.0, 12.0) + Vector3.UP * 8.0 + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
			_you_spat.rpc_id(id, v)
			_beast_sound.rpc("spit", mouth)
	# beast shoves through trees
	_tree_t -= dt
	if _tree_t <= 0.0 and beast.speed > 0.6:
		_tree_t = 0.25
		for probe in [beast.ground_pos + beast.forward() * 9.0, beast.ground_pos, beast.ground_pos - beast.forward() * 9.0]:
			for t in world.terrain.obstacles_near(probe, 7.5):
				if not t.has("variant"):
					continue
				_server_shake_tree(t, 1.6, 0.7)
	# replication
	_snap_t -= dt
	if _snap_t <= 0.0:
		_snap_t = 0.05
		to_ready(self, "_beast_snap", [beast.get_snapshot()])
	_fruit_t -= dt
	if _fruit_t <= 0.0:
		_fruit_t = 1.0 / 15.0
		_send_fruit_states()
	_state_t -= dt
	if _state_t <= 0.0:
		_state_t = 0.5
		to_ready(self, "_run_state_rpc", [_run_state()])

func _pick_mood() -> String:
	match phase:
		Phase.ARRIVED:
			return "arrived"
		Phase.NIGHT:
			return "night"
		Phase.WON, Phase.LOST:
			return "silent"
	if time_of_day < DAY_START + 0.035:
		return "dawn"
	if DAY_END - time_of_day < 0.05 or beast.satiety < 12.0 or beast.itch > 75.0:
		return "tense"
	return "travel"

func _next_dawn() -> void:
	time_of_day = DAY_START
	_set_phase(Phase.TRAVEL)
	_spawn_keepsakes(waystone_idx)

func _set_phase(p: int) -> void:
	phase = p
	phase_t = 0.0
	_run_state_rpc.rpc(_run_state())
	_phase_changed.rpc(p, day, waystone_idx)
	match p:
		Phase.TRAVEL:
			var w := {"mist": "Mist so thick you could spread it on toast.", "gale": "A gale blew all day.", "clear": ["Clear skies.", "A fine walking day.", "Bright and breezy."][day % 3]}
			jot("day", "%s" % w.get(weather, ""), 1)
		Phase.ARRIVED:
			jot("arrived", "Reached the %s waystone. The old stones hummed back." % ["first", "second", "third", "fourth"][mini(waystone_idx, 3)])
		Phase.NIGHT:
			jot("night", "Night fell short of the waystone. A day lost.")
		Phase.WON:
			jot("won", "Reached the wintering hollow. It lay down and slept for a month.")
			_send_awards()
		Phase.LOST:
			jot("lost", "Winter caught us in the open. It curled up anyway, and we slept in the cottage.")
			_send_awards()

@rpc("authority", "call_local", "reliable")
func _phase_changed(p: int, p_day: int, p_way: int) -> void:
	if world == null:
		return
	phase = p
	day = p_day
	match p:
		Phase.ARRIVED:
			Music.stinger("waystone")
			Sfx.play("bell", waystones[mini(p_way, waystones.size() - 1)] if not waystones.is_empty() else beast.global_head(), 6.0)
			_flash = 0.6
			_arrival_spectacle(p_way)
			var sub := "The Mossback hums at the old stones."
			var today := journal.filter(func(e: Array) -> bool: return int(e[0]) == p_day and not String(e[1]).begins_with("Reached") and not String(e[1]).begins_with("Crossed"))
			if today.size() > 1:
				sub = "From today's page: \"%s\"" % String(today[randi() % today.size()][1])
			big_message.emit("Waystone %d reached" % (p_way + 1), sub)
		Phase.NIGHT:
			Music.stinger("day_lost")
			big_message.emit("Night falls", "The Mossback curls up to sleep. A day is lost.")
		Phase.TRAVEL:
			waystone_idx = p_way
			_build_waystone()
			roll_weather()
			var fork := fork_text()
			if fork != "":
				toast.emit(fork)
			if weather == "mist":
				big_message.emit("Day %d of %d  ·  Mist" % [p_day, DAYS], "Can't see the smoke. Someone get up on the roof with the spyglass.")
			elif weather == "gale":
				big_message.emit("Day %d of %d  ·  Gale" % [p_day, DAYS], "When the wind howls, hold R to flop flat, or grab something.")
			elif p_day == 1 and p_way == 0:
				big_message.emit(beast.beast_name, "the %s. It %s. Follow the marigold smoke." % [beast.temperament.to_lower(), beast.temperament_blurb()])
			elif fork != "":
				big_message.emit("Day %d of %d  ·  A fork in the road" % [p_day, DAYS], "Two smokes on the horizon. Steer for the one you want.")
			else:
				big_message.emit("Day %d of %d" % [p_day, DAYS], "Follow the smoke.")
		Phase.WON:
			Music.stinger("won")
			Sfx.play("bell", beast.global_head(), 6.0)
			_flash = 0.8
			big_message.emit("The migration is complete", "Your Mossback reached the wintering hollow.")
		Phase.LOST:
			big_message.emit("Winter came early", "The Mossback settles in the open.")
	if hud:
		hud.on_phase(p)

func _run_state() -> Dictionary:
	return {"phase": phase, "day": day, "way": waystone_idx, "tod": time_of_day, "station": beast.lure_operator, "stats": stats, "shelf": beast.shelf, "stolen": stolen_hats.keys(), "nests": _nest_info, "path": path}

@rpc("authority", "call_remote", "unreliable_ordered")
func _run_state_rpc(s: Dictionary) -> void:
	_apply_run_state(s)

func _apply_run_state(s: Dictionary) -> void:
	if s.has("journal"):
		journal = s.journal
	var pth: Array = s.get("path", path)
	if pth.size() > path.size():
		for i in range(path.size(), pth.size()):
			_reached(int(pth[i]))
	var way: int = s.way
	if way != waystone_idx:
		waystone_idx = way
		_build_waystone()
	phase = s.phase
	if day != s.day:
		day = s.day
		roll_weather()
	day = s.day
	if absf(time_of_day - s.tod) > 0.01:
		time_of_day = s.tod
	stats = s.stats
	beast.set_shelf(s.get("shelf", []))
	for peer in s.get("stolen", []):
		if not stolen_hats.has(peer):
			_hat_stolen(peer, 0)
	var ni: Dictionary = s.get("nests", {})
	for key in ni:
		if not _nest_info.has(key) or _nest_info[key][1] != ni[key][1]:
			_nest_set(key, ni[key][0], ni[key][1])

@rpc("authority", "call_remote", "unreliable_ordered")
func _beast_snap(s: PackedFloat32Array) -> void:
	if beast:
		beast.push_snapshot(Time.get_ticks_msec() / 1000.0, s)

@rpc("authority", "call_local", "reliable")
func _beast_sound(kind: String, pos: Vector3) -> void:
	match kind:
		"moan": Sfx.play("beast_moan", pos, 2.0, randf_range(0.9, 1.1))
		"happy": Sfx.play("beast_happy", pos, 2.0)
		"grumble": Sfx.play("beast_grumble", pos, 3.0)
		"sneeze_in": Sfx.play("beast_sneeze_in", pos, 3.0)
		"chomp":
			Sfx.play("beast_chomp", pos, 2.0)
			if fx:
				fx.puff(pos, 8, G.MARIGOLD, 0.25, 3.0, 1.0, 0.7, -6.0, 0.5)
			get_tree().create_timer(0.5).timeout.connect(func() -> void: Sfx.play("beast_gulp", pos, 0.0))
			get_tree().create_timer(1.0).timeout.connect(func() -> void: Sfx.play("beast_happy", pos, 0.0))
			if randf() < 0.35:
				Music.stinger("fed")
		"spit": Sfx.play("spit", pos, 3.0)
		"nibble":
			Sfx.play("munch", pos, -8.0, randf_range(1.6, 2.1))
		"hum":
			Sfx.play("beast_happy", pos, -4.0, randf_range(0.72, 0.8))
			if fx:
				for k in 3:
					fx.puff(pos + Vector3(randf_range(-3, 3), 3.0 + k, randf_range(-3, 3)), 1, [G.ROSE, G.BUTTER, G.MINT][k], 0.3, 1.0, 2.5, 1.6, -0.2, 0.2)
		"punt":
			Sfx.play("bonk", pos, -2.0, 1.4)
			if fx:
				fx.puff(pos, 5, G.PLUM, 0.25, 2.5, 0.5, 0.5, -2.0, 0.3)

func _on_beast_step(pos: Vector3, strength: float) -> void:
	Sfx.play("beast_step", pos, -2.0 + strength * 3.0, randf_range(0.9, 1.05))
	if pos.y < Terrain.WATER_LEVEL + 0.2:
		fx.puff(Vector3(pos.x, Terrain.WATER_LEVEL, pos.z), 9, G.PAPER, 0.7, 5.0, 2.0, 0.9, -9.0, 1.2)
		if pos.y < Terrain.WATER_LEVEL - 0.8:
			Sfx.play("splash", Vector3(pos.x, Terrain.WATER_LEVEL, pos.z), -1.0, randf_range(0.9, 1.1))
	else:
		fx.puff(pos + Vector3(0, 0.3, 0), 6, world.terrain.ground_color(pos.x, pos.z, pos.y, Vector3.UP).lightened(0.25), 0.9, 3.0, 0.4, 1.1, -0.3, 1.4)
	if local_player:
		local_player.on_beast_step(pos, strength)

func _on_beast_sneeze(origin: Vector3) -> void:
	Sfx.play("beast_sneeze", origin, 6.0)
	Music.stinger("sneeze")
	var fwd := beast.forward()
	for k in 5:
		fx.puff(origin + fwd * (1.0 + k * 2.0), 6, G.BUTTER if k % 2 == 0 else G.PAPER, 0.8 + k * 0.25, 6.0 + k * 2.0, 0.6, 1.6, 0.2, 0.8 + k * 0.4)
	stats.sneezes += 1
	if multiplayer.is_server():
		jot("sneeze", ["%s sneezed. Everyone aboard went up like confetti.", "%s sneezed at a meadow. The meadow won.", "%s sneezed again. Bless it."][_count("sneeze") % 3] % beast.beast_name, 2)
	if local_player:
		local_player.on_sneeze(origin, beast.forward())
		toast_local("BLESS YOU")
	if multiplayer.is_server():
		for f in fruits.values():
			if f.held_by == 0 and f.global_position.distance_to(beast.body_xf.origin + Vector3(0, 14, 0)) < 22.0:
				f.fling(Vector3.UP * 7.0 + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)))

# ---------------------------------------------------------------- fruit
func _spawn_start_fruit() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v + 5
	for i in 7:
		var a := rng.randf() * TAU
		var r := rng.randf_range(18.0, 32.0)
		var p := _start_pos + Vector3(cos(a) * r, 0, sin(a) * r)
		p.y = world.terrain.height(p.x, p.z) + 0.6
		server_spawn_fruit("gourdle" if i == 0 else "plumbob", p, Vector3.ZERO)
	# a little pantry on the back, near the hut door
	for i in 3:
		var lp := BeastBuild.top_point(-1.6 + i * 1.2, 1.0) + Vector3(0, 0.8, 0)
		server_spawn_fruit("plumbob", beast.body_xf * lp, Vector3.ZERO)

func server_spawn_fruit(kind: String, pos: Vector3, vel: Vector3) -> void:
	var id := next_fruit_id
	next_fruit_id += 1
	_spawn_fruit.rpc(id, kind, pos, vel)

@rpc("authority", "call_local", "reliable")
func _spawn_fruit(id: int, kind: String, pos: Vector3, vel: Vector3) -> void:
	_spawn_fruit_local(id, kind, pos, vel)

func _spawn_fruit_local(id: int, kind: String, pos: Vector3, vel: Vector3) -> void:
	if fruits.has(id) or props_node == null:
		return
	var f := Fruit.new()
	f.setup(id, kind, multiplayer.is_server())
	f.game = self
	props_node.add_child(f)
	f.global_position = pos
	f.set_remote_state(pos, Quaternion.IDENTITY, 0)
	if multiplayer.is_server():
		f.linear_velocity = vel
		f.body_entered.connect(_on_fruit_hit.bind(f))
	fruits[id] = f

@rpc("authority", "call_local", "reliable")
func _remove_fruit(id: int) -> void:
	var f: Fruit = fruits.get(id)
	if f == null:
		return
	for p in players.values():
		if p.held_fruit == id:
			p.held_fruit = 0
	fruits.erase(id)
	f.queue_free()

func fruit_heavy(id: int) -> bool:
	var f: Fruit = fruits.get(id)
	return f != null and f.heavy

func _send_fruit_states() -> void:
	var data := PackedFloat32Array()
	for f in fruits.values():
		if f.sleeping and f.held_by == 0 and Engine.get_physics_frames() % 60 > 3:
			continue
		var q: Quaternion = f.quaternion
		data.append_array([f.id, f.global_position.x, f.global_position.y, f.global_position.z, q.x, q.y, q.z, q.w, f.held_by])
	if data.size() > 0:
		to_ready(self, "_fruit_states", [data])

@rpc("authority", "call_remote", "unreliable_ordered")
func _fruit_states(data: PackedFloat32Array) -> void:
	var i := 0
	while i + 8 < data.size():
		var f: Fruit = fruits.get(int(data[i]))
		if f:
			f.set_remote_state(Vector3(data[i + 1], data[i + 2], data[i + 3]), Quaternion(data[i + 4], data[i + 5], data[i + 6], data[i + 7]), int(data[i + 8]))
		i += 9

func _on_fruit_hit(body: Node, f: Fruit) -> void:
	if body is Player and f.held_by == 0:
		var spd := f.linear_velocity.length()
		var now := Time.get_ticks_msec() / 1000.0
		if spd > 6.0 and now - f._last_bonk > 0.5:
			f._last_bonk = now
			var p: Player = body
			_you_knocked.rpc_id(p.peer_id, f.linear_velocity.normalized() * (4.0 + spd * 0.5) + Vector3.UP * 3.0)

# ---------------------------------------------------------------- local actions -> server
func try_interact(p: Player) -> void:
	if p.global_position.distance_to(beast.lure_handle_global()) < 2.6 and p.state == Player.St.NORMAL:
		_request_station.rpc_id(1)
		return
	if p.global_position.distance_to(beast.spyglass_global()) < 2.2 and p.state == Player.St.NORMAL:
		p.enter_spy()
		return
	if p.global_position.distance_to(beast.flinger_stand_global()) < 2.2 and p.state == Player.St.NORMAL:
		_request_flinger.rpc_id(1)
		return
	if beast.in_hut(p.global_position) and p.held_fruit == 0:
		_try_on_hat(p)
		return
	for key in _nest_info:
		var np: Vector3 = _nest_info[key][0]
		if String(key).begins_with("g") and p.global_position.distance_to(np) < 3.0:
			_request_nest.rpc_id(1, key)
			return
	var t := _nearest_tree(p.global_position, 3.4)
	if not t.is_empty():
		_request_shake.rpc_id(1, t.pos)

func _nearest_tree(pos: Vector3, radius: float) -> Dictionary:
	var best := {}
	var bd := radius
	for t in world.terrain.obstacles_near(pos, radius):
		if not t.has("variant"):
			continue
		var d := Vector2(t.pos.x - pos.x, t.pos.z - pos.z).length()
		if d < bd and absf(t.pos.y - pos.y) < 3.0:
			bd = d
			best = t
	return best

func interaction_hint(p: Player) -> String:
	if p.state == Player.St.STATION:
		return "A / D  swing the lure     W / S  lower · raise     E  let go"
	if p.state == Player.St.CARRIED:
		return "Mash SPACE to wriggle free"
	if p.state == Player.St.TUMBLE:
		return ""
	if p.state == Player.St.SPY:
		return "Find the signal smoke and hold it in the glass     E  step back"
	if p.state == Player.St.FLING:
		return "Mouse / A·D  aim     hold LMB  wind it up, release to fling     E  let go"
	if p.global_position.distance_to(beast.lure_handle_global()) < 2.6:
		return "E  take the lure" if beast.lure_operator == 0 else "Someone's steering"
	if p.global_position.distance_to(beast.spyglass_global()) < 2.2:
		return "E  look through the spyglass"
	if p.global_position.distance_to(beast.flinger_stand_global()) < 2.2:
		return "E  man the flinger" if beast.fl_operator == 0 else "Someone's at the flinger"
	if beast.in_bowl(p.global_position):
		return "You're sitting in the flinger bowl. Bold."
	if beast.in_hut(p.global_position) and p.held_fruit == 0:
		return "E  try on another hat  (%s)" % G.HAT_NAMES.get(G.player_hat, G.player_hat)
	if p.held_fruit != 0 or p.carrying_peer != 0:
		return "Hold RMB to throw   ·   LMB drop"
	var t := _nearest_tree(p.global_position, 3.4)
	if not t.is_empty():
		return "E  shake the tree" + ("  (there's a magpie nest up there!)" if _nest_info.has("%d,%d" % [int(t.pos.x), int(t.pos.z)]) else "")
	for key in _nest_info:
		if String(key).begins_with("g") and p.global_position.distance_to(_nest_info[key][0]) < 3.0:
			return "E  rummage through the magpie nest"
	if _find_grab_target(p) != null:
		return "LMB  pick up"
	return ""

func _find_grab_target(p: Player) -> Node3D:
	var best: Node3D = null
	var bd := 2.6
	var fwd := Basis(Vector3.UP, p.facing) * Vector3.FORWARD
	for f in fruits.values():
		if f.held_by != 0:
			continue
		var to: Vector3 = f.global_position - (p.global_position + Vector3(0, 0.5, 0))
		var d := to.length() - (0.6 if to.normalized().dot(fwd) > 0.3 else 0.0)
		if d < bd:
			bd = d
			best = f
	for o in players.values():
		if o == p or o.state == Player.St.GULPED or o.carried_by != 0 or o.carrying_peer != 0:
			continue
		var d: float = o.global_position.distance_to(p.global_position)
		if d < 1.7 and d < bd:
			bd = d
			best = o
	return best

func try_grab(p: Player) -> void:
	var t := _find_grab_target(p)
	if t is Fruit:
		p.held_fruit = t.id  # predict; server confirms or corrects
		Sfx.play("pickup", p.global_position, -6.0)
		_request_grab_fruit.rpc_id(1, t.id)
	elif t is Player:
		_request_grab_player.rpc_id(1, t.peer_id)

func request_throw(p: Player, vel: Vector3) -> void:
	Sfx.play("throw", p.global_position, -4.0)
	if p.held_fruit != 0:
		var id := p.held_fruit
		p.held_fruit = 0
		_request_release_fruit.rpc_id(1, id, p.hand_point(), vel)
	elif p.carrying_peer != 0:
		var t := p.carrying_peer
		p.carrying_peer = 0
		_request_throw_player.rpc_id(1, t, vel)

func request_drop(p: Player, vel: Vector3) -> void:
	if p.held_fruit != 0:
		var id := p.held_fruit
		p.held_fruit = 0
		_request_release_fruit.rpc_id(1, id, p.hand_point(), vel)
	elif p.carrying_peer != 0:
		var t := p.carrying_peer
		p.carrying_peer = 0
		_request_throw_player.rpc_id(1, t, vel)

func request_break_free(_p: Player) -> void:
	_request_break_free.rpc_id(1)

func do_whistle(p: Player) -> void:
	_whistle.rpc(p.peer_id, p.global_position, p.on_beast)

func do_emote(p: Player) -> void:
	_emote.rpc(p.peer_id, p.global_position)

func send_lure(yaw: float, down: float) -> void:
	_lure_send_t -= get_physics_process_delta_time()
	if _lure_send_t > 0.0:
		return
	_lure_send_t = 0.05
	if multiplayer.is_server():
		_set_lure(yaw, down)
	else:
		_set_lure.rpc_id(1, yaw, down)

func release_station(p: Player) -> void:
	p.state = Player.St.NORMAL
	p.state_t = 0.0
	_request_release_station.rpc_id(1)

func toast_local(text: String) -> void:
	toast.emit(text)

func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()

# ---------------------------------------------------------------- server handlers
@rpc("any_peer", "call_local", "reliable")
func _request_station() -> void:
	if not multiplayer.is_server():
		return
	var id := _sender()
	if beast.lure_operator == 0 or get_player(beast.lure_operator) == null:
		beast.lure_operator = id
		if id != multiplayer.get_unique_id():
			_station_granted.rpc_id(id)
		else:
			_station_granted()

@rpc("authority", "call_remote", "reliable")
func _station_granted() -> void:
	if local_player:
		local_player.state = Player.St.STATION
		local_player.state_t = 0.0
		beast.lure_operator = local_player.peer_id
		Sfx.play("creak", local_player.global_position, -4.0)

@rpc("any_peer", "call_local", "reliable")
func _request_release_station() -> void:
	if multiplayer.is_server() and beast.lure_operator == _sender():
		beast.lure_operator = 0

@rpc("any_peer", "call_local", "unreliable_ordered")
func _set_lure(yaw: float, down: float) -> void:
	if multiplayer.is_server() and beast.lure_operator == _sender():
		beast.lure_yaw = clampf(yaw, -1.0, 1.0)
		beast.lure_down = clampf(down, 0.0, 1.0)

@rpc("any_peer", "call_local", "reliable")
func _request_shake(pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	for t in world.terrain.obstacles_near(pos, 1.0):
		if t.has("variant"):
			_server_shake_tree(t, 1.0, 1.0, _sender())
			return

func _server_shake_tree(t: Dictionary, strength: float, drop_chance: float, who := 0) -> void:
	var key := "%d,%d" % [int(t.pos.x), int(t.pos.z)]
	var now := Time.get_ticks_msec() / 1000.0
	if _shaken.has(key) and now - _shaken[key] < 2.5:
		return
	_shaken[key] = now
	_tree_shaken.rpc(t.pos, strength)
	_empty_nest(key, who)
	if t.fruit:
		var left: int = _fruit_left.get(key, 4)
		var n := mini(left, randi_range(1, 2) if drop_chance < 1.0 else randi_range(1, 3))
		if randf() > drop_chance:
			n = 0
		_fruit_left[key] = left - n
		for i in n:
			var p: Vector3 = t.pos + Vector3(randf_range(-1.8, 1.8), 4.5 * t.scale, randf_range(-1.8, 1.8))
			server_spawn_fruit("gourdle" if randf() < 0.12 else "plumbob", p, Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)))

@rpc("authority", "call_local", "reliable")
func _tree_shaken(pos: Vector3, strength: float) -> void:
	if world == null:
		return
	for t in world.terrain.obstacles_near(pos, 0.5):
		if t.has("variant"):
			world.shake_tree(t, strength)
			Sfx.play("rustle", pos + Vector3(0, 4, 0), -2.0)
			fx.puff(pos + Vector3(0, 5.0 * t.scale, 0), 10, G.MOSS if t.variant != 3 else G.BUTTER, 0.3, 2.5, 0.2, 2.2, -1.2, 2.0)
			return

@rpc("any_peer", "call_local", "reliable")
func _request_grab_fruit(id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := _sender()
	var f: Fruit = fruits.get(id)
	var p := get_player(sender)
	if f and p and f.held_by == 0 and f.global_position.distance_to(p.global_position) < 4.0:
		if f.keepsake and f.last_holder == 0:
			jot("found_" + f.kind, "%s found %s out in the grass." % [pname(sender), PropsLib.KEEPSAKES[f.kind].name])
		f.held_by = sender
		f.last_holder = sender
		f.freeze = true
		_fruit_held.rpc(id, sender)
	else:
		_fruit_held.rpc(id, f.held_by if f else 0)

@rpc("authority", "call_local", "reliable")
func _fruit_held(id: int, by: int) -> void:
	var f: Fruit = fruits.get(id)
	if f:
		f.held_by = by
	for p in players.values():
		if p.held_fruit == id and p.peer_id != by:
			p.held_fruit = 0
	var holder := get_player(by)
	if holder:
		holder.held_fruit = id

@rpc("any_peer", "call_local", "reliable")
func _request_release_fruit(id: int, pos: Vector3, vel: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var f: Fruit = fruits.get(id)
	if f == null or f.held_by != _sender():
		return
	f.held_by = 0
	f.global_position = pos
	f.freeze = false
	f.stun = 1.2
	f.linear_velocity = vel
	f.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	f.sleeping = false
	_fruit_held.rpc(id, 0)

@rpc("any_peer", "call_local", "reliable")
func _request_grab_player(target: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := _sender()
	var a := get_player(sender)
	var b := get_player(target)
	if a == null or b == null or b.carried_by != 0 or a.carried_by != 0:
		return
	if a.global_position.distance_to(b.global_position) > 3.0:
		return
	_carry_link.rpc(sender, target)

@rpc("authority", "call_local", "reliable")
func _carry_link(carrier: int, target: int) -> void:
	var a := get_player(carrier)
	var b := get_player(target)
	if a:
		a.carrying_peer = target
	if b:
		b.carried_by = carrier
		if b.is_local:
			b.set_carried(carrier)
			toast_local("%s picked you up!" % a.display_name if a else "Picked up!")
	Sfx.play("pickup", b.global_position if b else Vector3.ZERO, -2.0, 0.7)

@rpc("any_peer", "call_local", "reliable")
func _request_throw_player(target: int, vel: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var a := get_player(_sender())
	if a == null:
		return
	_carry_unlink.rpc(_sender(), target, vel)

@rpc("any_peer", "call_local", "reliable")
func _request_break_free() -> void:
	if not multiplayer.is_server():
		return
	var b := get_player(_sender())
	if b and b.carried_by != 0:
		_carry_unlink.rpc(b.carried_by, b.peer_id, Vector3.UP * 5.0)

@rpc("authority", "call_local", "reliable")
func _carry_unlink(carrier: int, target: int, vel: Vector3) -> void:
	var a := get_player(carrier)
	var b := get_player(target)
	if a:
		a.carrying_peer = 0
	if b:
		b.carried_by = 0
		if b.is_local:
			b.thrown(vel)

func _release_everything_of(id: int) -> void:
	for f in fruits.values():
		if f.held_by == id:
			f.held_by = 0
			if multiplayer.is_server():
				f.freeze = false
	for p in players.values():
		if p.carrying_peer == id:
			p.carrying_peer = 0
		if p.carried_by == id and p.is_local:
			p.set_carried(0)
	if multiplayer.is_server() and beast.lure_operator == id:
		beast.lure_operator = 0
	if multiplayer.is_server() and beast.fl_operator == id:
		beast.fl_operator = 0
		beast.fl_charge = 0.0

@rpc("any_peer", "call_local", "reliable")
func _whistle(peer: int, pos: Vector3, on_beast: bool) -> void:
	var p := get_player(peer)
	var pitch := 1.0 + ((p.color_idx if p else 0) % 4) * 0.09
	Sfx.play("whistle", pos + Vector3(0, 1.2, 0), 0.0, pitch)
	if multiplayer.is_server() and not on_beast:
		beast.whistle(pos, peer == beast.favourite)
	if multiplayer.is_server() and mosslet:
		mosslet.coax(peer, pos)
	if multiplayer.is_server():
		for m in magpies.values():
			if m.global_position.distance_to(pos) < 16.0 and m.scare():
				_announce.rpc("%s whistled. The magpie dropped its loot!" % (p.display_name if p else "Someone"))
				tally(peer, "shooed")
				jot("shoo", "%s whistled a magpie into dropping its loot." % pname(peer), 2)

@rpc("any_peer", "call_local", "reliable")
func _emote(peer: int, pos: Vector3) -> void:
	var p := get_player(peer)
	Sfx.play("munch", pos + Vector3(0, 1, 0), -2.0, 1.6)
	if p and not p.is_local:
		p.visual.waving = 1.5

@rpc("authority", "call_local", "reliable")
func _you_knocked(impulse: Vector3) -> void:
	if local_player:
		local_player.knock(impulse)

func _gulp(peer: int) -> void:
	if _gulped.has(peer):
		return
	_gulped[peer] = Time.get_ticks_msec() / 1000.0 + 1.6
	stats.gulps += 1
	tally(peer, "gulped")
	jot("gulp", "%s got eaten along with their snack. Spat out shortly after, damp." % pname(peer), 2)
	if peer != multiplayer.get_unique_id():
		_you_gulped.rpc_id(peer)
	else:
		_you_gulped()
	var p := get_player(peer)
	_announce.rpc("The Mossback ate %s's snack. And %s." % [p.display_name, p.display_name] if p else "Gulp.")

@rpc("authority", "call_remote", "reliable")
func _you_gulped() -> void:
	if local_player:
		local_player.gulped()

@rpc("authority", "call_local", "reliable")
func _you_spat(vel: Vector3) -> void:
	if local_player:
		local_player.spat(vel)

@rpc("authority", "call_local", "reliable")
func _announce(text: String) -> void:
	toast.emit(text)

# ---------------------------------------------------------------- restart
func request_new_migration() -> void:
	if multiplayer.is_server():
		_restart.rpc(randi())

@rpc("authority", "call_local", "reliable")
func _restart(new_seed: int) -> void:
	if main:
		main.restart_game(new_seed)

# ---------------------------------------------------------------- pests & shakes
func _spawn_mites(dt: float, count: int) -> void:
	if waystone_idx < 1 and day < 2:
		return  # first leg is a gentle one
	if count >= 10 or beast.speed < 0.4 or phase != Phase.TRAVEL:
		return
	_mite_t -= dt
	if _mite_t > 0.0:
		return
	_mite_t = 0.5
	var th := world.terrain.thistle_at(beast.ground_pos.x, beast.ground_pos.z)
	var chance := th * (0.35 + 0.12 * day) + (0.01 * day if day >= 3 else 0.0)
	chance *= {"windward": 0.4, "thistle": 2.2, "meadow": 0.5}.get(active_trait(), 1.0)
	if randf() < chance:
		var a := randf() * TAU
		var lp := BeastBuild.shell_point(Vector3(cos(a), 0.55, sin(a)).normalized())
		server_spawn_fruit("mite", beast.body_xf * (lp + Vector3(0, 0.6, 0)), Vector3.UP * 2.0)
		stats.mites += 1

func despawn_prop(id: int) -> void:
	if multiplayer.is_server() and fruits.has(id):
		var f: Fruit = fruits[id]
		if f.pest and f.last_holder != 0:
			tally(f.last_holder, "tossed")
		_remove_fruit.rpc(id)

func _on_beast_shake() -> void:
	stats.shakes += 1
	if multiplayer.is_server():
		jot("shake", "It shook like a wet dog. Thistlemites everywhere, and Tenders too.")
	Sfx.play("beast_grumble", beast.global_head(), 4.0, 1.3)
	Sfx.play("rustle", beast.body_xf.origin + Vector3(0, 14, 0), 6.0, 0.7)
	toast_local("SHAKE! Grab the lure pole to hold on.")
	if local_player:
		local_player.on_shake()
	for k in 10:
		var a := randf() * TAU
		fx.puff(beast.body_xf * BeastBuild.shell_point(Vector3(cos(a), 0.0, sin(a))), 3, G.FUR_LIGHT, 1.2, 4.0, 0.3, 1.0, -1.0, 1.0)
	if multiplayer.is_server():
		for f in fruits.values():
			if f.held_by == 0 and f.global_position.distance_to(beast.body_xf.origin + Vector3(0, 14, 0)) < 16.0:
				if f.pest and randf() < 0.25:
					continue  # this one clings on
				var side: Vector3 = (f.global_position - beast.body_xf.origin)
				side.y = 0
				f.fling(side.normalized() * randf_range(7, 11) + Vector3.UP * randf_range(5, 8))

# ---------------------------------------------------------------- weather & the lookout
var weather := "clear"
var marker_until := 0.0

func roll_weather() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 13 + day * 101
	weather = "clear"
	var r := rng.randf()
	if day >= 2 and r < 0.3:
		weather = "mist"
	elif day >= 2 and r < 0.55:
		weather = "gale"

func current_waystone() -> Vector3:
	var best := Vector3.INF
	for id in option_ids():
		var p := node_pos(id)
		if best == Vector3.INF or p.distance_to(beast.ground_pos) < best.distance_to(beast.ground_pos):
			best = p
	return best

func marker_visible() -> bool:
	return weather != "mist" or Time.get_ticks_msec() / 1000.0 < marker_until

func report_spotted() -> void:
	_spotted.rpc(local_player.display_name if local_player else "Someone")

@rpc("any_peer", "call_local", "reliable")
func _spotted(who: String) -> void:
	marker_until = Time.get_ticks_msec() / 1000.0 + 50.0
	Sfx.play("whistle", local_player.global_position if local_player else Vector3.ZERO, -4.0, 1.4)
	toast.emit("%s spotted the smoke! (marked for a while)" % who)
	if multiplayer.is_server():
		tally(_sender(), "spots")
		jot("spotted", "%s spotted the smoke through the spyglass." % who)

# ---------------------------------------------------------------- the flinger
func request_fling(power: float) -> void:
	_request_fling.rpc_id(1, power)

func send_flinger(yaw: float, charge: float) -> void:
	if multiplayer.is_server():
		return  # the host's beast is the authority already
	if Engine.get_physics_frames() % 3 == 0:
		_set_flinger.rpc_id(1, yaw, charge)

func release_flinger(p: Player) -> void:
	p.state = Player.St.NORMAL
	p.state_t = 0.0
	beast.fl_charge = 0.0
	_request_release_flinger.rpc_id(1)

@rpc("any_peer", "call_local", "reliable")
func _request_flinger() -> void:
	if not multiplayer.is_server():
		return
	var id := _sender()
	if beast.fl_operator == 0 or get_player(beast.fl_operator) == null:
		beast.fl_operator = id
		beast.fl_charge = 0.0
		if id != multiplayer.get_unique_id():
			_flinger_granted.rpc_id(id)
		else:
			_flinger_granted()

@rpc("authority", "call_remote", "reliable")
func _flinger_granted() -> void:
	if local_player:
		local_player.state = Player.St.FLING
		local_player.state_t = 0.0
		local_player.cam_yaw = beast.yaw + beast.fl_yaw
		beast.fl_operator = local_player.peer_id
		Sfx.play("creak", local_player.global_position, -4.0, 0.8)

@rpc("any_peer", "call_local", "reliable")
func _request_release_flinger() -> void:
	if multiplayer.is_server() and beast.fl_operator == _sender():
		beast.fl_operator = 0
		beast.fl_charge = 0.0

@rpc("any_peer", "call_local", "unreliable_ordered")
func _set_flinger(yaw: float, charge: float) -> void:
	if multiplayer.is_server() and beast.fl_operator == _sender():
		beast.fl_yaw = Beast.clamp_fl_yaw(yaw)
		beast.fl_charge = clampf(charge, 0.0, 1.0)

@rpc("any_peer", "call_local", "reliable")
func _request_fling(power: float) -> void:
	if not multiplayer.is_server() or beast.fl_operator != _sender():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_fling < 1.2:
		return
	_last_fling = now
	power = clampf(power, 0.0, 1.0)
	var vel := beast.flinger_velocity(power)
	var at := beast.flinger_release_global()
	var op := _sender()
	tally(op, "flings")
	var flown: Array = []
	for pl in players.values():
		if pl.peer_id != op and beast.in_bowl(pl.global_position):
			flown.append(pl.display_name)
			tally(pl.peer_id, "flown")
	var cargo := ""
	for f in fruits.values():
		if f.held_by == 0 and beast.in_bowl(f.global_position):
			cargo = "a thistlemite" if f.pest else (PropsLib.KEEPSAKES[f.kind].name if f.keepsake else "a " + f.kind)
	if not flown.is_empty():
		jot("fling_crew", "%s flung %s off the back%s." % [pname(op), " and ".join(flown), (" along with " + cargo) if cargo != "" else ""], 3)
	elif cargo != "":
		jot("fling", "%s flung %s at the horizon." % [pname(op), cargo], 2)
	for f in fruits.values():
		if f.held_by == 0 and beast.in_bowl(f.global_position):
			f.freeze = false
			f.sleeping = false
			f.global_position = at + Vector3(randf_range(-0.3, 0.3), randf_range(-0.2, 0.2), randf_range(-0.3, 0.3))
			f.linear_velocity = vel * randf_range(0.95, 1.05)
			f.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
			f.stun = 2.5
	_flinger_fired.rpc(at, vel)

@rpc("authority", "call_local", "reliable")
func _flinger_fired(at: Vector3, vel: Vector3) -> void:
	if world == null:
		return
	beast.fire_flinger_anim()
	Sfx.play("thwack", beast.flinger_xf().origin + Vector3(0, 1.0, 0), 3.0)
	Sfx.play("throw", at, 0.0, 0.7)
	fx.puff(at, 7, G.PAPER, 0.5, 4.0, 0.5, 0.8, -1.0, 0.8)
	if local_player and local_player.state in [Player.St.NORMAL, Player.St.TUMBLE] and beast.in_bowl(local_player.global_position):
		stats.flings += 1
		local_player.flung(at + Vector3(0, 0.4, 0), vel * PLAYER_FLING)

# ---------------------------------------------------------------- keepsakes
## Server: scatter two trinkets well off this leg's path, out where only the curious go.
func _spawn_keepsakes(leg: int) -> void:
	if not multiplayer.is_server() or leg >= WAYSTONES or _keepsake_legs.has(leg):
		return
	_keepsake_legs[leg] = true
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 31 + leg * 7
	# the host's still-locked hats come first, so each run is likely to unlock something
	var kinds: Array = PropsLib.KEEPSAKES.keys()
	kinds.sort_custom(func(x: String, y: String) -> bool: return ((x.hash() + leg * 977) % 1000) < ((y.hash() + leg * 977) % 1000))
	var locked := kinds.filter(func(k: String) -> bool: return not PropsLib.KEEPSAKES[k].hat in G.unlocked_hats)
	var pool: Array = locked + kinds.filter(func(k: String) -> bool: return not k in locked)
	_maybe_spawn_calf(leg)
	var a := leg_from()
	var ops := option_ids()
	var placed := 0
	for oi in ops.size():
		var b := node_pos(ops[oi])
		var count := 2 if ops.size() == 1 else (2 if wtree[ops[oi]].trait == "magpie" else 1)
		for k in count:
			if _scatter_keepsake(rng, a, b, pool[(leg * 3 + placed) % pool.size()], k):
				placed += 1

## Server: the lost calf waits ~90 m to one side of where this leg begins.
func _maybe_spawn_calf(leg: int) -> void:
	if mosslet != null or leg != 1 + (seed_v % 2):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 53 + leg
	var from := leg_from()
	var ahead := Vector3.ZERO
	for id in option_ids():
		ahead += (node_pos(id) - from).normalized()
	ahead = ahead.normalized()
	var side := Vector3(-ahead.z, 0, ahead.x) * (1.0 if rng.randf() < 0.5 else -1.0)
	var t := world.terrain
	for tries in 30:
		var p := from + ahead * rng.randf_range(60.0, 160.0) + side * rng.randf_range(70.0, 110.0)
		var h := t.height(p.x, p.z)
		if h > Terrain.WATER_LEVEL + 1.0 and t.normal(p.x, p.z).y > 0.88:
			_spawn_calf.rpc(Vector3(p.x, h, p.z))
			return

@rpc("authority", "call_local", "reliable")
func _spawn_calf(pos: Vector3) -> void:
	_make_calf(pos)

func _make_calf(pos: Vector3) -> Mosslet:
	if world == null or mosslet != null:
		return mosslet
	mosslet = Mosslet.new()
	mosslet.game = self
	props_node.add_child(mosslet)
	mosslet.build()
	mosslet.global_position = pos
	mosslet.set_remote(pos, 0.0, Mosslet.S.LOST, 0.0)
	return mosslet

func _tick_calf(dt: float) -> void:
	if mosslet == null:
		return
	mosslet.server_tick(dt)
	if mosslet.state == Mosslet.S.LOST and not _calf_hinted and mosslet.global_position.distance_to(beast.ground_pos) < 150.0:
		_calf_hinted = true
		var side := "left" if beast.forward().cross(mosslet.global_position - beast.ground_pos).y > 0.0 else "right"
		_announce.rpc("A small bleat, somewhere off to the %s..." % side)
		jot("calf_heard", "Heard a small bleat off to the %s. Something lost." % side)
	_calf_send_t -= dt
	if _calf_send_t <= 0.0:
		_calf_send_t = 0.1
		to_ready(self, "_calf_state", [mosslet.global_position, mosslet.rotation.y, mosslet.state, mosslet.speed])

@rpc("authority", "call_remote", "unreliable_ordered")
func _calf_state(pos: Vector3, yaw: float, st: int, spd: float) -> void:
	var m := _make_calf(pos)
	if m:
		m.set_remote(pos, yaw, st, spd)

func mosslet_bleat(pos: Vector3) -> void:
	_calf_bleat.rpc(pos)

@rpc("authority", "call_local", "unreliable")
func _calf_bleat(pos: Vector3) -> void:
	Sfx.play("beast_happy", pos + Vector3(0, 2, 0), -3.0, randf_range(2.0, 2.3))
	if fx:
		fx.puff(pos + Vector3(0, 3.2, -0.8), 2, G.PAPER, 0.25, 1.0, 2.0, 0.8, -0.5, 0.2)

func mosslet_follows(peer: int) -> void:
	_announce.rpc("The lost mosslet is following %s!" % pname(peer))
	jot("calf_follow", "A lost mosslet calf started following %s." % pname(peer), 2)

func mosslet_lost(peer: int) -> void:
	_announce.rpc("The mosslet lost sight of %s and sat down." % pname(peer))

func mosslet_joined(peer: int) -> void:
	_announce.rpc("The mosslet found the herd. It trots alongside %s now." % beast.beast_name)
	jot("calf_joined", "%s brought the lost mosslet home. It trotted alongside for the rest of the way, and the big one stopped fretting about food." % (pname(peer) if peer != 0 else "Somebody"))
	beast.joy = 1.0
	beast.mods.hunger = float(beast.mods.hunger) * 0.85
	if peer != 0:
		tally(peer, "calf")
		befriend(peer, 8.0)
	_beast_sound.rpc("happy", beast.global_head())

func _scatter_keepsake(rng: RandomNumberGenerator, a: Vector3, b: Vector3, kind: String, k: int) -> bool:
	var t := world.terrain
	var dir := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	var perp := Vector3(-dir.z, 0, dir.x)
	for tries in 24:
		var along := rng.randf_range(0.2, 0.85)
		var side := 1.0 if (k + tries) % 2 == 0 else -1.0
		var p := a.lerp(b, along) + perp * side * rng.randf_range(35.0, 90.0)
		var h := t.height(p.x, p.z)
		if h < Terrain.WATER_LEVEL + 1.5 or t.normal(p.x, p.z).y < 0.9 or not t.obstacles_near(p, 4.0).is_empty():
			continue
		server_spawn_fruit(kind, Vector3(p.x, h + 0.1, p.z), Vector3.ZERO)
		return true
	return false

func _tick_keepsakes() -> void:
	for f in fruits.values():
		if not f.keepsake:
			continue
		if f.held_by == 0:
			# far-off trinkets wait, frozen, until there's ground under them to land on
			var ok := world.has_collision_at(f.global_position)
			if f.freeze == ok:
				f.freeze = not ok
		if beast.in_hut(f.global_position):
			var who := get_player(f.last_holder)
			_remove_fruit.rpc(f.id)
			stats.keepsakes += 1
			tally(f.last_holder, "keepsakes")
			jot("shelf_" + f.kind, "%s put %s on the cottage shelf." % [who.display_name if who else "Someone", PropsLib.KEEPSAKES[f.kind].name])
			beast.joy = minf(beast.joy + 0.25, 1.0)
			_keepsake_shelved.rpc(f.kind, who.display_name if who else "Someone")
			_beast_sound.rpc("happy", beast.global_head())
			return

@rpc("authority", "call_local", "reliable")
func _keepsake_shelved(kind: String, who: String) -> void:
	if world == null:
		return
	beast.add_to_shelf(kind)
	var info: Dictionary = PropsLib.KEEPSAKES[kind]
	var hat: String = info.hat
	toast.emit("%s brought home %s. It's on the shelf now." % [who, info.name])
	Sfx.play("bell", beast.hut_door_global(), -6.0, 1.6)
	Music.stinger("fed")
	fx.puff(beast.hut_door_global() + Vector3(0, 1.5, 0), 10, G.BUTTER, 0.3, 3.0, 1.5, 1.0, -1.0, 0.8)
	if G.unlock_hat(hat):
		big_message.emit("New hat: %s" % G.HAT_NAMES[hat], "Step into the cottage and press E to try it on.")

func _try_on_hat(p: Player) -> void:
	var hats := G.available_hats()
	var i := hats.find(G.player_hat)
	G.player_hat = hats[(i + 1) % hats.size()]
	G.save_prefs()
	Net.update_my_look()
	Sfx.play("hat_pop", p.global_position + Vector3(0, 1.6, 0), 0.0)
	fx.puff(p.global_position + Vector3(0, 1.6, 0), 5, G.PAPER, 0.18, 1.5, 1.0, 0.6, -1.0, 0.2)

# ---------------------------------------------------------------- kalimbas
func play_note(idx: int) -> void:
	_note.rpc(clampi(idx, 0, 7))

@rpc("any_peer", "call_local", "reliable")
func _note(idx: int) -> void:
	if world == null:
		return
	var p := get_player(_sender())
	if p == null:
		return
	idx = clampi(idx, 0, 7)
	var pos := p.global_position + Vector3(0, 1.0, 0)
	var sc := Music.player_scale()
	Music.play_positional_note(sc[idx], pos)
	p.play_t = 0.7
	p.visual.playing = 0.7
	var col := G.crew_color(p.color_idx)
	var fwd := Basis(Vector3.UP, p.facing) * Vector3(0, 0, -0.5)
	fx.puff(pos + fwd + Vector3(0, 0.3, 0), 1, col.lightened(0.15 * (idx % 3)), 0.12 + idx * 0.012, 0.6, 2.4, 1.3, -0.4, 0.1)
	if p == local_player and hud:
		hud.kalimba_pressed(idx)
	if multiplayer.is_server():
		tally(p.peer_id, "notes")
		if mosslet:
			mosslet.coax(p.peer_id, p.global_position)
		if pos.distance_to(beast.global_head()) < 20.0:
			beast.hear_note(p.peer_id, idx)
			befriend(p.peer_id, 0.12)

# ---------------------------------------------------------------- arrival
func _arrival_spectacle(way: int) -> void:
	var wp := waystones[mini(way, waystones.size() - 1)]
	var col: Color = smoke_color(path[way]) if way < path.size() else G.MARIGOLD
	beast.celebrate()
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		if is_instance_valid(beast):
			Sfx.play("beast_happy", beast.global_head(), 8.0, 0.62))
	# a ring of coloured smoke bursts from the turf, then the column blooms
	for k in 30:
		var a := TAU * k / 30.0
		var gp := wp + Vector3(cos(a) * 12.0, 0, sin(a) * 12.0)
		gp.y = world.terrain.height(gp.x, gp.z) + 0.4
		fx.puff(gp, 2, col if k % 2 == 0 else G.PAPER, 0.9, 3.0, 3.0, 1.8, -0.3, 0.8)
	for k in 6:
		fx.puff(wp + Vector3(0, 12.0 + k * 1.5, 0), 4, [col, G.BUTTER, G.PAPER][k % 3], 1.4, 7.0, 1.2, 2.0, -0.6, 2.2)
	if waystone_node and waystone_node.get_child_count() > 0:
		var stone := waystone_node.get_child(0) as MeshInstance3D
		if stone:
			stone.material_override = Mats.glow(Color.WHITE, 0.45)
		var light := OmniLight3D.new()
		light.light_color = col.lightened(0.3)
		light.omni_range = 30.0
		light.position = Vector3(0, 9.0, 0)
		waystone_node.add_child(light)
		var tw := create_tween()
		tw.tween_property(light, "light_energy", 4.0, 0.4)
		tw.tween_property(light, "light_energy", 1.2, 3.0)

# ---------------------------------------------------------------- gales
const GUST_WARN := 2.0

@rpc("authority", "call_local", "reliable")
func _gust(dir: Vector3) -> void:
	if world == null:
		return
	gust_dir = dir
	gust_at = Time.get_ticks_msec() / 1000.0 + GUST_WARN
	if local_player:
		Sfx.play("gust", local_player.global_position - dir * 10.0 + Vector3(0, 3, 0), 2.0, randf_range(0.92, 1.05))
	get_tree().create_timer(GUST_WARN).timeout.connect(_gust_hit.bind(dir))

func _gust_hit(dir: Vector3) -> void:
	if world == null:
		return
	if local_player:
		Sfx.play("rustle", local_player.global_position + Vector3(0, 2, 0), 6.0, 0.4)
		local_player.on_gust(dir)
		# leaves tearing past
		for k in 24:
			var p := local_player.global_position - dir * 18.0 + Vector3(randf_range(-12, 12), randf_range(0, 7), randf_range(-12, 12))
			fx.streak(p, dir * randf_range(14.0, 22.0) + Vector3(0, randf_range(-1, 2), 0), [G.MOSS, G.MEADOW_DRY, G.BUTTER][k % 3], 0.18, 1.8)
	if multiplayer.is_server():
		for f in fruits.values():
			if f.held_by == 0 and f.global_position.distance_to(beast.body_xf.origin + Vector3(0, 14, 0)) < 18.0:
				if f.pest:
					f.fling(dir * randf_range(5, 8) + Vector3.UP * 3.0)   # the wind helps with mites, at least
				else:
					f.fling(dir * randf_range(2.5, 4.5) + Vector3.UP * 1.5)

func gust_warning() -> float:
	## 0..1 while a gust is incoming or blowing (for the HUD's wind lines)
	var dtg := gust_at - Time.get_ticks_msec() / 1000.0
	if dtg > GUST_WARN or dtg < -1.2:
		return 0.0
	return clampf(1.0 - dtg / GUST_WARN, 0.0, 1.0) if dtg > 0.0 else 1.0

# ---------------------------------------------------------------- magpies
func hat_stolen(peer: int) -> bool:
	return stolen_hats.has(peer)

func _tick_magpies(dt: float) -> void:
	var tr := active_trait()
	if phase == Phase.TRAVEL and (waystone_idx >= 1 or day >= 2) and magpies.size() < (3 if tr == "magpie" else 2) and tr != "meadow":
		_magpie_t -= dt * (2.0 if tr == "magpie" else 1.0)
		if _magpie_t <= 0.0:
			_magpie_t = randf_range(70.0, 130.0)
			for k in (2 if randf() < 0.35 else 1):
				var a := randf() * TAU
				_spawn_magpie.rpc(_next_magpie, beast.ground_pos + Vector3(cos(a) * 80.0, 45.0, sin(a) * 80.0))
				_next_magpie += 1
			_announce.rpc("Magpies! They're after anything shiny. Whistle (Q) to shoo them.")
	for m in magpies.values().duplicate():
		if is_instance_valid(m):
			m.server_tick(dt)
	# a fast-flying plumbob is the other answer to a magpie
	for m in magpies.values():
		if m.state in [Magpie.S.ARRIVE, Magpie.S.SWOOP, Magpie.S.ESCAPE]:
			for f in fruits.values():
				if f.held_by == 0 and f.linear_velocity.length() > 6.0 and f.global_position.distance_to(m.global_position) < 1.6:
					if m.scare():
						_beast_sound.rpc("punt", m.global_position)
						_announce.rpc("Bonk! The magpie dropped its loot.")
						tally(f.last_holder, "shooed")
						jot("bonk", "%s bonked a magpie out of the sky with a %s." % [pname(f.last_holder), "thistlemite" if f.pest else f.kind.trim_prefix("ks_")], 2)
					break
	_magpie_send_t -= dt
	if _magpie_send_t <= 0.0 and not magpies.is_empty():
		_magpie_send_t = 0.1
		var data := PackedFloat32Array()
		for m in magpies.values():
			data.append_array([m.id, m.global_position.x, m.global_position.y, m.global_position.z, m.rotation.y, m.state])
		to_ready(self, "_magpie_states", [data])

@rpc("authority", "call_local", "reliable")
func _spawn_magpie(mid: int, pos: Vector3) -> void:
	_make_magpie(mid, pos)

func _make_magpie(mid: int, pos: Vector3) -> Magpie:
	if world == null or magpies.has(mid):
		return magpies.get(mid)
	var m := Magpie.new()
	m.id = mid
	m.game = self
	props_node.add_child(m)
	m.build()
	m.global_position = pos
	m.set_remote(pos, 0.0, Magpie.S.ARRIVE)
	magpies[mid] = m
	return m

@rpc("authority", "call_remote", "unreliable_ordered")
func _magpie_states(data: PackedFloat32Array) -> void:
	var i := 0
	while i + 5 < data.size():
		var pos := Vector3(data[i + 1], data[i + 2], data[i + 3])
		var m := _make_magpie(int(data[i]), pos)
		if m:
			m.set_remote(pos, data[i + 4], int(data[i + 5]))
		i += 6

func server_magpie_gone(m: Magpie) -> void:
	_magpie_gone.rpc(m.id)

@rpc("authority", "call_local", "reliable")
func _magpie_gone(mid: int) -> void:
	var m: Magpie = magpies.get(mid)
	if m:
		magpies.erase(mid)
		m.queue_free()

func magpie_chatter(pos: Vector3) -> void:
	_magpie_chatter.rpc(pos)

@rpc("authority", "call_local", "unreliable")
func _magpie_chatter(pos: Vector3) -> void:
	Sfx.play("magpie", pos, -2.0, randf_range(0.92, 1.08))

func server_magpie_grab(m: Magpie) -> void:
	if m.target_peer != 0:
		m.loot = {"kind": "hat", "peer": m.target_peer}
		_hat_stolen.rpc(m.target_peer, m.id)
		tally(m.target_peer, "robbed")
		jot("robbed", "A magpie made off with %s's %s." % [pname(m.target_peer), G.HAT_NAMES.get(String(Net.players.get(m.target_peer, {}).get("hat", "hat")), "hat").to_lower()], 3)
	else:
		var f: Fruit = fruits.get(m.target_prop)
		if f == null or f.held_by != 0:
			m.state = Magpie.S.ARRIVE
			m.t = 0.0
			return
		f.held_by = -m.id
		f.freeze = true
		m.loot = {"kind": "prop", "id": f.id}
		_fruit_held.rpc(f.id, -m.id)
		if f.keepsake:
			_announce.rpc("A magpie snatched %s!" % PropsLib.KEEPSAKES[f.kind].name)
			jot("snatched", "A magpie snatched %s." % PropsLib.KEEPSAKES[f.kind].name, 2)
	_pick_nest(m)
	m.state = Magpie.S.ESCAPE
	m.t = 0.0

func _pick_nest(m: Magpie) -> void:
	for radius in [55.0, 90.0, 140.0]:
		var a := randf() * TAU
		var c: Vector3 = beast.ground_pos + Vector3(cos(a), 0, sin(a)) * radius
		var trees: Array = world.terrain.obstacles_near(c, 40.0).filter(func(o: Dictionary) -> bool: return o.has("variant"))
		if not trees.is_empty():
			var tr: Dictionary = trees[randi() % trees.size()]
			m.nest_key = "%d,%d" % [int(tr.pos.x), int(tr.pos.z)]
			m.nest_pos = tr.pos + Vector3(0, (8.2 if tr.variant == 2 else 6.4) * float(tr.scale), 0)
			return
	var a2 := randf() * TAU
	var gp := beast.ground_pos + Vector3(cos(a2) * 70.0, 0, sin(a2) * 70.0)
	gp.y = world.terrain.height(gp.x, gp.z) + 0.2
	m.nest_key = "g%d" % m.id   # no trees anywhere: a nest in the long grass
	m.nest_pos = gp

func server_magpie_nest(m: Magpie) -> void:
	if m.loot.is_empty():
		return
	var n: Dictionary = nests.get(m.nest_key, {"pos": m.nest_pos, "loot": []})
	(n.loot as Array).append(m.loot)
	if m.loot.kind == "prop":
		var f: Fruit = fruits.get(m.loot.id)
		if f:
			f.held_by = NEST_HOLD
			f.global_position = m.nest_pos + Vector3(randf_range(-0.3, 0.3), 0.35, randf_range(-0.3, 0.3))
			_fruit_held.rpc(f.id, NEST_HOLD)
	m.loot = {}
	nests[m.nest_key] = n
	_magpie_drop_visual.rpc(m.id)
	_nest_set.rpc(m.nest_key, n.pos, (n.loot as Array).size())

func server_magpie_drop(m: Magpie) -> void:
	if m.loot.is_empty():
		return
	if m.loot.kind == "hat":
		_hat_returned.rpc(m.loot.peer)
	else:
		var f: Fruit = fruits.get(m.loot.id)
		if f:
			f.held_by = 0
			f.freeze = false
			f.linear_velocity = m.vel * 0.4
			_fruit_held.rpc(f.id, 0)
	m.loot = {}
	_magpie_drop_visual.rpc(m.id)

func _empty_nest(key: String, who := 0) -> void:
	if not multiplayer.is_server() or not nests.has(key):
		return
	if who != 0:
		jot("nest", "%s shook the magpie's hoard out of a tree." % pname(who), 3)
	else:
		jot("nest_beast", "The Mossback barged through the magpie's tree and the whole hoard fell out.")
	var n: Dictionary = nests[key]
	nests.erase(key)
	for l in n.loot:
		if l.kind == "hat":
			_hat_returned.rpc(l.peer)
		else:
			var f: Fruit = fruits.get(l.id)
			if f:
				f.held_by = 0
				f.freeze = false
				f.global_position = n.pos + Vector3(randf_range(-0.5, 0.5), 0.6, randf_range(-0.5, 0.5))
				f.fling(Vector3(randf_range(-2, 2), 2.0, randf_range(-2, 2)))
				_fruit_held.rpc(f.id, 0)
	for m in magpies.values():
		if m.nest_key == key:
			m.flee()
	_nest_set.rpc(key, n.pos, 0)
	_announce.rpc("The magpie's hoard came tumbling down!")

@rpc("any_peer", "call_local", "reliable")
func _request_nest(key: String) -> void:
	if multiplayer.is_server():
		var p := get_player(_sender())
		if p and nests.has(key) and p.global_position.distance_to(nests[key].pos) < 4.0:
			_empty_nest(key, _sender())

@rpc("authority", "call_local", "reliable")
func _hat_stolen(peer: int, mid: int) -> void:
	stolen_hats[peer] = true
	var p := get_player(peer)
	if p == null:
		return
	p.hat_stolen = true
	if p.visual.hat_node:
		p.visual.hat_node.visible = false
	var m: Magpie = magpies.get(mid)
	if m:
		m.show_loot(TenderVisual.hat_for(p.visual.hat, p.visual.color))
	toast.emit("A magpie stole %s's %s!" % [p.display_name, G.HAT_NAMES.get(p.visual.hat, "hat").to_lower()])
	if p == local_player:
		Sfx.play("pickup", p.global_position + Vector3(0, 1.6, 0), 0.0, 1.6)

@rpc("authority", "call_local", "reliable")
func _hat_returned(peer: int) -> void:
	stolen_hats.erase(peer)
	var p := get_player(peer)
	if p == null:
		return
	p.hat_stolen = false
	if p.visual.hat_node:
		p.visual.hat_node.visible = true
	fx.puff(p.global_position + Vector3(0, 1.7, 0), 5, G.PAPER, 0.2, 1.5, 1.0, 0.6, -1.0, 0.2)
	Sfx.play("hat_pop", p.global_position + Vector3(0, 1.6, 0), 2.0)
	toast.emit("%s got their hat back." % p.display_name)

@rpc("authority", "call_local", "reliable")
func _magpie_drop_visual(mid: int) -> void:
	var m: Magpie = magpies.get(mid)
	if m:
		m.clear_loot()

@rpc("authority", "call_local", "reliable")
func _nest_set(key: String, pos: Vector3, count: int) -> void:
	if world == null:
		return
	if count > 0:
		_nest_info[key] = [pos, count]
		if not _nest_nodes.has(key):
			var mi := Mats.mesh_instance(PropsLib.get_mesh("nest"))
			mi.position = pos
			add_child(mi)
			_nest_nodes[key] = mi
	else:
		_nest_info.erase(key)
		if _nest_nodes.has(key):
			_nest_nodes[key].queue_free()
			_nest_nodes.erase(key)

# ---------------------------------------------------------------- field journal
func pname(peer: int) -> String:
	var p := get_player(peer)
	if p:
		return p.display_name
	return String(pstats.get(peer, {}).get("name", "Someone"))

func _count(kind: String) -> int:
	return int(_log_counts.get("%s:%d" % [kind, day], 0))

## Server: write a line in the crew's journal (at most `cap` of a kind per day).
func jot(kind: String, text: String, cap := 1) -> void:
	if not multiplayer.is_server() or text == "":
		return
	var key := "%s:%d" % [kind, day]
	var n: int = _log_counts.get(key, 0)
	if n >= cap:
		return
	_log_counts[key] = n + 1
	_journal_add.rpc(day, text)

@rpc("authority", "call_local", "reliable")
func _journal_add(d: int, text: String) -> void:
	journal.append([d, text])

## Server: per-Tender tallies for the end-of-run commendations.
func tally(peer: int, key: String, amount := 1.0) -> void:
	if not multiplayer.is_server() or peer <= 0:
		return
	if not pstats.has(peer):
		var info: Dictionary = Net.players.get(peer, {})
		pstats[peer] = {"name": info.get("name", "Someone"), "color": int(info.get("color", 0))}
	var d: Dictionary = pstats[peer]
	d[key] = float(d.get(key, 0.0)) + amount
	var kindness: float = {"fed": 4.0, "keepsakes": 6.0, "tossed": 1.5, "shooed": 2.5, "steer": 0.04, "spots": 3.0}.get(key, 0.0)
	if kindness > 0.0:
		befriend(peer, kindness * amount)

## Server: affection for the beast; announces a new favourite.
func befriend(peer: int, amount: float) -> void:
	var nf := beast.befriend(peer, amount)
	if nf != 0:
		_announce.rpc("%s has taken a shine to %s." % [beast.beast_name, pname(nf)])
		jot("favourite", "%s has taken a shine to %s. Nobody else is speaking to %s." % [beast.beast_name, pname(nf), pname(nf)], 2)

var _nuzzle_t := 0.0
func _tick_favourite(dt: float) -> void:
	_nuzzle_t -= dt
	if beast.favourite == 0 or _nuzzle_t > 0.0 or beast.speed > 2.0 or not beast.act in [Beast.Act.IDLE, Beast.Act.WALK]:
		return
	var fav := get_player(beast.favourite)
	if fav == null or not fav.visible:
		return
	var m := beast.mouth_global()
	var gp := fav.global_position
	if Vector2(gp.x - m.x, gp.z - m.z).length() < 7.0 and gp.y < world.terrain.height(gp.x, gp.z) + 2.5:
		_nuzzle_t = 25.0
		_nuzzle_rpc.rpc(fav.peer_id)
		jot("nuzzle", "%s got nuzzled and booped up onto its back." % fav.display_name, 2)

@rpc("authority", "call_local", "reliable")
func _nuzzle_rpc(peer: int) -> void:
	if world == null:
		return
	beast.nuzzle()
	Sfx.play("beast_happy", beast.global_head(), 2.0, 1.15)
	fx.puff(beast.mouth_global(), 6, G.ROSE, 0.3, 2.0, 1.5, 1.0, -1.0, 0.6)
	var fav := get_player(peer)
	if fav:
		toast.emit("%s nuzzled %s." % [beast.beast_name, fav.display_name])
	get_tree().create_timer(1.1).timeout.connect(func() -> void:
		if local_player == null or local_player.peer_id != peer or world == null:
			return
		if local_player.global_position.distance_to(beast.mouth_global()) > 10.0:
			return
		# boop: a ballistic arc that lands on the back, allowing for the walk
		var target := beast.body_xf * (BeastBuild.top_point(randf_range(-1.5, 1.5), -2.5) + Vector3(0, 1.2, 0))
		var tt := 1.3
		target += beast.forward() * beast.speed * tt
		var v := (target - local_player.global_position) / tt + Vector3(0, 0.5 * Player.GRAVITY * tt, 0)
		local_player.flung(local_player.global_position + Vector3(0, 0.3, 0), v))

func _tick_journal(dt: float) -> void:
	_tick_favourite(dt)
	if beast.lure_operator != 0:
		tally(beast.lure_operator, "steer", dt)
	# the river: a refusal, then how it was talked across
	if beast.balk and not _was_balk:
		_balked_at = phase_t
		var near_river := world.terrain.river_dist(beast.ground_pos.x, beast.ground_pos.z) < 70.0
		jot("balk", "%s stopped dead at %s and would not go in." % [beast.beast_name, "the river's edge" if near_river else "the edge of a deep mere"], 2)
	_was_balk = beast.balk
	if phase_t - _balked_at < 120.0 and beast.ground_pos.y < Terrain.WATER_LEVEL - 1.2:
		_balked_at = -1000.0
		if beast.serenade > 0.55:
			jot("ford", "%s sang it across, note by note." % _recent_players(), 2)
		else:
			jot("ford", "Lured across with a snack on the far bank.", 2)
	if beast.serenade > 0.55 and _enchanted_day != day:
		_enchanted_day = day
		jot("enchanted", "%s played until it hummed along." % _recent_players())

func _recent_players() -> String:
	var names: Array = []
	for k in beast._note_peers:
		if beast._time - float(beast._note_peers[k][0]) < 8.0:
			names.append(pname(k))
	if names.is_empty():
		return "The crew"
	if names.size() == 1:
		return names[0]
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + names[-1]

func _send_awards() -> void:
	if beast.favourite != 0:
		tally(beast.favourite, "pet")
	_awards.rpc(pstats)

@rpc("authority", "call_local", "reliable")
func _awards(ps: Dictionary) -> void:
	pstats = ps

@rpc("authority", "call_local", "reliable")
func _reached(id: int) -> void:
	if path.has(id) or wtree.is_empty():
		return
	path.append(id)
	waystones.append(node_pos(id))

# ---------------------------------------------------------------- pings
var pings: Array = []   # [pos, label, peer, time]
var mosslet: Mosslet
var _calf_send_t := 0.0
var _calf_hinted := false

func ping(at: Vector3, label: String) -> void:
	_ping.rpc(at, label.left(24))

@rpc("any_peer", "call_local", "reliable")
func _ping(at: Vector3, label: String) -> void:
	if world == null:
		return
	var peer := _sender()
	var p := get_player(peer)
	if p == null:
		return
	pings = pings.filter(func(e: Array) -> bool: return e[2] != peer)   # one live ping each
	pings.append([at, label, peer, Time.get_ticks_msec() / 1000.0])
	Sfx.play("chirp", at, -4.0, 1.6)
	if not p.is_local:
		p.visual.pointing = 1.2
