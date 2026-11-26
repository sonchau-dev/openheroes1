# src/ui/adventure_options_dialog.gd
class_name AdventureOptionsDialog
extends CanvasLayer

## Adventure options popup over the map, rendered on the authentic HOMM1
## adventure options panel art (apanel.png = stone frame + baked golden buttons).
## Provides View Puzzle, View World, Cast Spell, Dig, and OKAY buttons.
##
## Geometry is panel-local within apanel.png (322x236), placed at PANEL_POS.

const BG := UiKit.ART + "apanel.png"       # baked adventure options panel background (322x236)
const APANEL := UiKit.ART + "apanel/"      # apanel.icn buttons (up=base, pressed=+1)

const APANEL_WORLD := 0
const APANEL_PUZZLE := 2
const APANEL_SPELL := 4
const APANEL_DIG := 6
const APANEL_OKAY := 8

const PANEL_POS := Vector2(159, 40)  # centers horizontally on 640x480 screen (x=159, y=40)

const BTN_L_X := 46.0
const BTN_R_X := 179.0
const BTN_ROW1_Y := 31.0
const BTN_ROW2_Y := 107.0
const OKAY_POS := Vector2(112, 184)

signal closed
signal puzzle_requested
signal world_requested
signal spell_requested
signal dig_requested

var _dim: ColorRect
var _holder: Control
var _buttons: Dictionary = {}

func open() -> void:
	layer = 200

	# Transparent click-blocker (no dimming — matches the DOS adventure options
	# screen, leaving the map + HUD at full brightness). Swallows stray clicks.
	_dim = ColorRect.new()
	_dim.name = "InputBlocker"
	_dim.color = Color(0, 0, 0, 0)
	_dim.position = Vector2.ZERO
	_dim.size = Vector2(640, 480)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	var holder := Control.new()
	holder.name = "PanelHolder"
	holder.position = PANEL_POS
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(holder)
	_holder = holder

	UiKit.add_tex(holder, BG, Vector2.ZERO)

	# 5 buttons push down on click (IcnButton up/pressed art from apanel.icn).
	_add_button(holder, APANEL_WORLD, "world", Vector2(BTN_L_X, BTN_ROW1_Y))
	_add_button(holder, APANEL_PUZZLE, "puzzle", Vector2(BTN_R_X, BTN_ROW1_Y))
	_add_button(holder, APANEL_SPELL, "spell", Vector2(BTN_L_X, BTN_ROW2_Y))
	_add_button(holder, APANEL_DIG, "dig", Vector2(BTN_R_X, BTN_ROW2_Y))
	_add_button(holder, APANEL_OKAY, "okay", OKAY_POS)

func get_button(btn_name: String) -> IcnButton:
	return _buttons.get(btn_name, null)

func _add_button(parent: Control, base: int, action: String, pos: Vector2) -> void:
	var btn := IcnButton.new()
	btn.setup(APANEL, base, action)
	btn.position = pos
	btn.pressed.connect(_on_action)
	parent.add_child(btn)
	_buttons[action] = btn

func _on_action(action: String) -> void:
	hide()
	queue_free()
	closed.emit()
	match action:
		"puzzle":
			puzzle_requested.emit()
		"world":
			world_requested.emit()
		"spell":
			spell_requested.emit()
		"dig":
			dig_requested.emit()
		"okay":
			pass

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# apanel.bin: View World M, Puzzle P, Cast C, Dig D, Okay Esc.
		if event.keycode == KEY_ESCAPE:
			_on_action("okay")
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_P:
			_on_action("puzzle")
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_M:
			_on_action("world")
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_C:
			_on_action("spell")
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_D:
			_on_action("dig")
			get_viewport().set_input_as_handled()
			return
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_on_action("okay")
		get_viewport().set_input_as_handled()
