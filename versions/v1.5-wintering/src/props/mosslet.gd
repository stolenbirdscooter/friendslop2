class_name Mosslet
extends Node3D
## A lost Mossback calf. It waits somewhere off the path, bleating, until a Tender coaxes it
## along with a tune or a whistle; near the big beast it falls in alongside and stays.
## The server walks it (Game owns spawning); everyone else interpolates.

enum S { LOST, FOLLOW, JOINED }

var game: Game
var state: int = S.LOST
var leader := 0
var _lonely := 0.0
var _bleat := 3.0
var speed := 0.0
var _phase := 0.0
var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _side := 1.0
var _body: Node3D
var _head: Node3D
var _legs: Array[Node3D] = []
var _tail: Node3D

func build() -> void:
	var fur := BeastBuild.fur.lightened(0.15)
	var light := BeastBuild.fur_light.lightened(0.1)
	_body = Node3D.new()
	add_child(_body)
	_body.add_child(Mats.mesh_instance(Geo.merge([
		[Geo.blob(Vector3(1.0, 0.85, 1.45), fur, 0.06, 101, 10, 14), Transform3D(Basis(), Vector3(0, 1.7, 0))],
		[Geo.blob(Vector3(0.85, 0.3, 1.1), G.MOSS, 0.2, 102, 6, 10), Transform3D(Basis(), Vector3(0, 2.35, 0.1))],
		[Geo.blob(Vector3(0.18, 0.4, 0.18), G.MOSS_DARK, 0.2, 103, 4, 6), Transform3D(Basis(Vector3.FORWARD, 0.2), Vector3(0.1, 2.75, 0.2))],
	]), Mats.toon(Color.WHITE, true, 0.06)))
	_head = Node3D.new()
	_head.position = Vector3(0, 2.1, -1.35)
	_body.add_child(_head)
	_head.add_child(Mats.mesh_instance(Geo.merge([
		[Geo.blob(Vector3(0.75, 0.68, 0.75), fur, 0.04, 104, 10, 12), Transform3D()],
		[Geo.blob(Vector3(0.55, 0.38, 0.45), light, 0.03, 105, 8, 10), Transform3D(Basis(), Vector3(0, -0.22, -0.55))],
		[Geo.sphere(0.07, G.INK, 6, 4), Transform3D(Basis(), Vector3(0.17, -0.12, -0.98))],
		[Geo.sphere(0.07, G.INK, 6, 4), Transform3D(Basis(), Vector3(-0.17, -0.12, -0.98))],
		[Geo.blob(Vector3(0.3, 0.14, 0.12), fur.darkened(0.1), 0.05, 106, 4, 8), Transform3D(Basis(Vector3.FORWARD, 0.6), Vector3(0.7, 0.35, 0.1))],
		[Geo.blob(Vector3(0.3, 0.14, 0.12), fur.darkened(0.1), 0.05, 107, 4, 8), Transform3D(Basis(Vector3.FORWARD, -0.6), Vector3(-0.7, 0.35, 0.1))],
	])))
	for sx in [-1.0, 1.0]:
		# big shiny calf eyes
		var eye := Mats.mesh_instance(Geo.merge([
			[Geo.sphere(0.24, G.PAPER, 10, 8), Transform3D()],
			[Geo.sphere(0.15, G.INK, 8, 6), Transform3D(Basis(), Vector3(0, -0.02, -0.14))],
			[Geo.sphere(0.05, G.PAPER, 4, 3), Transform3D(Basis(), Vector3(0.05, 0.05, -0.27))],
		]))
		eye.position = Vector3(sx * 0.38, 0.18, -0.55)
		_head.add_child(eye)
	var leg_mesh := Geo.merge([
		[Geo.cylinder(0.2, 0.24, 1.1, fur.darkened(0.05), 7), Transform3D(Basis(), Vector3(0, -0.55, 0))],
		[Geo.blob(Vector3(0.28, 0.14, 0.34), G.BARK, 0.05, 108, 4, 8), Transform3D(Basis(), Vector3(0, -1.1, -0.04))],
	])
	for k in 4:
		var leg := Node3D.new()
		leg.position = Vector3((-0.55 if k % 2 == 0 else 0.55), 1.25, (-0.85 if k < 2 else 0.85))
		_body.add_child(leg)
		leg.add_child(Mats.mesh_instance(leg_mesh))
		_legs.append(leg)
	_tail = Node3D.new()
	_tail.position = Vector3(0, 1.95, 1.4)
	_body.add_child(_tail)
	_tail.add_child(Mats.mesh_instance(Geo.merge([
		[Geo.cylinder(0.06, 0.1, 0.7, fur, 5), Transform3D(Basis(Vector3.RIGHT, 0.9), Vector3(0, -0.15, 0.28))],
		[Geo.blob(Vector3(0.18, 0.15, 0.22), BeastBuild.fur_dark, 0.2, 109, 5, 6), Transform3D(Basis(), Vector3(0, -0.4, 0.55))],
	])))

