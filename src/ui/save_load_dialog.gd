class_name SaveLoadDialog
extends CanvasLayer

## Modal save/load slot picker rendered on the authentic HOMM1 file dialog art
## (request.png background + request.icn OKAY/CANCEL buttons), measured off the
## DOS original.
## The opener owns the actual Game.save_game/load_game call via `confirmed` —
## this class only picks a slot name, so it stays testable without autoloads.
##
## Geometry is dialog-local within request.png (320x331), from request.bin:
## ten list rows (56, 41 + 20k, 207x20), the name field (48,253,225x19), OKAY
## and CANCEL at (36,280) and (189,280). Both modes show the file list and the
## file name only; the size/difficulty panel belongs to the scenario picker.

signal confirmed(slot: String)
signal closed

enum Mode { SAVE, LOAD }

const BG := UiKit.ART + "request.png"
const REQ_ICN := UiKit.ART + "request/"
const FONT_DIR := UiKit.FONT

# Where the original opens each dialog (DOSBox captures): Save over the
# adventure map, Load on the right of the main menu.
const SAVE_DIALOG_POS := Vector2(160, 40)
const LOAD_DIALOG_POS := Vector2(310, 14)

const TITLE_RECT := Rect2(12, 22, 296, 16)
const LIST_X := 56.0
const LIST_TOP := 40.0   # request.bin row 41; a centred Button draws 1 px lower
const LIST_W := 207.0
const ROW_H := 20.0
const MAX_ROWS := 10
const NEW_NAME_MAX := 12   # new saves; older, longer names still list (ellipsized) and load
const ELLIPSIS := "..."
const ROW_PAD := 8.0
const NAME_RECT := Rect2(52, 247, 216, 16)   # glyphs on the original's rows in the name field (SAVE)
const ERR_RECT := Rect2(18, 224, 244, 15)
const OKAY_POS := Vector2(36, 280)            # baked-gold (40,280) minus 4px margin
const CANCEL_POS := Vector2(189, 280)         # baked-gold (193,280) minus 4px margin

const SCROLL_UP_POS := Vector2(278, 35)
const SCROLL_DOWN_POS := Vector2(278, 233)
const SCROLL_ICN := UiKit.ART + "scroll2/"
const THUMB := UiKit.ART + "scroll/0004.png"
const THUMB_X := 283.0
const THUMB_TOP := 56.0
const THUMB_TRAVEL := 156.0   # the original centres it (top 134) when nothing scrolls

# request.bin's name field (48,253), 2 px lower because a top-aligned Label
# draws the glyphs 2 px higher than the original (DOSBox capture).
const SELECTED_NAME_POS := Vector2(48, 255)
const SELECTED_NAME_SIZE := Vector2(225, 19)

var _mode: int = Mode.SAVE
var _dir: String = SaveGame.SAVE_DIR
var _slots: Array = []            # SaveGame.list_slots() entries
var _selected: int = -1
var _scroll_offset: int = 0
var _rows: Array = []             # Button per slot row
var _scroll_up_btn: IcnButton = null
var _scroll_down_btn: IcnButton = null
var _name_edit: LineEdit = null   # SAVE mode only
var _selected_name_label: Label = null   # LOAD mode file name on the purple bar
var _thumb: TextureRect = null
var _highlight: TextureRect = null
var _error_label: Label = null
var _root: Control = null
var _font: Font = null
var _game_mode_filter: String = ""

