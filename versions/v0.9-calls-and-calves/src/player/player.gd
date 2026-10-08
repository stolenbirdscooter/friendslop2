class_name Player
extends CharacterBody3D
## A crew member. Owner-authoritative movement (sent to everyone ~20 Hz);
## anything touching shared state goes through Game's server requests.

enum St { NORMAL, TUMBLE, STATION, GULPED, CARRIED, SPY, FLING }

const WALK := 4.6
const SPRINT := 7.2
const JUMP := 6.6
const GRAVITY := 18.0
const SYNC_HZ := 20.0

var peer_id := 1
var is_local := false
var game: Game
var visual: TenderVisual
var state: int = St.NORMAL
var state_t := 0.0
var display_name := "Tender"
var color_idx := 0

# camera rig (local player only)
var cam_root: Node3D
var spring: SpringArm3D
var camera: Camera3D
var cam_yaw := 0.0
var cam_pitch := -0.22
var cam_dist := 5.0
var shake := 0.0
var post_mat: ShaderMaterial

var facing := 0.0
var held_fruit := 0
var carrying_peer := 0
var carried_by := 0
var throw_charge := -1.0
var coyote := 0.0
var jump_buf := 0.0
var air_time := 0.0
var peak_y := 0.0
var on_beast := false
var beast_frame := false
var _beast_frame_t := 0.0
var whistle_t := 0.0
var wave_t := 0.0
var struggle := 0
var _last_beast_yaw := 0.0
var _sync_t := 0.0
var _snaps: Array = []
var _remote_flags := 0
var _remote_vel := Vector3.ZERO
var _step_t := 0.0
var _tumble_spin := Vector3.ZERO
var _gulp_spit_at := 0.0
var flatten := 0.0
var flopping := false
var spy_hold := 0.0
var fling_cool := 0.0
var hat_stolen := false
var play_t := 0.0
var _note_t := 0.0

func setup(p_game: Game, p_peer: int, info: Dictionary) -> void:
	game = p_game
	peer_id = p_peer
	name = str(peer_id)
	is_local = p_peer == p_game.multiplayer.get_unique_id()
	set_multiplayer_authority(peer_id)
	display_name = info.get("name", "Tender")
	color_idx = int(info.get("color", 0))
	collision_layer = G.PLAYER_LAYER
	collision_mask = G.WORLD_LAYER | G.BEAST_LAYER
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.7
	floor_stop_on_slope = true
	floor_constant_speed = true
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_ADD_VELOCITY
	platform_floor_layers = 0xFFFFFFFF
	safe_margin = 0.02
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.15
	cs.shape = cap
	cs.position = Vector3(0, 0.6, 0)
	add_child(cs)
	visual = TenderVisual.new()
	add_child(visual)
	visual.build(G.crew_color(color_idx), info.get("hat", "beanie"))
	if is_local:
		_build_camera()

func refresh_look(info: Dictionary) -> void:
	display_name = info.get("name", display_name)
	color_idx = int(info.get("color", color_idx))
	visual.build(G.crew_color(color_idx), info.get("hat", "beanie"))
	if hat_stolen and visual.hat_node:
		visual.hat_node.visible = false

func _build_camera() -> void:
	cam_root = Node3D.new()
	cam_root.top_level = true
	add_child(cam_root)
	spring = SpringArm3D.new()
	spring.collision_mask = G.WORLD_LAYER
	spring.spring_length = cam_dist
	spring.margin = 0.3
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	spring.shape = probe
	spring.add_excluded_object(get_rid())
	cam_root.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 72.0
	camera.far = 1600.0
	camera.near = 0.08
	spring.add_child(camera)
	camera.current = true
	post_mat = PostFX.attach(camera)

func hand_point() -> Vector3:
	return global_position + Basis(Vector3.UP, facing) * Vector3(0, 0.95, -0.62)

func cam_forward() -> Vector3:
	if camera:
		return -camera.global_transform.basis.z
	return Basis(Vector3.UP, facing) * Vector3.FORWARD

