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
		"fork":
			_fork(p, b)
		"favourite":
			_favourite(p, b)
		"calf":
			_calf(p, b)
		"ping":
			if step == 0 and step_t > 1.5:
				p.cam_pitch = -0.6
				p._ping()
				_next()
			elif step == 1 and step_t > 0.5:
				print("BOT RESULT ping: pings=%d label=%s" % [game.pings.size(), game.pings[0][1] if game.pings.size() > 0 else ""])
				get_tree().quit()
		"autopilot":
			_autopilot(p, b)
		"fuzz":
			_fuzz(p, b)
		"reboard":
			_reboard(p, b)
		"ladder":
			_ladder(p, b)
		"brambles":
			_brambles(p, b)
		"sitfeed":
			if step == 0 and step_t > 1.0:
				b.satiety = 0.0
				_next()
			elif step == 1 and step_t > 4.0:
				print("SIT act=%d (SIT=5)" % b.act)
				var fp := b.mouth_global() + b.forward() * 2.0
				fp.y = game.world.terrain.height(fp.x, fp.z) + 0.5
				game.server_spawn_fruit("plumbob", fp, Vector3.ZERO)
				game.server_spawn_fruit("plumbob", fp + b.forward(), Vector3.ZERO)
				_next()
			elif step == 2 and step_t > 8.0:
				print("BOT RESULT sitfeed: satiety=%.1f fed=%d act=%d" % [b.satiety, game.stats.fed, b.act])
				get_tree().quit()
		"groundfeed":
			if step == 0 and step_t > 1.0:
				b.satiety = 40.0
				var fp := b.mouth_global() + b.forward() * 7.0
				fp.y = game.world.terrain.height(fp.x, fp.z) + 0.5
				game.server_spawn_fruit("plumbob", fp, Vector3.ZERO)
				_next()
			elif step == 1 and fmod(step_t, 1.0) < 0.02:
				var m := b.mouth_global()
				for f in game.fruits.values():
					if f.kind == "plumbob" and f.global_position.distance_to(b.ground_pos) < 50.0 and f.global_position.y < b.ground_pos.y + 3.0:
						print("GF t=%.0f act=%d act_t=%.1f target=%s horiz=%.1f vert=%.1f spd=%.2f" % [step_t, b.act, b.act_t, b.fruit_target == f, Vector2(f.global_position.x - m.x, f.global_position.z - m.z).length(), m.y - f.global_position.y, b.speed])
				if step_t > 15.0:
					print("BOT RESULT groundfeed: satiety 40 -> %.1f fed=%d act=%d" % [b.satiety, game.stats.fed, b.act])
					get_tree().quit()
			elif step == 1 and step_t > 15.0:
				print("BOT RESULT groundfeed: satiety 40 -> %.1f fed=%d act=%d" % [b.satiety, game.stats.fed, b.act])
				get_tree().quit()
		"perf":
			b.lure_operator = 0
			b.lure_down = 1.0
			b.lure_yaw = sin(t * 0.1) * 0.4
			if t > 10.0 and fmod(t, 5.0) < 0.02:
				print("PERF t=%.0f fps=%d process=%.2fms physics=%.2fms objects=%d nodes=%d phys_active=%d" % [t, Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)])
			if t > 41.0:
				get_tree().quit()
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
				for f in game.fruits.values():
					if f.pest and f.on_beast:
						print("PEST still aboard at local %s stun=%.2f" % [(b.body_xf.affine_inverse() * f.global_position).snapped(Vector3.ONE * 0.1), f.stun])
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
				var rv: Dictionary = game.world.terrain._rivers[0]
				var dir2 := Vector2(cos(float(rv.mid)), sin(float(rv.mid)))
				var start: Vector2 = (rv.c as Vector2) + dir2 * (game.world.terrain.river_radius(rv, 0.0) - 45.0)
				var across := dir2
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
					if t2.has("fruit"):
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

