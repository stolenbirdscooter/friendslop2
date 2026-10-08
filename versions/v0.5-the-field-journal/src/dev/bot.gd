extends Node
## Scripted input driver for headless regression tests: --bot=steer|feed|hop
## Presses real input actions so the Player code path is exercised end to end.

var game: Game
var scenario := "steer"
var t := 0.0
var step := 0
var step_t := 0.0
var _log_t := 0.0
var _start_beast := Vector3.ZERO
var _held: Array[String] = []

func _press(a: String) -> void:
	var ev := InputEventAction.new()
	ev.action = a
	ev.pressed = true
	Input.parse_input_event(ev)
	if a not in _held:
		_held.append(a)

func _release(a: String) -> void:
	var ev := InputEventAction.new()
	ev.action = a
	ev.pressed = false
	Input.parse_input_event(ev)
	_held.erase(a)

func _tap(a: String) -> void:
	_press(a)
	get_tree().create_timer(0.1).timeout.connect(_release.bind(a))

func _release_all() -> void:
	for a in _held.duplicate():
		_release(a)

func _next() -> void:
	_release_all()
	step += 1
	step_t = 0.0

func _face(p: Player, target: Vector3) -> float:
	var to := target - p.global_position
	p.cam_yaw = atan2(-to.x, -to.z)
	return Vector2(to.x, to.z).length()

func _physics_process(dt: float) -> void:
	if game == null or not is_instance_valid(game):
		game = get_parent().get("game")
	if game == null or game.local_player == null:
		return
	var p := game.local_player
	var b := game.beast
	t += dt
	step_t += dt
	_log_t -= dt
	if _log_t <= 0.0:
		_log_t = 1.0
		print("BOT t=%.0f step=%d st=%d onb=%s beast_ok=%s pos=%s bpos=%s spd=%.2f yaw=%.2f lure=%.2f/%.2f sat=%.1f act=%d balk=%s" % [
			t, step, p.state, p.on_beast, p.global_position.y > b.ground_pos.y + 8.0, p.global_position.snapped(Vector3.ONE * 0.1),
			b.ground_pos.snapped(Vector3.ONE * 0.1), b.speed, b.yaw, b.lure_yaw, b.lure_down, b.satiety, b.act, b.balk])
	match scenario:
		"steer":
			_steer(p, b)
		"hop":
			_hop(p, b)
		"chaos":
			_chaos(p, b)
		"release":
			_release_test(p, b)
		"pests":
			_pests(p, b)
		"spy":
			_spy(p, b)
		"fling":
			_fling(p, b)
		"keepsake":
			_keepsake(p, b)
		"serenade":
			_serenade(p, b)
		"journal":
			_journal(p, b)
		"postcard":
			if step == 0 and step_t > 4.0:
				game.hud._take_postcard()
				_next()
			elif step == 1 and step_t > 3.0:
				var files := DirAccess.get_files_at("user://postcards")
				print("BOT RESULT postcard: files=%d last=%s" % [files.size(), files[-1] if files.size() > 0 else ""])
				if files.size() > 0 and Args.arg("shotpath") != "":
					DirAccess.copy_absolute(ProjectSettings.globalize_path("user://postcards/" + files[-1]), Args.arg("shotpath"))
				get_tree().quit()
		"ford":
			_ford(p, b)
		"magpie":
			_magpie(p, b)
		"gale":
			_gale(p, b)
		"watch":
			if step_t > 1.0:
				step_t = 0.0
				var others := []
				for o in game.players.values():
					if o != p:
						others.append("%s@%s st=%s" % [o.display_name, o.global_position.snapped(Vector3.ONE * 0.1), o.visual.at_station])
				print("WATCH t=%.0f players=%d beast=%s spd=%.2f lure=%.2f fruits=%d me=%s onb=%s others=%s" % [t, game.players.size(), b.ground_pos.snapped(Vector3.ONE * 0.1), b.speed, b.lure_down, game.fruits.size(), p.global_position.snapped(Vector3.ONE * 0.1), p.on_beast, others])
			if t > 26.0:
				get_tree().quit()

