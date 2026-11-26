# src/ui/spell_info_dialog.gd
class_name SpellInfoDialog
extends CanvasLayer

## HOMM1 spell-information popup opened from the Mage Guild or Spellbook.
## heroes.exe shows the spell's description string (title, blank line, text;
## table at data 0x21054) in its stone message box 0xd0428 with the spells.icn
## icon (box type 8) and the spell's name under it (0x7e124, guild 0xbcab5).
## The box is evntwinN.bin; 0xd0428 picks N and places the icon
## (ui-bin-format.md 3.1). DOS captures of five spellbook boxes
## (2, 3, 4 and 7 description lines, 2026-10-29) match it to the pixel.

signal closed

const BUYBUILD := UiKit.ART + "buybuild/"
const SYSTEM := UiKit.ART + "system/"
const SPELLS := UiKit.ART + "spells/"

const DIALOG_WIDTH := 302
const TOP_HEIGHT := 77  # buybuild 0 drawn from the window's second row
const STRIP_HEIGHT := 45
const BOTTOM_HEIGHT := 48
## Window left: centred, or over the adventure map's view when that is the
## screen underneath (0xd059a).
const WINDOW_X := 177
const MAP_WINDOW_X := 97
const TEXT_RECT := Rect2(31, 54, 240, 0)
const LINE_SPACING := 2  # 16 px a line
const BUTTON_POS := Vector2(102, 0)  # on the bottom piece
const ICON_X := 132  # the 38 px icon box, centred; the frame adds its spec offset
const ICON_BOX_H := 52  # 40 px icon plus the caption line (0xd0c1d)
const CAPTION_Y := 42  # below the icon box top
const CAPTION_H := 14

var _closing := false

## The description string for a spell (data 0x21054, by native spell id).
static func info_text(spell_id: String) -> String:
	var spell := SpellData.get_spell(spell_id)
	return String(spell.get("info", spell.get("name", spell_id.capitalize())))

var _hold := false

## `hold`: a right-click popup with no OKAY that goes when the button is let
## go (message box style 4).
## `on_map`: opened over the adventure map rather than the hero, town or
## combat screen.
func setup(spell_id: String, hold := false, on_map := false) -> void:
	_hold = hold
	layer = 210
	var spell := SpellData.get_spell(spell_id)
	var font := UiKit.font_big()
	var small := UiKit.font_small()
	var text := info_text(spell_id)
	if font != null:
		text = Homm1Font.wrap(font, text, TEXT_RECT.size.x)
	var icon_id := int(spell.get("icon", 0))
	var icon_tex := load(SPELLS + "%04d.png" % icon_id) as Texture2D

	# 0xd0428: 16 px a line, 39 for OKAY, the icon box, then whole strips.
	var text_h := text.split("\n").size() * 16
	var strips := clampi((text_h + (0 if hold else 39) + ICON_BOX_H) / STRIP_HEIGHT, 0 if hold else 1, 7)
	var height := 129 + strips * STRIP_HEIGHT
	var bottom_y := TOP_HEIGHT + strips * STRIP_HEIGHT
	var icon_y := height - ICON_BOX_H - 27 - (0 if hold else 39) - 1

	var blocker := ColorRect.new()
	blocker.name = "InputBlocker"
	blocker.color = Color.TRANSPARENT
	blocker.position = Vector2.ZERO
	blocker.size = Vector2(640, 480)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)
	blocker.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_close()
	)

	var dialog := Control.new()
	dialog.name = "SpellInfoDialog"
	dialog.position = Vector2((MAP_WINDOW_X if on_map else WINDOW_X) - 8,
			mini((480 - height) / 2, 28) + 1)
	dialog.size = Vector2(DIALOG_WIDTH, bottom_y + BOTTOM_HEIGHT)
	dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dialog)

	var shadow := ColorRect.new()
	shadow.name = "Shadow"
	shadow.color = Color(0, 0, 0, 0.45)
	shadow.position = Vector2(18, 62)
	shadow.size = Vector2(286, bottom_y - 10)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.add_child(shadow)

	_add_segment(dialog, BUYBUILD + "0000.png", 0)
	for k in strips:
		_add_segment(dialog, BUYBUILD + "0001.png", TOP_HEIGHT + k * STRIP_HEIGHT)
	_add_segment(dialog, BUYBUILD + "0002.png", bottom_y)

	UiKit.add_boxed_label(dialog, "Description", text,
			Rect2(TEXT_RECT.position, Vector2(TEXT_RECT.size.x, text_h + 4)), font, false, LINE_SPACING)
	if icon_tex != null:
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.texture = icon_tex
		var offset: Vector2i = SpecLoader.sprite(SPELLS, icon_id).get("offset", Vector2i.ZERO)
		icon.position = Vector2(ICON_X, icon_y) + Vector2(offset)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dialog.add_child(icon)
	UiKit.add_boxed_label(dialog, "Caption", String(spell.get("name", "")),
			Rect2(TEXT_RECT.position.x, icon_y + CAPTION_Y, TEXT_RECT.size.x, CAPTION_H),
			small if small != null else font, false)

	var okay := TextureButton.new()
	okay.name = "Okay"
	okay.texture_normal = load(SYSTEM + "0009.png") as Texture2D
	okay.texture_pressed = load(SYSTEM + "0010.png") as Texture2D
	okay.position = BUTTON_POS + Vector2(0, bottom_y)
	okay.pressed.connect(_close)
	okay.visible = not hold
	dialog.add_child(okay)

## One row of the frame: the right half as drawn, the left half its mirror.
func _add_segment(parent: Control, texture_path: String, y: float) -> void:
	var texture := load(texture_path) as Texture2D
	if texture == null:
		return
	for flip: bool in [true, false]:
		var segment := TextureRect.new()
		segment.texture = texture
		segment.position = Vector2(151 - texture.get_width() if flip else 151, y)
		segment.flip_h = flip
		segment.size = texture.get_size()
		segment.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		segment.stretch_mode = TextureRect.STRETCH_KEEP
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(segment)

## A hold popup goes when the right button is let go.
func _input(event: InputEvent) -> void:
	if _hold and event is InputEventMouseButton and not event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		_close()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed \
			and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]:
		_close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		_close()
		get_viewport().set_input_as_handled()

func close() -> void:
	_close()

func _close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()