func _fork(p: Player, b: Beast) -> void:
	match step:
		0:
			if step_t > 1.0:
				var ops := game.option_ids()
				print("FORK tree nodes=%d path=%s options=%s" % [game.wtree.size(), game.path, ops])
				for id in ops:
					var n: Dictionary = game.wtree[id]
					print("FORK option %d trait=%s dist=%.0f biome=%s" % [id, n.trait, Vector2(n.pos.x - b.ground_pos.x, n.pos.z - b.ground_pos.z).length(), Terrain.BIOMES[game.world.terrain.biome_index(n.pos.x, n.pos.z)].name])
				print("FORK text: %s" % game.fork_text())
				for lv in Game.WAYSTONES:
					var names: Array = []
					for n in game.wtree:
						if n.level == lv:
							names.append(Terrain.BIOMES[game.world.terrain.biome_index(n.pos.x, n.pos.z)].name)
					print("FORK level %d biomes %s" % [lv, names])
				_next()
		1:
			# drive toward option 1, check the road label flips to its trait
			var target: Vector3 = game.node_pos(game.option_ids()[1])
			var from := game.leg_from()
			var p2 := from.lerp(target, 0.5)
			b.ground_pos = Vector3(p2.x, game.world.terrain.height(p2.x, p2.z), p2.z)
			b.setup_snap()
			game.respawn_on_beast(p)
			_next()
		2:
			if step_t > 1.0:
				print("FORK active trait mid-leg=%s (want %s)" % [game.active_trait(), game.wtree[game.option_ids()[1]].trait])
				var target: Vector3 = game.node_pos(game.option_ids()[1])
				b.ground_pos = Vector3(target.x + 5.0, game.world.terrain.height(target.x + 5.0, target.z), target.z)
				b.setup_snap()
				game.respawn_on_beast(p)
				_next()
		3:
			if step_t > 12.0:
				print("BOT RESULT fork: path=%s waystone_idx=%d phase=%d next options=%s journal_last=%s" % [game.path, game.waystone_idx, game.phase, game.option_ids(), game.journal[-1] if game.journal.size() > 0 else ""])
				get_tree().quit()

var _yaw0 := 0.0
func _favourite(p: Player, b: Beast) -> void:
	match step:
		0:
			if step_t > 1.0:
				game.tally(p.peer_id, "fed", 4.0)
				print("FAV favourite=%d (me=%d) affection=%s" % [b.favourite, p.peer_id, b.affection])
				# hop down in front of its face
				var m := b.mouth_global() + b.forward() * 3.0
				p.global_position = Vector3(m.x, game.world.terrain.height(m.x, m.z) + 0.5, m.z)
				p.velocity = Vector3.ZERO
				_next()
		1:
			if p.state == Player.St.TUMBLE and step_t > 1.0:
				print("FAV booped at t=%.1f vel=%s" % [step_t, p.velocity.snapped(Vector3.ONE * 0.1)])
				_next()
			elif step_t > 8.0:
				print("BOT FAIL no nuzzle")
				get_tree().quit()
		2:
			if step_t > 3.0:
				print("FAV after boop on_beast=%s beast_frame=%s height_above_ground=%.1f" % [p.on_beast, p.beast_frame, p.global_position.y - b.ground_pos.y])
				# whistle test: lure down, us off to the side
				b.lure_down = 1.0
				b.lure_yaw = 0.0
				_yaw0 = b.yaw
				var side := b.ground_pos + b.body_xf.basis.x * 60.0
				p.global_position = Vector3(side.x, game.world.terrain.height(side.x, side.z) + 0.5, side.z)
				_next()
		3:
			if step_t > 0.5 and step_t < 0.55:
				game._whistle(p.peer_id, p.global_position, false)
			if step_t > 6.0:
				print("BOT RESULT favourite: yaw change toward whistler=%.2f rad (lure was straight ahead)" % wrapf(b.yaw - _yaw0, -PI, PI))
				get_tree().quit()

func _calf(p: Player, b: Beast) -> void:
	match step:
		0:
			if step_t > 1.0:
				# a calf 60 m off to the side, us next to it
				var side := b.ground_pos + b.body_xf.basis.x * 60.0
				side.y = game.world.terrain.height(side.x, side.z)
				game._spawn_calf.rpc(side)
				p.global_position = side + Vector3(4, 1, 0)
				_next()
		1:
			if fmod(step_t, 0.35) < 0.02:
				_tap("note_%d" % ([0, 2, 4, 2][int(step_t / 0.35) % 4] + 1))
			if game.mosslet.state == Mosslet.S.FOLLOW:
				print("CALF following after %.1fs, leader=%d" % [step_t, game.mosslet.leader])
				_next()
			elif step_t > 6.0:
				print("BOT FAIL calf not coaxed")
				get_tree().quit()
		2:
			# walk back towards the beast; the calf should tag along and join
			var d := _face(p, b.ground_pos)
			_press("move_forward")
			if fmod(step_t, 2.0) < 0.02:
				print("CALF t=%.0f state=%d calf->beast=%.1f me->beast=%.1f" % [step_t, game.mosslet.state, game.mosslet.global_position.distance_to(b.ground_pos), d])
			if step_t > 12.0 and step_t < 12.05:
				game.respawn_on_beast(p)   # climb aboard, as a player would
			if game.mosslet.state == Mosslet.S.JOINED or step_t > 30.0:
				_next()
		3:
			if step_t > 4.0:
				print("BOT RESULT calf: state=%d (JOINED=2) hunger_mod=%.2f journal_last=%s" % [game.mosslet.state, b.mods.hunger, game.journal[-1][1] if game.journal.size() > 0 else ""])
				get_tree().quit()