func set_remote(p: Vector3, yaw: float, st: int, spd: float) -> void:
	_target_pos = p
	_target_yaw = yaw
	state = st
	speed = spd

func _process(dt: float) -> void:
	if _body == null:
		return
	if game and not game.multiplayer.is_server():
		global_position = global_position.lerp(_target_pos, G.damp(8.0, dt))
		rotation.y = lerp_angle(rotation.y, _target_yaw, G.damp(8.0, dt))
	_phase += dt * (2.0 + speed * 2.4)
	var walk := clampf(speed / 3.0, 0.0, 1.0)
	for k in 4:
		var ph := _phase + (PI if k == 1 or k == 2 else 0.0)
		_legs[k].rotation.x = sin(ph) * 0.55 * walk
	_body.position.y = absf(sin(_phase)) * 0.12 * walk
	var t := Time.get_ticks_msec() * 0.001
	_head.rotation.x = sin(_phase * 2.0) * 0.05 * walk + (sin(t * 1.3) * 0.15 - 0.1 if state == S.LOST else 0.0)
	_head.rotation.y = sin(t * 0.7) * (0.5 if state == S.LOST else 0.1)
	_tail.rotation.y = sin(t * (9.0 if state == S.JOINED else 3.0)) * (0.6 if state == S.JOINED else 0.25)
	if state == S.LOST:
		_body.rotation.x = lerpf(_body.rotation.x, 0.0, G.damp(4.0, dt))

# ---------------------------------------------------------------- server brain
func server_tick(dt: float) -> void:
	var b := game.beast
	var goal := global_position
	var want_speed := 0.0
	match state:
		S.LOST:
			_bleat -= dt
			if _bleat <= 0.0:
				_bleat = randf_range(5.0, 8.0)
				game.mosslet_bleat(global_position)
			if global_position.distance_to(b.ground_pos) < 34.0:
				_join()
		S.FOLLOW:
			var p := game.get_player(leader)
			if p == null:
				state = S.LOST
				return
			var to := p.global_position - global_position
			to.y = 0
			if to.length() > 4.0:
				goal = p.global_position - to.normalized() * 3.0
				want_speed = clampf(to.length() * 0.6, 1.5, 5.5)
			if to.length() > 28.0:
				_lonely += dt
				if _lonely > 10.0:
					state = S.LOST
					game.mosslet_lost(leader)
			else:
				_lonely = 0.0
			var leader_aboard := p.global_position.y > b.ground_pos.y + 8.0 and Vector2(p.global_position.x - b.ground_pos.x, p.global_position.z - b.ground_pos.z).length() < 16.0
			if global_position.distance_to(b.ground_pos) < 34.0 or (leader_aboard and global_position.distance_to(b.ground_pos) < 50.0):
				_join()
		S.JOINED:
			# trot alongside the big one's flank
			goal = b.body_xf * Vector3(_side * 13.5, 0, 3.0)
			var d := Vector2(goal.x - global_position.x, goal.z - global_position.z).length()
			want_speed = clampf(b.speed + d * 0.5, 0.0, 6.5)
	var to_goal := goal - global_position
	to_goal.y = 0
	speed = move_toward(speed, want_speed if to_goal.length() > 0.6 else 0.0, dt * 4.0)
	if to_goal.length() > 0.3 and speed > 0.05:
		var dir := to_goal.normalized()
		global_position += dir * minf(speed * dt, to_goal.length())
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), G.damp(5.0, dt))
	elif state == S.JOINED:
		rotation.y = lerp_angle(rotation.y, b.yaw, G.damp(2.0, dt))
	var h := game.world.terrain.height(global_position.x, global_position.z)
	global_position.y = maxf(h, Terrain.WATER_LEVEL - 1.6)   # it paddles across water

## Server: a tune or whistle from this Tender, from here.
func coax(peer: int, from: Vector3) -> void:
	if state == S.JOINED or from.distance_to(global_position) > 16.0:
		return
	if state == S.LOST or leader != peer:
		leader = peer
		state = S.FOLLOW
		_lonely = 0.0
		game.mosslet_follows(peer)

func _join() -> void:
	state = S.JOINED
	var lp := game.beast.body_xf.affine_inverse() * global_position
	_side = 1.0 if lp.x >= 0.0 else -1.0
	game.mosslet_joined(leader)
