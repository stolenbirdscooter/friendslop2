class_name Magpie
extends Node3D
## A thieving magpie. The server flies it (Game owns spawning and loot); everyone else interpolates.
## It swoops on hats, keepsakes and fruit on the beast's back and carries them to a nest tree.

enum S { ARRIVE, SWOOP, ESCAPE, PERCH, FLEE }

const SCALE := 1.6

var id := 0
var game: Game
var state: int = S.ARRIVE
var t := 0.0
var vel := Vector3.ZERO
var target_peer := 0
var target_prop := 0
var loot := {}           # server: {"kind": "hat", "peer": id} or {"kind": "prop", "id": n}
var nest_key := ""
var nest_pos := Vector3.ZERO
var _orbit := randf() * TAU
var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _flap_t := randf() * 10.0
var _chatter := 2.0
var _body: Node3D
var _wings: Array[Node3D] = []
var _loot_node: Node3D

func build() -> void:
	_body = Node3D.new()
	_body.scale = Vector3.ONE * SCALE
	add_child(_body)
	_body.add_child(Mats.mesh_instance(PropsLib.get_mesh("magpie")))
	for side in [-1.0, 1.0]:
		var w := Node3D.new()
		w.position = Vector3(side * 0.12, 0.08, -0.05)
		_body.add_child(w)
		w.add_child(Mats.mesh_instance(PropsLib.get_mesh("magpie_wing:%d" % int(side))))
		_wings.append(w)
	_loot_node = Node3D.new()
	_loot_node.position = Vector3(0, -0.05, -0.5)
	_body.add_child(_loot_node)

func beak_global() -> Vector3:
	return global_transform * (Vector3(0, -0.15, -0.75) * SCALE)

func set_remote(p: Vector3, yaw: float, st: int) -> void:
	_target_pos = p
	_target_yaw = yaw
	state = st

## Show what it carries (hats are rebuilt from the owner's look, props from their mesh).
func show_loot(n: Node3D) -> void:
	clear_loot()
	if n:
		_loot_node.add_child(n)

func clear_loot() -> void:
	for c in _loot_node.get_children():
		c.queue_free()

func _process(dt: float) -> void:
	if _body == null:
		return
	if game and not game.multiplayer.is_server():
		global_position = global_position.lerp(_target_pos, G.damp(8.0, dt))
		rotation.y = lerp_angle(rotation.y, _target_yaw, G.damp(8.0, dt))
	_flap_t += dt
	var flying := state != S.PERCH
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var w := _wings[i]
		if flying:
			var beat := sin(_flap_t * (17.0 if state != S.ARRIVE else 11.0))
			w.rotation = Vector3(0, 0, -side * beat * 0.95)
			w.scale = Vector3.ONE
		else:
			w.rotation = Vector3(0, side * 0.5, side * 0.25)
			w.scale = Vector3(0.55, 1, 1)
	# a bob while perched, a cocky head tilt
	_body.position.y = absf(sin(_flap_t * 3.0)) * 0.05 if not flying else sin(_flap_t * 17.0) * 0.04
	_body.rotation.z = sin(_flap_t * 1.3) * (0.25 if not flying else 0.05)