func open(mode: int, dir: String = SaveGame.SAVE_DIR, game_mode_filter: String = "") -> void:
	_mode = mode
	_dir = dir
	_game_mode_filter = game_mode_filter
	layer = 200
	_font = UiKit.font()

	# Transparent modal blocker (added first = bottom): swallows clicks outside
	# the dialog without dimming the map, matching the DOS file dialog.
	var blocker := ColorRect.new()
	blocker.color = Color(0, 0, 0, 0)
	blocker.size = Vector2(640, 480)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)

	_root = Control.new()
	_root.position = LOAD_DIALOG_POS if _mode == Mode.LOAD else SAVE_DIALOG_POS
	_root.size = Vector2(320, 331)
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_root)
	UiKit.add_tex(_root, BG, Vector2.ZERO)
	_thumb = UiKit.add_tex(_root, THUMB, Vector2(THUMB_X, THUMB_TOP))

	var title_text := "File to Save:" if _mode == Mode.SAVE else "File to Load:"
	UiKit.add_label(_root, title_text, TITLE_RECT.position, TITLE_RECT.size, _font, Color8(255, 255, 255))

	_highlight = TextureRect.new()
	var hl_tex := load(REQ_ICN + "0000.png") as Texture2D
	if hl_tex != null:
		_highlight.texture = hl_tex
	_highlight.position = Vector2(48, LIST_TOP)
	_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_highlight.visible = false
	_root.add_child(_highlight)

	_slots = SaveGame.list_slots(_dir, _game_mode_filter)
	_scroll_offset = 0

	var y := LIST_TOP
	for i in MAX_ROWS:
		var row := Button.new()
		row.flat = true
		row.position = Vector2(LIST_X, y)
		row.size = Vector2(LIST_W, ROW_H)
		row.alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		if _font != null:
			row.add_theme_font_override("font", _font)
			row.add_theme_font_size_override("font_size", _font.fixed_size)
		_style_row_button(row)
		var row_idx := i
		row.pressed.connect(func(): _on_row_clicked(row_idx))
		_root.add_child(row)
		_rows.append(row)
		y += ROW_H

	_scroll_up_btn = IcnButton.new()
	_scroll_up_btn.setup(SCROLL_ICN, 0, "scroll_up")
	_scroll_up_btn.position = SCROLL_UP_POS
	_scroll_up_btn.pressed.connect(func(_a): _scroll(-1))
	_root.add_child(_scroll_up_btn)

	_scroll_down_btn = IcnButton.new()
	_scroll_down_btn.setup(SCROLL_ICN, 2, "scroll_down")
	_scroll_down_btn.position = SCROLL_DOWN_POS
	_scroll_down_btn.pressed.connect(func(_a): _scroll(1))
	_root.add_child(_scroll_down_btn)

	_refresh_rows()

	if _mode == Mode.SAVE:
		_name_edit = LineEdit.new()
		_name_edit.max_length = NEW_NAME_MAX
		_name_edit.position = NAME_RECT.position
		# custom_minimum_size pins the control to the bar height; without it the
		# LineEdit keeps its tall theme minimum and vertically centers the text
		# well below the purple bar.
		_name_edit.custom_minimum_size = NAME_RECT.size
		_name_edit.size = NAME_RECT.size
		_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name_edit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		_name_edit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		_name_edit.add_theme_color_override("font_color", Color8(255, 255, 255))
		_name_edit.add_theme_color_override("caret_color", Color8(255, 234, 120))
		if _font != null:
			_name_edit.add_theme_font_override("font", _font)
			_name_edit.add_theme_font_size_override("font_size", _font.fixed_size)
		_root.add_child(_name_edit)
	else:
		_selected_name_label = UiKit.add_label(_root, "", SELECTED_NAME_POS, SELECTED_NAME_SIZE,
				_font, Color8(255, 255, 255))
		# The original opens Load with the first file already chosen.
		if not _slots.is_empty():
			select_slot(0)

	_error_label = UiKit.add_label(_root, "", ERR_RECT.position, ERR_RECT.size, _font, Color8(255, 110, 90))

	var okay := IcnButton.new()
	okay.setup(REQ_ICN, 1, "okay")
	okay.position = OKAY_POS
	okay.pressed.connect(func(_a): confirm())
	_root.add_child(okay)

	var cancel := IcnButton.new()
	cancel.setup(REQ_ICN, 3, "cancel")
	cancel.position = CANCEL_POS
	cancel.pressed.connect(func(_a): _close())
	_root.add_child(cancel)

func _scroll(delta: int) -> void:
	var max_offset := maxi(0, _slots.size() - MAX_ROWS)
	_scroll_offset = clampi(_scroll_offset + delta, 0, max_offset)
	_refresh_rows()

func _refresh_rows() -> void:
	var max_offset := maxi(0, _slots.size() - MAX_ROWS)
	_scroll_offset = clampi(_scroll_offset, 0, max_offset)
	if _scroll_up_btn != null:
		_scroll_up_btn.visible = (_slots.size() > MAX_ROWS)
		_scroll_up_btn.disabled = (_scroll_offset <= 0)
	if _scroll_down_btn != null:
		_scroll_down_btn.visible = (_slots.size() > MAX_ROWS)
		_scroll_down_btn.disabled = (_scroll_offset >= max_offset)

	if _highlight != null:
		_highlight.visible = false
	if _thumb != null:
		_thumb.position.y = thumb_y(_scroll_offset, max_offset)

	for i in MAX_ROWS:
		var row: Button = _rows[i]
		var slot_idx := _scroll_offset + i
		if slot_idx < _slots.size():
			var s: Dictionary = _slots[slot_idx]
			row.text = _row_text(String(s["save_name"]))
			row.visible = true
			color_row(row, slot_idx == _selected)
		else:
			row.text = ""
			row.visible = false

## The scroll thumb's top for a list scrolled to `offset` of `max_offset`.
static func thumb_y(offset: int, max_offset: int) -> float:
	return THUMB_TOP + (THUMB_TRAVEL * offset / max_offset if max_offset > 0 else THUMB_TRAVEL / 2.0)

