# src/ui/message_box.gd
class_name MessageBox
extends CanvasLayer

## heroes.exe's stone message box, routine 0xd0428 (ui-bin-format.md 3.1).
## One text, a style (OKAY, YES/NO or a right-click HOLD popup) and up to two
## icons given as [type, value] pairs with the original's own type numbers.
## The text is wrapped at 240 px in bigfont, 16 px a line; the title, when a
## message has one, is simply its first line. The window takes 129 + 45N px
## for N strips, N = (text + 39 for the button row + tallest icon box + 12,
## minus 12) / 45, clamped to 1..7 (0 for a HOLD popup), and sits at x 97
## over the adventure map or 177 elsewhere, y = min((480 - height) / 2, 28).
## Subclasses keep their old names and call build().

signal closed
signal chosen(option_index: int)

const DialogFrame := preload("res://src/ui/dialog_frame.gd")

const OKAY := 1
const YES_NO := 2
const HOLD := 4

## Icon types (heroes.exe's numbering). The value is the resource amount
## (negative for "per day", 0 for no caption), the artifact id, the spell id,
## the crest colour, the experience amount (-1 for none) or the portrait index.
const ICON_WOOD := 0
const ICON_MERCURY := 1
const ICON_ORE := 2
const ICON_SULFUR := 3
const ICON_CRYSTAL := 4
const ICON_GEMS := 5
const ICON_GOLD := 6
const ICON_ARTIFACT := 7
const ICON_SPELL := 8
const ICON_CREST := 9
const ICON_GOOD_LUCK := 10
const ICON_BAD_LUCK := 11
const ICON_GOOD_MORALE := 12
const ICON_BAD_MORALE := 13
const ICON_EXPERIENCE := 14
const ICON_PORTRAIT := 15
const RESOURCE_TYPES := {"wood": 0, "mercury": 1, "ore": 2, "sulfur": 3, "crystal": 4, "gems": 5, "gold": 6}

const BUYBUILD := UiKit.ART + "buybuild/"
const SYSTEM := UiKit.ART + "system/"
const NEWGAME := UiKit.ART + "newgame/"
const RESOURCE := UiKit.ART + "resource/"
const SPELLS := UiKit.ART + "spells/"
const BRCREST := UiKit.ART + "brcrest/"
const EXPMRL := UiKit.ART + "expmrl/"
const SURRENDR := UiKit.ART + "surrendr/"
const ARTIFACT := UiKit.ART + "artifact/"

const MAP_X := 97
const SCREEN_X := 177
const FRAME_X := 8  # the window's left edge inside the 302 px frame art
const TOP_HEIGHT := 77  # buybuild 0 drawn from the window's second row
const STRIP_HEIGHT := 45
const BOTTOM_HEIGHT := 48
const TEXT_RECT := Rect2(31, 54, 240, 0)  # window (23, 53)
const LINE_SPACING := 2  # 16 px a line
const OKAY_X := 102  # window x 94
const YES_X := 31  # window x 23
const NO_X := 173  # window x 165
## The box height each icon type reserves when the window is sized (0xd04c0..0xd0518).
const SIZE_BOX := {0: 44, 1: 44, 2: 44, 3: 44, 4: 44, 5: 44, 6: 26, 7: 76, 8: 52, 9: 55,
		10: 28, 11: 57, 12: 62, 13: 59, 14: 76, 15: 111}
## The box each icon type is drawn in (0xd0b67..0xd0c2a); a caption adds 12.
const DRAW_BOX := {0: Vector2i(38, 32), 1: Vector2i(38, 32), 2: Vector2i(38, 32), 3: Vector2i(38, 32),
		4: Vector2i(38, 32), 5: Vector2i(38, 32), 6: Vector2i(76, 26), 7: Vector2i(76, 76),
		8: Vector2i(38, 40), 9: Vector2i(50, 55), 10: Vector2i(64, 28), 11: Vector2i(64, 57),
		12: Vector2i(64, 62), 13: Vector2i(64, 59), 14: Vector2i(64, 64), 15: Vector2i(111, 105)}

var style := OKAY
var on_close: Callable
var window: Control
var bottom_y := 0  # the bottom piece's y inside `window`
var _closing := false

