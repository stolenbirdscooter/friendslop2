extends Node
## Top-level flow: title menu <-> a migration. Dev flags (after `--`):
##   --autostart=solo|host|join  --ip=1.2.3.4  --shot=out.png  --seed=N  --frames=N

var menu: Menu
var game: Game

func _ready() -> void:
	Net.joined_ok.connect(_on_joined)
	Net.join_failed.connect(func(reason: String) -> void:
		print("JOIN FAILED: ", reason)
		if menu:
			menu.show_error(reason))
	Net.session_ended.connect(func(reason: String) -> void:
		print("SESSION ENDED: ", reason)
		leave_to_menu()
		_show_error_later.call_deferred(reason))
	var auto := Args.arg("autostart")
	if auto == "":
		show_menu()
	else:
		G.player_name = Args.arg("name", G.player_name)
		match auto:
			"solo":
				Net.start_solo()
				_start_server_game()
			"host":
				Net.host()
				_start_server_game()
			"join":
				Net.join(Args.arg("ip", "127.0.0.1"))
	if Args.arg("cam") != "":
		_dev_cam.call_deferred(Args.arg("cam"))
	Args.maybe_capture(get_tree())
	if Args.arg("bot") != "":
		var bot: Node = load("res://src/dev/bot.gd").new()
		bot.scenario = Args.arg("bot")
		add_child(bot)
		await get_tree().process_frame
		bot.game = game

func _show_error_later(reason: String) -> void:
	await get_tree().process_frame
	if menu:
		menu.show_error(reason)

func show_menu() -> void:
	if game:
		game.queue_free()
		game = null
	menu = Menu.new()
	menu.main = self
	add_child(menu)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _clear_menu() -> void:
	if menu:
		menu.queue_free()
		menu = null

func play_solo() -> void:
	G.save_prefs()
	Net.start_solo()
	_start_server_game()

func host_game() -> void:
	G.save_prefs()
	var err := Net.host()
	if err != OK:
		menu.show_error("Couldn't open port %d (%s)." % [Net.PORT, error_string(err)])
		return
	_start_server_game()

func join_game(ip: String) -> void:
	G.save_prefs()
	var err := Net.join(ip)
	if err != OK:
		menu.show_error("Couldn't start connecting (%s)." % error_string(err))
		return
	menu.show_status("Walking over to %s..." % ip)
	get_tree().create_timer(10.0).timeout.connect(func() -> void:
		if game == null and menu and not Net.players.has(Net.my_id()):
			Net.leave()
			menu.show_error("No answer from %s." % ip))

func _on_joined() -> void:
	if game != null:
		return
	_clear_menu()
	game = Game.new()
	game.main = self
	add_child(game)
	game.start_as_client()

func _start_server_game() -> void:
	_clear_menu()
	game = Game.new()
	game.main = self
	add_child(game)
	var s := int(Args.arg("seed", str(randi() % 1000000)))
	game.start_as_server(s)

func restart_game(new_seed: int) -> void:
	_do_restart.call_deferred(new_seed)

func _do_restart(new_seed: int) -> void:
	if game:
		game.free()
	game = Game.new()
	game.main = self
	add_child(game)
	if multiplayer.is_server():
		game.start_as_server(new_seed)
	else:
		game.start_as_client()

func leave_to_menu() -> void:
	Net.leave()
	_leave_deferred.call_deferred()

func _leave_deferred() -> void:
	if game:
		game.free()
		game = null
	if menu == null:
		show_menu()

