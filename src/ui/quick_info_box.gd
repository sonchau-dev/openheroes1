# src/ui/quick_info_box.gd
class_name QuickInfoBox
extends CanvasLayer

## Transient right-click inspection box (holds open while RMB is pressed).
## Uses the authentic HOMM1 qwikinfo.png (146x82) parchment frame.

const ART := UiKit.ART
const QWIKINFO := ART + "qwikinfo.png"
const SMALL_FONT := ART + "smalfont/"

const DIALOG_WIDTH := 146.0
const DIALOG_HEIGHT := 82.0
const MAP_VIEW_RECT := Rect2(16, 16, 448, 448)
const TEXT_COLOR := Color8(240, 240, 240)

var _dialog: Control
var _bg: TextureRect
var _text_label: Label
var _font: Font

func _init() -> void:
	layer = 300
	visible = false

	_font = Homm1Font.load_font(SMALL_FONT)

	_dialog = Control.new()
	_dialog.name = "QuickInfoPanel"
	_dialog.size = Vector2(DIALOG_WIDTH, DIALOG_HEIGHT)
	_dialog.custom_minimum_size = Vector2(DIALOG_WIDTH, DIALOG_HEIGHT)
	_dialog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dialog)

	# Background parchment with wooden border (146x82)
	_bg = TextureRect.new()
	_bg.name = "Background"
	_bg.texture = load(QWIKINFO) as Texture2D
	_bg.position = Vector2.ZERO
	_bg.size = Vector2(DIALOG_WIDTH, DIALOG_HEIGHT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(_bg)

	_text_label = Label.new()
	_text_label.name = "TextLabel"
	_text_label.position = Vector2(10, 8)
	_text_label.size = Vector2(DIALOG_WIDTH - 20.0, DIALOG_HEIGHT - 16.0)
	_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _font != null:
		_text_label.add_theme_font_override("font", _font)
		_text_label.add_theme_font_size_override("font_size", 12)
	_text_label.add_theme_color_override("font_color", TEXT_COLOR)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(_text_label)

func show_info(title_text: String, body_text: String, mouse_pos: Vector2) -> void:
	if title_text.is_empty() and body_text.is_empty():
		hide_info()
		return

	if body_text.is_empty():
		_text_label.text = title_text
	elif title_text.is_empty():
		_text_label.text = body_text
	else:
		_text_label.text = "%s\n%s" % [title_text, body_text]

	var clamped_x: float
	var clamped_y: float
	if mouse_pos.x <= MAP_VIEW_RECT.end.x:
		clamped_x = clampf(mouse_pos.x - DIALOG_WIDTH / 2.0, MAP_VIEW_RECT.position.x, MAP_VIEW_RECT.end.x - DIALOG_WIDTH)
		clamped_y = clampf(mouse_pos.y - DIALOG_HEIGHT / 2.0, MAP_VIEW_RECT.position.y, MAP_VIEW_RECT.end.y - DIALOG_HEIGHT)
	else:
		clamped_x = clampf(mouse_pos.x - DIALOG_WIDTH / 2.0, 16.0, 624.0 - DIALOG_WIDTH)
		clamped_y = clampf(mouse_pos.y - DIALOG_HEIGHT / 2.0, 16.0, 464.0 - DIALOG_HEIGHT)

	_dialog.position = Vector2(clamped_x, clamped_y)
	visible = true

func hide_info() -> void:
	visible = false
