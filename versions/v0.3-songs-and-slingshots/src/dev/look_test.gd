extends Node3D
## Look-dev: world + sky + post, camera at a vantage point.

func _ready() -> void:
	var sky := SkyEnv.new()
	add_child(sky)
	sky.time_of_day = float(Args.arg("tod", "0.36"))
	sky.apply()
	var world := World.new()
	add_child(world)
	world.setup(int(Args.arg("seed", "7")))
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 70
	cam.far = 1500
	var p := Vector3(float(Args.arg("x", "20")), 0, float(Args.arg("z", "20")))
	p.y = world.terrain.height(p.x, p.z) + float(Args.arg("h", "14"))
	cam.position = p
	cam.rotation_degrees = Vector3(float(Args.arg("pitch", "-12")), float(Args.arg("yaw", "30")), 0)
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
	if Args.arg("beast") != "":
		var b := Beast.new()
		add_child(b)
		var bp := p + Vector3(fwd.x, 0, fwd.z).normalized() * float(Args.arg("bdist", "45"))
		b.setup(world, bp, deg_to_rad(float(Args.arg("byaw", "70"))))
		b.lure_down = float(Args.arg("lure", "1.0"))
		b.lure_yaw = 0.3
		b.speed = 3.0
		b.act = Beast.Act.WALK
	if Args.arg("props") != "":
		# prop line-up in front of the camera: flinger + every keepsake
		var base := p + Vector3(fwd.x, 0, fwd.z).normalized() * 7.0
		base.y = world.terrain.height(base.x, base.z) + 1.4
		var right := cam.global_transform.basis.x
		var fp := PropsLib.flinger_parts()
		var fl := Node3D.new()
		add_child(fl)
		fl.position = base - right * 2.5
		fl.rotation.y = cam.rotation.y + 1.2
		fl.add_child(Mats.mesh_instance(fp.base))
		var arm := Node3D.new()
		arm.position = PropsLib.FL_AXLE
		arm.rotation.x = -float(Args.arg("arm", "0"))
		fl.add_child(arm)
		arm.add_child(Mats.mesh_instance(fp.arm))
		var i := 0
		for k in PropsLib.KEEPSAKES:
			var mi := Mats.mesh_instance(PropsLib.get_mesh(k))
			add_child(mi)
			mi.position = base + right * (1.2 + (i % 3) * 0.9) + Vector3(0, 1.0 - (i / 3) * 0.9, 0) - fwd * 3.0
			mi.scale = Vector3.ONE * 1.5
			i += 1
	if Args.arg("nopost") == "":
		var pm := PostFX.attach(cam)
		pm.set_shader_parameter("debug_mode", int(Args.arg("dbg", "0")))
	Args.maybe_capture(get_tree())