static func present(parent: Node, text: String, p_style: int = OKAY, icons: Array = [],
		on_map := true, x := -1, y := -1, or_word := false) -> MessageBox:
	var box := MessageBox.new()
	parent.add_child(box)
	box.build(text, p_style, icons, on_map, x, y, or_word)
	return box

## `x`/`y`: the window's screen position, -1 for the original's own placement.
## `or_word`: "or" between two icons (the treasure chest).
func build(text: String, p_style: int = OKAY, icons: Array = [], on_map := true,
		x := -1, y := -1, or_word := false) -> void:
	style = p_style
	if layer == 1:
		layer = 200
	var font := UiKit.font_big()
	var wrapped := Homm1Font.wrap(font, text, TEXT_RECT.size.x) if font != null else text
	var text_h := wrapped.split("\n").size() * 16
	var with_buttons := style != HOLD

	var captions: Array[String] = []
	var draw_boxes: Array[Vector2i] = []
	var tallest := 0
	for icon in icons:
		var kind := int(icon[0])
		var caption := _caption(kind, icon[1])
		var box: Vector2i = DRAW_BOX.get(kind, Vector2i.ZERO)
		if caption != "":
			box.y += 12
		captions.append(caption)
		draw_boxes.append(box)
		tallest = maxi(tallest, int(SIZE_BOX.get(kind, 0)))
	var total := text_h + (39 if with_buttons else 0)
	if tallest > 0:
		total += tallest + 12
	var strips := clampi((total - 12) / STRIP_HEIGHT, 1 if with_buttons else 0, 7)
	var height := 129 + strips * STRIP_HEIGHT
	bottom_y = TOP_HEIGHT + strips * STRIP_HEIGHT
	if x < 0 or x + 286 >= 640:
		x = MAP_X if on_map else SCREEN_X
	if y < 0 or y + height >= 480:
		y = mini((480 - height) / 2, 28)

	var blocker := ColorRect.new()
	blocker.name = "InputBlocker"
	blocker.color = Color.TRANSPARENT
	blocker.size = Vector2(640, 480)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)
	blocker.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and style != YES_NO:
			choose(0)
	)

	window = Control.new()
	window.name = _window_name()
	window.position = Vector2(x - FRAME_X, y + 1)
	window.size = Vector2(302, bottom_y + BOTTOM_HEIGHT)
	window.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(window)

	var shadow := ColorRect.new()
	shadow.name = "Shadow"
	shadow.color = Color(0, 0, 0, 0.45)
	shadow.position = Vector2(18, 62)
	shadow.size = Vector2(286, bottom_y - 10)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.add_child(shadow)

	for flip: bool in [true, false]:
		DialogFrame.add_segment(window, BUYBUILD + "0000.png", 0, flip)
		for k in strips:
			DialogFrame.add_segment(window, BUYBUILD + "0001.png", TOP_HEIGHT + k * STRIP_HEIGHT, flip)
		DialogFrame.add_segment(window, BUYBUILD + "0002.png", bottom_y, flip)

	var copy := UiKit.create_label(wrapped, TEXT_RECT.position, Vector2(TEXT_RECT.size.x, text_h + 4), font,
			Color8(240, 240, 240), HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, 0, Color.BLACK, LINE_SPACING)
	copy.name = "Description"
	window.add_child(copy)

	# Icons sit at window x 143 alone, or 95 and 190 as a pair (0xd08ba); the
	# box top is height - box - 27 - 39, centred against a taller neighbour.
	var slots: Array = [143] if icons.size() == 1 else [95, 190]
	var icon_y := 0
	for i in icons.size():
		var kind := int(icons[i][0])
		var value = icons[i][1]
		var box := draw_boxes[i]
		icon_y = height - box.y - 27 - (39 if with_buttons else 0) - 1
		if tallest > box.y:
			icon_y -= (tallest - box.y) / 2
		var slot: int = FRAME_X + slots[i]
		var left := slot - box.x / 2
		match kind:
			0, 1, 2, 3, 4, 5, 6:
				_add_icon("Icon%d" % i, RESOURCE, kind, left, icon_y)
			ICON_ARTIFACT:
				_add_icon("IconFrame%d" % i, RESOURCE, 7, left, icon_y)
				_add_texture("Icon%d" % i, ArtifactCatalog.shared().artifact_icon_path(String(value)), left + 6, icon_y + 6)
			ICON_SPELL:
				_add_icon("Icon%d" % i, SPELLS, int(SpellData.get_spell(String(value)).get("icon", 0)), left, icon_y)
			ICON_CREST:
				_add_icon("Icon%d" % i, BRCREST, clampi(int(value), 0, 3), left, icon_y)
				_add_icon("IconFrame%d" % i, BRCREST, 4, left - 4, icon_y - 4)
			10, 11, 12, 13, 14:
				_add_icon("Icon%d" % i, EXPMRL, kind - 10, left, icon_y)
			ICON_PORTRAIT:
				_add_icon("IconFrame%d" % i, SURRENDR, 4, left, icon_y)
				_add_icon("Icon%d" % i, UiKit.ART + "port%04d/" % int(value), 0, left + 5, icon_y + 5)
		if captions[i] != "":
			_add_small_label("Caption%d" % i, captions[i], Rect2(slot - 50, icon_y + box.y - 10, 100, 14))
	if or_word and icons.size() == 2:
		_add_small_label("Or", "or", Rect2(FRAME_X + 143 - 17, icon_y + 30, 40, 14))

	if style == YES_NO:
		_add_button("yes", SYSTEM, 5, YES_X).name = "Yes"
		_add_button("no", SYSTEM, 7, NO_X).name = "No"
	elif style == OKAY:
		_add_button("okay", NEWGAME, 23, OKAY_X).name = "Okay"