# ---------------------------------------------------------------- input
func _unhandled_input(event: InputEvent) -> void:
	if not is_local or game.ui_blocking():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw -= event.relative.x * G.mouse_sens
		cam_pitch -= event.relative.y * G.mouse_sens * (-1.0 if G.invert_y else 1.0)
		cam_pitch = clampf(cam_pitch, -1.35, 0.9)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_dist = clampf(cam_dist - 0.5, 2.2, 10.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_dist = clampf(cam_dist + 0.5, 2.2, 10.0)

# ---------------------------------------------------------------- simulation
func _physics_process(dt: float) -> void:
	if game == null:
		return
	if not is_local:
		_remote_update()
		return
	state_t += dt
	whistle_t = maxf(whistle_t - dt, 0.0)
	wave_t = maxf(wave_t - dt, 0.0)
	flatten = maxf(flatten - dt, 0.0)
	fling_cool = maxf(fling_cool - dt, 0.0)
	play_t = maxf(play_t - dt, 0.0)
	_note_t -= dt
	if not game.ui_blocking() and Input.is_action_just_pressed("ping") and _note_t <= 0.0:
		_note_t = 0.3
		_ping()
	if not game.ui_blocking() and state != St.CARRIED:
		for i in 8:
			if Input.is_action_just_pressed("note_%d" % (i + 1)) and _note_t <= 0.0:
				_note_t = 0.05
				game.play_note(i)
	# keep the camera turning with the beast while standing on it
	var by := game.beast.yaw
	if on_beast:
		var d := wrapf(by - _last_beast_yaw, -PI, PI)
		cam_yaw += d
		facing += d
	_last_beast_yaw = by
	if not game.ui_blocking():
		var look := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
		if look.length() > 0.15:
			cam_yaw -= look.x * dt * 2.8
			cam_pitch = clampf(cam_pitch - look.y * dt * 2.0, -1.35, 0.9)
	match state:
		St.NORMAL:
			_move_normal(dt)
		St.TUMBLE:
			_move_tumble(dt)
		St.STATION:
			_move_station(dt)
		St.GULPED:
			global_position = game.beast.mouth_global() + Vector3(0, -0.6, 0)
			velocity = Vector3.ZERO
		St.CARRIED:
			_move_carried(dt)
		St.SPY:
			_move_spy(dt)
		St.FLING:
			_move_fling(dt)
	_update_beast_frame(dt)
	if state != St.GULPED and state != St.CARRIED:
		var r := game.beast.surface_rescue(global_position)
		if r != global_position:
			global_position = r
			velocity.y = maxf(velocity.y, 0.0)
	_animate_local(dt)
	_sync_t -= dt
	if _sync_t <= 0.0:
		_sync_t = 1.0 / SYNC_HZ
		_send_sync()
	if global_position.y < Terrain.WATER_LEVEL - 40.0:
		game.respawn_on_beast(self)

func _process(dt: float) -> void:
	if is_local and cam_root:
		_update_camera(dt)

func _input_dir() -> Vector3:
	if game.ui_blocking():
		return Vector3.ZERO
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var b := Basis(Vector3.UP, cam_yaw)
	var d := b * Vector3(v.x, 0, v.y)
	return d.limit_length(1.0)

func _move_normal(dt: float) -> void:
	var dir := _input_dir()
	var grounded := is_on_floor()
	var in_water := global_position.y < Terrain.WATER_LEVEL - 0.6
	var top := SPRINT if Input.is_action_pressed("sprint") else WALK
	if held_fruit != 0 and game.fruit_heavy(held_fruit):
		top *= 0.65
	if carrying_peer != 0:
		top *= 0.7
	if in_water:
		top *= 0.55
	if flatten > 0.0:
		top *= 0.3
	var target := dir * top
	var accel := 38.0 if grounded else 11.0
	var hv := Vector3(velocity.x, 0, velocity.z)
	# platform velocity is applied by CharacterBody3D itself; we steer relative velocity only
	hv = hv.move_toward(target, accel * dt)
	velocity.x = hv.x
	velocity.z = hv.z
	if grounded:
		coyote = 0.13
		if air_time > 0.05:
			_on_landed()
		air_time = 0.0
		peak_y = global_position.y
	else:
		coyote -= dt
		air_time += dt
		peak_y = maxf(peak_y, global_position.y)
	if Input.is_action_just_pressed("jump") and not game.ui_blocking():
		jump_buf = 0.14
	jump_buf -= dt
	if jump_buf > 0.0 and (coyote > 0.0 or in_water) and flatten <= 0.0:
		velocity.y = JUMP * (0.6 if in_water else 1.0)
		jump_buf = 0.0
		coyote = 0.0
		Sfx.play("jump", global_position, -6.0, 1.0 + color_idx * 0.04)
		visual.squash = -0.6
	if in_water:
		velocity.y = move_toward(velocity.y, 1.0 if global_position.y < Terrain.WATER_LEVEL - 0.9 else -1.0, 20.0 * dt)
	else:
		velocity.y -= GRAVITY * dt
	if dir.length() > 0.1:
		facing = lerp_angle(facing, atan2(-dir.x, -dir.z), G.damp(12.0, dt))
	elif throw_charge >= 0.0 or held_fruit != 0:
		facing = lerp_angle(facing, cam_yaw, G.damp(10.0, dt))
	move_and_slide()
	_check_on_beast()
	# footsteps
	if grounded and hv.length() > 1.0:
		_step_t -= dt * hv.length()
		if _step_t <= 0.0:
			_step_t = 1.6
			Sfx.play("step_soft", global_position, -14.0)
	_handle_actions(dt)

func _on_landed() -> void:
	var fall := peak_y - global_position.y
	if fall > 9.0:
		visual.land(4.0)
		enter_tumble(Vector3(velocity.x, 2.0, velocity.z) * 0.5, 1.0)
		Sfx.play("splat", global_position, -2.0)
		game.fx.puff(global_position + Vector3(0, 0.2, 0), 8, G.PAPER_DARK, 0.4, 3.0, 0.3, 0.8, -0.5, 0.4)
		shake = 0.5
	elif fall > 0.8:
		visual.land(fall)
		Sfx.play("land", global_position, -10.0)

func _check_on_beast() -> void:
	on_beast = false
	if is_on_floor():
		for i in get_slide_collision_count():
			var c := get_slide_collision(i)
			var o := c.get_collider()
			if o == game.beast.body or o == game.beast.head:
				on_beast = true

func _update_beast_frame(dt: float) -> void:
	if on_beast:
		beast_frame = true
		_beast_frame_t = 0.0
	elif is_on_floor():
		beast_frame = false
	else:
		_beast_frame_t += dt
		if _beast_frame_t > 2.5:
			beast_frame = false

func _handle_actions(dt: float) -> void:
	if game.ui_blocking():
		return
	if Input.is_action_just_pressed("interact"):
		game.try_interact(self)
	if Input.is_action_just_pressed("grab"):
		if held_fruit != 0 or carrying_peer != 0:
			game.request_drop(self, velocity * 0.5 + cam_forward() * 1.5)
		else:
			game.try_grab(self)
	if held_fruit != 0 or carrying_peer != 0:
		if Input.is_action_just_pressed("throw"):
			throw_charge = 0.0
		if throw_charge >= 0.0:
			throw_charge = minf(throw_charge + dt, 1.0)
			if Input.is_action_just_released("throw"):
				var aim := cam_forward()
				aim.y = maxf(aim.y + 0.22, -0.3)
				var heavy := held_fruit != 0 and game.fruit_heavy(held_fruit)
				var power := lerpf(7.0, 19.0, throw_charge) * (0.6 if heavy else 1.0)
				game.request_throw(self, aim.normalized() * power + get_platform_velocity() + Vector3(velocity.x, 0, velocity.z) * 0.4)
				throw_charge = -1.0
				visual.squash = -0.4
	else:
		throw_charge = -1.0
	if Input.is_action_just_pressed("whistle") and whistle_t <= 0.0:
		whistle_t = 1.4
		game.do_whistle(self)
	if Input.is_action_just_pressed("emote"):
		wave_t = 1.6
		game.do_emote(self)
	if Input.is_action_just_pressed("flop"):
		flopping = true
		enter_tumble(Vector3(velocity.x, 1.5, velocity.z), 0.35)

func _move_tumble(dt: float) -> void:
	velocity.y -= GRAVITY * dt
	if is_on_floor():
		var hv := Vector3(velocity.x, 0, velocity.z)
		hv = hv.move_toward(Vector3.ZERO, (9.0 + hv.length() * 0.8) * dt)   # big landings skid, then bite
		velocity.x = hv.x
		velocity.z = hv.z
		_tumble_spin = _tumble_spin.lerp(Vector3.ZERO, G.damp(4.0, dt))
	var pre := velocity
	move_and_slide()
	# bounce off walls a little so being flung feels springy
	if get_slide_collision_count() > 0 and pre.length() > 7.0 and not is_on_floor():
		var n := get_slide_collision(0).get_normal()
		velocity = pre.bounce(n) * 0.4
	_check_on_beast()
	if flopping:
		if Input.is_action_pressed("flop") and not game.ui_blocking():
			state_t = minf(state_t, 0.5)
		else:
			flopping = false
	var settled := is_on_floor() and Vector3(velocity.x, 0, velocity.z).length() < 1.4
	if (settled and state_t > 0.8) or state_t > 4.0:
		if Input.is_action_just_pressed("jump") or state_t > 1.6 or (settled and state_t > 1.1):
			state = St.NORMAL
			state_t = 0.0
			visual.squash = 0.6
			peak_y = global_position.y

func enter_tumble(vel: Vector3, spin_amt := 1.0) -> void:
	if state == St.STATION:
		game.release_station(self)
	elif state == St.FLING:
		game.release_flinger(self)
	if state == St.CARRIED:
		return
	state = St.TUMBLE
	state_t = 0.0
	velocity = vel
	_tumble_spin = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * (6.0 + vel.length() * 0.6) * spin_amt
	peak_y = global_position.y
	if randf() < 0.6:
		Sfx.play("tumble", global_position, -4.0, 0.9 + color_idx * 0.05)

func _move_station(dt: float) -> void:
	var b := game.beast
	var stand := b.lure_stand_global()
	global_position = global_position.lerp(stand, G.damp(18.0, dt))
	velocity = Vector3.ZERO
	facing = lerp_angle(facing, b.yaw + b.lure_yaw * Beast.LURE_MAX_YAW, G.damp(10.0, dt))
	on_beast = true
	if game.ui_blocking():
		return
	var steer := Input.get_axis("move_left", "move_right")
	var updown := Input.get_axis("move_back", "move_forward")
	b.lure_yaw = clampf(b.lure_yaw + steer * dt * 0.9, -1.0, 1.0)
	if absf(steer) < 0.1:
		b.lure_yaw = move_toward(b.lure_yaw, 0.0, dt * 0.35)
	b.lure_down = clampf(b.lure_down + updown * dt * 0.8, 0.0, 1.0)
	game.send_lure(b.lure_yaw, b.lure_down)
	if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("jump"):
		game.release_station(self)
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP

func _move_fling(dt: float) -> void:
	var b := game.beast
	global_position = global_position.lerp(b.flinger_stand_global(), G.damp(18.0, dt))
	velocity = Vector3.ZERO
	on_beast = true
	if game.ui_blocking():
		return
	# the camera aims the turntable; A / D nudge it as well
	cam_yaw -= Input.get_axis("move_left", "move_right") * dt * 1.2
	var rel := Beast.clamp_fl_yaw(cam_yaw - b.yaw)
	cam_yaw = b.yaw + rel
	b.fl_yaw = rel
	facing = b.yaw + rel
	if Input.is_action_pressed("grab") and fling_cool <= 0.0:
		if b.fl_charge == 0.0:
			Sfx.play("creak", global_position, -4.0, 0.6)
		b.fl_charge = minf(b.fl_charge + dt / 1.3, 1.0)
	elif b.fl_charge > 0.0:
		game.request_fling(b.fl_charge)
		b.fl_charge = 0.0
		fling_cool = 1.6
	game.send_flinger(b.fl_yaw, b.fl_charge)
	if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("jump"):
		game.release_flinger(self)

## Point at whatever is under the crosshair; everyone sees a labelled marker.
func _ping() -> void:
	if camera == null:
		return
	var from := camera.global_position
	var dir := cam_forward()
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 400.0, G.WORLD_LAYER | G.BEAST_LAYER | G.PROP_LAYER)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var at: Vector3 = hit.position if hit else from + dir * 120.0
	var label := "over there!" if hit else "that way!"
	if not hit:
		# far ground has no collider: march the ray over the analytic terrain instead
		var tr := game.world.terrain
		for i in range(1, 160):
			var pt := from + dir * (i * 2.5)
			if pt.y < maxf(tr.height(pt.x, pt.z), Terrain.WATER_LEVEL):
				at = pt
				label = "over there!"
				break
	var col: Object = hit.collider if hit else null
	if col is Fruit:
		var f: Fruit = col
		label = "thistlemite!" if f.pest else ("something shiny!" if f.keepsake else ("a gourdle!" if f.kind == "gourdle" else "a plumbob!"))
	elif col == game.beast.body or col == game.beast.head:
		label = "here!"
	else:
		for m in game.magpies.values():
			# a magpie near the line of sight counts even if the ray missed it
			var to: Vector3 = m.global_position - from
			if to.length() < 150.0 and dir.dot(to.normalized()) > 0.995:
				at = m.global_position
				label = "magpie!"
				break
		if label != "magpie!" and hit:
			for t in game.world.terrain.obstacles_near(at, 4.0):
				if t.has("variant"):
					label = "fruit tree!" if t.fruit else "tree"
					break
	game.ping(at, label)
	wave_t = 0.0
	visual.pointing = 1.2