func _steer(p: Player, b: Beast) -> void:
	match step:
		0:
			if step_t > 1.0:
				_start_beast = b.ground_pos
				_next()
		1:
			var d := _face(p, b.lure_stand_global())
			if d > 1.2:
				_press("move_forward")
			else:
				_next()
			if step_t > 12.0:
				print("BOT FAIL could not reach lure, d=", d)
				_next()
		2:
			_tap("interact")
			_next()
		3:
			if step_t > 0.5 and not "move_forward" in _held:
				print("BOT station state=", p.state, " operator=", b.lure_operator)
				_press("move_forward")
			if step_t > 2.5:
				_next()
		4:
			_press("move_left")
			if step_t > 1.5:
				_next()
		5:
			if step_t > 20.0:
				print("BOT RESULT beast moved %.1f m, player on beast=%s, yaw=%.2f" % [b.ground_pos.distance_to(_start_beast), p.global_position.y > b.ground_pos.y + 8.0, b.yaw])
				_next()
		6:
			_tap("interact")
			_next()
		7:
			var lp := b.body_xf.affine_inverse() * p.global_position
			print("REL t=%.2f st=%d floor=%s onb=%s local=%s top=%.2f vel=%s pitch=%.2f" % [step_t, p.state, p.is_on_floor(), p.on_beast, lp.snapped(Vector3.ONE * 0.01), BeastBuild.back_height(lp.x, lp.z), p.velocity.snapped(Vector3.ONE * 0.01), b._pitch])
			if step_t > 1.0:
				print("BOT released station state=", p.state, " operator=", b.lure_operator)
				_next()
		8:
			if step_t > 6.0:
				print("BOT RESULT after release: player on beast=%s speed=%.2f" % [p.global_position.y > b.ground_pos.y + 8.0, b.speed])
				get_tree().quit()

func _hop(p: Player, b: Beast) -> void:
	match step:
		0:
			if step_t > 1.0:
				_next()
		1:
			# run off the side of the beast
			var side := b.body_xf.basis.x
			_face(p, p.global_position + side * 10.0)
			_press("move_forward")
			_press("sprint")
			if p.global_position.y < b.ground_pos.y + 3.0 or step_t > 10.0:
				print("BOT landed on ground, state=", p.state, " pos=", p.global_position)
				_next()
		2:
			if step_t > 3.0:
				_tap("whistle")
				_next()
		3:
			if step_t > 6.0:
				print("BOT RESULT whistle: beast speed=%.2f act=%d dist=%.1f" % [b.speed, b.act, b.ground_pos.distance_to(p.global_position)])
				get_tree().quit()

var _sat0 := 0.0
var _wp := 0
func _chaos(p: Player, b: Beast) -> void:
	match step:
		0:
			if step_t > 1.0:
				_sat0 = b.satiety
				game.server_spawn_fruit("plumbob", b.mouth_global() + b.forward() * 0.5, Vector3.ZERO)
				_next()
		1:
			if step_t > 2.5:
				print("BOT RESULT feed: satiety %.1f -> %.1f act=%d fruits=%d" % [_sat0, b.satiety, b.act, game.fruits.size()])
				b.lure_down = 1.0
				b.pollen = 0.99
				_next()
		2:
			if p.state == Player.St.TUMBLE:
				print("BOT RESULT sneeze: player tumbling vel=", p.velocity.snapped(Vector3.ONE * 0.1), " act=", b.act)
				_next()
			elif step_t > 12.0:
				print("BOT FAIL no sneeze tumble; act=", b.act, " pollen=", b.pollen)
				_next()
		3:
			if step_t > 5.0:
				print("BOT after sneeze: state=%d pos=%s on_beast=%s" % [p.state, p.global_position.snapped(Vector3.ONE * 0.1), p.on_beast])
				# put the Tender in front of the mouth with a snack
				p.state = Player.St.NORMAL
				p.global_position = b.mouth_global() + b.forward() * 1.0
				var id := game.next_fruit_id
				game.server_spawn_fruit("plumbob", p.hand_point(), Vector3.ZERO)
				game.fruits[id].held_by = p.peer_id
				p.held_fruit = id
				_next()
		4:
			if p.state == Player.St.GULPED and step_t < 10.0:
				pass
			if step_t > 4.0:
				print("BOT RESULT gulp: state=%d (GULPED=3, TUMBLE=1) visible=%s gulps=%d" % [p.state, p.visible, game.stats.gulps])
				get_tree().quit()

