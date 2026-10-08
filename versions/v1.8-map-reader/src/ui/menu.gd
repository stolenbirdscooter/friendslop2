class_name Menu
extends Node3D
## Title screen: a Mossback ambles through the meadow behind a paper card.

var main: Node
var world: World
var sky: SkyEnv
var beast: Beast
var cam: Camera3D
var ui: Control
var status: Label
var name_edit: LineEdit
var ip_edit: LineEdit
var lan_box: VBoxContainer
var swatches: HBoxContainer
var hat_btn: Button
var preview: TenderVisual
var _wave_t := 4.0
var _t := 0.0
var _lan_t := 0.0

func _ready() -> void:
	sky = SkyEnv.new()
	add_child(sky)
	sky.time_of_day = 0.31
	sky.apply()
	world = World.new()
	add_child(world)
	world.setup(1234)
	beast = Beast.new()
	add_child(beast)
	var start := Vector3(40, 0, 40)
	beast.setup(world, start, 0.8)
	beast.lure_down = 1.0
	world.focus = start
	world.warm_up()
	cam = Camera3D.new()
	cam.fov = 55
	cam.far = 1600
	add_child(cam)
	cam.current = true
	PostFX.attach(cam)
	# your Tender, standing beside the card, dressed as chosen
	preview = TenderVisual.new()
	cam.add_child(preview)
	preview.position = Vector3(-0.42, -0.95, -3.3)
	preview.rotation = Vector3(0.1, PI + 0.35, 0)
	_rebuild_preview()
	_build_ui()
	Net.listen_lan(true)
	Sfx.set_ambience(0.5, 0.0)
	Music.set_mood("dawn")

func _exit_tree() -> void:
	Net.listen_lan(false)

func _rebuild_preview() -> void:
	if preview:
		preview.build(G.crew_color(G.player_color_idx), G.player_hat)
		preview.grounded = true

