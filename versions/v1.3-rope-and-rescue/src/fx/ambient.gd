class_name Ambient
extends Node3D
## Weather you can see: per-biome drifting things around the camera, all opaque so the ink
## pass sees them. Pollen in the meadows, seed fluff on the steppe, leaves in the ember woods,
## snow in the wintering hollow, and fireflies whenever dusk comes on. Gusts shove the lot.

const BOX := Vector3(70, 26, 70)

var game: Game
var _kinds := {}   # name -> {node, pm, base_gravity}
var _wind := Vector3.ZERO

func setup(p_game: Game) -> void:
	game = p_game
	_add("pollen", 260, 9.0, Geo.sphere(0.05, G.BUTTER, 4, 3), Vector3(0.15, 0.12, 0.05), 0.25, 0.5, Vector3(0.0, 0.2, 0.0), 0.0, 0.0)
	_add("fluff", 220, 8.0, _fluff_mesh(), Vector3(1.6, 0.25, 0.4), 0.6, 1.4, Vector3(0.8, -0.05, 0.25), 1.5, 1.0)
	_add("leaves", 320, 10.0, _leaf_mesh(), Vector3(0.3, -0.9, 0.15), 0.5, 1.2, Vector3(0.4, -0.55, 0.1), 4.0, 1.2)
	_add("snow", 1100, 11.0, _flake_mesh(), Vector3(0.2, -1.4, 0.1), 0.3, 0.6, Vector3(0.15, -0.9, 0.05), 2.0, 0.8)
	_add("fireflies", 90, 7.0, Geo.sphere(0.06, Color.WHITE, 5, 4), Vector3(0, 0.05, 0), 0.2, 0.6, Vector3.ZERO, 0.0, 0.0, true)

func _add(kind: String, amount: int, life: float, mesh: Mesh, vel: Vector3, vmin: float, vmax: float, grav: Vector3, spin: float, turb: float, glow := false) -> void:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.amount_ratio = 0.0
	p.local_coords = false
	p.visibility_aabb = AABB(-BOX, BOX * 2.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = BOX * 0.5
	pm.direction = vel.normalized() if vel.length() > 0.0 else Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = vmin
	pm.initial_velocity_max = vmax
	pm.gravity = grav
	pm.angular_velocity_min = -spin * 60.0
	pm.angular_velocity_max = spin * 60.0
	pm.particle_flag_rotate_y = spin > 0.0
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	if turb > 0.0:
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = turb
		pm.turbulence_noise_scale = 6.0
		pm.turbulence_influence_min = 0.05
		pm.turbulence_influence_max = 0.15
	if glow:
		# fireflies wander and blink (scale curve pulses them in and out)
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 2.0
		pm.turbulence_noise_scale = 3.0
		pm.turbulence_influence_min = 0.3
		pm.turbulence_influence_max = 0.5
		var c := Curve.new()
		for k in 9:
			c.add_point(Vector2(k / 8.0, 1.0 if k % 2 == 1 else 0.15))
		var ct := CurveTexture.new()
		ct.curve = c
		pm.scale_curve = ct
		pm.emission_box_extents = Vector3(BOX.x * 0.5, 3.0, BOX.z * 0.5)
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.material_override = _mote_mat(G.BUTTER, 2.2) if glow else _mote_mat(Color.WHITE, 0.55)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	_kinds[kind] = {"node": p, "pm": pm, "grav": grav}

## Bright, un-inked material for tiny drifting things (ink outlines turn them into specks).
static func _mote_mat(albedo: Color, emission: float) -> ShaderMaterial:
	var m := Mats.toon(albedo, false, 0.3).duplicate() as ShaderMaterial
	m.set_shader_parameter("emission_strength", emission)
	return m

## A cut-paper snowflake: six flat arms with little side-barbs.
static func _flake_mesh() -> Mesh:
	var parts: Array = []
	for k in 6:
		var b := Basis(Vector3.FORWARD, TAU * k / 6.0)
		parts.append([Geo.box(Vector3(0.022, 0.13, 0.006), G.PAPER), Transform3D(b, b * Vector3(0, 0.065, 0))])
		for sx in [-1.0, 1.0]:
			var bb := b * Basis(Vector3.FORWARD, sx * 0.7)
			parts.append([Geo.box(Vector3(0.016, 0.045, 0.006), G.PAPER), Transform3D(bb, b * Vector3(0, 0.08, 0) + bb * Vector3(0, 0.02, 0))])
	return Geo.merge(parts)

static func _leaf_mesh() -> Mesh:
	var parts: Array = []
	for k in 4:
		var col: Color = [G.TERRACOTTA, G.MARIGOLD, G.ROSE.darkened(0.2), G.BUTTER][k]
		# each particle is a little flurry of four differently coloured leaves
		parts.append([Geo.blob(Vector3(0.12, 0.012, 0.07), col, 0.1, 90 + k, 3, 6), Transform3D(Basis(Vector3.UP, k * 1.3) * Basis(Vector3.RIGHT, k * 0.7), Vector3(cos(k * 1.7) * 0.6, k * 0.35, sin(k * 1.7) * 0.6))])
	return Geo.merge(parts)

static func _fluff_mesh() -> Mesh:
	var parts: Array = [[Geo.sphere(0.04, G.PAPER_DARK, 4, 3), Transform3D()]]
	for k in 6:
		var a := TAU * k / 6.0
		parts.append([Geo.cylinder(0.006, 0.006, 0.14, G.PAPER, 3), Transform3D(Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.RIGHT, a), Vector3(cos(a) * 0.06, sin(a) * 0.06, 0))])
	return Geo.merge(parts)

func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set("gale", Vector3.ZERO)

func _process(dt: float) -> void:
	if game == null or game.local_player == null or game.local_player.camera == null:
		return
	var cam := game.local_player.camera
	global_position = cam.global_position + Vector3(0, 4.0, 0)
	var t := game.world.terrain
	var b := t.biome_at(cam.global_position.x, cam.global_position.z)
	var weights := [0.0, 0.0, 0.0, 0.0, 0.0]
	weights[b[0]] += 1.0 - float(b[2])
	weights[b[1]] += float(b[2])
	var dusk := clampf(game.sky.night_amount() * 1.6, 0.0, 1.0)
	var want := {
		"pollen": (weights[0] * 0.8 + weights[2] * 0.4) * (1.0 - dusk),
		"fluff": weights[1] * 0.9,
		"leaves": weights[3] * 0.9,
		"snow": weights[4] * 1.0,
		"fireflies": dusk * (1.0 - weights[4]),
	}
	if game.weather == "mist":
		want.pollen *= 0.4
	# gusts and gale days push everything downwind
	var gusting := game.gust_warning() >= 1.0
	var wind_target := game.gust_dir * (9.0 if gusting else (2.5 if game.weather == "gale" else 0.0))
	_wind = _wind.lerp(wind_target, G.damp(2.0, dt))
	RenderingServer.global_shader_parameter_set("gale", _wind * 0.06)
	for k in _kinds:
		var d: Dictionary = _kinds[k]
		var node: GPUParticles3D = d.node
		node.amount_ratio = move_toward(node.amount_ratio, clampf(want[k], 0.0, 1.0), dt * 0.25)
		node.emitting = node.amount_ratio > 0.01
		(d.pm as ParticleProcessMaterial).gravity = (d.grav as Vector3) + _wind