# ---------------------------------------------------------------- autopilot: a competent crew, for pacing research
var _ap := {"leg_t": 0.0, "sits": 0, "balk_s": 0.0, "feeds": 0, "mites": 0, "sit_s": 0.0, "last_day": 1, "last_way": 0, "log": []}
var _ap_feed_t := 0.0
var _ap_mite_t := 0.0
func _autopilot(p: Player, b: Beast) -> void:
	var dt := get_physics_process_delta_time()
	if game.phase in [Game.Phase.WON, Game.Phase.LOST]:
		if step == 0:
			step = 1
			print("AP RESULT %s day=%d way=%d sit_s=%.0f balk_s=%.0f thorn_s=%.0f feeds=%d mites=%d sneezes=%d shakes=%d dist=%.0f" % ["WON" if game.phase == Game.Phase.WON else "LOST", game.day, game.waystone_idx, _ap.sit_s, _ap.balk_s, float(_ap.get("thorn_s", 0.0)), _ap.feeds, _ap.mites, game.stats.sneezes, game.stats.shakes, game.stats.distance])
			for l in _ap.log:
				print("AP  ", l)
			get_tree().quit()
		return
	_ap.leg_t += dt
	if game.waystone_idx != _ap.last_way or game.day != _ap.last_day:
		_ap.log.append("day %d -> %d, way %d -> %d after %.0fs (tod=%.2f)" % [_ap.last_day, game.day, _ap.last_way, game.waystone_idx, _ap.leg_t, game.time_of_day])
		_ap.last_way = game.waystone_idx
		_ap.last_day = game.day
		_ap.leg_t = 0.0
	# the steerer
	b.lure_operator = p.peer_id
	p.state = Player.St.STATION
	var target := game.current_waystone()
	var ops := game.option_ids()
	if ops.size() > 1:
		target = game.node_pos(ops[game.seed_v % 2])   # commit to one road
	if target != Vector3.INF:
		var a := b._angle_to(target - b.ground_pos)
		b.lure_yaw = clampf(-a * 1.8, -1.0, 1.0)
		b.lure_down = 1.0
	if b.act == Beast.Act.SIT:
		_ap.sit_s += dt
	if b.balk and b.thorns:
		# a couple of crew hop off and hack a gap (server-side shortcut for the sim)
		_ap.thorn_s = float(_ap.get("thorn_s", 0.0)) + dt
		if fmod(_ap.thorn_s, 0.5) < dt:
			var bi: int = game._bramble_at(b.ground_pos + b.forward() * 15.0, 8.0)
			if bi >= 0:
				game.bramble_hp[bi] -= 1
				if game.bramble_hp[bi] <= 0:
					game._bramble_cut.rpc(bi)
	elif b.balk:
		_ap.balk_s += dt
		# someone plays it a tune
		if fmod(_ap.balk_s, 0.35) < dt:
			b.hear_note(p.peer_id, randi() % 8)
	# a forager: when it's peckish, a plumbob lands ahead of it (one at a time, with a delay)
	_ap_feed_t -= dt
	if b.satiety < 40.0 and _ap_feed_t <= 0.0:
		_ap_feed_t = 25.0
		var fp := b.mouth_global() + b.forward() * 7.0
		fp.y = game.world.terrain.height(fp.x, fp.z) + 0.5
		game.server_spawn_fruit("plumbob", fp, Vector3.ZERO)
		_ap.feeds += 1
	# pest control: every so often someone tosses a mite overboard
	_ap_mite_t -= dt
	if _ap_mite_t <= 0.0:
		_ap_mite_t = 12.0
		for f in game.fruits.values():
			if f.pest and f.on_beast:
				game.despawn_prop(f.id)
				_ap.mites += 1
				break