func _process(dt: float) -> void:
	_t += dt
	if preview:
		_wave_t -= dt
		if _wave_t <= 0.0:
			_wave_t = randf_range(5.0, 9.0)
			preview.waving = 1.6
		preview.look_dir = -cam.global_transform.basis.z
		preview.rotation.y = PI + 0.35 + sin(_t * 0.6) * 0.12
	beast.lure_yaw = sin(_t * 0.05) * 0.25
	var target := beast.body_xf.origin + Vector3(0, 10, 0)
	var a := _t * 0.035 + 2.2
	var p := target + Vector3(cos(a) * 62.0, 0, sin(a) * 62.0)
	p.y = maxf(world.terrain.height(p.x, p.z) + 4.0, target.y - 6.0)
	cam.global_position = p
	cam.look_at(target + Vector3(0, 2, 0) + Vector3(cos(a + 1.57), 0, sin(a + 1.57)) * 18.0)
	world.focus = beast.ground_pos
	_lan_t -= dt
	if _lan_t <= 0.0:
		_lan_t = 1.0
		_refresh_lan()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.theme = Ui.theme()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	var title := Ui.label("Mossback", 112, G.PAPER, true)
	title.position = Vector2(64, 36)
	title.add_theme_color_override("font_outline_color", G.INK)
	title.add_theme_constant_override("outline_size", 22)
	ui.add_child(title)
	var sub := Ui.label("a co-op game about walking a very large friend", 24, G.PAPER)
	sub.position = Vector2(72, 172)
	sub.add_theme_color_override("font_outline_color", G.INK)
	sub.add_theme_constant_override("outline_size", 8)
	ui.add_child(sub)
	var al: Dictionary = G.almanac
	if int(al.runs) > 0:
		var lines := "%d migration%s walked · %d reached the hollow%s · %d keepsake%s brought home" % [int(al.runs), "" if int(al.runs) == 1 else "s", int(al.won), (" (best: %d days)" % int(al.best_days)) if int(al.best_days) > 0 else "", int(al.keepsakes), "" if int(al.keepsakes) == 1 else "s"]
		if int(al.favourite_of) > 0:
			lines += " · favourite of %d beast%s" % [int(al.favourite_of), "" if int(al.favourite_of) == 1 else "s"]
		if int(al.calves) > 0:
			lines += " · %d calf%s brought home" % [int(al.calves), "" if int(al.calves) == 1 else "s"]
		var alm := Ui.label(lines, 17, G.PAPER)
		alm.position = Vector2(72, 204)
		alm.add_theme_color_override("font_outline_color", G.INK)
		alm.add_theme_constant_override("outline_size", 6)
		ui.add_child(alm)
		if String(al.last_line) != "":
			var last := Ui.label("Last time, with %s: \"%s\"" % [al.last_beast, al.last_line], 16, G.BUTTER)
			last.position = Vector2(72, 226)
			last.add_theme_color_override("font_outline_color", G.INK)
			last.add_theme_constant_override("outline_size", 6)
			ui.add_child(last)
	var card := Ui.panel()
	card.position = Vector2(64, 262)
	card.custom_minimum_size = Vector2(430, 0)
	ui.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	v.add_child(Ui.label("Your Tender", 26, G.INK, true))
	name_edit = LineEdit.new()
	name_edit.text = G.player_name
	name_edit.max_length = 16
	name_edit.text_changed.connect(func(t: String) -> void: G.player_name = t if t.strip_edges() != "" else "Tender")
	name_edit.focus_exited.connect(G.save_prefs)
	v.add_child(name_edit)
	swatches = HBoxContainer.new()
	swatches.add_theme_constant_override("separation", 6)
	v.add_child(swatches)
	for i in G.CREW_COLORS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(40, 34)
		var sb := StyleBoxFlat.new()
		sb.bg_color = G.CREW_COLORS[i]
		sb.border_color = G.INK
		sb.set_border_width_all(2)
		b.add_theme_stylebox_override("normal", sb)
		var sbh := sb.duplicate()
		sbh.set_border_width_all(4)
		b.add_theme_stylebox_override("hover", sbh)
		b.add_theme_stylebox_override("pressed", sbh)
		b.add_theme_stylebox_override("focus", sbh)
		b.pressed.connect(func() -> void:
			G.player_color_idx = i
			G.save_prefs()
			_rebuild_preview()
			Sfx.play("ui_click")
			_mark_swatch())
		swatches.add_child(b)
	_mark_swatch()
	hat_btn = Ui.button("")
	hat_btn.pressed.connect(func() -> void:
		var hats := G.available_hats()
		var i := hats.find(G.player_hat)
		G.player_hat = hats[(i + 1) % hats.size()]
		G.save_prefs()
		_rebuild_preview()
		Sfx.play("hat_pop")
		_update_hat_btn())
	v.add_child(hat_btn)
	_update_hat_btn()
	v.add_child(HSeparator.new())
	var solo := Ui.button("Wander alone")
	solo.pressed.connect(func() -> void: main.play_solo())
	v.add_child(solo)
	var host := Ui.button("Host a crew")
	host.pressed.connect(func() -> void: main.host_game())
	v.add_child(host)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "host address, e.g. 192.168.1.20"
	ip_edit.text = "127.0.0.1"
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ip_edit)
	var join := Ui.button("Join")
	join.pressed.connect(func() -> void: main.join_game(ip_edit.text.strip_edges()))
	row.add_child(join)
	v.add_child(row)
	lan_box = VBoxContainer.new()
	v.add_child(lan_box)
	status = Ui.label("", 16, G.TERRACOTTA)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(380, 0)
	v.add_child(status)
	var settings := Ui.button("Settings")
	var box := Ui.settings_box()
	box.visible = false
	settings.pressed.connect(func() -> void:
		box.visible = not box.visible
		Sfx.play("ui_click"))
	v.add_child(settings)
	v.add_child(box)
	var quit := Ui.button("Go home")
	quit.pressed.connect(func() -> void: get_tree().quit())
	v.add_child(quit)
	var help := Ui.label("WASD walk · SPACE hop · SHIFT dash · E use · LMB grab · hold RMB throw · Q whistle · F wave · hold R flop · 1-8 kalimba · G ping · P postcard · T talk (if push-to-talk)", 15, G.PAPER)
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help.position = Vector2(64, -44)
	help.add_theme_color_override("font_outline_color", G.INK)
	help.add_theme_constant_override("outline_size", 6)
	ui.add_child(help)

func _mark_swatch() -> void:
	for i in swatches.get_child_count():
		var b: Button = swatches.get_child(i)
		b.text = "•" if i == G.player_color_idx else ""
		b.add_theme_color_override("font_color", G.INK)

func _update_hat_btn() -> void:
	var earned := G.unlocked_hats.size()
	hat_btn.text = "Hat: %s%s" % [G.HAT_NAMES.get(G.player_hat, G.player_hat), "   (%d/%d keepsake hats)" % [earned, G.KEEPSAKE_HATS.size()] if earned > 0 else ""]

func _refresh_lan() -> void:
	for c in lan_box.get_children():
		c.queue_free()
	for ip in Net.lan_hosts:
		var h: Dictionary = Net.lan_hosts[ip]
		var b := Ui.button("Join %s's crew (%d aboard) — %s" % [h.name, h.crew, ip])
		b.pressed.connect(func() -> void: main.join_game(ip))
		lan_box.add_child(b)

func show_error(text: String) -> void:
	if status:
		status.text = text
		status.add_theme_color_override("font_color", G.TERRACOTTA)

func show_status(text: String) -> void:
	if status:
		status.text = text
		status.add_theme_color_override("font_color", G.TEAL)