func _release_test(p: Player, b: Beast) -> void:
	match step:
		0:
			if step_t > 1.0:
				p.global_position = b.lure_stand_global() + Vector3(0, 0.3, 0)
				_tap("interact")
				_next()
		1:
			if step_t > 0.3:
				b.lure_down = 1.0
				_press("move_forward")
			if step_t > 3.0:
				_next()
				_tap("interact")
		2:
			var lp := b.body_xf.affine_inverse() * p.global_position
			var top := BeastBuild.back_height(lp.x, lp.z)
			print("REL t=%.2f st=%d floor=%s onb=%s local=%s top=%.2f vel=%s" % [step_t, p.state, p.is_on_floor(), p.on_beast, lp.snapped(Vector3.ONE * 0.01), top, p.velocity.snapped(Vector3.ONE * 0.01)])
			if step_t > 1.5:
				get_tree().quit()

func _pests(p: Player, b: Beast) -> void:
	var aboard := 0
	var total := 0
	for f in game.fruits.values():
		if f.pest:
			total += 1
			if f.on_beast:
				aboard += 1
	match step:
		0:
			if step_t > 1.0:
				for k in 6:
					var a := TAU * k / 6.0
					game.server_spawn_fruit("mite", b.body_xf * (BeastBuild.top_point(cos(a) * 4.0, sin(a) * 6.0) + Vector3(0, 0.5, 0)), Vector3.ZERO)
				_next()
		1:
			if fmod(step_t, 1.0) < 0.02:
				print("PEST t=%.0f mites=%d aboard=%d itch=%.1f act=%d" % [step_t, total, aboard, b.itch, b.act])
			if b.act == Beast.Act.SHAKE:
				print("PEST shake started at t=%.1f" % step_t)
				_next()
			elif step_t > 30.0:
				print("BOT FAIL no shake")
				get_tree().quit()
		2:
			if step_t > 0.6 and step_t < 0.65:
				print("PEST player state during shake=%d (TUMBLE=1) vel=%s" % [p.state, p.velocity.snapped(Vector3.ONE * 0.1)])
			if step_t > 5.0:
				print("BOT RESULT pests: after shake mites=%d aboard=%d itch=%.1f player_state=%d shakes=%d" % [total, aboard, b.itch, p.state, game.stats.shakes])
				get_tree().quit()

func _spy(p: Player, b: Beast) -> void:
	match step:
		0:
			if step_t > 1.0:
				game.weather = "mist"
				var wp: Array = [BeastBuild.RAMP_FROM + Vector3(0, 0, -1.5), BeastBuild.RAMP_FROM, BeastBuild.RAMP_TO, Vector3(1.2, 3.3, 1.2), BeastBuild.SPYGLASS + Vector3(0.0, -0.55, 0.7)]
				var target: Vector3 = b.body_xf * (b._hut_pos + wp[mini(_wp, 4)])
				var d := _face(p, target)
				_press("move_forward")
				if d < 0.9:
					print("SPY waypoint %d reached, y=%.2f local=%s" % [_wp, p.global_position.y, (b.body_xf.affine_inverse() * p.global_position).snapped(Vector3.ONE * 0.1)])
					_wp += 1
				if fmod(step_t, 1.0) < 0.02 and _wp >= 2:
					print("SPY trace wp=%d hutlocal=%s floor=%s vel=%s" % [_wp, (b.body_xf.affine_inverse() * p.global_position - b._hut_pos).snapped(Vector3.ONE * 0.01), p.is_on_floor(), p.velocity.snapped(Vector3.ONE * 0.1)])
				if _wp > 4 or step_t > 25.0:
					print("SPY at spyglass? dist=%.2f" % p.global_position.distance_to(b.spyglass_global()))
					_next()
		1:
			_tap("interact")
			_next()
		2:
			if step_t > 0.5:
				var w := game.current_waystone() + Vector3(0, 40, 0)
				var to := w - p.camera.global_position
				p.cam_yaw = atan2(-to.x, -to.z)
				p.cam_pitch = atan2(to.y, Vector2(to.x, to.z).length())
			if step_t > 3.0:
				print("BOT RESULT spy: state=%d marker_visible=%s hold=%.2f fov=%.1f" % [p.state, game.marker_visible(), p.spy_hold, p.camera.fov])
				get_tree().quit()