## Dev: frame a screenshot. presets: back, side, front, far, player
func _dev_cam(preset: String) -> void:
	for i in 5:
		await get_tree().process_frame
	if game == null or game.local_player == null:
		return
	var p := game.local_player
	var b := game.beast
	match preset:
		"side":
			p.cam_yaw = b.yaw + PI * 0.5
			p.cam_pitch = -0.12
			p.cam_dist = 10.0
			p.spring.collision_mask = 0
			p.spring.spring_length = 38.0
			p.cam_dist = 38.0
		"front":
			p.cam_yaw = b.yaw + PI * 0.85
			p.cam_pitch = -0.05
			p.spring.collision_mask = 0
			p.cam_dist = 46.0
		"far":
			p.cam_yaw = b.yaw + PI * 0.65
			p.cam_pitch = -0.18
			p.spring.collision_mask = 0
			p.cam_dist = 80.0
		"flinger":
			b.fl_yaw = 0.35
			p.global_position = b.flinger_stand_global() + Vector3(0, 0.5, 0)
			p.cam_yaw = b.yaw - 1.0
			p.cam_pitch = -0.32
			p.spring.collision_mask = 0
			p.cam_dist = 9.0
			for f in game.fruits.values():
				if not f.pest:
					f.global_position = b.flinger_xf() * (PropsLib.FL_BOWL + Vector3(0, 0.6, 0))
					break
		"river":
			var rv: Dictionary = game.world.terrain._rivers[0]
			var across := Vector2(cos(float(rv.mid)), sin(float(rv.mid)))
			var st: Vector2 = (rv.c as Vector2) + across * (game.world.terrain.river_radius(rv, 0.0) - 32.0)
			b.ground_pos = Vector3(st.x, game.world.terrain.height(st.x, st.y), st.y)
			b.yaw = atan2(-across.x, -across.y)
			b.setup_snap()
			game.respawn_on_beast(p)
			p.cam_yaw = b.yaw + PI * 0.75
			p.cam_pitch = -0.2
			p.spring.collision_mask = 0
			p.cam_dist = 55.0
		"snow", "leaves":
			# jump to the right ring of the route and look along the ground
			var edges: PackedFloat32Array = game.world.terrain._radial_edges
			var r: float = edges[3] + 30.0 if preset == "snow" else lerpf(edges[2], edges[3], 0.4)
			var c: Vector2 = game.world.terrain._radial_center
			var dir := Vector2(game.node_pos(0).x - c.x, game.node_pos(0).z - c.y).normalized()
			var q := c + dir * r
			b.ground_pos = Vector3(q.x, game.world.terrain.height(q.x, q.y), q.y)
			b.setup_snap()
			game.respawn_on_beast(p)
			p.cam_yaw = b.yaw + PI * 0.7
			p.cam_pitch = -0.08
			p.spring.collision_mask = 0
			p.cam_dist = 12.0
			if preset == "snow":
				game.time_of_day = 0.6
		"dusk":
			game.time_of_day = Game.DAY_END - 0.02
			p.cam_yaw = b.yaw + PI * 0.6
			p.cam_pitch = -0.05
			p.spring.collision_mask = 0
			p.cam_dist = 14.0
		"calf":
			var cp := b.body_xf * Vector3(-13.5, 0, 3.0)
			cp.y = game.world.terrain.height(cp.x, cp.z)
			game._spawn_calf.rpc(cp)
			game.mosslet.state = Mosslet.S.JOINED
			game.mosslet._side = -1.0
			game.mosslet.rotation.y = b.yaw
			# stand on the grass a little way off and look back at the pair
			var stand := b.body_xf * Vector3(-22.0, 0, -3.0)
			p.global_position = Vector3(stand.x, game.world.terrain.height(stand.x, stand.z) + 0.5, stand.z)
			var look := b.body_xf * Vector3(-10.0, 0, 4.0) - p.global_position
			p.cam_yaw = atan2(-look.x, -look.z)
			p.cam_pitch = 0.12
			p.spring.collision_mask = 0
			p.cam_dist = 7.0
			var tm := Timer.new()
			tm.wait_time = 0.5
			tm.autostart = true
			add_child(tm)
			tm.timeout.connect(func() -> void:
				game._ping.rpc(game.mosslet.global_position + Vector3(0, 3.5, 0), "the mosslet!")
				pass)
		"hut":
			p.global_position = b.body_xf * (b._hut_pos + Vector3(0.8, 0.4, -0.6))
			p.cam_yaw = b.yaw + PI + 0.25
			p.cam_pitch = -0.1
			p.cam_dist = 2.4
			for k in ["ks_teacup", "ks_crown", "ks_shell", "ks_lampshade", "ks_acorn", "ks_feather"]:
				b.add_to_shelf(k)
		"player":
			p.cam_yaw = b.yaw + PI * 0.9
			p.cam_pitch = -0.25
			p.cam_dist = 3.2
		_:
			p.cam_yaw = b.yaw
			p.cam_pitch = -0.3
			p.cam_dist = 6.0
	p.spring.spring_length = p.cam_dist
	if Args.arg("walk") != "":
		b.lure_down = 1.0
