extends Node
## Globals: palette, input map, local settings, small helpers.

# --- "Field guide" palette. Every visible colour in the game should come from here.
const INK := Color("2a2238")
const PAPER := Color("f3e9d2")
const PAPER_DARK := Color("dccdaa")
const MOSS := Color("7d9a4a")
const MOSS_DARK := Color("4f6b35")
const MEADOW := Color("a3b55a")
const MEADOW_DRY := Color("cdb96a")
const MEADOW_DEEP := Color("6f8f45")
const SOIL := Color("8a6a4c")
const BARK := Color("6b4a3a")
const WOOD := Color("a8794f")
const WOOD_LIGHT := Color("d1a36b")
const STONE := Color("a39d8e")
const STONE_DARK := Color("6e6a64")
const TERRACOTTA := Color("c8643b")
const MARIGOLD := Color("e8a83a")
const PLUM := Color("7a3b5e")
const SKY := Color("8fb8c9")
const TEAL := Color("3f7f7a")
const ROSE := Color("e08b7d")
const MINT := Color("8ccfa5")
const BUTTER := Color("f2d36b")
const FUR := Color("8f7d6b")
const FUR_LIGHT := Color("c2ad8f")
const FUR_DARK := Color("5e4f45")
const WATER := Color("5f9ea3")

const CREW_COLORS: Array[Color] = [
	Color("e8a83a"), Color("c8643b"), Color("3f7f7a"), Color("7a3b5e"),
	Color("8fb8c9"), Color("e08b7d"), Color("8ccfa5"), Color("f2d36b"),
]
const HATS: Array[String] = ["beanie", "cone", "bucket", "sprout", "beret", "none"]

const PLAYER_LAYER := 2
const PROP_LAYER := 4
const BEAST_LAYER := 8
const WORLD_LAYER := 1

var font_display: FontVariation
var font_body: Font
var font_bold: Font

# local player settings
var player_name := "Tender"
var player_color_idx := 0
var player_hat := "beanie"
var mouse_sens := 0.0025
var invert_y := false

func _ready() -> void:
	_setup_input()
	_setup_fonts()
	randomize()
	player_color_idx = randi() % CREW_COLORS.size()
	player_hat = HATS[randi() % (HATS.size() - 1)]
	player_name = ["Pip", "Moss", "Bramble", "Fennel", "Clover", "Tuck", "Wren", "Burdock"][randi() % 8]

func _setup_fonts() -> void:
	var f: FontFile = load("res://fonts/Fraunces.ttf")
	font_display = FontVariation.new()
	font_display.base_font = f
	# Fraunces axes: opsz, wght, SOFT, WONK
	font_display.variation_opentype = {"wght": 760, "SOFT": 100, "WONK": 1, "opsz": 72}
	font_body = load("res://fonts/Atkinson-Regular.ttf")
	font_bold = load("res://fonts/Atkinson-Bold.ttf")

func _add_key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev: InputEvent
		if k is int and k < 10:
			ev = InputEventMouseButton.new()
			ev.button_index = k
		else:
			ev = InputEventKey.new()
			ev.physical_keycode = k
		InputMap.action_add_event(action, ev)

func _add_pad(action: String, button: int) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)

func _setup_input() -> void:
	_add_key("move_forward", [KEY_W, KEY_UP])
	_add_key("move_back", [KEY_S, KEY_DOWN])
	_add_key("move_left", [KEY_A, KEY_LEFT])
	_add_key("move_right", [KEY_D, KEY_RIGHT])
	_add_key("jump", [KEY_SPACE])
	_add_key("sprint", [KEY_SHIFT])
	_add_key("interact", [KEY_E])
	_add_key("grab", [MOUSE_BUTTON_LEFT])
	_add_key("throw", [MOUSE_BUTTON_RIGHT])
	_add_key("whistle", [KEY_Q])
	_add_key("emote", [KEY_F])
	_add_key("pause", [KEY_ESCAPE])
	_add_key("toggle_cam", [KEY_V])
	_add_key("flop", [KEY_R])
	_add_pad("flop", JOY_BUTTON_B)
	_add_pad("jump", JOY_BUTTON_A)
	_add_pad("interact", JOY_BUTTON_X)
	_add_pad("grab", JOY_BUTTON_RIGHT_SHOULDER)
	_add_pad("throw", JOY_BUTTON_LEFT_SHOULDER)
	_add_pad("whistle", JOY_BUTTON_Y)
	_add_pad("sprint", JOY_BUTTON_LEFT_STICK)
	_add_pad("pause", JOY_BUTTON_START)

func crew_color(idx: int) -> Color:
	return CREW_COLORS[posmod(idx, CREW_COLORS.size())]

## Exponential smoothing factor that is framerate independent.
static func damp(rate: float, dt: float) -> float:
	return 1.0 - exp(-rate * dt)

static func wrap_angle(a: float) -> float:
	return wrapf(a, -PI, PI)