# ---------------------------------------------------------------- fuzz: a crew of toddlers, hunting for errors
const FUZZ_ACTIONS := ["move_forward", "move_back", "move_left", "move_right", "jump", "sprint", "interact", "grab", "throw", "whistle", "emote", "flop", "ping", "note_1", "note_3", "note_5", "note_8"]
var _fz_t := 0.0
func _fuzz(p: Player, b: Beast) -> void:
	var dt := get_physics_process_delta_time()
	_fz_t -= dt
	p.cam_yaw += randf_range(-2.0, 2.0) * dt
	p.cam_pitch = clampf(p.cam_pitch + randf_range(-1.0, 1.0) * dt, -1.2, 0.6)
	if _fz_t > 0.0:
		return
	_fz_t = randf_range(0.15, 0.8)
	_release_all()
	for k in randi_range(1, 3):
		var a: String = FUZZ_ACTIONS[randi() % FUZZ_ACTIONS.size()]
		if randf() < 0.5:
			_tap(a)
		else:
			_press(a)
	var r := randf()
	if r < 0.02:
		# hop to an interesting spot so stations, the flinger and the hut get poked
		var spots: Array = [b.lure_handle_global() + Vector3(0, 0.4, 0), b.flinger_stand_global() + Vector3(0, 0.4, 0), b.spyglass_global(), b.body_xf * (b._hut_pos + Vector3(0, 0.6, 0)), b.mouth_global() + b.forward() * 3.0, b.ladder_anchor_global(randi() % 2) + Vector3(0, 0.5, 0), b.ladder_point(randi() % 2, 0.5)]
		p.global_position = spots[randi() % spots.size()]
		p.velocity = Vector3.ZERO
	elif r < 0.025 and multiplayer.is_server():
		game.server_spawn_fruit(["plumbob", "gourdle", "mite"][randi() % 3], b.body_xf * Vector3(randf_range(-3, 3), 18, randf_range(-4, 4)), Vector3.ZERO)
	elif r < 0.028 and multiplayer.is_server():
		game._spawn_magpie.rpc(game._next_magpie, b.body_xf * Vector3(0, 30, 0))
		game._next_magpie += 1
	elif r < 0.03 and multiplayer.is_server():
		game._gust.rpc(b.body_xf.basis.x)
	if t > float(Args.arg("fuzz_s", "600")):
		print("BOT RESULT fuzz: survived %.0fs, fruits=%d magpies=%d journal=%d" % [t, game.fruits.size(), game.magpies.size(), game.journal.size()])
		get_tree().quit()

var _rb_phase := 0
func _reboard(p: Player, b: Beast) -> void:
	b.lure_operator = 0
	b.lure_down = 1.0
	b.lure_yaw = 0.0
	match step:
		0:
			if step_t > 2.0:
				var start := b.body_xf * Vector3(float(Args.arg("rx", "0")), 0, float(Args.arg("rz", "48")))
				p.global_position = Vector3(start.x, game.world.terrain.height(start.x, start.z) + 0.5, start.z)
				p.velocity = Vector3.ZERO
				p.state = Player.St.NORMAL
				_next()
		1:
			# run for the tail tip, then up the tail toward the cottage
			var tip := b.body_xf * Vector3(0, 0.5, 29.0)
			var lp := b.body_xf.affine_inverse() * p.global_position
			# phases: out around the flank -> behind the tail tip -> up the tail
			if _rb_phase == 0 and (lp.z > 30.0 and absf(lp.x) < 3.0):
				_rb_phase = 1
			var target: Vector3
			if _rb_phase == 0:
				var wide := b.body_xf * Vector3(signf(lp.x if absf(lp.x) > 0.5 else 1.0) * 13.0, 0, 36.0)
				target = wide if lp.z < 32.0 else tip + b.forward() * -4.0
			else:
				target = tip if lp.z > 30.5 else b.body_xf * Vector3(0, 16.0, 4.0)
			_face(p, target)
			_press("move_forward")
			_press("sprint")
			if fmod(step_t, 0.6) < 0.02 and p.is_on_floor() and lp.y < 3.0 and lp.z < 31.0:
				_tap("jump")
			if fmod(step_t, 3.0) < 0.02:
				print("REBOARD t=%.0f local=%s onb=%s state=%d" % [step_t, lp.snapped(Vector3.ONE * 0.1), p.on_beast, p.state])
			if p.on_beast and lp.y > 12.0:
				print("BOT RESULT reboard: aboard after %.1fs (beast speed %.1f)" % [step_t, b.speed])
				get_tree().quit()
			elif step_t > 60.0:
				print("BOT RESULT reboard: FAILED after 60s, local=%s" % lp.snapped(Vector3.ONE * 0.1))
				get_tree().quit()