## A gale gust arrives. Flopping flat, holding a station or carrying something heavy keeps you put.
func on_gust(dir: Vector3) -> void:
	if state in [St.STATION, St.FLING, St.SPY, St.GULPED, St.CARRIED] or game.beast.in_hut(global_position):
		shake = maxf(shake, 0.35)
		return
	if state == St.TUMBLE and flopping:
		game.toast_local("Flat as a pancake. The wind can't shift you.")
		return
	if carrying_peer != 0 or (held_fruit != 0 and game.fruit_heavy(held_fruit)):
		shake = maxf(shake, 0.4)
		game.toast_local("Weighed down: you stood firm.")
		return
	if on_beast or beast_frame:
		enter_tumble(dir * randf_range(7.0, 9.5) + Vector3.UP * 5.0 + get_platform_velocity(), 1.2)
		shake = 0.7
		game.toast_local("Blown clean over!")
	elif is_on_floor():
		enter_tumble(dir * 5.0 + Vector3.UP * 3.0, 0.8)

## Launched from the flinger bowl.
func flung(at: Vector3, vel: Vector3) -> void:
	if state == St.GULPED or state == St.CARRIED:
		return
	global_position = at
	enter_tumble(vel, 1.5)
	shake = 0.7
	Sfx.play("tumble", at, 0.0, 1.3)
	game.toast_local(["Wheeeee!", "Up you go!", "Bye bye!", "Airborne!"][randi() % 4])

