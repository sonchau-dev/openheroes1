# src/town/tavern_dialog.gd
class_name TavernDialog
extends CanvasLayer

## Authentic HOMM1 Tavern dialog decoded from tavwin.bin
## (302x325 window, 286x309 drawable at Vector2(177, 77)).
## Displays the animated tavern scene (tavwin.icn at 6.0 FPS),
## the morale boost notice, and a SYSTEM.ICN OKAY button.

signal closed

const BUYBUILD := UiKit.ART + "buybuild/"
const SYSTEM := UiKit.ART + "system/"
const TAVWIN := UiKit.ART + "tavwin/"

const FRAME_POS := Vector2(177, 77)
const FRAME_SIZE := Vector2(286, 309)
const MID_Y := [78, 123, 168, 213]
const BOTTOM_Y := 258

const TITLE_POS := Vector2(23, 53)
const TITLE_SIZE := Vector2(240, 16)
const ART_BASE_POS := Vector2(49, 73)
const ART_OVERLAY_OFFSET := Vector2(93, 63)
const BODY_POS := Vector2(23, 180)
const BODY_SIZE := Vector2(240, 80)
const OKAY_POS := Vector2(94, 261)

const ANIM_FPS := 6.0
const FRAME_DURATION := 1.0 / ANIM_FPS

var _root: Control
var _font_big: FontFile
var _title_label: Label
var _body_label: Label
var _overlay_sprite: Sprite2D
var _okay_btn: IcnButton
var _overlay_textures: Array[Texture2D] = []
var _anim_frame: int = 1
var _anim_timer: float = 0.0
var _closing: bool = false

func open() -> void:
	layer = 220
	_closing = false
	_font_big = UiKit.font_big()

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.45)
	dim.position = Vector2.ZERO
	dim.size = Vector2(640, 480)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			close()
	)

	_root = Control.new()
	_root.name = "DialogRoot"
	_root.position = FRAME_POS
	_root.size = FRAME_SIZE
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var shadow := ColorRect.new()
	shadow.name = "Shadow"
	shadow.color = Color(0, 0, 0, 0.45)
	shadow.position = Vector2(10, 10)
	shadow.size = FRAME_SIZE
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shadow)

	# Stone frame segments (buybuild.icn)
	_piece(0, 0)
	_fill_top_seam()
	for y: int in MID_Y:
		_piece(1, y)
	_piece(2, BOTTOM_Y)

	# Title: "Tavern"
	_title_label = UiKit.add_label(_root, "Tavern", TITLE_POS, TITLE_SIZE, _font_big,
			Color8(240, 240, 240), HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, "Title")

	# Base artwork (tavwin/0000.png)
	UiKit.add_sprite(_root, TAVWIN + "0000.png", ART_BASE_POS, 0, "TavernBase")

	# Animated overlay artwork (tavwin/0001.png..0008.png)
	_overlay_textures.clear()
	for i in range(1, 9):
		_overlay_textures.append(UiKit.load_texture(TAVWIN + "%04d.png" % i))

	_overlay_sprite = Sprite2D.new()
	_overlay_sprite.name = "TavernOverlay"
	_overlay_sprite.texture = _overlay_textures[0]
	_overlay_sprite.centered = false
	_overlay_sprite.position = ART_BASE_POS + ART_OVERLAY_OFFSET
	_root.add_child(_overlay_sprite)

	# Body text
	_body_label = UiKit.add_boxed_label(_root, "Description", "The tavern increases the morale of all garrisoned troops.",
			Rect2(BODY_POS, BODY_SIZE), _font_big, true)
	_body_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	(_body_label.get_parent() as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

	# OKAY button (system.icn frame 1 normal, 2 pressed)
	_okay_btn = IcnButton.new()
	_okay_btn.name = "OkayButton"
	_okay_btn.setup(SYSTEM, 1, "okay")
	_okay_btn.position = OKAY_POS
	_okay_btn.pressed.connect(func(_action: String): close())
	_root.add_child(_okay_btn)

func _process(delta: float) -> void:
	advance_anim(delta)

func advance_anim(delta: float) -> void:
	if _overlay_textures.is_empty():
		return
	_anim_timer += delta
	while _anim_timer >= FRAME_DURATION:
		_anim_timer -= FRAME_DURATION
		_anim_frame = (_anim_frame % 8) + 1
		if _overlay_sprite != null:
			_overlay_sprite.texture = _overlay_textures[_anim_frame - 1]

func current_anim_frame() -> int:
	return _anim_frame

func dialog_rect() -> Rect2:
	return Rect2(FRAME_POS, FRAME_SIZE)

func title_text() -> String:
	return _title_label.text if _title_label != null else ""

func body_text() -> String:
	return _body_label.text if _body_label != null else ""

func okay_button() -> IcnButton:
	return _okay_btn

func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()

func _piece(frame: int, local_y: int) -> void:
	var tex := UiKit.load_texture(BUYBUILD + "%04d.png" % frame)
	if tex == null:
		return
	for mirrored: bool in [true, false]:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.centered = false
		sprite.flip_h = mirrored
		sprite.position = Vector2(143 - tex.get_width() if mirrored else 143, local_y)
		_root.add_child(sprite)

func _fill_top_seam() -> void:
	var tex := UiKit.load_texture(BUYBUILD + "0000.png")
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
		sprite.position = Vector2(143 - tex.get_width() if mirrored else 143, 77)
		_root.add_child(sprite)

func _unhandled_input(event: InputEvent) -> void:
	if _closing:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			close()
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			close()
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
