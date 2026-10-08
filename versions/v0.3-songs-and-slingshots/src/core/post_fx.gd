class_name PostFX
## Full-screen ink/paper pass, attached in front of a camera.

static func attach(cam: Camera3D) -> ShaderMaterial:
	var mi := MeshInstance3D.new()
	mi.name = "PostFX"
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/post.gdshader")
	m.render_priority = 127
	mi.material_override = m
	mi.extra_cull_margin = 16384.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 0, -1)
	cam.add_child(mi)
	return m
