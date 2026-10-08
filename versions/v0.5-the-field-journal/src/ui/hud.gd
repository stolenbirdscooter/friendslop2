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
var coach: Label
var _coach_seen := {}
var _coach_t := 0.0
var _coach_key := ""
var _alive_t := 0.0
var _pause_journal: Label
var _postcard := false
var _kal_t := 0.0
var _kal_flash := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])

func kalimba_pressed(idx: int) -> void:
	_kal_t = 2.5
	_kal_flash[idx] = 1.0

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
	coach = Ui.label("", 19, G.INK)
	coach.set_anchors_preset(Control.PRESET_CENTER_TOP)
	coach.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coach.position = Vector2(-330, 98)
	coach.size = Vector2(660, 30)
	coach.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(coach)
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
	if event.is_action_pressed("postcard") and not is_blocking() and not _postcard:
		_take_postcard()
		return
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
	if on and _pause_journal:
		var lines: Array = []
		for e in game.journal.slice(maxi(game.journal.size() - 5, 0)):
			lines.append("Day %d: %s" % [e[0], e[1]])
		_pause_journal.text = "\n".join(lines) if not lines.is_empty() else "Nothing yet. Give it time."

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
	sens.drag_ended.connect(func(_c: bool) -> void: G.save_prefs())
	v.add_child(Ui.label("Look sensitivity", 16, G.INK))
	v.add_child(sens)
	var ptt := CheckBox.new()
	ptt.text = "Push-to-talk (hold T)"
	ptt.button_pressed = Voice.push_to_talk
	ptt.toggled.connect(func(on: bool) -> void: Voice.push_to_talk = on)
	v.add_child(ptt)
	var mute := CheckBox.new()
	mute.text = "Mute my microphone"
	mute.button_pressed = not Voice.enabled
	mute.toggled.connect(func(on: bool) -> void: Voice.enabled = not on)
	v.add_child(mute)
	v.add_child(Ui.label("Lately, in the journal", 18, G.TERRACOTTA, true))
	_pause_journal = Ui.label("", 15, G.STONE_DARK)
	_pause_journal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pause_journal.custom_minimum_size = Vector2(400, 0)
	v.add_child(_pause_journal)
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

const AWARDS := [
	["notes", "Beast Whisperer", "played it a single note", "played it %d notes"],
	["fed", "Snack Courier", "fed it once", "fed it %d times"],
	["flown", "Frequent Flyer", "flung off the back once", "flung off the back %d times"],
	["flings", "Head of Artillery", "fired the flinger once", "fired the flinger %d times"],
	["robbed", "Magpie's Favourite", "robbed by a magpie", "robbed %d times"],
	["shooed", "Scarecrow", "saw off a magpie", "saw off %d magpies"],
	["tossed", "Pest Control", "evicted a thistlemite", "evicted %d thistlemites"],
	["steer", "Helmsperson", "a minute on the lure", "%d minutes on the lure"],
	["gulped", "Lunch", "swallowed once", "swallowed %d times"],
	["keepsakes", "Collector", "brought home a keepsake", "brought home %d keepsakes"],
	["spots", "Eagle Eye", "spotted the smoke", "spotted the smoke %d times"],
]

## One commendation per category, best Tender wins; spread them so everyone gets mentioned.
func _commendations() -> Array:
	var out: Array = []
	var got := {}
	for a in AWARDS:
		var key: String = a[0]
		var best := 0
		var best_v := 0.0
		for peer in game.pstats:
			var v := float(game.pstats[peer].get(key, 0.0))
			if key == "steer":
				v /= 60.0
			if v > best_v + 0.001 or (absf(v - best_v) < 0.001 and v > 0.0 and got.get(peer, 0) < got.get(best, 0)):
				best_v = v
				best = peer
		if best != 0 and best_v >= (1.0 if key != "steer" else 0.5):
			var n := maxi(int(round(best_v)), 1)
			out.append([a[1], game.pstats[best], a[2] if n == 1 else a[3] % n, got.get(best, 0)])
			got[best] = got.get(best, 0) + 1
	out.sort_custom(func(x: Array, y: Array) -> bool: return x[3] < y[3])
	return out.slice(0, 6)

