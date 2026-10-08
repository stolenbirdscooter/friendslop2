extends Node3D
## Look-dev: world + sky + post, camera at a vantage point.

func _ready() -> void:
	var sky := SkyEnv.new()
	add_child(sky)
	sky.time_of_day = float(Shot.arg("tod", "0.36"))
	sky.apply()
	var world := World.new()
	add_child(world)
	world.setup(int(Shot.arg("seed", "7")))
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 70
	cam.far = 1500
	var p := Vector3(float(Shot.arg("x", "20")), 0, float(Shot.arg("z", "20")))
	p.y = world.terrain.height(p.x, p.z) + float(Shot.arg("h", "14"))
	cam.position = p
	cam.rotation_degrees = Vector3(float(Shot.arg("pitch", "-12")), float(Shot.arg("yaw", "30")), 0)
	world.focus = p
	world.warm_up()
	var m := MeshInstance3D.new()
	m.mesh = PropsLib.get_mesh("waystone")
	m.material_override = Mats.toon()
	add_child(m)
	var fwd := -cam.global_transform.basis.z
	var wp := p + Vector3(fwd.x, 0, fwd.z).normalized() * 70.0
	wp.y = world.terrain.height(wp.x, wp.z)
	m.position = wp
	if Shot.arg("beast") != "":
		var b := Beast.new()
		add_child(b)
		var bp := p + Vector3(fwd.x, 0, fwd.z).normalized() * float(Shot.arg("bdist", "45"))
		b.setup(world, bp, deg_to_rad(float(Shot.arg("byaw", "70"))))
		b.lure_down = float(Shot.arg("lure", "1.0"))
		b.lure_yaw = 0.3
		b.speed = 3.0
		b.act = Beast.Act.WALK
	if Shot.arg("nopost") == "":
		var pm := PostFX.attach(cam)
		pm.set_shader_parameter("debug_mode", int(Shot.arg("dbg", "0")))
	Shot.maybe_capture(get_tree())
