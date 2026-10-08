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
var players_node: Node3D
var props_node: Node3D
var players := {}
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
var stats := {"fed": 0, "sneezes": 0, "gulps": 0, "pancakes": 0, "distance": 0.0}
var _last_beast_pos := Vector3.ZERO

func _ready() -> void:
	name = "Game"

func ui_blocking() -> bool:
	return paused_menu or (hud != null and hud.is_blocking())

# ---------------------------------------------------------------- setup
func start_as_server(p_seed: int) -> void:
	_build(p_seed)
	phase = Phase.TRAVEL
	_spawn_start_fruit()
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
	_welcome.rpc_id(id, seed_v, _run_state(), fl, beast.get_snapshot())

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
	var heading := _start_yaw
	var p := start
	waystones.clear()
	for i in WAYSTONES:
		var best := Vector3.ZERO
		var best_score := -INF
		for k in 14:
			var h := heading + rng.randf_range(-0.6, 0.6)
			var dist := rng.randf_range(430.0, 560.0) + i * 40.0
			var c := p + Vector3(-sin(h), 0, -cos(h)) * dist
			var ht := t.height(c.x, c.z)
			var score := -absf(h - heading) - (100.0 if ht < Terrain.WATER_LEVEL + 1.5 else 0.0) + t.normal(c.x, c.z).y * 2.0
			if score > best_score:
				best_score = score
				best = c
		heading = atan2(-(best.x - p.x), -(best.z - p.z))
		t.add_flatten(Vector2(best.x, best.z), 26.0)
		best.y = t.height(best.x, best.z)
		waystones.append(best)
		p = best
	_start_pos.y = t.height(_start_pos.x, _start_pos.z)

func _build_waystone() -> void:
	if waystone_node:
		waystone_node.queue_free()
	waystone_node = Node3D.new()
	add_child(waystone_node)
	if waystone_idx >= waystones.size():
		return
	var wp := waystones[waystone_idx]
	waystone_node.position = Vector3(wp.x, world.terrain.height(wp.x, wp.z) - 0.4, wp.z)
	waystone_node.add_child(Mats.mesh_instance(PropsLib.get_mesh("waystone")))
	var bell := Mats.mesh_instance(PropsLib.get_mesh("bell"))
	bell.position = Vector3(0, 11.8, 0)
	bell.scale = Vector3.ONE * 1.6
	waystone_node.add_child(bell)
	# signal smoke: opaque puffs rising (no transparency - the ink pass reads opaque only)
	var smoke_col: Color = [G.MARIGOLD, G.ROSE, G.SKY, G.MINT][waystone_idx % 4]
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
	waystone_node.add_child(parts)

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
			if p.is_local:
				local_player = p
				respawn_on_beast(p)
				p.cam_yaw = beast.yaw
			else:
				p.global_position = beast.body_xf * Vector3(0, 16, 4)
		else:
			players[id].refresh_look(Net.players[id])
	for id in players.keys():
		if not Net.players.has(id):
			var p: Player = players[id]
			_release_everything_of(id)
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
	sky.apply()
	beast.dark = sky.night_amount() > 0.5
	Sfx.set_ambience(0.55, sky.night_amount())
	Sfx.set_listener_hint(focus)
	_update_grass_pushers()

func _process(dt: float) -> void:
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
	for f in fruits.values():
		food.append(f)
	beast.set_food_list(food)
	stats.distance += beast.ground_pos.distance_to(_last_beast_pos) if _last_beast_pos != Vector3.ZERO else 0.0
	_last_beast_pos = beast.ground_pos
	match phase:
		Phase.TRAVEL:
			time_of_day += dt * (DAY_END - DAY_START) / DAY_SECONDS
			if waystone_idx < waystones.size():
				var wp := waystones[waystone_idx]
				if Vector2(beast.ground_pos.x - wp.x, beast.ground_pos.z - wp.z).length() < ARRIVE_RADIUS:
					_set_phase(Phase.ARRIVED)
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
		if f.global_position.distance_to(mouth) < 2.9 and beast.act != Beast.Act.SIT and beast.satiety < 99.5:
			var holder: int = f.held_by
			beast.feed(f.value)
			stats.fed += 1
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
		_beast_snap.rpc(beast.get_snapshot())
	_fruit_t -= dt
	if _fruit_t <= 0.0:
		_fruit_t = 1.0 / 15.0
		_send_fruit_states()
	_state_t -= dt
	if _state_t <= 0.0:
		_state_t = 0.5
		_run_state_rpc.rpc(_run_state())

func _next_dawn() -> void:
	time_of_day = DAY_START
	_set_phase(Phase.TRAVEL)

func _set_phase(p: int) -> void:
	phase = p
	phase_t = 0.0
	_run_state_rpc.rpc(_run_state())
	_phase_changed.rpc(p, day, waystone_idx)