func _show_end(won: bool) -> void:
	if end_panel:
		end_panel.queue_free()
	_end_open = true
	game.paused_menu = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	end_panel = Ui.panel()
	end_panel.set_anchors_preset(Control.PRESET_CENTER)
	end_panel.position = Vector2(-540, -330)
	end_panel.custom_minimum_size = Vector2(1080, 0)
	root.add_child(end_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	end_panel.add_child(v)
	v.add_child(Ui.label("Wintering hollow, reached." if won else "Snowed in.", 40, G.INK, true))
	var spread := HBoxContainer.new()
	spread.add_theme_constant_override("separation", 28)
	v.add_child(spread)
	# left page: the journal
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(560, 0)
	left.add_theme_constant_override("separation", 4)
	spread.add_child(left)
	left.add_child(Ui.label("From the field journal", 22, G.TERRACOTTA, true))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var entries := VBoxContainer.new()
	entries.add_theme_constant_override("separation", 3)
	entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(entries)
	var last_day := -1
	for e in game.journal:
		if int(e[0]) != last_day:
			last_day = int(e[0])
			entries.add_child(Ui.label("Day %d" % last_day, 18, G.INK, true))
		var row := MarginContainer.new()
		row.add_theme_constant_override("margin_left", 18)
		var l := Ui.label(String(e[1]), 16, G.STONE_DARK)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(510, 0)
		row.add_child(l)
		entries.add_child(row)
	# right page: commendations
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(420, 0)
	right.add_theme_constant_override("separation", 6)
	spread.add_child(right)
	right.add_child(Ui.label("Commendations", 22, G.TERRACOTTA, true))
	var awards := _commendations()
	if awards.is_empty():
		right.add_child(Ui.label("Nobody did anything remarkable.\nThe Mossback did it all itself.", 16, G.STONE_DARK))
	for a in awards:
		var who: Dictionary = a[1]
		right.add_child(Ui.label(a[0], 20, G.INK, true))
		var row := Ui.label("    %s, %s" % [who.get("name", "Someone"), a[2]], 16, G.crew_color(int(who.get("color", 0))).darkened(0.25))
		right.add_child(row)
	var s: Dictionary = game.stats
	right.add_child(HSeparator.new())
	right.add_child(Ui.label("%d days · %d m walked · %d snacks · %d sneezes · %d keepsakes" % [game.day, int(s.distance), int(s.fed), int(s.sneezes), int(s.get("keepsakes", 0))], 15, G.STONE_DARK))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	v.add_child(buttons)
	if multiplayer.is_server():
		var again := Ui.button("Start a new migration")
		again.pressed.connect(func() -> void: game.request_new_migration())
		buttons.add_child(again)
	else:
		buttons.add_child(Ui.label("Waiting for the host to start another...", 16, G.STONE_DARK))
	var leave := Ui.button("Back to the menu")
	leave.pressed.connect(func() -> void: game.main.leave_to_menu())
	buttons.add_child(leave)

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
	_alive_t += dt
	_kal_t = maxf(_kal_t - dt, 0.0)
	for i in 8:
		_kal_flash[i] = maxf(_kal_flash[i] - dt * 4.0, 0.0)
	_update_coach(dt)
	canvas.queue_redraw()

## First-time hints, each shown once, in priority order.
func _update_coach(dt: float) -> void:
	var lp := game.local_player
	var b := game.beast
	_coach_t -= dt
	if _coach_t > 0.0:
		return
	var want := ""
	var text := ""
	if b.lure_operator == 0 and b.lure_down < 0.3 and _alive_t > 6.0:
		want = "lure"
		text = "The Mossback follows the sweetroot. Walk to the pole at the front of its back and press E."
	if lp.state == Player.St.STATION and b.lure_down < 0.5:
		want = "lower"
		text = "Hold W to lower the sweetroot in front of its nose. A / D swings it to steer."
	elif not lp.on_beast and not lp.beast_frame and lp.global_position.distance_to(b.ground_pos) > 30.0:
		want = "aboard"
		text = "Left behind? Run up its tail, or whistle (Q) so it turns towards you."
	elif b.satiety < 45.0:
		want = "feed"
		text = "It's getting peckish. Shake fruit trees (E), then hold RMB to throw fruit into its mouth."
	elif b.itch > 25.0:
		want = "mites"
		text = "Thistlemites! Grab them (LMB) and fling them overboard before it shakes everyone off."
	elif b.pollen > 0.55:
		want = "pollen"
		text = "Flowers make it sneezy. Steer around the bright patches... or hold on tight."
	elif b.balk and not _coach_seen.has("ford"):
		want = "ford"
		text = "It won't wade into deep water. Play it a tune (1 to 8) to coax it across, or toss food over to the far bank."
	elif not game.magpies.is_empty() and not _coach_seen.has("magpie"):
		want = "magpie"
		text = "Magpies steal hats and keepsakes. Whistle (Q) near one or bonk it with fruit. Shake the nest tree to get things back."
	elif lp.global_position.distance_to(b.flinger_stand_global()) < 7.0 and lp.state == Player.St.NORMAL and not _coach_seen.has("flinger"):
		want = "flinger"
		text = "The flinger! Drop fruit, mites or a friend in the bowl. Whoever mans it (E) can launch the lot."
	elif _alive_t > 75.0 and not _coach_seen.has("kalimba"):
		want = "kalimba"
		text = "Press 1 to 8 to play your kalimba. The Mossback adores a tune: it hums, trots and forgets its hunger."
	elif _alive_t > 140.0 and not _coach_seen.has("keepsake"):
		want = "keepsake"
		text = "Things glint out in the grass, far off the path. Bring keepsakes home to the cottage for new hats."
	if want != "" and not _coach_seen.has(want) and want != _coach_key:
		_coach_seen[want] = true
		_coach_key = want
		coach.text = text
		coach.modulate.a = 1.0
		_coach_t = 9.0
		var tw := create_tween()
		tw.tween_interval(8.0)
		tw.tween_property(coach, "modulate:a", 0.0, 0.8)

# ---------------------------------------------------------------- drawing
func _draw_canvas() -> void:
	var lp := game.local_player
	if lp == null or lp.camera == null or _end_open:
		return
	var vs := canvas.get_viewport_rect().size
	if _postcard:
		_draw_postcard_frame(vs)
		return
	if coach and coach.modulate.a > 0.01 and coach.text != "":
		var w := minf(G.font_body.get_string_size(coach.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x + 40.0, 700.0)
		var lines := 1 if w < 690.0 else 2
		var r := Rect2(Vector2(vs.x * 0.5 - w * 0.5, 90), Vector2(w, 20 + 26 * lines))
		var a := coach.modulate.a
		canvas.draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(G.INK, 0.3 * a))
		canvas.draw_rect(r, Color(G.BUTTER, 0.97 * a))
		canvas.draw_rect(r, Color(G.INK, a), false, 2.0)
	_draw_day_tag(Vector2(28, 24))
	_draw_compass(Vector2(vs.x * 0.5, 34), lp)
	_draw_belly(Vector2(36, vs.y - 178))
	_draw_name_tags(lp)
	if lp.state == Player.St.SPY and lp.camera.fov < 40.0:
		# brass eyepiece: everything outside a circle goes to ink
		var c := vs * 0.5
		var r := vs.y * 0.42
		var ring := PackedVector2Array()
		for i in 65:
			var a := TAU * i / 64.0
			ring.append(c + Vector2(cos(a), sin(a)) * r)
		canvas.draw_rect(Rect2(0, 0, c.x - r, vs.y), G.INK)
		canvas.draw_rect(Rect2(c.x + r, 0, vs.x - c.x - r, vs.y), G.INK)
		for i in 64:
			var a0 := ring[i]
			var a1 := ring[i + 1]
			var e0 := Vector2(a0.x, 0.0 if a0.y < c.y else vs.y)
			var e1 := Vector2(a1.x, 0.0 if a1.y < c.y else vs.y)
			canvas.draw_colored_polygon(PackedVector2Array([a0, a1, e1, e0]), G.INK)
		canvas.draw_polyline(ring, Color("b0803e"), 10.0, true)
		canvas.draw_line(c - Vector2(14, 0), c + Vector2(14, 0), Color(G.PAPER, 0.6), 1.5)
		canvas.draw_line(c - Vector2(0, 14), c + Vector2(0, 14), Color(G.PAPER, 0.6), 1.5)
		if lp.spy_hold > 0.0:
			canvas.draw_arc(c, 40.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(lp.spy_hold, 0.0, 1.0), 32, G.MINT, 4.0, true)
	if lp.state == Player.St.SPY and lp.camera.fov < 40.0:
		_draw_keepsake_marks(lp, vs)
	var g := game.gust_warning()
	if g > 0.0:
		_draw_wind(vs, lp, g)
	if lp.state == Player.St.FLING and not is_blocking():
		_draw_fling_arc(lp)
	if _kal_t > 0.0:
		_draw_kalimba(Vector2(vs.x * 0.5, vs.y - 150), minf(_kal_t, 1.0))
	if lp.throw_charge >= 0.0 and not is_blocking():
		_draw_throw_arc(lp)
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
	if game.waystone_idx < game.waystones.size() and game.marker_visible():
		var wp := game.waystones[game.waystone_idx]
		_compass_marker(center, w, yaw, wp - lp.global_position, [G.MARIGOLD, G.ROSE, G.SKY, G.MINT][game.waystone_idx % 4], "%d m" % int(Vector2(wp.x - game.beast.ground_pos.x, wp.z - game.beast.ground_pos.z).length()))
	if not lp.on_beast and lp.global_position.distance_to(game.beast.ground_pos) > 25.0:
		_compass_marker(center, w, yaw, game.beast.ground_pos - lp.global_position, G.FUR, "beast")
	for key in game._nest_info:
		var np: Vector3 = game._nest_info[key][0]
		_compass_marker(center, w, yaw, np - lp.global_position, G.BARK, "nest")

func _compass_marker(center: Vector2, w: float, yaw: float, to: Vector3, col: Color, label: String) -> void:
	var a := atan2(-to.x, -to.z)
	var d := wrapf(a - yaw, -PI, PI)
	var x := center.x - clampf(d / 1.3, -1.0, 1.0) * w * 0.5
	var pts := PackedVector2Array([Vector2(x, center.y + 14), Vector2(x - 8, center.y - 2), Vector2(x + 8, center.y - 2)])
	canvas.draw_colored_polygon(pts, col)
	canvas.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), G.INK, 1.5, true)
	canvas.draw_string(G.font_bold, Vector2(x - 30, center.y + 40), label, HORIZONTAL_ALIGNMENT_CENTER, 60, 15, G.PAPER)