func _ladder(p: Player, b: Beast) -> void:
	b.lure_operator = 0
	b.lure_down = 1.0
	b.lure_yaw = 0.0
	match step:
		0:
			if step_t > 1.5:
				# go to the left post and lower the ladder
				p.global_position = b.ladder_anchor_global(0) + Vector3(0, 0.5, 0)
				_next()
		1:
			if step_t > 0.6:
				_tap("interact")
				_next()
		2:
			if step_t > 2.0:
				print("LADDER down=%s by=%d" % [b.ladder_down(0), b.ladder_by[0]])
				b.ladder_by[0] = 999   # pretend a crewmate lowered it, to test the journal credit
				game.pstats[999] = {"name": "Wren", "color": 2}
				# drop to the ground at its foot
				var foot := b.ladder_point(0, 0.0)
				p.global_position = Vector3(foot.x, game.world.terrain.height(foot.x, foot.z) + 0.5, foot.z)
				p.velocity = Vector3.ZERO
				p.state = Player.St.NORMAL
				_next()
		3:
			if step_t > 0.5 and step_t < 0.55:
				print("LADDER hint at foot: %s" % game.interaction_hint(p))
				_tap("interact")
			if step_t > 0.8:
				_press("move_forward")
			if p.state == Player.St.NORMAL and step_t > 2.0 and p.on_beast:
				print("BOT RESULT ladder: aboard after climbing %.1fs, journal_last=%s" % [step_t, game.journal[-1][1] if game.journal.size() > 0 else ""])
				get_tree().quit()
			elif step_t > 20.0:
				print("BOT RESULT ladder: FAILED state=%d climb_h=%.1f" % [p.state, p.climb_h])
				get_tree().quit()

var _br_target := -1
func _brambles(p: Player, b: Beast) -> void:
	b.lure_operator = 0
	b.lure_down = 1.0
	b.lure_yaw = 0.0
	match step:
		0:
			if step_t > 1.0:
				var bp: Vector3 = game.brambles[game.brambles.size() / 2]
				var out := Vector3(bp.x - game._start_pos.x, 0, bp.z - game._start_pos.z).normalized()
				var st := bp - out * 45.0
				b.ground_pos = Vector3(st.x, game.world.terrain.height(st.x, st.z), st.z)
				b.yaw = atan2(-out.x, -out.z)
				b.setup_snap()
				game.respawn_on_beast(p)
				b.satiety = 90.0
				print("BRAMBLE hedge has %d bushes" % game.brambles.size())
				_next()
		1:
			if b.balk and b.thorns:
				print("BRAMBLE balked at thorns after %.1fs, %.1f m from hedge" % [step_t, Vector2(b.ground_pos.x - game._start_pos.x, b.ground_pos.z - game._start_pos.z).length() - game._hedge_r])
				_next()
			elif step_t > 30.0:
				print("BOT FAIL never balked at brambles")
				get_tree().quit()
		2:
			# hop down in front and hack until the beast can pass
			var probe := b.ground_pos + b.forward() * 15.0
			var bi: int = game._bramble_at(probe, 8.0)
			if bi < 0:
				print("BRAMBLE gap open after %.1fs of chopping, chops=%d" % [step_t, int(game.pstats.get(p.peer_id, {}).get("chops", 0.0))])
				_next()
				return
			if bi != _br_target:
				_br_target = bi
				var bp: Vector3 = game.brambles[bi]
				p.global_position = bp + (b.ground_pos - bp).normalized() * 2.0 + Vector3(0, 1.0, 0)
				p.velocity = Vector3.ZERO
			if fmod(step_t, 0.3) < 0.02:
				_tap("interact")
			if fmod(step_t, 3.0) < 0.02:
				print("BRAMBLE chopping target=%d hp=%d my_dist=%.1f hint=%s state=%d" % [bi, game.bramble_hp[bi], p.global_position.distance_to(game.brambles[bi]), game.interaction_hint(p), p.state])
			if step_t > 60.0:
				print("BOT FAIL gap never opened")
				get_tree().quit()
		3:
			if step_t > 15.0:
				var past := Vector2(b.ground_pos.x - game._start_pos.x, b.ground_pos.z - game._start_pos.z).length() - game._hedge_r
				print("BOT RESULT brambles: beast is %.1f m past the hedge line, balk=%s journal_last=%s" % [past, b.balk, game.journal[-1][1] if game.journal.size() > 0 else ""])
				get_tree().quit()