func enter_spy() -> void:
	state = St.SPY
	state_t = 0.0
	spy_hold = 0.0
	Sfx.play("creak", global_position, -8.0, 1.5)

func _move_spy(dt: float) -> void:
	var b := game.beast
	global_position = global_position.lerp(b.spyglass_stand_global(), G.damp(18.0, dt))
	velocity = Vector3.ZERO
	on_beast = true
	facing = cam_yaw
	# hold the signal smoke in the eyepiece to spot it for the whole crew
	var seen := false
	for id in game.option_ids():
		var to := (game.node_pos(id) + Vector3(0, 40, 0) - camera.global_position).normalized()
		seen = seen or cam_forward().dot(to) > cos(deg_to_rad(5.0))
	if not game.option_ids().is_empty():
		if seen:
			spy_hold += dt
			if spy_hold > 1.0:
				spy_hold = -999.0
				game.report_spotted()
		elif spy_hold > 0.0:
			spy_hold = maxf(spy_hold - dt * 2.0, 0.0)
	if game.ui_blocking():
		return
	if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("jump"):
		state = St.NORMAL
		state_t = 0.0

func _move_carried(dt: float) -> void:
	var carrier := game.get_player(carried_by)
	if carrier == null:
		state = St.NORMAL
		carried_by = 0
		return
	global_position = global_position.lerp(carrier.hand_point() + Vector3(0, -0.2, 0), G.damp(25.0, dt))
	velocity = Vector3.ZERO
	if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("grab"):
		struggle += 1
		visual.squash = 0.5
		if struggle >= 6:
			game.request_break_free(self)