func _draw_throw_arc(lp: Player) -> void:
	# mirrors Player's throw maths so the dots show where it will really go
	var aim := lp.cam_forward()
	aim.y = maxf(aim.y + 0.22, -0.3)
	var heavy := lp.held_fruit != 0 and game.fruit_heavy(lp.held_fruit)
	var power := lerpf(7.0, 19.0, lp.throw_charge) * (0.6 if heavy else 1.0)
	var v := aim.normalized() * power + lp.get_platform_velocity() + Vector3(lp.velocity.x, 0, lp.velocity.z) * 0.4
	var p := lp.hand_point()
	var mouth := game.beast.mouth_global()
	var hit_mouth := false
	var pts: Array[Vector3] = []
	for i in 40:
		pts.append(p)
		v.y -= 9.8 * 0.05
		p += v * 0.05
		if p.distance_to(mouth) < 2.9:
			hit_mouth = true
			pts.append(p)
			break
		if p.y < game.world.terrain.height(p.x, p.z):
			break
	var col := G.MINT if hit_mouth else G.PAPER
	for i in range(1, pts.size()):
		if lp.camera.is_position_behind(pts[i]):
			continue
		var sp := lp.camera.unproject_position(pts[i])
		var r := 4.0 if i % 2 == 0 else 2.5
		canvas.draw_circle(sp, r + 1.5, G.INK)
		canvas.draw_circle(sp, r, col)
	if hit_mouth:
		var sp := lp.camera.unproject_position(pts[pts.size() - 1])
		canvas.draw_string(G.font_bold, sp + Vector2(12, -8), "yum", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, G.MINT)

