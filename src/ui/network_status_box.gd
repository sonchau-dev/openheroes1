class_name NetworkStatusBox
extends CanvasLayer

## The original's network status banner: `netbox.icn`, a single 640x62 red box
## holding three bigfont lines. Geometry read out of `netbox.bin` — three text
## widgets at box-local y = 5, 21, 42, each x = 20, w = 600, h = 16 (KB
## homm1-native-data.md §5.5).
##
## Used for both phases of remote play: the connect handshake ("Initializing
## network." / "Waiting On Guest.") and the in-game wait while the other
## machine takes its turn ("%s player turn."). It blocks input underneath, so
## the parked player cannot act out of turn.

signal aborted

const ART := UiKit.ART
const BOX := ART + "netbox/0000.png"
const BOX_SIZE := Vector2(640, 62)
## Vertically centred on the 640x480 screen.
const BOX_POS := Vector2(0, 209)
const LINE_Y := [5.0, 21.0, 42.0]
const LINE_X := 20.0
const LINE_W := 600.0
const LINE_H := 16.0

var _labels: Array[Label] = []
var _blocker: ColorRect = null
var _box: TextureRect = null

func open(lines: PackedStringArray = PackedStringArray(),
		block_input: bool = true) -> void:
	layer = 900

	_blocker = ColorRect.new()
	_blocker.color = Color(0, 0, 0, 0)
	_blocker.size = Vector2(640, 480)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP if block_input \
			else Control.MOUSE_FILTER_IGNORE
	add_child(_blocker)

	var box := TextureRect.new()
	_box = box
	box.texture = load(BOX) as Texture2D
	box.position = BOX_POS
	box.size = BOX_SIZE
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(box)

	var font := Homm1Font.load_font(ART + "font/")
	for y: float in LINE_Y:
		var label := Label.new()
		label.position = Vector2(LINE_X, y)
		label.size = Vector2(LINE_W, LINE_H)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if font != null:
			label.add_theme_font_override("font", font)
			label.add_theme_font_size_override("font_size", font.fixed_size)
		box.add_child(label)
		_labels.append(label)

	set_lines(lines)

## The banner itself, for callers that place a widget on one of its three
## lines (the address entry sits on the lighter lower strip).
func banner() -> TextureRect:
	return _box

func set_lines(lines: PackedStringArray) -> void:
	for i in _labels.size():
		_labels[i].text = String(lines[i]) if i < lines.size() else ""

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		aborted.emit()