# ---------------------------------------------------------------- events from the world
func on_beast_step(foot: Vector3, strength: float) -> void:
	var d := Vector2(foot.x - global_position.x, foot.z - global_position.z).length()
	if on_beast:
		shake = maxf(shake, 0.12 * strength)
		if is_on_floor() and state == St.NORMAL:
			velocity.y += 1.1 * strength
	elif absf(global_position.y - foot.y) < 3.0:
		if d < 2.6 and state != St.GULPED:
			flatten = 2.4
			visual.flattened = 2.4
			enter_tumble(Vector3((global_position - foot).normalized().x * 3.0, 1.0, (global_position - foot).normalized().z * 3.0), 0.2)
			Sfx.play("splat", global_position, 0.0)
			shake = 0.6
			game.toast_local("Pancaked!")
		elif d < 16.0:
			shake = maxf(shake, (1.0 - d / 16.0) * 0.45 * strength)
			if d < 6.0 and state == St.NORMAL and is_on_floor():
				velocity.y = 3.0

func on_sneeze(origin: Vector3, fwd: Vector3) -> void:
	if state == St.GULPED or state == St.CARRIED:
		return
	if on_beast or beast_frame:
		var side := (global_position - game.beast.global_head()).normalized()
		var v := Vector3(side.x * randf_range(2.0, 5.0), randf_range(9.0, 13.0), side.z * randf_range(2.0, 5.0)) - fwd * randf_range(1.0, 4.0)
		enter_tumble(v + get_platform_velocity())
		shake = 0.8
	else:
		var to := global_position - origin
		if to.length() < 22.0 and to.normalized().dot(fwd) > 0.3:
			enter_tumble(fwd * 16.0 + Vector3.UP * 6.0)
			shake = 0.7

