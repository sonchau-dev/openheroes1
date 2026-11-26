class_name ScenarioPicker
extends Control

signal confirmed(info: ScenarioInfo)
signal cancelled

const ART := UiKit.ART
const BG := ART + "request.png"
const REQ_EXTRA_BG := ART + "reqextra.png"
const REQ_ICN := ART + "request/"
const FONT_DIR := UiKit.FONT
const SCROLL_ICN := ART + "scroll2/"
const THUMB := SaveLoadDialog.THUMB

const PANEL_POS := Vector2(310, 14)   # where the original opens it (DOSBox capture)
const EXTRA_OFFSET_Y := 318.0

const TITLE_RECT := Rect2(12, 22, 296, 16)
const LIST_X := 56.0
const LIST_TOP := 40.0   # request.bin row 41; a centred Button draws 1 px lower
const LIST_W := 207.0
const ROW_H := 20.0
const MAX_ROWS := 10

# request.bin edit field (48,253) and reqextra.bin's three bigfont fields (25,34),
# (162,34), (34,64) below EXTRA_OFFSET_Y, each 2 px lower because a top-aligned
# Label draws the glyphs 2 px higher than the original (DOSBox capture).
const SELECTED_NAME_POS := Vector2(48, 255)
const SELECTED_NAME_SIZE := Vector2(225, 19)
const SIZE_LABEL_POS := Vector2(25, 354)
const SIZE_LABEL_SIZE := Vector2(90, 16)
const DIFF_LABEL_POS := Vector2(162, 354)
const DIFF_LABEL_SIZE := Vector2(130, 16)
const DESC_LABEL_POS := Vector2(34, 384)
const DESC_LABEL_SIZE := Vector2(250, 48)

const OKAY_POS := Vector2(36, 280)
const CANCEL_POS := Vector2(189, 280)
const SCROLL_UP_POS := Vector2(278, 35)
const SCROLL_DOWN_POS := Vector2(278, 233)
const ELLIPSIS := "..."

var scenarios: Array[ScenarioInfo] = []
var selected_index: int = 0
var scroll_offset: int = 0
var _panel: Control
var _rows: Array[Button] = []
var _scroll_up_btn: IcnButton = null
var _scroll_down_btn: IcnButton = null
var _thumb: TextureRect = null
var _selected_name: Label
var _size_value: Label
var _difficulty_value: Label
var _description: Label
var _font: Font = null

func open(entries: Array[ScenarioInfo], current_path: String) -> void:
	scenarios = entries
	for i in scenarios.size():
		if scenarios[i].path == current_path:
			selected_index = i
			break
	scroll_offset = clampi(selected_index - MAX_ROWS / 2, 0,
			maxi(0, scenarios.size() - MAX_ROWS))
	if is_inside_tree() and not _rows.is_empty():
		_refresh()

func _ready() -> void:
	if _panel != null:
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var blocker := ColorRect.new()
	blocker.color = Color(0, 0, 0, 0)
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)

	_panel = Control.new()
	_panel.position = PANEL_POS
	_panel.size = Vector2(320, 459)
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_panel)

	var top := UiKit.texture_rect(BG)
	_panel.add_child(top)

	var extra := UiKit.texture_rect(REQ_EXTRA_BG, Vector2(0, EXTRA_OFFSET_Y))
	_panel.add_child(extra)
	_thumb = UiKit.add_tex(_panel, THUMB, Vector2(SaveLoadDialog.THUMB_X, SaveLoadDialog.THUMB_TOP))

	_font = UiKit.font_normal()

	var title := UiKit.create_label("File to Load:", TITLE_RECT.position, TITLE_RECT.size,
			_font, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)
	_panel.add_child(title)

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
		_panel.add_child(row)
		_rows.append(row)
		y += ROW_H

	_scroll_up_btn = IcnButton.new()
	_scroll_up_btn.setup(SCROLL_ICN, 0, "scroll_up")
	_scroll_up_btn.position = SCROLL_UP_POS
	_scroll_up_btn.pressed.connect(func(_a): _scroll(-1))
	_panel.add_child(_scroll_up_btn)

	_scroll_down_btn = IcnButton.new()
	_scroll_down_btn.setup(SCROLL_ICN, 2, "scroll_down")
	_scroll_down_btn.position = SCROLL_DOWN_POS
	_scroll_down_btn.pressed.connect(func(_a): _scroll(1))
	_panel.add_child(_scroll_down_btn)

	_selected_name = UiKit.create_label("", SELECTED_NAME_POS, SELECTED_NAME_SIZE,
			_font, Color.WHITE)
	_panel.add_child(_selected_name)

	_size_value = UiKit.create_label("", SIZE_LABEL_POS, SIZE_LABEL_SIZE,
			_font, Color.WHITE)
	_panel.add_child(_size_value)

	_difficulty_value = UiKit.create_label("", DIFF_LABEL_POS, DIFF_LABEL_SIZE,
			_font, Color.WHITE)
	_panel.add_child(_difficulty_value)

	_description = UiKit.create_label("", DESC_LABEL_POS, DESC_LABEL_SIZE,
			_font, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, 0, Color.BLACK, 2)
	_panel.add_child(_description)

	var okay := IcnButton.new()
	okay.setup(REQ_ICN, 1, "okay")
	okay.position = OKAY_POS
	okay.pressed.connect(func(_a): _on_action("okay"))
	_panel.add_child(okay)

	var cancel := IcnButton.new()
	cancel.setup(REQ_ICN, 3, "cancel")
	cancel.position = CANCEL_POS
	cancel.pressed.connect(func(_a): _on_action("cancel"))
	_panel.add_child(cancel)

	_refresh()

