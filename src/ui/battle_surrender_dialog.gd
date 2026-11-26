class_name BattleSurrenderDialog
extends CanvasLayer

## Native surrender offer reconstructed from surrendr.bin and surrendr.bmp.
## The BIN's 486x221 bounds include an 8px external margin; the 470x205 bitmap
## and every child below keep their literal inner coordinates.

signal accepted
signal declined

const BG := UiKit.ART + "surrendr.png"
const SURRENDER := UiKit.ART + "surrendr/"
const PORT := UiKit.ART + "port%04d/0000.png"
const DIALOG_POS := Vector2(85, 137)
const DIALOG_SIZE := Vector2(470, 205)
const PORTRAIT_FRAME_POS := Vector2(39, 32)
const PORTRAIT_POS := Vector2(44, 38)
const PORTRAIT_SIZE := Vector2(101, 93)
const ACCEPT_POS := Vector2(75, 152)
const DECLINE_POS := Vector2(279, 152)
const BUTTON_SIZE := Vector2(116, 27)

var _panel: Control

func setup(opponent: HeroModel, cost: int) -> void:
	layer = 290
	var blocker := ColorRect.new()
	blocker.color = Color(0, 0, 0, 0)
	blocker.size = Vector2(640, 480)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)
	_panel = Control.new()
	_panel.name = "Panel"
	_panel.position = DIALOG_POS
	_panel.size = DIALOG_SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	UiKit.add_texture(_panel, BG, Vector2.ZERO)
	UiKit.add_texture(_panel, SURRENDER + "0004.png", PORTRAIT_FRAME_POS)
	if opponent == null:
		opponent = HeroModel.sample()
	UiKit.add_texture(_panel, PORT % opponent.portrait_idx, PORTRAIT_POS)
	var font := UiKit.font()
	var text := wrapped_offer_text(opponent.hero_name, cost, font)
	UiKit.add_label(_panel, text, Vector2(182, 38),
			Vector2(236, 103), font, Color8(240, 240, 240), HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP,
			"", 0, Color.BLACK, 2)
	_button("Accept", 0, 1, ACCEPT_POS, _accept)
	_button("Decline", 2, 3, DECLINE_POS, _decline)

## One bigfont field, its quote opened and never closed (heroes.exe data
## 0x2f7c, surrendr.bin text field 2 at 182,38 236x103).
static func offer_text(hero_name: String, cost: int) -> String:
	return "%s states:\n\n\"I will accept your surrender and grant you and your troops safe passage for the price of %d gold." % [hero_name, cost]

## Pre-wraps the offer text across 236px width, exactly as heroes.exe 0xd7de4
## renders it (6 lines, 16px line cadence via line_spacing=2).
static func wrapped_offer_text(hero_name: String, cost: int, font: Font = null) -> String:
	var f := font if font != null else UiKit.font()
	var raw := offer_text(hero_name, cost)
	return Homm1Font.wrap(f, raw, 236.0) if f != null else raw

func dialog_rect() -> Rect2:
	return Rect2(DIALOG_POS, DIALOG_SIZE)

func portrait_rect() -> Rect2:
	return Rect2(DIALOG_POS + PORTRAIT_POS, PORTRAIT_SIZE)

func button_rect(action: StringName) -> Rect2:
	match action:
		&"accept": return Rect2(DIALOG_POS + ACCEPT_POS, BUTTON_SIZE)
		&"decline": return Rect2(DIALOG_POS + DECLINE_POS, BUTTON_SIZE)
	return Rect2()

func _button(button_name: String, up: int, down: int, pos: Vector2,
		callback: Callable) -> void:
	var button := TextureButton.new()
	button.name = button_name
	button.texture_normal = load(SURRENDER + "%04d.png" % up) as Texture2D
	button.texture_pressed = load(SURRENDER + "%04d.png" % down) as Texture2D
	button.position = pos
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	_panel.add_child(button)

func _accept() -> void:
	accepted.emit()
	queue_free()

func _decline() -> void:
	declined.emit()
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_accept()
		elif event.keycode == KEY_ESCAPE:
			_decline()
		else:
			return
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		_decline()
		get_viewport().set_input_as_handled()