func on_shake() -> void:
	if state == St.STATION:
		game.toast_local("You clung to the lure pole!")
		shake = 0.6
		return
	if state == St.GULPED or state == St.CARRIED:
		return
	if on_beast or beast_frame:
		var lp := game.beast.body_xf.affine_inverse() * global_position
		var side := game.beast.body_xf.basis.x * signf(lp.x if absf(lp.x) > 0.3 else randf_range(-1, 1))
		enter_tumble(side * randf_range(6.0, 8.5) + Vector3.UP * randf_range(6.0, 8.0) + game.beast.forward() * game.beast.speed)
		shake = 0.9

func knock(impulse: Vector3) -> void:
	if state == St.GULPED or state == St.CARRIED:
		return
	enter_tumble(velocity * 0.3 + impulse, 1.0)
	Sfx.play("bonk", global_position, 0.0, randf_range(0.9, 1.15))
	shake = 0.4

func gulped() -> void:
	if state == St.STATION:
		game.release_station(self)
	elif state == St.FLING:
		game.release_flinger(self)
	state = St.GULPED
	state_t = 0.0
	visible = false

func spat(vel: Vector3) -> void:
	visible = true
	state = St.TUMBLE
	state_t = 0.0
	velocity = vel
	_tumble_spin = Vector3(9, 3, 0)
	shake = 0.6

func set_carried(by: int) -> void:
	carried_by = by
	if by != 0:
		if state == St.STATION:
			game.release_station(self)
		elif state == St.FLING:
			game.release_flinger(self)
		state = St.CARRIED
		struggle = 0
	elif state == St.CARRIED:
		state = St.NORMAL

func thrown(vel: Vector3) -> void:
	carried_by = 0
	state = St.NORMAL
	enter_tumble(vel)

# ---------------------------------------------------------------- camera
func _update_camera(dt: float) -> void:
	var head := global_position + Vector3(0, 1.45, 0)
	if state == St.GULPED:
		head = game.beast.global_head() + Vector3(0, 6, 0)
	elif state == St.SPY:
		head = game.beast.spyglass_global() + Vector3(0, 0.1, 0)
	cam_root.global_position = cam_root.global_position.lerp(head, G.damp(22.0, dt)) if cam_root.global_position.distance_to(head) < 6.0 else head
	cam_root.global_rotation = Vector3(cam_pitch, cam_yaw, 0)
	var arm := cam_dist if state != St.STATION else cam_dist + 2.5
	if state == St.FLING:
		arm = cam_dist + 3.5
		head += Vector3(0, 1.5, 0)
	if state == St.SPY:
		arm = 0.0
	spring.spring_length = lerpf(spring.spring_length, arm, G.damp(10.0, dt))
	shake = maxf(shake - dt * 1.6, 0.0)
	var s := shake * shake
	var t := Time.get_ticks_msec() * 0.001
	camera.h_offset = sin(t * 37.0) * s * 0.6
	camera.v_offset = sin(t * 43.0 + 1.3) * s * 0.6
	var want_fov := 72.0 + clampf(Vector3(velocity.x, 0, velocity.z).length() - 5.0, 0.0, 8.0)
	if state == St.SPY:
		want_fov = 16.0
	camera.fov = lerpf(camera.fov, want_fov, G.damp(6.0, dt))
	visual.visible = not (state == St.SPY and camera.fov < 40.0)

