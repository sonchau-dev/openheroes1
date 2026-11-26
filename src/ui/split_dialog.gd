class_name SplitDialog
extends CanvasLayer

## Native HOMM1 stack-split dialog reconstructed from splitwin.bin.
## Displays the authentic prompt "Move how many %s troops from %s to %s?"
## with a 286x219 buybuild frame, recessed quantity input box, arrow steppers,
## and OKAY / CANCEL buttons. The first %s is the creature name as heroes.exe
## spells it, lower case and singular ("Move how many sprite troops from
## Rebecca to Luna?", DOS capture of the exchange window).

signal confirmed(quantity: int)
signal cancelled
signal closed

const ART := UiKit.ART
const BUYBUILD := ART + "buybuild/"
const TOWNWIND := ART + "townwind/"
const SYSTEM := ART + "system/"
const FONT_BIG := ART + "font/"
const FONT_SMALL := ART + "smalfont/"

const FRAME_POS := Vector2(177, 130)
const FRAME_SIZE := Vector2(286, 219)
const MID_Y := [78, 123]
const BOTTOM_Y := 168

var _unit: String = ""
var _from_name: String = ""
var _to_name: String = ""
var _min_qty: int = 1
var _max_qty: int = 1
var _quantity: int = 1
var _typed_buffer: String = ""

var _root: Control
var _font_big: FontFile
var _font_small: FontFile
var _prompt: Label
var _qty_label: Label
var _buttons: Dictionary = {}

func open(unit: String, from_name: String, to_name: String, min_qty: int, max_qty: int, default_qty := -1) -> void:
	layer = 280
	_unit = unit
	_from_name = from_name
	_to_name = to_name
	_min_qty = maxi(1, min_qty)
	_max_qty = maxi(_min_qty, max_qty)
	if default_qty >= _min_qty and default_qty <= _max_qty:
		_quantity = default_qty
	else:
		_quantity = maxi(_min_qty, int(_max_qty / 2))
	_typed_buffer = ""

	_font_big = Homm1Font.load_font(FONT_BIG)
	_font_small = Homm1Font.load_font(FONT_SMALL)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.4)
	dim.size = Vector2(640, 480)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_piece(0, 0)
	_fill_top_seam()
	for y: int in MID_Y:
		_piece(1, y)
	_piece(2, BOTTOM_Y)

	# Prompt text decoded from splitwin.bin (x=23, y=53, w=240, h=60)
	_prompt = Label.new()
	# Wrap before the size goes in: set_size clamps a non-wrapping label to its unwrapped width.
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD
	_prompt.text = "Move how many %s troops from %s to %s?" % [
		CreatureCatalog.singular(_unit),
		_from_name,
		_to_name
	]
	_prompt.position = FRAME_POS + Vector2(23, 53)
	_prompt.size = Vector2(240, 60)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_theme_color_override("font_color", Color8(240, 240, 240))
	_prompt.add_theme_font_override("font", _font_big)
	_prompt.add_theme_font_size_override("font_size", _font_big.fixed_size)
	_root.add_child(_prompt)

	# Recessed quantity input box decoded from splitwin.bin (x=110, y=120, w=68, h=19)
	var box_sprite := Sprite2D.new()
	box_sprite.texture = load(TOWNWIND + "0004.png") as Texture2D
	box_sprite.centered = false
	box_sprite.position = FRAME_POS + Vector2(110, 120)
	_root.add_child(box_sprite)

	_qty_label = Label.new()
	_qty_label.text = str(_quantity)
	_qty_label.position = FRAME_POS + Vector2(110, 122)
	_qty_label.size = Vector2(68, 16)
	_qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_qty_label.add_theme_color_override("font_color", Color8(240, 240, 240))
	_qty_label.add_theme_font_override("font", _font_big)
	_qty_label.add_theme_font_size_override("font_size", _font_big.fixed_size)
	_root.add_child(_qty_label)

	# Arrow stepper buttons decoded from splitwin.bin (x=179, y=115 up, y=130 down)
	_button("up", TOWNWIND, 5, 6, Vector2(179, 115), _on_up_pressed)
	_button("down", TOWNWIND, 7, 8, Vector2(179, 130), _on_down_pressed)

	# Action buttons decoded from splitwin.bin (OKAY at x=23, y=168; CANCEL at x=165, y=168)
	_button("okay", SYSTEM, 9, 10, Vector2(23, 168), _on_okay_pressed)
	_button("cancel", SYSTEM, 11, 12, Vector2(165, 168), _on_cancel_pressed)

