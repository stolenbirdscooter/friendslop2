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
	Net.start_solo()
	_start_server_game()

func host_game() -> void:
	var err := Net.host()
	if err != OK:
		menu.show_error("Couldn't open port %d (%s)." % [Net.PORT, error_string(err)])
		return
	_start_server_game()

func join_game(ip: String) -> void:
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