func _animate_local(_dt: float) -> void:
	visual.rotation.y = facing
	visual.move_speed = Vector3(velocity.x, 0, velocity.z).length() if state == St.NORMAL else 0.0
	visual.grounded = is_on_floor() or state == St.STATION
	visual.vert_speed = velocity.y
	visual.tumbling = state == St.TUMBLE
	visual.spin = _tumble_spin
	visual.carrying = held_fruit != 0 or carrying_peer != 0
	visual.at_station = state == St.STATION or state == St.FLING
	visual.playing = play_t
	visual.whistling = whistle_t - 0.6
	visual.waving = wave_t
	visual.look_dir = cam_forward()
	visual.talk = Voice.level(peer_id)
	visible = state != St.GULPED

# ---------------------------------------------------------------- replication
func _flags() -> int:
	var f := 0
	if is_on_floor(): f |= 1
	if state == St.TUMBLE: f |= 2
	if held_fruit != 0 or carrying_peer != 0: f |= 4
	if state == St.STATION or state == St.SPY or state == St.FLING: f |= 8
	if whistle_t > 0.6: f |= 16
	if wave_t > 0.0: f |= 32
	if state == St.GULPED: f |= 64
	if flatten > 0.0: f |= 128
	if play_t > 0.0: f |= 256
	return f

func _send_sync() -> void:
	var p := global_position
	var frame := 0
	if beast_frame:
		frame = 1
		p = game.beast.body_xf.affine_inverse() * p
	var f := facing - (game.beast.yaw if frame == 1 else 0.0)
	game.to_ready(self, "_sync", [frame, p, f, velocity, _flags(), _tumble_spin])

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync(frame: int, p: Vector3, f: float, vel: Vector3, flags: int, spin: Vector3) -> void:
	_snaps.append([Time.get_ticks_msec() / 1000.0, frame, p, f, vel, flags, spin])
	while _snaps.size() > 10:
		_snaps.pop_front()

func _resolve(s: Array) -> Array:
	var p: Vector3 = s[2]
	var f: float = s[3]
	if s[1] == 1:
		p = game.beast.body_xf * p
		f += game.beast.yaw
	return [p, f]

func _remote_update() -> void:
	if _snaps.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0 - 0.1
	var a: Array = _snaps[0]
	var b: Array = _snaps[_snaps.size() - 1]
	for i in _snaps.size() - 1:
		if _snaps[i][0] <= now and _snaps[i + 1][0] >= now:
			a = _snaps[i]
			b = _snaps[i + 1]
			break
	var k := 0.0
	if b[0] > a[0]:
		k = clampf((now - a[0]) / (b[0] - a[0]), 0.0, 1.0)
	var ra := _resolve(a)
	var rb := _resolve(b)
	if a[1] != b[1]:
		ra = rb
	global_position = (ra[0] as Vector3).lerp(rb[0], k)
	facing = lerp_angle(ra[1], rb[1], k)
	_remote_vel = b[4]
	_remote_flags = b[5]
	visual.rotation.y = facing
	visual.move_speed = Vector3(_remote_vel.x, 0, _remote_vel.z).length() if (_remote_flags & 2) == 0 else 0.0
	visual.grounded = (_remote_flags & 1) != 0 or (_remote_flags & 8) != 0
	visual.vert_speed = _remote_vel.y
	visual.tumbling = (_remote_flags & 2) != 0
	visual.spin = b[6]
	visual.carrying = (_remote_flags & 4) != 0
	visual.at_station = (_remote_flags & 8) != 0
	visual.whistling = 1.0 if (_remote_flags & 16) != 0 else 0.0
	visual.waving = 1.0 if (_remote_flags & 32) != 0 else 0.0
	visual.flattened = 1.0 if (_remote_flags & 128) != 0 else visual.flattened
	visual.playing = 0.3 if (_remote_flags & 256) != 0 else visual.playing
	visual.talk = Voice.level(peer_id)
	visible = (_remote_flags & 64) == 0
