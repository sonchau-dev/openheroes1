class_name DimensionDoorDialog
extends CanvasLayer

## Authentic Dimension Door targeting overlay reconstructed from dimdoor.bin (640x480).
## Prompts "Dimension Door:\nSelect Destination" in bigfont.fnt within the 144x144
## woodgrai.png panel at (480, 16), with authentic Cancel button from legend.icn at (512, 119),
## while allowing destination selection on the adventure map viewport (Rect2(16, 16, 448, 456)).

signal destination_selected(tile: Vector2i)
signal cancelled
signal closed

const ART := UiKit.ART
const WOODGRAI := ART + "woodgrai.png"
const LEGEND := ART + "legend/"
const FONT_BIG := ART + "font/"

const VIEWPORT_RECT := Rect2(16, 16, 448, 456)
const PANEL_RECT := Rect2(480, 16, 144, 144)
const CANCEL_BTN_POS := Vector2(512, 119)
const CANCEL_BTN_SIZE := Vector2(80, 25)

var _map: MapData
var _root_ctrl: Control
var _prompt_label: Label
var _cancel_btn: TextureButton

func _init() -> void:
	layer = 210

func open(map: MapData = null) -> void:
	_map = map
	_build_ui()

func _build_ui() -> void:
	for child in get_children():
		child.queue_free()

	_root_ctrl = Control.new()
	_root_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_ctrl.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_root_ctrl)

	# Click catcher for adventure map viewport (16, 16, 448, 456)
	var vp_catcher := Control.new()
	vp_catcher.position = VIEWPORT_RECT.position
	vp_catcher.size = VIEWPORT_RECT.size
	vp_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	vp_catcher.gui_input.connect(_on_viewport_input)
	_root_ctrl.add_child(vp_catcher)

	# Right-side wood grain panel from dimdoor.bin (x=480, y=16, w=144, h=144)
	var wood_tex := load(WOODGRAI) as Texture2D
	if wood_tex != null:
		var wood_rect := TextureRect.new()
		wood_rect.texture = wood_tex
		wood_rect.position = PANEL_RECT.position
		wood_rect.size = PANEL_RECT.size
		wood_rect.mouse_filter = Control.MOUSE_FILTER_STOP
		_root_ctrl.add_child(wood_rect)

	# Text prompt decoded from dimdoor.bin: "Dimension Door:\nSelect Destination" at (480, 32)
	var font := Homm1Font.load_font(FONT_BIG)
	_prompt_label = Label.new()
	# heroes.exe 0xd7de4 word-wraps text records to their width; "Select Destination" is wider than 144.
	_prompt_label.text = Homm1Font.wrap(font, "Dimension Door:\nSelect Destination", PANEL_RECT.size.x)
	_prompt_label.position = Vector2(480, 32)
	_prompt_label.size = Vector2(144, 80)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_label.add_theme_font_override("font", font)
	_prompt_label.add_theme_font_size_override("font_size", font.fixed_size)
	_prompt_label.add_theme_color_override("font_color", Color8(240, 240, 240))
	_prompt_label.add_theme_constant_override("line_spacing", 2)  # 16 px bigfont line cadence
	_root_ctrl.add_child(_prompt_label)

	# Authentic Cancel button decoded from dimdoor.bin (legend.icn 80x25 at 512, 119)
	_cancel_btn = TextureButton.new()
	_cancel_btn.texture_normal = load(LEGEND + "0000.png") as Texture2D
	_cancel_btn.texture_pressed = load(LEGEND + "0001.png") as Texture2D
	_cancel_btn.position = CANCEL_BTN_POS
	_cancel_btn.size = CANCEL_BTN_SIZE
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	_root_ctrl.add_child(_cancel_btn)

func _on_viewport_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var screen_pos := VIEWPORT_RECT.position + mb.position
			var tile := _screen_to_tile(screen_pos)
			_on_tile_selected(tile)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_on_cancel_pressed()

func _screen_to_tile(screen_pos: Vector2) -> Vector2i:
	var vp := get_viewport()
	var world := screen_pos
	if vp != null:
		world = vp.get_canvas_transform().affine_inverse() * screen_pos
	var tile_size := _map.tile_size if _map != null else 32
	return Vector2i(int(world.x) / tile_size, int(world.y) / tile_size)

## The listener closes the dialog once it accepts the tile; a refused click leaves it open.
func _on_tile_selected(tile: Vector2i) -> void:
	destination_selected.emit(tile)

func _on_cancel_pressed() -> void:
	cancelled.emit()
	close()

func close() -> void:
	closed.emit()
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ESCAPE:
			_on_cancel_pressed()
			get_viewport().set_input_as_handled()

func dialog_rect() -> Rect2:
	return PANEL_RECT

func cancel_button_rect() -> Rect2:
	return Rect2(CANCEL_BTN_POS, CANCEL_BTN_SIZE)

func prompt_text() -> String:
	return _prompt_label.text if _prompt_label != null else ""

func select_tile(tile: Vector2i) -> void:
	_on_tile_selected(tile)

func cancel() -> void:
	_on_cancel_pressed()
