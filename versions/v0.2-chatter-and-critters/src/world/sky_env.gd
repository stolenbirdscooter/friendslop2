class_name SkyEnv
extends Node3D
## Environment, sun and the day cycle. `time_of_day`: 0 midnight, .25 sunrise, .5 noon, .75 sunset.

var env: Environment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var time_of_day := 0.3
var post: ShaderMaterial  # set by Game, gets flash etc.
var mist := 0.0

# keyframes: [t, sky_top, horizon, sun_col, sun_energy, ambient, amb_energy, cloud, cloud_shadow]
var _keys := [
	[0.00, Color("1d2342"), Color("3b3d64"), Color("8e9ad0"), 0.25, Color("2e3366"), 0.9, Color("4a4e78"), Color("2c2f52")],
	[0.20, Color("2c3560"), Color("6a5a7e"), Color("c0a0c0"), 0.25, Color("3d3a6a"), 0.9, Color("7a6a8e"), Color("4a4366")],
	[0.26, Color("8ea4c6"), Color("f2b48a"), Color("ffc896"), 1.1, Color("77749a"), 1.0, Color("fbe0c8"), Color("c99aa8")],
	[0.34, Color("6fa7c6"), Color("efe2c6"), Color("fff0d4"), 1.35, Color("737a9e"), 0.95, Color("fdf8ee"), Color("c6c8da")],
	[0.50, Color("6aa6c8"), Color("eee6d0"), Color("fff6e2"), 1.4, Color("78809f"), 0.95, Color("fefbf3"), Color("c8cbdc")],
	[0.66, Color("7d9cc4"), Color("f4d2a0"), Color("ffe0ac"), 1.3, Color("767399"), 0.95, Color("fdf0dc"), Color("cdbcc8")],
	[0.74, Color("5d6194"), Color("ee9a7a"), Color("ffa27c"), 0.75, Color("5d5185"), 0.95, Color("f7c0a0"), Color("9a7d9c")],
	[0.80, Color("2c3462"), Color("6b5578"), Color("c09ab4"), 0.3, Color("3b3868"), 0.9, Color("6e5e82"), Color("403a5e")],
	[1.00, Color("1d2342"), Color("3b3d64"), Color("8e9ad0"), 0.25, Color("2e3366"), 0.9, Color("4a4e78"), Color("2c2f52")],
]

func _ready() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 90.0
	env.fog_depth_end = 520.0
	env.fog_depth_curve = 1.4
	env.fog_sky_affect = 0.0
	env.fog_density = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 140.0
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	apply()

func _sample(t: float) -> Array:
	for i in _keys.size() - 1:
		var a: Array = _keys[i]
		var b: Array = _keys[i + 1]
		if t >= a[0] and t <= b[0]:
			var k: float = (t - a[0]) / maxf(b[0] - a[0], 0.0001)
			k = k * k * (3.0 - 2.0 * k)
			var out := [t]
			for j in range(1, a.size()):
				if a[j] is Color:
					out.append((a[j] as Color).lerp(b[j], k))
				else:
					out.append(lerpf(a[j], b[j], k))
			return out
	return _keys[0]

func apply() -> void:
	var s := _sample(fposmod(time_of_day, 1.0))
	var top: Color = s[1]
	var hor: Color = s[2]
	var sun_c: Color = s[3]
	var ang := (time_of_day - 0.25) * TAU
	var elev := sin(ang)
	# stylised: the sun never skims the horizon during play, so the crew stays readable
	var sun_dir := Vector3(cos(ang) * 0.75, 0.42 + maxf(elev, 0.0) * 0.6, 0.45).normalized()
	var is_night := elev < -0.05
	if is_night:
		# moonlight from a fixed high angle so the world stays readable
		sun_dir = Vector3(-0.35, 0.75, -0.55).normalized()
	sun.look_at_from_position(sun_dir * 100.0, Vector3.ZERO, Vector3.UP)
	sun.light_color = sun_c
	sun.light_energy = s[4]
	env.ambient_light_color = s[5]
	env.ambient_light_energy = s[6]
	env.fog_light_color = hor.lerp(top, 0.35).lerp(Color("e9e6dc"), mist * 0.7)
	env.fog_depth_begin = lerpf(90.0, 8.0, mist)
	env.fog_depth_end = lerpf(520.0, 150.0, mist)
	env.fog_sky_affect = mist * 0.85
	sky_mat.set_shader_parameter("top_color", top)
	sky_mat.set_shader_parameter("horizon_color", hor)
	sky_mat.set_shader_parameter("ground_color", hor.darkened(0.12))
	sky_mat.set_shader_parameter("sun_color", sun_c.lightened(0.3))
	sky_mat.set_shader_parameter("cloud_color", s[7])
	sky_mat.set_shader_parameter("cloud_shadow", s[8])
	var night_k := clampf(-elev * 4.0, 0.0, 1.0)
	sky_mat.set_shader_parameter("stars", night_k)
	sky_mat.set_shader_parameter("sun_size", 1.0 if is_night else 0.9994)

func night_amount() -> float:
	var elev := sin((time_of_day - 0.25) * TAU)
	return clampf(-elev * 3.0 + 0.2, 0.0, 1.0)