func _on_row_clicked(row_idx: int) -> void:
	var slot_idx := _scroll_offset + row_idx
	if slot_idx < _slots.size():
		if _selected == slot_idx:
			confirm()
		else:
			select_slot(slot_idx)

func select_slot(i: int) -> void:
	_selected = i
	if _selected >= 0 and _selected < _slots.size():
		if _selected < _scroll_offset:
			_scroll_offset = _selected
		elif _selected >= _scroll_offset + MAX_ROWS:
			_scroll_offset = _selected - MAX_ROWS + 1
	_refresh_rows()
	if _mode == Mode.SAVE and _name_edit != null and i >= 0 and i < _slots.size():
		_name_edit.text = String(_slots[i]["save_name"])
	elif _mode == Mode.LOAD and _selected_name_label != null:
		_selected_name_label.text = String(_slots[i]["save_name"]) if i >= 0 and i < _slots.size() else ""

func selected_name() -> String:
	return _selected_name_label.text if _selected_name_label != null else ""

## The save name, shortened with an ellipsis to fit the list row. The
## original's file list shows names only, with no day.
static func fit_row_text(font: Font, save_name: String, max_width: float) -> String:
	if font == null or font.get_string_size(save_name).x <= max_width:
		return save_name
	var n := save_name.length()
	while n > 0 and font.get_string_size(save_name.left(n).strip_edges() + ELLIPSIS).x > max_width:
		n -= 1
	return save_name.left(n).strip_edges() + ELLIPSIS

func _row_text(save_name: String) -> String:
	return fit_row_text(_font, save_name, LIST_W - ROW_PAD)

func slot_count() -> int:
	return _slots.size()

func set_name_text(t: String) -> void:
	if _name_edit != null:
		_name_edit.text = t

func show_error(msg: String) -> void:
	if _error_label != null:
		_error_label.text = msg

func error_text() -> String:
	return _error_label.text if _error_label != null else ""

## SAVE: emit the typed (sanitized-nonempty) name. LOAD: emit the selected slot.
## Stays open — the opener closes it on success or calls show_error() on failure.
func confirm() -> void:
	if _mode == Mode.SAVE:
		var slot_name := SaveGame.sanitize_slot(_name_edit.text if _name_edit != null else "").left(NEW_NAME_MAX).strip_edges()
		if slot_name == "":
			show_error("Enter a save name")
			return
		# Keeping a listed name overwrites that row's own file: the per-mode
		# autosaves are all named AUTOSAVE but live in separate files.
		if _selected >= 0 and _selected < _slots.size() and String(_slots[_selected]["save_name"]) == slot_name:
			slot_name = String(_slots[_selected]["slot"])
		confirmed.emit(slot_name)
	else:
		if _selected < 0 or _selected >= _slots.size():
			show_error("Select a saved game")
			return
		confirmed.emit(String(_slots[_selected]["slot"]))

func _close() -> void:
	closed.emit()
	queue_free()

## Flat row over the dark list inset: transparent in every state so the baked
## stone shows through; selection is conveyed by font color (see select_slot).
func _style_row_button(b: Button) -> void:
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(s, empty)
	color_row(b, false)

## Selected rows are gold in every button state. A tapped or clicked row keeps
## focus, and a touch keeps the pointer over it, so a gold font_color alone is
## hidden behind the focus or hover color.
static func color_row(b: Button, selected: bool) -> void:
	var c := Color8(255, 234, 120) if selected else Color8(230, 230, 230)
	for k in ["font_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, c)
	b.add_theme_color_override("font_hover_color", c if selected else Color8(255, 255, 255))

## The in-game Load path opens a YES/NO confirmation on top of this dialog.
## Both are CanvasLayers, and Godot still calls _input on this one first, so
## without this guard Enter would re-confirm the file selection and stack
## another confirmation instead of answering the one already showing.
func _has_dialog_above() -> bool:
	var parent := get_parent()
	if parent == null:
		return false
	for c in parent.get_children():
		if c == self or not (c is CanvasLayer):
			continue
		var other := c as CanvasLayer
		if other.visible and other.layer > layer:
			return true
	return false

func _input(event: InputEvent) -> void:
	if _has_dialog_above():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			# Mark it first: _close() may free this node, and confirm() may
			# switch scenes, either of which leaves get_viewport() null.
			get_viewport().set_input_as_handled()
			_close()
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER] and _name_edit == null:
			get_viewport().set_input_as_handled()
			confirm()
		elif event.keycode == KEY_UP:
			if _selected > 0:
				select_slot(_selected - 1)
			elif _selected == -1 and not _slots.is_empty():
				select_slot(0)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_DOWN:
			if _selected < _slots.size() - 1:
				select_slot(_selected + 1)
			elif _selected == -1 and not _slots.is_empty():
				select_slot(0)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll(-1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll(1)
			get_viewport().set_input_as_handled()