## Inked gust lines streaming across the view, thickening as the gust arrives.
func _draw_wind(vs: Vector2, lp: Player, g: float) -> void:
	var sx := signf(game.gust_dir.dot(lp.camera.global_transform.basis.x))
	if sx == 0.0:
		sx = 1.0
	var tt := Time.get_ticks_msec() * 0.001
	for k in 9:
		var y := vs.y * (0.18 + 0.08 * k) + sin(k * 7.3) * 30.0
		var x0 := fposmod(tt * 900.0 * (0.8 + 0.05 * k) + k * 377.0, vs.x + 400.0) - 200.0
		if sx < 0.0:
			x0 = vs.x - x0
		var pts := PackedVector2Array()
		for i in 12:
			var u := i / 11.0
			pts.append(Vector2(x0 - sx * u * 220.0 * g, y + sin(u * 5.0 + tt * 6.0 + k) * 8.0))
		canvas.draw_polyline(pts, Color(G.INK, 0.5 * g), 4.0, true)
		canvas.draw_polyline(pts, Color(G.PAPER, 0.85 * g), 2.0, true)
	if g < 1.0:
		canvas.draw_string(G.font_display, Vector2(vs.x * 0.5 - 140, vs.y * 0.36), "Gust coming!  hold R", HORIZONTAL_ALIGNMENT_CENTER, 280, 30, Color(G.PAPER, g))