var _fruit_id := 0
var _fl_start := Vector3.ZERO
func _fling(p: Player, b: Beast) -> void:
	match step:
		0:
			if step_t > 1.5:
				p.global_position = b.flinger_stand_global() + Vector3(0, 0.3, 0)
				_next()
		1:
			if step_t > 0.5:
				_tap("interact")
				_next()
		2:
			if step_t > 0.5:
				print("FLING operator state=%d (FLING=6) fl_op=%d" % [p.state, b.fl_operator])
				for f in game.fruits.values():
					if not f.pest and not f.keepsake:
						_fruit_id = f.id
						f.global_position = b.flinger_xf() * (PropsLib.FL_BOWL + Vector3(0, 0.8, 0))
						f.linear_velocity = Vector3.ZERO
						break
				_next()
		3:
			if step_t > 1.5:
				var f: Fruit = game.fruits.get(_fruit_id)
				print("FLING fruit in bowl=%s" % (f != null and b.in_bowl(f.global_position)))
				_press("grab")
				_next()
		4:
			_press("grab")
			if step_t > 1.0:
				_release("grab")
				_fl_start = game.fruits[_fruit_id].global_position if game.fruits.has(_fruit_id) else Vector3.ZERO
				_next()
		5:
			if step_t > 3.5:
				var f: Fruit = game.fruits.get(_fruit_id)
				var d := f.global_position.distance_to(_fl_start) if f else -1.0
				print("FLING fruit travelled %.1f m, beast dist %.1f, arm=%.2f" % [d, f.global_position.distance_to(b.ground_pos) if f else -1.0, b.fl_arm.rotation.x])
				_tap("interact")
				_next()
		6:
			if step_t > 0.5:
				# now launch ourselves: stand in the bowl, operate remotely as the server
				p.global_position = b.flinger_xf() * (PropsLib.FL_BOWL + Vector3(0, 0.5, 0))
				_next()
		7:
			if step_t > 1.0:
				print("FLING self in bowl=%s state=%d" % [b.in_bowl(p.global_position), p.state])
				b.fl_operator = 1
				game._last_fling = -100.0
				_fl_start = p.global_position
				game._request_fling(0.7)
				_next()
		8:
			if step_t > 0.3 and step_t < 0.33:
				print("FLING self state=%d vel=%s" % [p.state, p.velocity.snapped(Vector3.ONE * 0.1)])
			if step_t > 4.0:
				print("BOT RESULT fling: player travelled %.1f m, state=%d, flings=%d" % [Vector2(p.global_position.x - _fl_start.x, p.global_position.z - _fl_start.z).length(), p.state, game.stats.flings])
				get_tree().quit()

func _keepsake(p: Player, b: Beast) -> void:
	match step:
		0:
			if step_t > 1.5:
				var best: Fruit = null
				for f in game.fruits.values():
					if f.keepsake:
						best = f
						break
				if best == null:
					print("BOT FAIL no keepsake spawned")
					get_tree().quit()
					return
				_fruit_id = best.id
				print("KEEP found %s at %s, %.0f m from beast, frozen=%s" % [best.kind, best.global_position.snapped(Vector3.ONE * 0.1), best.global_position.distance_to(b.ground_pos), best.freeze])
				p.global_position = best.global_position + Vector3(1.0, 1.0, 0)
				_next()
		1:
			var f: Fruit = game.fruits.get(_fruit_id)
			_face(p, f.global_position)
			if step_t > 2.5:
				print("KEEP after settle pos=%s frozen=%s collision=%s" % [f.global_position.snapped(Vector3.ONE * 0.1), f.freeze, game.world.has_collision_at(f.global_position)])
				_tap("grab")
				_next()
		2:
			if step_t > 0.8:
				print("KEEP held=%d" % p.held_fruit)
				p.global_position = b.body_xf * (b._hut_pos + Vector3(0, 0.5, 0))
				_next()
		3:
			if step_t > 1.0:
				print("BOT RESULT keepsake: shelf=%s unlocked=%s held=%d keepsakes=%d" % [b.shelf, G.unlocked_hats, p.held_fruit, game.stats.keepsakes])
				_hat_before = G.player_hat
				_tap("interact")
				_next()
		4:
			if step_t > 0.5:
				print("KEEP hat %s -> %s, visual hat=%s" % [_hat_before, G.player_hat, p.visual.hat])
				get_tree().quit()

var _hat_before := ""
var _melody := [0, 2, 4, 5, 4, 2, 0, 7, 6, 4]
func _serenade(p: Player, b: Beast) -> void:
	match step:
		0:
			if step_t > 1.0:
				print("SERENADE dist to head %.1f" % p.global_position.distance_to(b.global_head()))
				_next()
		1:
			if fmod(step_t, 0.32) < 0.02:
				_tap("note_%d" % (_melody[int(step_t / 0.32) % _melody.size()] + 1))
			if fmod(step_t, 2.0) < 0.02:
				print("SERENADE t=%.0f serenade=%.2f joy=%.2f" % [step_t, b.serenade, b.joy])
			if step_t > 14.0:
				print("BOT RESULT serenade: serenade=%.2f joy=%.2f scale=%s" % [b.serenade, b.joy, Music.player_scale()])
				get_tree().quit()

