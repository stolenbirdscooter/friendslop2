class_name Hud
extends CanvasLayer
## In-game overlay. Paper tags and ink, drawn mostly with _draw for a hand-made feel.

var game: Game
var root: Control
var canvas: Control
var hint_label: Label
var big_title: Label
var big_sub: Label
var toasts: VBoxContainer
var pause_panel: PanelContainer
var end_panel: PanelContainer
var _big_t := 0.0
var _pause_open := false
var _end_open := false

func _ready() -> void:
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Ui.theme()
	add_child(root)
	canvas = Control.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw_canvas)
	root.add_child(canvas)
	hint_label = Ui.label("", 20, G.PAPER)
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.position = Vector2(-400, -96)
	hint_label.size = Vector2(800, 30)
	hint_label.add_theme_color_override("font_outline_color", G.INK)
	hint_label.add_theme_constant_override("outline_size", 8)
	root.add_child(hint_label)
	big_title = Ui.label("", 64, G.PAPER, true)
	big_title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	big_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_title.position = Vector2(-700, 150)
	big_title.size = Vector2(1400, 80)
	big_title.add_theme_color_override("font_outline_color", G.INK)
	big_title.add_theme_constant_override("outline_size", 14)
	root.add_child(big_title)
	big_sub = Ui.label("", 24, G.PAPER)
	big_sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	big_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_sub.position = Vector2(-700, 236)
	big_sub.size = Vector2(1400, 40)
	big_sub.add_theme_color_override("font_outline_color", G.INK)
	big_sub.add_theme_constant_override("outline_size", 8)
	root.add_child(big_sub)
	toasts = VBoxContainer.new()
	toasts.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	toasts.position = Vector2(-420, 120)
	toasts.size = Vector2(390, 300)
	toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toasts)
	game.toast.connect(_on_toast)
	game.big_message.connect(_on_big)
	_build_pause()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func is_blocking() -> bool:
	return _pause_open or _end_open

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _end_open:
			return
		_set_pause(not _pause_open)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not is_blocking():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _set_pause(on: bool) -> void:
	_pause_open = on
	pause_panel.visible = on
	game.paused_menu = on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
	Sfx.play("ui_click")