func _draw_fling_arc(lp: Player) -> void:
	var b := game.beast
	var v := b.flinger_velocity(b.fl_charge)
	var p := b.flinger_release_global()
	var pts: Array[Vector3] = []
	for i in 200:
		if i % 3 == 0:
			pts.append(p)
		v.y -= 9.8 * 0.04
		p += v * 0.04
		if p.y < game.world.terrain.height(p.x, p.z) and i > 10:
			break
	for i in range(1, pts.size()):
		if lp.camera.is_position_behind(pts[i]):
			continue
		var sp := lp.camera.unproject_position(pts[i])
		var r := 4.5 if i % 2 == 0 else 3.0
		canvas.draw_circle(sp, r + 1.5, G.INK)
		canvas.draw_circle(sp, r, G.BUTTER if b.fl_charge > 0.0 else G.PAPER)
	if not lp.camera.is_position_behind(p):
		# landing mark: an inked X with the distance
		var sp := lp.camera.unproject_position(p)
		canvas.draw_line(sp - Vector2(9, 9), sp + Vector2(9, 9), G.INK, 4.0)
		canvas.draw_line(sp - Vector2(9, -9), sp + Vector2(9, -9), G.INK, 4.0)
		canvas.draw_line(sp - Vector2(7, 7), sp + Vector2(7, 7), G.TERRACOTTA, 2.0)
		canvas.draw_line(sp - Vector2(7, -7), sp + Vector2(7, -7), G.TERRACOTTA, 2.0)
		var d := Vector2(p.x - lp.global_position.x, p.z - lp.global_position.z).length()
		canvas.draw_string(G.font_bold, sp + Vector2(14, -6), "%d m" % int(d), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, G.PAPER)
	# wind-up gauge under the crosshair
	var c := canvas.get_viewport_rect().size * 0.5 + Vector2(0, 46)
	canvas.draw_rect(Rect2(c - Vector2(60, 6), Vector2(120, 12)), G.PAPER_DARK)
	canvas.draw_rect(Rect2(c - Vector2(60, 6), Vector2(120 * b.fl_charge, 12)), G.TERRACOTTA)
	canvas.draw_rect(Rect2(c - Vector2(60, 6), Vector2(120, 12)), G.INK, false, 2.0)