func _ford(p: Player, b: Beast) -> void:
	match step:
		0:
			if step_t > 1.0:
				# put the beast 40 m short of the river, facing it
				var rv: Array = game.world.terrain._rivers[0]
				var pts: PackedVector2Array = rv[0]
				var mid := pts[7]
				var dir2 := (pts[8] - pts[6]).normalized()
				var across := Vector2(-dir2.y, dir2.x)
				var start := mid - across * 45.0
				b.ground_pos = Vector3(start.x, game.world.terrain.height(start.x, start.y), start.y)
				b.yaw = atan2(-across.x, -across.y)
				b.setup_snap()
				game.respawn_on_beast(p)
				b.lure_operator = 1
				b.lure_down = 1.0
				b.lure_yaw = 0.0
				b.satiety = 90.0
				print("FORD river dist at start %.1f" % game.world.terrain.river_dist(b.ground_pos.x, b.ground_pos.z))
				_next()
		1:
			b.lure_down = 1.0
			b.lure_yaw = 0.0
			if fmod(step_t, 2.0) < 0.02:
				print("FORD t=%.0f balk=%s spd=%.2f river_dist=%.1f" % [step_t, b.balk, b.speed, game.world.terrain.river_dist(b.ground_pos.x, b.ground_pos.z)])
			if step_t > 18.0:
				print("FORD balked=%s before music" % b.balk)
				_next()
		2:
			b.lure_down = 1.0
			if fmod(step_t, 0.3) < 0.02:
				_tap("note_%d" % ([0, 2, 4, 6, 5, 3][int(step_t / 0.3) % 6] + 1))
			if fmod(step_t, 2.0) < 0.02:
				print("FORD music t=%.0f serenade=%.2f balk=%s spd=%.2f river_dist=%.1f" % [step_t, b.serenade, b.balk, b.speed, game.world.terrain.river_dist(b.ground_pos.x, b.ground_pos.z)])
			if step_t > 30.0:
				print("BOT RESULT ford: crossed=%s river_dist=%.1f" % [game.world.terrain.river_dist(b.ground_pos.x, b.ground_pos.z) > 25.0, game.world.terrain.river_dist(b.ground_pos.x, b.ground_pos.z)])
				get_tree().quit()

func _magpie(p: Player, b: Beast) -> void:
	match step:
		0:
			if step_t > 1.0:
				game._spawn_magpie.rpc(game._next_magpie, b.body_xf * Vector3(0, 30, 0))
				game._next_magpie += 1
				print("MAGPIE spawned, my hat=%s" % Net.players[p.peer_id].get("hat", "?"))
				_next()
		1:
			if fmod(step_t, 1.0) < 0.02:
				var m: Magpie = game.magpies.values()[0] if not game.magpies.is_empty() else null
				print("MAGPIE t=%.0f state=%d dist=%.1f stolen=%s" % [step_t, m.state if m else -1, m.global_position.distance_to(p.global_position) if m else -1.0, game.hat_stolen(p.peer_id)])
			if game.hat_stolen(p.peer_id) or not game.magpies.is_empty() and game.magpies.values()[0].state == Magpie.S.ESCAPE:
				print("MAGPIE grabbed something: hat_stolen=%s" % game.hat_stolen(p.peer_id))
				_next()
			elif step_t > 40.0:
				print("BOT FAIL magpie never grabbed")
				get_tree().quit()
		2:
			if step_t > 6.0:
				var m: Magpie = game.magpies.values()[0] if not game.magpies.is_empty() else null
				print("MAGPIE escaping state=%d nest=%s" % [m.state if m else -1, m.nest_key if m else ""])
				# let it reach the nest
				_next()
		3:
			var m: Magpie = game.magpies.values()[0] if not game.magpies.is_empty() else null
			if m == null or m.state == Magpie.S.PERCH or step_t > 40.0:
				print("MAGPIE nests=%s" % [game._nest_info])
				_next()
		4:
			if game._nest_info.is_empty():
				print("BOT FAIL no nest")
				get_tree().quit()
				return
			var key: String = game._nest_info.keys()[0]
			if key.begins_with("g"):
				game._request_nest(key)
			else:
				var parts := key.split(",")
				for t2 in game.world.terrain.obstacles_near(Vector3(float(parts[0]), 0, float(parts[1])), 2.0):
					if t2.has("variant"):
						game._server_shake_tree(t2, 1.0, 1.0)
						break
			_next()
		5:
			if step_t > 1.0:
				print("MAGPIE round 1: nests=%d" % game._nest_info.size())
				# round 2: nothing else shiny aboard, so it must go for the hat
				for f in game.fruits.values():
					if not f.pest and f.global_position.distance_to(b.body_xf * Vector3(0, 16, 0)) < 20.0:
						game.despawn_prop(f.id)
				game.respawn_on_beast(p)
				game._spawn_magpie.rpc(game._next_magpie, b.body_xf * Vector3(0, 30, 0))
				game._next_magpie += 1
				_next()
		6:
			if game.hat_stolen(p.peer_id):
				print("MAGPIE hat stolen at t=%.1f, visual hidden=%s" % [step_t, not p.visual.hat_node.visible])
				_next()
			elif step_t > 40.0:
				print("BOT FAIL hat never stolen")
				get_tree().quit()
		7:
			if step_t > 1.5:
				# whistle at it while it's still close
				var m: Magpie = game.magpies.values()[-1]
				print("MAGPIE whistling, dist=%.1f" % m.global_position.distance_to(p.global_position))
				game._whistle(p.peer_id, m.global_position, true)
				_next()
		8:
			if step_t > 1.0:
				print("BOT RESULT magpie: hat_stolen_after_whistle=%s visual_hat_visible=%s" % [game.hat_stolen(p.peer_id), p.visual.hat_node.visible if p.visual.hat_node else false])
				get_tree().quit()