func _build_pause() -> void:
	pause_panel = Ui.panel()
	pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.position = Vector2(-220, -210)
	pause_panel.custom_minimum_size = Vector2(440, 0)
	pause_panel.visible = false
	root.add_child(pause_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pause_panel.add_child(v)
	v.add_child(Ui.label("Resting a moment", 34, G.INK, true))
	var info := Ui.label("", 17, G.INK)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(400, 0)
	if Net.hosting and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		var ips := []
		for a in IP.get_local_addresses():
			if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254"):
				ips.append(a)
		info.text = "Friends join at  %s  (port %d). Over the internet you'll need to forward that port." % [", ".join(ips), Net.PORT]
	else:
		info.text = "Crew aboard: %d" % Net.players.size()
	v.add_child(info)
	var sens := HSlider.new()
	sens.min_value = 0.0005
	sens.max_value = 0.006
	sens.step = 0.0001
	sens.value = G.mouse_sens
	sens.value_changed.connect(func(x: float) -> void: G.mouse_sens = x)
	v.add_child(Ui.label("Look sensitivity", 16, G.INK))
	v.add_child(sens)
	var resume := Ui.button("Back to the beast")
	resume.pressed.connect(func() -> void: _set_pause(false))
	v.add_child(resume)
	var leave := Ui.button("Leave the migration")
	leave.pressed.connect(func() -> void:
		game.paused_menu = false
		game.main.leave_to_menu())
	v.add_child(leave)

func on_phase(p: int) -> void:
	if p == Game.Phase.WON or p == Game.Phase.LOST:
		get_tree().create_timer(4.0).timeout.connect(_show_end.bind(p == Game.Phase.WON))

func _show_end(won: bool) -> void:
	if end_panel:
		end_panel.queue_free()
	_end_open = true
	game.paused_menu = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	end_panel = Ui.panel()
	end_panel.set_anchors_preset(Control.PRESET_CENTER)
	end_panel.position = Vector2(-280, -230)
	end_panel.custom_minimum_size = Vector2(560, 0)
	root.add_child(end_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	end_panel.add_child(v)
	v.add_child(Ui.label("Wintering hollow, reached." if won else "Snowed in.", 40, G.INK, true))
	var s: Dictionary = game.stats
	var lines := [
		"Days on the road: %d" % game.day,
		"Distance walked: %d m" % int(s.distance),
		"Snacks fed: %d" % int(s.fed),
		"Sneezes survived: %d" % int(s.sneezes),
		"Crew swallowed: %d" % int(s.gulps),
	]
	for l in lines:
		v.add_child(Ui.label(l, 20, G.INK))
	if multiplayer.is_server():
		var again := Ui.button("Start a new migration")
		again.pressed.connect(func() -> void: game.request_new_migration())
		v.add_child(again)
	else:
		v.add_child(Ui.label("Waiting for the host to start another...", 16, G.STONE_DARK))
	var leave := Ui.button("Back to the menu")
	leave.pressed.connect(func() -> void: game.main.leave_to_menu())
	v.add_child(leave)

func _on_toast(text: String) -> void:
	var l := Ui.label(text, 19, G.INK)
	var p := Ui.panel(8)
	p.add_child(l)
	toasts.add_child(p)
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)
	while toasts.get_child_count() > 5:
		toasts.get_child(0).free()

func _on_big(title: String, sub: String) -> void:
	big_title.text = title
	big_sub.text = sub
	_big_t = 5.0

func _process(dt: float) -> void:
	if game == null or game.local_player == null:
		return
	_big_t -= dt
	var a := clampf(_big_t, 0.0, 1.0)
	big_title.modulate.a = a
	big_sub.modulate.a = a
	hint_label.text = game.interaction_hint(game.local_player) if not is_blocking() else ""
	canvas.queue_redraw()

# ---------------------------------------------------------------- drawing
func _draw_canvas() -> void:
	var lp := game.local_player
	if lp == null or lp.camera == null:
		return
	var vs := canvas.get_viewport_rect().size
	_draw_day_tag(Vector2(28, 24))
	_draw_compass(Vector2(vs.x * 0.5, 34), lp)
	_draw_belly(Vector2(36, vs.y - 120))
	_draw_name_tags(lp)
	if (lp.held_fruit != 0 or lp.carrying_peer != 0) and not is_blocking():
		var c := vs * 0.5
		var r := 5.0 + (lp.throw_charge * 14.0 if lp.throw_charge >= 0.0 else 0.0)
		canvas.draw_arc(c, r, 0, TAU, 24, G.PAPER, 2.5, true)
		canvas.draw_arc(c, r + 2.0, 0, TAU, 24, G.INK, 1.5, true)

func _tag(rect: Rect2) -> void:
	canvas.draw_rect(Rect2(rect.position + Vector2(3, 4), rect.size), Color(G.INK, 0.35))
	canvas.draw_rect(rect, Color(G.PAPER, 0.96))
	canvas.draw_rect(rect, G.INK, false, 2.0)

func _draw_day_tag(at: Vector2) -> void:
	var rect := Rect2(at, Vector2(250, 92))
	_tag(rect)
	var f := G.font_display
	canvas.draw_string(f, at + Vector2(16, 38), "Day %d" % game.day, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, G.INK)
	canvas.draw_string(G.font_body, at + Vector2(110, 36), "of %d" % Game.DAYS, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, G.STONE_DARK)
	canvas.draw_string(G.font_body, at + Vector2(16, 72), "Waystone %d of %d" % [mini(game.waystone_idx + 1, Game.WAYSTONES), Game.WAYSTONES], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, G.INK)
	# sun arc clock: dawn (left) to dusk (right)
	var c := at + Vector2(205, 64)
	var r := 30.0
	canvas.draw_arc(c, r, PI, TAU, 24, G.INK, 2.0, true)
	canvas.draw_line(c + Vector2(-r - 6, 0), c + Vector2(r + 6, 0), G.INK, 2.0)
	var k := clampf((game.time_of_day - Game.DAY_START) / (Game.DAY_END - Game.DAY_START), 0.0, 1.0)
	var ang := PI + k * PI
	var sp := c + Vector2(cos(ang), sin(ang)) * r
	canvas.draw_circle(sp, 7.0, G.MARIGOLD if k < 0.85 else G.TERRACOTTA)
	canvas.draw_arc(sp, 7.0, 0, TAU, 16, G.INK, 1.5, true)

func _draw_compass(center: Vector2, lp: Player) -> void:
	var w := 560.0
	var rect := Rect2(center - Vector2(w * 0.5, 18), Vector2(w, 36))
	_tag(rect)
	var yaw := lp.cam_yaw
	var marks := {"N": 0.0, "E": -PI * 0.5, "S": PI, "W": PI * 0.5}
	for k in marks:
		var d: float = wrapf(marks[k] - yaw, -PI, PI)
		if absf(d) < 1.3:
			var x := center.x - d / 1.3 * w * 0.5
			canvas.draw_string(G.font_bold, Vector2(x - 6, center.y + 7), k, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, G.STONE_DARK)
	for i in 24:
		var a := float(i) / 24.0 * TAU
		var d := wrapf(a - yaw, -PI, PI)
		if absf(d) < 1.3:
			var x := center.x - d / 1.3 * w * 0.5
			canvas.draw_line(Vector2(x, center.y + 10), Vector2(x, center.y + 15), G.STONE_DARK, 1.5)
	if game.waystone_idx < game.waystones.size():
		var wp := game.waystones[game.waystone_idx]
		_compass_marker(center, w, yaw, wp - lp.global_position, [G.MARIGOLD, G.ROSE, G.SKY, G.MINT][game.waystone_idx % 4], "%d m" % int(Vector2(wp.x - game.beast.ground_pos.x, wp.z - game.beast.ground_pos.z).length()))
	if not lp.on_beast and lp.global_position.distance_to(game.beast.ground_pos) > 25.0:
		_compass_marker(center, w, yaw, game.beast.ground_pos - lp.global_position, G.FUR, "beast")

func _compass_marker(center: Vector2, w: float, yaw: float, to: Vector3, col: Color, label: String) -> void:
	var a := atan2(-to.x, -to.z)
	var d := wrapf(a - yaw, -PI, PI)
	var x := center.x - clampf(d / 1.3, -1.0, 1.0) * w * 0.5
	var pts := PackedVector2Array([Vector2(x, center.y + 14), Vector2(x - 8, center.y - 2), Vector2(x + 8, center.y - 2)])
	canvas.draw_colored_polygon(pts, col)
	canvas.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), G.INK, 1.5, true)
	canvas.draw_string(G.font_bold, Vector2(x - 30, center.y + 40), label, HORIZONTAL_ALIGNMENT_CENTER, 60, 15, G.PAPER)

