# src/town/buy_spellbook_dialog.gd
class_name BuySpellbookDialog
extends CanvasLayer

const DialogFrame := preload("res://src/ui/dialog_frame.gd")

## Native Buy Spellbook popup reconstructed from buybook.bin.
## Offers the visiting hero a spellbook for 500 gold.

signal closed
signal bought

const BUYBUILD := UiKit.ART + "buybuild/"
const SYSTEM := UiKit.ART + "system/"
const ARTIFACT := UiKit.ART + "artifact/"
const RESOURCE := UiKit.ART + "resource/"

const FRAME_POS := Vector2(177, 108)
const FRAME_SIZE := Vector2(286, 264)
const MID_Y := [78, 123, 168]
const BOTTOM_Y := 213

var _player: PlayerState
var _hero: HeroModel
var _root: Control
var _font_big: FontFile
var _font_small: FontFile
var _okay_btn: Button = null
var _cancel_btn: Button = null

func open(player: PlayerState, hero: HeroModel) -> void:
	_player = player
	_hero = hero
	layer = 260
	_font_big = UiKit.font_big()
	_font_small = UiKit.font_small()

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	DialogFrame.add_piece(_root, FRAME_POS, 0, 0)
	DialogFrame.fill_top_seam(_root, FRAME_POS)
	for y: int in MID_Y:
		DialogFrame.add_piece(_root, FRAME_POS, 1, y)
	DialogFrame.add_piece(_root, FRAME_POS, 2, BOTTOM_Y)

	UiKit.add_label(_root, "Buy Spellbook:", FRAME_POS + Vector2(23, 53), Vector2(240, 16), _font_big,
			Color8(240, 240, 240), HORIZONTAL_ALIGNMENT_CENTER)

	# Spellbook icon
	UiKit.add_sprite(_root, ARTIFACT + "0037.png", FRAME_POS + Vector2(111, 74))

	UiKit.add_label(_root, "Resource cost:", FRAME_POS + Vector2(23, 151), Vector2(240, 16), _font_big,
			Color8(240, 240, 240), HORIZONTAL_ALIGNMENT_CENTER)

	# Gold icon and cost
	UiKit.add_sprite(_root, RESOURCE + "0006.png", FRAME_POS + Vector2(103, 177))

	# buybook.bin has the cost as " 500", with a leading space.
	UiKit.add_label(_root, " 500", FRAME_POS + Vector2(103, 202), Vector2(80, 12), _font_small,
			Color8(240, 240, 240), HORIZONTAL_ALIGNMENT_CENTER)

	var can_afford: bool = _player != null and _player.town != null \
			and _player.town.gold >= _player.town.SPELLBOOK_COST

	_okay_btn = _button(SYSTEM, 9, 10, Vector2(23, 216), _on_buy)
	_okay_btn.disabled = not can_afford
	_cancel_btn = _button(SYSTEM, 11, 12, Vector2(165, 216), close)

func buy_button() -> Button:
	return _okay_btn

func cancel_button() -> Button:
	return _cancel_btn

func dialog_rect() -> Rect2:
	return Rect2(FRAME_POS, FRAME_SIZE)

func _on_buy() -> void:
	if _player != null and _player.buy_spellbook(_hero):
		if _player.town != null:
			_player.town.teach_visiting_hero(_hero)
		bought.emit()
	close()

func close() -> void:
	closed.emit()
	queue_free()

func _button(dir: String, up_frame: int, down_frame: int, local_pos: Vector2,
		callback: Callable) -> Button:
	var btn := Button.new()
	var tex_normal := UiKit.load_texture(dir + "%04d.png" % up_frame)
	var tex_pressed := UiKit.load_texture(dir + "%04d.png" % down_frame)
	var sb_normal := StyleBoxTexture.new()
	sb_normal.texture = tex_normal
	var sb_pressed := StyleBoxTexture.new()
	sb_pressed.texture = tex_pressed
	btn.add_theme_stylebox_override("normal", sb_normal)
	btn.add_theme_stylebox_override("hover", sb_normal)
	btn.add_theme_stylebox_override("pressed", sb_pressed)
	btn.add_theme_stylebox_override("disabled", sb_normal)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.position = FRAME_POS + local_pos
	btn.size = tex_normal.get_size()
	btn.pressed.connect(callback)
	_root.add_child(btn)
	return btn

func _unhandled_input(event: InputEvent) -> void:
	# buybook.bin: OKAY is Enter, CANCEL is Esc.
	if event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		if not _okay_btn.disabled:
			_on_buy()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		close()
		get_viewport().set_input_as_handled()