func _set_quantity(val: int) -> void:
	_quantity = clampi(val, _min_qty, _max_qty)
	if _qty_label != null:
		_qty_label.text = str(_quantity)

func _on_up_pressed() -> void:
	_typed_buffer = ""
	_set_quantity(_quantity + 1)

func _on_down_pressed() -> void:
	_typed_buffer = ""
	_set_quantity(_quantity - 1)

func _on_okay_pressed() -> void:
	confirmed.emit(_quantity)
	close()

func _on_cancel_pressed() -> void:
	cancelled.emit()
	close()

func close() -> void:
	closed.emit()
	queue_free()

func dialog_rect() -> Rect2:
	return Rect2(FRAME_POS, FRAME_SIZE)

func button_rect(name: String) -> Rect2:
	var btn = _buttons.get(name) as TextureButton
	if btn != null:
		return Rect2(btn.position, btn.size)
	return Rect2()

func prompt_text() -> String:
	return _prompt.text if _prompt != null else ""

func quantity() -> int:
	return _quantity

func set_quantity(val: int) -> void:
	_set_quantity(val)

func up_pressed() -> void:
	_on_up_pressed()

func down_pressed() -> void:
	_on_down_pressed()

func okay_pressed() -> void:
	_on_okay_pressed()

func _piece(frame: int, local_y: int) -> void:
	var tex := load(BUYBUILD + "%04d.png" % frame) as Texture2D
	if tex == null:
		return
	for mirrored: bool in [true, false]:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.centered = false
		sprite.flip_h = mirrored
		sprite.position = FRAME_POS + Vector2(143 - tex.get_width() if mirrored else 143, local_y)
		_root.add_child(sprite)

func _fill_top_seam() -> void:
	var tex := load(BUYBUILD + "0000.png") as Texture2D
	if tex == null:
		return
	var final_row := AtlasTexture.new()
	final_row.atlas = tex
	final_row.region = Rect2(0, tex.get_height() - 1, tex.get_width(), 1)
	for mirrored: bool in [true, false]:
		var sprite := Sprite2D.new()
		sprite.texture = final_row
		sprite.centered = false
		sprite.flip_h = mirrored
		sprite.position = FRAME_POS + Vector2(143 - tex.get_width() if mirrored else 143, 77)
		_root.add_child(sprite)

func _button(name: String, dir: String, up: int, down: int, local: Vector2, callback: Callable) -> void:
	var button := TextureButton.new()
	button.texture_normal = load(dir + "%04d.png" % up) as Texture2D
	button.texture_pressed = load(dir + "%04d.png" % down) as Texture2D
	button.position = FRAME_POS + local
	button.size = button.texture_normal.get_size()
	button.pressed.connect(callback)
	_buttons[name] = button
	_root.add_child(button)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ESCAPE:
			_on_cancel_pressed()
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER:
			_on_okay_pressed()
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_UP:
			_on_up_pressed()
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_DOWN:
			_on_down_pressed()
			get_viewport().set_input_as_handled()
		elif key_event.keycode >= KEY_0 and key_event.keycode <= KEY_9:
			var digit := str(key_event.keycode - KEY_0)
			_typed_buffer += digit
			_set_quantity(int(_typed_buffer))
			get_viewport().set_input_as_handled()
		elif key_event.keycode >= KEY_KP_0 and key_event.keycode <= KEY_KP_9:
			var digit := str(key_event.keycode - KEY_KP_0)
			_typed_buffer += digit
			_set_quantity(int(_typed_buffer))
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_BACKSPACE:
			if _typed_buffer.length() > 0:
				_typed_buffer = _typed_buffer.substr(0, _typed_buffer.length() - 1)
				if _typed_buffer.is_empty():
					_set_quantity(_min_qty)
				else:
					_set_quantity(int(_typed_buffer))
			else:
				_set_quantity(_min_qty)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and not dialog_rect().has_point(mb.position):
			_on_cancel_pressed()
			get_viewport().set_input_as_handled()
