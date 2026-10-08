class_name Ui
## Shared UI building blocks: paper panels, ink buttons, fonts.

static var _theme: Theme

static func theme() -> Theme:
	if _theme:
		return _theme
	_theme = Theme.new()
	_theme.default_font = G.font_body
	_theme.default_font_size = 18
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(G.PAPER, 0.97)
	paper.border_color = G.INK
	paper.set_border_width_all(2)
	paper.set_corner_radius_all(3)
	paper.set_content_margin_all(22)
	paper.shadow_color = Color(G.INK, 0.35)
	paper.shadow_offset = Vector2(4, 5)
	paper.shadow_size = 0
	_theme.set_stylebox("panel", "PanelContainer", paper)
	var b_normal := StyleBoxFlat.new()
	b_normal.bg_color = G.PAPER_DARK
	b_normal.border_color = G.INK
	b_normal.set_border_width_all(2)
	b_normal.set_corner_radius_all(3)
	b_normal.content_margin_left = 18
	b_normal.content_margin_right = 18
	b_normal.content_margin_top = 9
	b_normal.content_margin_bottom = 9
	var b_hover := b_normal.duplicate()
	b_hover.bg_color = G.BUTTER
	var b_press := b_normal.duplicate()
	b_press.bg_color = G.MARIGOLD
	var b_focus := b_normal.duplicate()
	b_focus.bg_color = Color(0, 0, 0, 0)
	b_focus.border_color = G.TERRACOTTA
	b_focus.set_border_width_all(3)
	for t in ["Button", "OptionButton"]:
		_theme.set_stylebox("normal", t, b_normal)
		_theme.set_stylebox("hover", t, b_hover)
		_theme.set_stylebox("pressed", t, b_press)
		_theme.set_stylebox("focus", t, b_focus)
		_theme.set_color("font_color", t, G.INK)
		_theme.set_color("font_hover_color", t, G.INK)
		_theme.set_color("font_pressed_color", t, G.INK)
		_theme.set_color("font_focus_color", t, G.INK)
		_theme.set_font("font", t, G.font_bold)
		_theme.set_font_size("font_size", t, 20)
	var le := StyleBoxFlat.new()
	le.bg_color = Color("fffaf0")
	le.border_color = G.INK
	le.set_border_width_all(2)
	le.set_content_margin_all(8)
	_theme.set_stylebox("normal", "LineEdit", le)
	var le_f := le.duplicate()
	le_f.border_color = G.TERRACOTTA
	_theme.set_stylebox("focus", "LineEdit", le_f)
	_theme.set_color("font_color", "LineEdit", G.INK)
	_theme.set_color("caret_color", "LineEdit", G.TERRACOTTA)
	_theme.set_color("font_color", "Label", G.INK)
	var slider := StyleBoxFlat.new()
	slider.bg_color = G.PAPER_DARK
	slider.border_color = G.INK
	slider.set_border_width_all(1)
	slider.content_margin_top = 4
	slider.content_margin_bottom = 4
	_theme.set_stylebox("slider", "HSlider", slider)
	return _theme

static func label(text: String, size := 18, color := G.INK, display := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if display:
		l.add_theme_font_override("font", G.font_display)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.mouse_entered.connect(func() -> void: Sfx.play("ui_hover", null, -8.0))
	b.pressed.connect(func() -> void: Sfx.play("ui_click"))
	return b

static func panel(margin := 22) -> PanelContainer:
	var p := PanelContainer.new()
	if margin != 22:
		var sb: StyleBoxFlat = theme().get_stylebox("panel", "PanelContainer").duplicate()
		sb.set_content_margin_all(margin)
		p.add_theme_stylebox_override("panel", sb)
	return p