func _style_row_button(b: Button) -> void:
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(s, empty)
	SaveLoadDialog.color_row(b, false)

static func _wrap_text_to_width(font: Font, text: String, max_width: float, max_lines: int = 0) -> String:
	var lines: Array[String] = []
	for paragraph in text.split("\n"):
		var words := paragraph.split(" ", false)
		var current_line := ""
		for word in words:
			var candidate := word if current_line == "" else current_line + " " + word
			if current_line != "" and font.get_string_size(candidate).x > max_width:
				lines.append(current_line)
				current_line = word
			else:
				current_line = candidate
		if current_line != "":
			lines.append(current_line)
	if max_lines > 0 and lines.size() > max_lines:
		lines = lines.slice(0, max_lines)
		var last := lines[max_lines - 1]
		if not last.ends_with(ELLIPSIS):
			var trimmed := last
			while trimmed.length() > 0 and font.get_string_size(trimmed + ELLIPSIS).x > max_width:
				trimmed = trimmed.left(trimmed.length() - 1).strip_edges()
			lines[max_lines - 1] = trimmed + ELLIPSIS
	return "\n".join(lines)

func _refresh() -> void:
	if scenarios.is_empty() or _rows.is_empty():
		return
	selected_index = clampi(selected_index, 0, scenarios.size() - 1)
	var max_offset := maxi(0, scenarios.size() - MAX_ROWS)
	scroll_offset = clampi(scroll_offset, 0, max_offset)

	if _scroll_up_btn != null:
		_scroll_up_btn.visible = (scenarios.size() > MAX_ROWS)
		_scroll_up_btn.disabled = (scroll_offset <= 0)
	if _scroll_down_btn != null:
		_scroll_down_btn.visible = (scenarios.size() > MAX_ROWS)
		_scroll_down_btn.disabled = (scroll_offset >= max_offset)
	if _thumb != null:
		_thumb.position.y = SaveLoadDialog.thumb_y(scroll_offset, max_offset)

	for i in MAX_ROWS:
		var row: Button = _rows[i]
		var idx := scroll_offset + i
		if idx < scenarios.size():
			row.text = scenarios[idx].name
			row.visible = true
			SaveLoadDialog.color_row(row, idx == selected_index)
		else:
			row.text = ""
			row.visible = false

	var info := scenarios[selected_index]
	_selected_name.text = info.name
	var size_idx := clampi(info.size, 0, 2)
	_size_value.text = ["Small", "Medium", "Large"][size_idx]
	var diff_idx := clampi(info.map_difficulty, 0, 3)
	_difficulty_value.text = ["Easy", "Normal", "Hard", "Impossible"][diff_idx]
	_description.text = _wrap_text_to_width(_font, info.description, DESC_LABEL_SIZE.x, 3) if _font != null else info.description

func _on_row_clicked(row_idx: int) -> void:
	var idx := scroll_offset + row_idx
	if idx < scenarios.size():
		if selected_index == idx:
			_on_action("okay")
		else:
			select_index(idx)

func select_index(index: int) -> void:
	if scenarios.is_empty():
		return
	selected_index = clampi(index, 0, scenarios.size() - 1)
	if selected_index < scroll_offset:
		scroll_offset = selected_index
	elif selected_index >= scroll_offset + MAX_ROWS:
		scroll_offset = selected_index - MAX_ROWS + 1
	_refresh()

func _scroll(delta: int) -> void:
	var max_offset := maxi(0, scenarios.size() - MAX_ROWS)
	scroll_offset = clampi(scroll_offset + delta, 0, max_offset)
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_UP:
				select_index(selected_index - 1)
				get_viewport().set_input_as_handled()
			KEY_DOWN:
				select_index(selected_index + 1)
				get_viewport().set_input_as_handled()
			KEY_PAGEUP:
				select_index(selected_index - MAX_ROWS)
				get_viewport().set_input_as_handled()
			KEY_PAGEDOWN:
				select_index(selected_index + MAX_ROWS)
				get_viewport().set_input_as_handled()
			KEY_HOME:
				select_index(0)
				get_viewport().set_input_as_handled()
			KEY_END:
				select_index(scenarios.size() - 1)
				get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_KP_ENTER:
				_on_action("okay")
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				_on_action("cancel")
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll(-1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll(1)
			get_viewport().set_input_as_handled()

func _on_action(action: String) -> void:
	if action == "okay" and not scenarios.is_empty():
		confirmed.emit(scenarios[selected_index])
	else:
		cancelled.emit()
	queue_free()
