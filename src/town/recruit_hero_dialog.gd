class_name RecruitHeroDialog
extends CanvasLayer

const DialogFrame := preload("res://src/ui/dialog_frame.gd")

## Native recruit-hero popup reconstructed from rcrthero.bin. The binary's
## 302x325 window includes an 8px outer margin; its drawable 286x309 frame is
## placed at (177, 16) in the 640x480 town screen, matching the DOS reference.

signal closed
signal recruited(hero: HeroModel)

const ART := UiKit.ART
const BUYBUILD := UiKit.ART + "buybuild/"
const TOWNWIND := UiKit.ART + "townwind/"
const SYSTEM := UiKit.ART + "system/"
const PORT := UiKit.ART + "port%04d/0000.png"
const HERO_SCREEN := preload("res://src/hero/hero_screen.gd")

const FRAME_POS := Vector2(177, 16)
const FRAME_SIZE := Vector2(286, 309)
const MID_Y := [78, 123, 168, 213]
const BOTTOM_Y := 258
const CANDIDATE_X := [26, 149]

var _player: PlayerState
var _candidates: Array = []
var _root: Control
var _font_big: FontFile
var _font_small: FontFile
var _town_tile := Vector2i(-1, -1)
var _hero_screen: Node2D
var _view_only := false   # right-click window: no buttons, closed from outside

## `view_only` draws the window with no buttons and no portrait clicks, the
## way a right click on a Castle Options cell shows it.
func open(player: PlayerState, candidates: Array, town_tile := Vector2i(-1, -1),
		view_only := false) -> void:
	_view_only = view_only
	_player = player
	_candidates = candidates.slice(0, mini(2, candidates.size()))
	_town_tile = town_tile
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

	var title := _label("Recruit Hero", Vector2(23, 53), Vector2(240, 16), _font_big)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	for i in _candidates.size():
		_draw_candidate(i, _candidates[i] as HeroModel)

	_sprite_frame("resource", 6, Vector2(103, 223))
	var cost := _label(str(HeroPool.COST), Vector2(103, 248), Vector2(80, 12), _font_small)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not _view_only:
		_button(SYSTEM, 3, 4, Vector2(94, 261), close)

func dialog_rect() -> Rect2:
	return Rect2(FRAME_POS, FRAME_SIZE)

func candidate_rect(index: int) -> Rect2:
	if index < 0 or index >= CANDIDATE_X.size():
		return Rect2()
	return Rect2(FRAME_POS + Vector2(CANDIDATE_X[index], 74), Vector2(111, 122))

func candidate_button_rect(index: int) -> Rect2:
	if index < 0 or index >= CANDIDATE_X.size():
		return Rect2()
	return Rect2(FRAME_POS + Vector2(CANDIDATE_X[index], 196), Vector2(111, 25))

func select_candidate(index: int) -> bool:
	if index < 0 or index >= _candidates.size():
		return false
	var hero := _candidates[index] as HeroModel
	if hero == null or not _player.hire(hero, _town_tile):
		return false
	recruited.emit(hero)
	close()
	return true

func close() -> void:
	closed.emit()
	queue_free()

## Either mouse button on a portrait opens the full hero screen, the same one
## the adventure map opens, read-only over this dialog.
func show_candidate_details(index: int) -> void:
	if _hero_screen != null or index < 0 or index >= _candidates.size():
		return
	_hero_screen = HERO_SCREEN.open_preview(self, _candidates[index] as HeroModel)
	_hero_screen.closed.connect(func() -> void: _hero_screen = null)

func _draw_candidate(index: int, hero: HeroModel) -> void:
	var x: int = CANDIDATE_X[index]
	_sprite(TOWNWIND + "0018.png", Vector2(x, 74))
	_sprite(PORT % hero.portrait_idx, Vector2(x + 5, 80))
	var class_label := _label(hero.hero_class.capitalize(), Vector2(x, 182),
			Vector2(111, 12), _font_small)
	class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if _view_only:
		return
	var inspect_ctrl := Control.new()
	inspect_ctrl.position = FRAME_POS + Vector2(x, 74)
	inspect_ctrl.size = Vector2(111, 122)
	inspect_ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
	inspect_ctrl.gui_input.connect(func(ev: InputEvent):
		var mb := ev as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			show_candidate_details(index)
	)
	_root.add_child(inspect_ctrl)

	_button(TOWNWIND, 20, 21, Vector2(x, 196), select_candidate.bind(index))

func _sprite(path: String, local: Vector2) -> Sprite2D:
	return UiKit.add_sprite(_root, path, FRAME_POS + local)

func _sprite_frame(dir: String, frame: int, anchor: Vector2) -> void:
	var sp := SpecLoader.sprite(ART + dir, frame)
	if not sp.is_empty():
		_sprite(ART + "%s/%s" % [dir, String(sp.file)], anchor + Vector2(sp.offset))

func _label(value: String, local: Vector2, label_size: Vector2, font: FontFile) -> Label:
	return UiKit.add_label(_root, value, FRAME_POS + local, label_size, font, Color8(240, 240, 240))

func _button(dir: String, up: int, down: int, local: Vector2, callback: Callable) -> void:
	var button := TextureButton.new()
	button.texture_normal = UiKit.load_texture(dir + "%04d.png" % up)
	button.texture_pressed = UiKit.load_texture(dir + "%04d.png" % down)
	button.position = FRAME_POS + local
	button.size = button.texture_normal.get_size()
	button.pressed.connect(callback)
	_root.add_child(button)

func _unhandled_input(event: InputEvent) -> void:
	if _view_only or _hero_screen != null:
		return
	if event is InputEventKey and event.pressed and (event.keycode == KEY_ESCAPE or event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and not dialog_rect().has_point(mb.position):
			close()
			get_viewport().set_input_as_handled()