@rpc("authority", "call_local", "reliable")
func _phase_changed(p: int, p_day: int, p_way: int) -> void:
	phase = p
	day = p_day
	match p:
		Phase.ARRIVED:
			Sfx.play("bell", waystones[mini(p_way, waystones.size() - 1)], 6.0)
			_flash = 0.6
			big_message.emit("Waystone %d reached" % (p_way + 1), "The Mossback hums at the old stones.")
		Phase.NIGHT:
			big_message.emit("Night falls", "The Mossback curls up to sleep. A day is lost.")
		Phase.TRAVEL:
			waystone_idx = p_way
			_build_waystone()
			big_message.emit("Day %d of %d" % [p_day, DAYS], "Follow the %s smoke." % ["marigold", "rose", "blue", "mint"][p_way % 4])
		Phase.WON:
			Sfx.play("bell", beast.global_head(), 6.0)
			_flash = 0.8
			big_message.emit("The migration is complete", "Your Mossback reached the wintering hollow.")
		Phase.LOST:
			big_message.emit("Winter came early", "The Mossback settles in the open.")
	if hud:
		hud.on_phase(p)

func _run_state() -> Dictionary:
	return {"phase": phase, "day": day, "way": waystone_idx, "tod": time_of_day, "station": beast.lure_operator, "stats": stats}

@rpc("authority", "call_remote", "unreliable_ordered")
func _run_state_rpc(s: Dictionary) -> void:
	_apply_run_state(s)

func _apply_run_state(s: Dictionary) -> void:
	var way: int = s.way
	if way != waystone_idx:
		waystone_idx = way
		_build_waystone()
	phase = s.phase
	day = s.day
	if absf(time_of_day - s.tod) > 0.01:
		time_of_day = s.tod
	stats = s.stats

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
			get_tree().create_timer(0.5).timeout.connect(func() -> void: Sfx.play("beast_gulp", pos, 0.0))
			get_tree().create_timer(1.0).timeout.connect(func() -> void: Sfx.play("beast_happy", pos, 0.0))
		"spit": Sfx.play("spit", pos, 3.0)

func _on_beast_step(pos: Vector3, strength: float) -> void:
	Sfx.play("beast_step", pos, -2.0 + strength * 3.0, randf_range(0.9, 1.05))
	if local_player:
		local_player.on_beast_step(pos, strength)

func _on_beast_sneeze(origin: Vector3) -> void:
	Sfx.play("beast_sneeze", origin, 6.0)
	stats.sneezes += 1
	if local_player:
		local_player.on_sneeze(origin, beast.forward())
		toast_local("BLESS YOU")
	if multiplayer.is_server():
		for f in fruits.values():
			if f.held_by == 0 and f.global_position.distance_to(beast.body_xf.origin) < 22.0:
				f.apply_central_impulse((Vector3.UP * 7.0 + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))) * f.mass)

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
	if fruits.has(id):
		return
	var f := Fruit.new()
	f.setup(id, kind, multiplayer.is_server())
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
		_fruit_states.rpc(data)

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
	if p.global_position.distance_to(beast.lure_handle_global()) < 2.6:
		return "E  take the lure" if beast.lure_operator == 0 else "Someone's steering"
	if p.held_fruit != 0 or p.carrying_peer != 0:
		return "Hold RMB to throw   ·   LMB drop"
	var t := _nearest_tree(p.global_position, 3.4)
	if not t.is_empty():
		return "E  shake the tree"
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
			_server_shake_tree(t, 1.0, 1.0)
			return

func _server_shake_tree(t: Dictionary, strength: float, drop_chance: float) -> void:
	var key := "%d,%d" % [int(t.pos.x), int(t.pos.z)]
	var now := Time.get_ticks_msec() / 1000.0
	if _shaken.has(key) and now - _shaken[key] < 2.5:
		return
	_shaken[key] = now
	_tree_shaken.rpc(t.pos, strength)
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
	for t in world.terrain.obstacles_near(pos, 0.5):
		if t.has("variant"):
			world.shake_tree(t, strength)
			Sfx.play("rustle", pos + Vector3(0, 4, 0), -2.0)
			return

@rpc("any_peer", "call_local", "reliable")
func _request_grab_fruit(id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := _sender()
	var f: Fruit = fruits.get(id)
	var p := get_player(sender)
	if f and p and f.held_by == 0 and f.global_position.distance_to(p.global_position) < 4.0:
		f.held_by = sender
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

@rpc("any_peer", "call_local", "reliable")
func _whistle(peer: int, pos: Vector3, on_beast: bool) -> void:
	var p := get_player(peer)
	var pitch := 1.0 + ((p.color_idx if p else 0) % 4) * 0.09
	Sfx.play("whistle", pos + Vector3(0, 1.2, 0), 0.0, pitch)
	if multiplayer.is_server() and not on_beast:
		beast.whistle(pos)

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