func _draw_belly(at: Vector2) -> void:
	var rect := Rect2(at, Vector2(280, 84))
	_tag(rect)
	var sat: float = game.beast.satiety
	canvas.draw_string(G.font_display, at + Vector2(14, 32), "Belly", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, G.INK)
	var mood := "content"
	if sat < 1.0:
		mood = "sulking. feed it!"
	elif sat < 25.0:
		mood = "rumbly"
	elif sat > 80.0:
		mood = "delighted"
	canvas.draw_string(G.font_body, at + Vector2(96, 30), mood, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, G.STONE_DARK)
	var bar := Rect2(at + Vector2(14, 46), Vector2(252, 22))
	canvas.draw_rect(bar, G.PAPER_DARK)
	var fill := Rect2(bar.position, Vector2(bar.size.x * sat / 100.0, bar.size.y))
	var col := G.MOSS if sat > 40.0 else (G.MARIGOLD if sat > 20.0 else G.TERRACOTTA)
	canvas.draw_rect(fill, col)
	# notches so the bar reads like a hand-ruled gauge
	for i in range(1, 10):
		var x := bar.position.x + bar.size.x * i / 10.0
		canvas.draw_line(Vector2(x, bar.position.y + 14), Vector2(x, bar.end.y), Color(G.INK, 0.5), 1.0)
	canvas.draw_rect(bar, G.INK, false, 2.0)

func _draw_name_tags(lp: Player) -> void:
	for p in game.players.values():
		if p == lp or not p.visible:
			continue
		var wp: Vector3 = p.global_position + Vector3(0, 1.9, 0)
		if lp.camera.is_position_behind(wp):
			continue
		var dist := lp.camera.global_position.distance_to(wp)
		if dist > 90.0:
			continue
		var sp := lp.camera.unproject_position(wp)
		var size := clampf(22.0 - dist * 0.12, 12.0, 20.0)
		var col := G.crew_color(p.color_idx)
		var tw := G.font_bold.get_string_size(p.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size)).x
		var r := Rect2(sp - Vector2(tw * 0.5 + 8, size + 4), Vector2(tw + 16, size + 10))
		canvas.draw_rect(r, Color(G.PAPER, 0.9))
		canvas.draw_rect(Rect2(r.position, Vector2(5, r.size.y)), col)
		canvas.draw_rect(r, G.INK, false, 1.5)
		canvas.draw_string(G.font_bold, Vector2(r.position.x + 10, r.end.y - 6), p.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size), G.INK)