# ---------------------------------------------------------------- server brain
func server_tick(dt: float) -> void:
	t += dt
	var b := game.beast
	var top := b.body_xf * Vector3(0, 19.0, 0)
	var goal := global_position
	var spd := 12.0
	match state:
		S.ARRIVE:
			_orbit += dt * 0.6
			goal = top + Vector3(cos(_orbit) * 11.0, 4.0 + sin(t * 1.7) * 1.5, sin(_orbit) * 11.0)
			if t > 3.0 and global_position.distance_to(top) < 20.0 and fmod(t, 1.0) < dt:
				_pick_target()
			if t > 25.0:
				flee()
		S.SWOOP:
			var tp := _target_point()
			if tp == Vector3.INF:
				state = S.ARRIVE
				t = 0.0
			else:
				goal = tp
				spd = 14.0
				if global_position.distance_to(tp) < 1.1:
					game.server_magpie_grab(self)
		S.ESCAPE:
			goal = nest_pos + Vector3(0, 0.6, 0)
			spd = 8.5   # laden: slow enough to chase and whistle at
			if global_position.distance_to(goal) < 1.2:
				game.server_magpie_nest(self)
				state = S.PERCH
				t = 0.0
		S.PERCH:
			goal = nest_pos + Vector3(0, 0.45, 0)
			spd = 3.0
			if t > 150.0:
				flee()
		S.FLEE:
			goal = global_position + Vector3(vel.x, 0, vel.z).normalized() * 10.0 + Vector3(0, 6, 0)
			spd = 15.0
			if t > 5.0:
				game.server_magpie_gone(self)
				return
	var to := goal - global_position
	var want := to.normalized() * minf(spd, to.length() * 3.0) if to.length() > 0.01 else Vector3.ZERO
	vel = vel.lerp(want, G.damp(3.5 if state != S.SWOOP else 5.0, dt))
	global_position += vel * dt
	var h := Vector2(vel.x, vel.z)
	if h.length() > 0.3:
		rotation.y = lerp_angle(rotation.y, atan2(-vel.x, -vel.z), G.damp(6.0, dt))
	_chatter -= dt
	if _chatter <= 0.0:
		_chatter = randf_range(3.0, 7.0) if state != S.PERCH else randf_range(6.0, 12.0)
		game.magpie_chatter(global_position)

func _pick_target() -> void:
	var cands: Array = []   # [weight, kind, id]
	var b := game.beast
	for p in game.players.values():
		if not p.visible or game.hat_stolen(p.peer_id) or b.in_hut(p.global_position):
			continue
		if String(Net.players.get(p.peer_id, {}).get("hat", "none")) == "none":
			continue
		if p.on_beast or p.beast_frame:
			cands.append([1.6, "hat", p.peer_id])
	for f in game.fruits.values():
		if f.held_by != 0 or f.pest:
			continue
		if f.global_position.distance_to(b.body_xf * Vector3(0, 16.0, 0)) < 16.0 and not b.in_hut(f.global_position):
			cands.append([2.2 if f.keepsake else 1.0, "prop", f.id])
	if cands.is_empty():
		return
	var total := 0.0
	for c in cands:
		total += c[0]
	var r := randf() * total
	for c in cands:
		r -= c[0]
		if r <= 0.0:
			if c[1] == "hat":
				target_peer = c[2]
				target_prop = 0
			else:
				target_prop = c[2]
				target_peer = 0
			state = S.SWOOP
			t = 0.0
			game.magpie_chatter(global_position)
			return

func _target_point() -> Vector3:
	if t > 10.0:
		return Vector3.INF   # gave up
	if target_peer != 0:
		var p: Player = game.get_player(target_peer)
		if p == null or not p.visible or game.hat_stolen(target_peer) or game.beast.in_hut(p.global_position):
			return Vector3.INF
		return p.global_position + Vector3(0, 1.75, 0) - (Basis(Vector3.UP, rotation.y) * Vector3(0, 0, -0.75 * SCALE))
	var f: Fruit = game.fruits.get(target_prop)
	if f == null or f.held_by != 0:
		return Vector3.INF
	return f.global_position + Vector3(0, 0.25, 0) - (Basis(Vector3.UP, rotation.y) * Vector3(0, 0, -0.75 * SCALE))

## Whistled at, bonked or crowded: drop everything and go.
func scare() -> bool:
	if state in [S.ARRIVE, S.SWOOP, S.ESCAPE]:
		game.server_magpie_drop(self)
		flee()
		return true
	return false

func flee() -> void:
	state = S.FLEE
	t = 0.0
	vel += Vector3(randf_range(-4, 4), 6.0, randf_range(-4, 4))