func _draw_keepsake_marks(lp: Player, vs: Vector2) -> void:
	var c := vs * 0.5
	var rad := vs.y * 0.42
	for f in game.fruits.values():
		if not f.keepsake or f.held_by != 0:
			continue
		var wp: Vector3 = f.global_position + Vector3(0, 1.2, 0)
		if lp.camera.is_position_behind(wp) or wp.distance_to(lp.camera.global_position) > 600.0:
			continue
		var sp := lp.camera.unproject_position(wp)
		if sp.distance_to(c) > rad - 16.0:
			continue
		var dm := PackedVector2Array([sp + Vector2(0, -11), sp + Vector2(9, 0), sp + Vector2(0, 11), sp + Vector2(-9, 0), sp + Vector2(0, -11)])
		canvas.draw_colored_polygon(dm, G.BUTTER)
		canvas.draw_polyline(dm, G.INK, 2.0, true)
		canvas.draw_string(G.font_bold, sp + Vector2(14, 6), "something glinting", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, G.BUTTER)

## The little thumb-piano strip that pops up while you play.
func _draw_kalimba(center: Vector2, a: float) -> void:
	var w := 300.0
	var box := Rect2(center - Vector2(w * 0.5, 0), Vector2(w, 64))
	canvas.draw_rect(Rect2(box.position + Vector2(3, 4), box.size), Color(G.INK, 0.3 * a))
	canvas.draw_rect(box, Color(G.WOOD, a))
	canvas.draw_rect(box, Color(G.INK, a), false, 2.0)
	var col := G.crew_color(game.local_player.color_idx)
	for i in 8:
		var len_t := 44.0 - absf(i - 3.5) * 6.0
		var x := box.position.x + 26.0 + i * 35.0
		var tine := Rect2(Vector2(x - 6, box.position.y + 6), Vector2(12, len_t))
		canvas.draw_rect(tine, Color(G.PAPER.lerp(col, _kal_flash[i]), a))
		canvas.draw_rect(tine, Color(G.INK, a), false, 1.5)
		canvas.draw_string(G.font_bold, Vector2(x - 4, box.end.y - 4), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(G.PAPER, a))