## Named after the dialog class, so tests and callers can find the window.
func _window_name() -> String:
	var global_name := String(get_script().get_global_name())
	return global_name if global_name != "" else "Window"

func _caption(kind: int, value) -> String:
	match kind:
		0, 1, 2, 3, 4, 5, 6:
			var amount := int(value)
			if amount > 0:
				return str(amount)
			if amount < 0:
				return "%d/day" % -amount
		ICON_SPELL:
			return String(SpellData.get_spell(String(value)).get("name", ""))
		ICON_EXPERIENCE:
			if int(value) != -1:
				return str(int(value))
	return ""

## A caption in smalfont, centred in its rect (0xd1681, 0xd195a).
func _add_small_label(node_name: String, text: String, rect: Rect2) -> void:
	var small := UiKit.font_small()
	var lbl := UiKit.create_label(text, rect.position, rect.size, small if small != null else UiKit.font_big())
	lbl.name = node_name
	window.add_child(lbl)

## A frame of an icn directory, drawn at the box plus its own offset.
func _add_icon(node_name: String, dir: String, frame: int, x: int, y: int) -> void:
	var offset: Vector2i = SpecLoader.sprite(dir, frame).get("offset", Vector2i.ZERO)
	_add_texture(node_name, dir + "%04d.png" % frame, x + offset.x, y + offset.y)

func _add_texture(node_name: String, path: String, x: int, y: int) -> void:
	if path == "" or not ResourceLoader.exists(path):
		return
	var icon := TextureRect.new()
	icon.name = node_name
	icon.texture = load(path)
	icon.size = icon.texture.get_size()
	icon.position = Vector2(x, y)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.add_child(icon)

func _add_button(action: String, dir: String, base: int, x: int) -> IcnButton:
	var btn := IcnButton.new()
	btn.setup(dir, base, action)
	btn.position = Vector2(x, bottom_y)
	btn.pressed.connect(func(_action): choose(1 if action == "no" else 0))
	window.add_child(btn)
	return btn

## 0 for YES or OKAY, 1 for NO.
func choose(idx: int) -> void:
	if _closing:
		return
	_closing = true
	chosen.emit(idx)
	closed.emit()
	queue_free()
	if on_close.is_valid():
		on_close.call()

func dismiss() -> void:
	choose(0)

func _on_okay() -> void:
	choose(0)

func _on_choose(idx: int) -> void:
	choose(idx)

## A HOLD popup goes when the right button is let go.
func _input(event: InputEvent) -> void:
	if style == HOLD and event is InputEventMouseButton and not event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		choose(0)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			choose(0)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			choose(1 if style == YES_NO else 0)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and style != YES_NO:
		choose(0)
		get_viewport().set_input_as_handled()
