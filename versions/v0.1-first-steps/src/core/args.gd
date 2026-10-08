class_name Shot
## Command-line screenshot helper: --shot=<path> [--shot-frames=N]

static func arg(name: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=", true, 1)[1]
		if a == "--%s" % name:
			return "1"
	return def

static func maybe_capture(tree: SceneTree) -> void:
	var path := arg("shot")
	if path == "":
		return
	var frames := int(arg("shot-frames", "30"))
	for i in frames:
		await tree.process_frame
	await RenderingServer.frame_post_draw
	tree.root.get_viewport().get_texture().get_image().save_png(path)
	print("SHOT saved ", path)
	tree.quit()