func _draw_belly(at: Vector2) -> void:
	var head := Rect2(at - Vector2(0, 30), Vector2(280, 32))
	canvas.draw_rect(Rect2(head.position + Vector2(3, 4), head.size), Color(G.INK, 0.35))
	canvas.draw_rect(head, G.INK)
	canvas.draw_string(G.font_bold, head.position + Vector2(12, 22), "%s · %s" % [game.beast.beast_name, game.beast.temperament.to_lower()], HORIZONTAL_ALIGNMENT_LEFT, 260, 17, G.PAPER)
	var rect := Rect2(at, Vector2(280, 142))
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
	var mood_col := G.STONE_DARK
	if game.beast.balk:
		mood = "won't wade in deep water"
		mood_col = G.TERRACOTTA
	elif game.beast.serenade > 0.55:
		mood = "enchanted by the tune"
		mood_col = G.ROSE
	canvas.draw_string(G.font_body, at + Vector2(96, 30), mood, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, mood_col)
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
	# itch: a scribble that gets wilder as the thistlemites nibble
	var itch: float = game.beast.itch
	var row := at + Vector2(14, 92)
	canvas.draw_string(G.font_body, row + Vector2(0, 6), "Itch", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, G.INK)
	var pts := PackedVector2Array()
	var amp := 2.0 + itch * 0.09
	for i in 40:
		var x := row.x + 44 + i * 5.2
		var wob := sin(i * 1.9 + Time.get_ticks_msec() * 0.012 * (0.3 + itch * 0.02)) * amp
		pts.append(Vector2(x, row.y + wob))
	canvas.draw_polyline(pts, G.PLUM if itch < 70.0 else G.TERRACOTTA, 2.0 + itch * 0.02, true)
	# tune: a little stave whose notes fill in as the crew serenades it
	var ser: float = game.beast.serenade
	var trow := at + Vector2(14, 120)
	canvas.draw_string(G.font_body, trow + Vector2(0, 6), "Tune", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, G.INK)
	for l in 3:
		canvas.draw_line(trow + Vector2(48, -6 + l * 5), trow + Vector2(252, -6 + l * 5), Color(G.INK, 0.35), 1.0)
	var lit := int(ceil(ser * 8.0 - 0.01))
	var tt := Time.get_ticks_msec() * 0.001
	for i in 8:
		var nx := trow.x + 62 + i * 25.0
		var ny := trow.y + 2 - (i % 4) * 3.0 + (sin(tt * 4.0 + i) * 2.0 if i < lit else 0.0)
		if i < lit:
			canvas.draw_circle(Vector2(nx, ny), 4.5, G.ROSE if ser > 0.55 else G.INK)
			canvas.draw_line(Vector2(nx + 4, ny), Vector2(nx + 4, ny - 14), G.INK, 1.5)
		else:
			canvas.draw_arc(Vector2(nx, ny), 4.0, 0, TAU, 10, Color(G.INK, 0.25), 1.0, true)


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
		if Voice.is_speaking(p.peer_id):
			# little sound arcs beside the tag
			var c := Vector2(r.end.x + 6, r.position.y + r.size.y * 0.5)
			for k in 3:
				canvas.draw_arc(c, 4.0 + k * 4.0, -0.8, 0.8, 8, G.PAPER, 2.0, true)

# ---------------------------------------------------------------- postcards
## Frame the view like a field-guide plate, save it, put the HUD back.
func _take_postcard() -> void:
	_postcard = true
	for n in [hint_label, big_title, big_sub, coach, toasts]:
		n.visible = false
	canvas.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://postcards")
	var path := "user://postcards/mossback_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
	var err := img.save_png(path)
	_postcard = false
	for n in [hint_label, big_title, big_sub, coach, toasts]:
		n.visible = true
	Sfx.play("ui_click")
	_on_toast("Postcard saved: %s" % ProjectSettings.globalize_path(path) if err == OK else "Couldn't save the postcard.")

func _draw_postcard_frame(vs: Vector2) -> void:
	var m := 26.0
	var band := 74.0
	canvas.draw_rect(Rect2(0, 0, vs.x, m), G.PAPER)
	canvas.draw_rect(Rect2(0, 0, m, vs.y), G.PAPER)
	canvas.draw_rect(Rect2(vs.x - m, 0, m, vs.y), G.PAPER)
	canvas.draw_rect(Rect2(0, vs.y - m - band, vs.x, m + band), G.PAPER)
	var inner := Rect2(m, m, vs.x - m * 2.0, vs.y - m * 2.0 - band)
	canvas.draw_rect(inner, G.INK, false, 3.0)
	canvas.draw_rect(inner.grow(6.0), Color(G.INK, 0.4), false, 1.0)
	var b := game.beast
	var biome: String = Terrain.BIOMES[game.world.terrain.biome_index(b.ground_pos.x, b.ground_pos.z)].name
	var y := vs.y - m - band + 42.0
	canvas.draw_string(G.font_display, Vector2(m + 6, y), "%s, %s" % [b.beast_name, biome], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, G.INK)
	var crew: Array = []
	for p in game.players.values():
		crew.append(p.display_name)
	canvas.draw_string(G.font_body, Vector2(m + 8, y + 26), "Day %d of the migration  ·  with %s" % [game.day, ", ".join(crew)], HORIZONTAL_ALIGNMENT_LEFT, vs.x * 0.6, 16, G.STONE_DARK)
	canvas.draw_string(G.font_display, Vector2(vs.x - m - 220, y + 8), "Mossback", HORIZONTAL_ALIGNMENT_RIGHT, 214, 34, G.TERRACOTTA)
