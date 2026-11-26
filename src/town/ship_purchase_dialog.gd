class_name ShipPurchaseDialog
extends CanvasLayer

signal closed

## shipwind.bin: 302x280 including its 8px outer padding; drawable content is
## 286x264. All local coordinates below are decoded directly from that file.
const ART := UiKit.ART
const X := 177.0
const Y := 108.0
const MID_Y := [78, 123, 168]
const BOTTOM_Y := 213

## heroes.exe 0xb9d51 refuses with this message box, and never opens the
## window, when 32 boats exist or the launch tile is taken.
const BLOCKED_MESSAGE := "Cannot build another boat."
const MAX_BOATS := 32

var _player: PlayerState
var _state: GameState
var _root: Control

static func is_blocked(player: PlayerState, state: GameState) -> bool:
	if state == null:
		return false
	return state.boats.size() >= MAX_BOATS \
			or player.town.can_buy_boat(player, state) == "occupied"

func open(player: PlayerState, state: GameState) -> void:
	_player = player
	_state = state
	layer = 260
	if is_blocked(player, state):
		var parent := get_parent()
		if parent != null:
			MapDialogs.info(parent, {"lines": [BLOCKED_MESSAGE], "centered": true})
		close()
		return
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.size = Vector2(640, 480)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	_piece(0, 0)
	_fill_top_seam()
	for y in MID_Y:
		_piece(1, y)
	_piece(2, BOTTOM_Y)
	_label("Build a new ship:", Vector2(23, 53), Vector2(240, 16), true)
	_label("Resource cost:", Vector2(23, 151), Vector2(240, 16), true)
	_sprite_frame("boat32", 26, Vector2(125, 136))
	_sprite_frame("resource", 6, Vector2(82, 177))
	_sprite_frame("resource", 0, Vector2(164, 170))
	_label("1000", Vector2(82, 202), Vector2(80, 12), false)
	_label("10", Vector2(164, 202), Vector2(40, 12), false)
	# shipwind.bin has no text line for a refusal: the window only drops BUY.
	var status := _player.town.can_buy_boat(_player, _state)
	if status == "buyable":
		_button(1, 2, Vector2(23, 216), _buy)
		_button(3, 4, Vector2(165, 216), close)
	else:
		_button(3, 4, Vector2(94, 216), close)

func _buy() -> void:
	var boat := _player.town.buy_boat(_player, _state)
	if boat == null:
		return
	close()

func close() -> void:
	closed.emit()
	queue_free()

func _piece(frame: int, local_y: float) -> void:
	var tex := UiKit.load_texture(ART + "buybuild/%04d.png" % frame)
	for mirrored in [true, false]:
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.centered = false
		spr.flip_h = mirrored
		spr.position = Vector2(X + (143 - tex.get_width() if mirrored else 143), Y + local_y)
		_root.add_child(spr)

func _fill_top_seam() -> void:
	var tex := UiKit.load_texture(ART + "buybuild/0000.png")
	if tex == null:
		return
	var final_row := AtlasTexture.new()
	final_row.atlas = tex
	final_row.region = Rect2(0, tex.get_height() - 1, tex.get_width(), 1)
	for mirrored in [true, false]:
		var spr := Sprite2D.new()
		spr.texture = final_row
		spr.centered = false
		spr.flip_h = mirrored
		spr.position = Vector2(X + (143 - tex.get_width() if mirrored else 143), Y + 77)
		_root.add_child(spr)

func _sprite(path: String, local: Vector2) -> void:
	UiKit.add_sprite(_root, ART + path, Vector2(X, Y) + local)

func _sprite_frame(dir: String, id: int, anchor: Vector2) -> void:
	var sp := SpecLoader.sprite(ART + dir, id)
	if not sp.is_empty():
		_sprite("%s/%s" % [dir, String(sp.file)], anchor + Vector2(sp.offset))

func _label(value: String, local: Vector2, size: Vector2, big: bool) -> Label:
	var font := UiKit.font_big() if big else UiKit.font_small()
	return UiKit.add_label(_root, value, Vector2(X, Y) + local, size, font, Color.WHITE,
			HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, "", 2, Color.BLACK)

func _button(up: int, down: int, local: Vector2, callback: Callable) -> void:
	var button := TextureButton.new()
	button.texture_normal = UiKit.load_texture(ART + "system/%04d.png" % up)
	button.texture_pressed = UiKit.load_texture(ART + "system/%04d.png" % down)
	button.position = Vector2(X, Y) + local
	button.size = button.texture_normal.get_size()
	button.pressed.connect(callback)
	_root.add_child(button)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		# shipwind.bin: BUY is Enter, CANCEL is Esc.
		if _player.town.can_buy_boat(_player, _state) == "buyable":
			_buy()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