func _gale(p: Player, b: Beast) -> void:
	match step:
		0:
			if step_t > 1.5:
				game.weather = "gale"
				game._gust.rpc(b.body_xf.basis.x)
				_next()
		1:
			if step_t > 2.3:
				print("GALE after gust: state=%d (TUMBLE=1) vel=%s" % [p.state, p.velocity.snapped(Vector3.ONE * 0.1)])
				_next()
		2:
			if step_t > 4.0 and p.state == Player.St.NORMAL:
				game.respawn_on_beast(p)
				_press("flop")
				_next()
		3:
			_press("flop")
			if step_t > 0.4 and step_t < 0.45:
				game._gust.rpc(b.body_xf.basis.x)
			if step_t > 2.8:
				print("BOT RESULT gale: flopping held on: on_beast=%s vel=%.1f" % [p.on_beast or p.beast_frame, p.velocity.length()])
				get_tree().quit()

func _journal(p: Player, b: Beast) -> void:
	match step:
		0:
			if fmod(step_t, 0.3) < 0.02:
				_tap("note_%d" % ([0, 2, 4, 6, 5, 3, 1][int(step_t / 0.3) % 7] + 1))
			if step_t > 9.0:
				_next()
		1:
			# a plumbob through the flinger, operated by us
			for f in game.fruits.values():
				if not f.pest and not f.keepsake:
					f.global_position = b.flinger_xf() * (PropsLib.FL_BOWL + Vector3(0, 0.8, 0))
					break
			_next()
		2:
			if step_t > 1.5:
				b.fl_operator = 1
				game._request_fling(0.8)
				# a few things the solo bot can't stage for real
				game.tally(1, "robbed")
				game.jot("robbed", "A magpie made off with %s's bobble beanie." % p.display_name, 3)
				game.tally(1, "shooed")
				game.jot("shoo", "%s whistled a magpie into dropping its loot." % p.display_name, 2)
				game.jot("balk", "%s stopped dead at the river's edge and would not go in." % b.beast_name, 2)
				game.jot("ford", "%s sang it across, note by note." % p.display_name, 2)
				game.day = 2
				game.jot("day", "A gale blew all day.")
				game.jot("gulp", "%s got eaten along with their snack. Spat out shortly after, damp." % p.display_name, 2)
				game.tally(1, "gulped")
				game.tally(1, "steer", 140.0)
				_next()
		3:
			if step_t > 1.0:
				game._set_phase(Game.Phase.WON)
				_next()
		4:
			if game.hud._end_open and step_t > 5.5:
				var path := Args.arg("shotpath", "")
				if path != "":
					await RenderingServer.frame_post_draw
					get_viewport().get_texture().get_image().save_png(path)
				print("BOT RESULT journal: entries=%d awards=%d" % [game.journal.size(), game.hud._commendations().size()])
				for e in game.journal:
					print("  day %d: %s" % [e[0], e[1]])
				get_tree().quit()
