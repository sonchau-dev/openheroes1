# src/menu/scenario_summary.gd
class_name ScenarioSummary
extends CanvasLayer

signal confirmed
signal cancelled

const ART := UiKit.ART
const BG := ART + "sceninfo.png"
const FONT_DIR := UiKit.FONT
const NEWGAME_DIR := ART + "newgame/"
const SCENINFO_DIR := ART + "sceninfo/"

const PANEL_POS := Vector2(159, 14)
const JEWEL_POS := Vector2(124, 153)
const OKAY_POS := Vector2(112, 407)

# Exact rects decoded from sceninfo.bin and aligned to reference:
const RECT_SCENARIO := Rect2(100, 38, 195, 16)
const RECT_SETTING := Rect2(161, 72, 135, 16)
const RECT_OPPONENTS := Rect2(83, 107, 212, 48)
const RECT_KOTH := Rect2(200, 209, 95, 16)
const RECT_RATING := Rect2(200, 241, 95, 16)
const RECT_SIZE := Rect2(25, 316, 90, 16)
const RECT_DIFFICULTY := Rect2(162, 316, 130, 16)
const RECT_DESCRIPTION := Rect2(34, 346, 250, 48)


var settings: NewGameSettings
var info: ScenarioInfo

var _dim: ColorRect
var _holder: Control
var _font: Font

func open(p_settings: NewGameSettings, p_info: ScenarioInfo) -> void:
	layer = 200
	settings = p_settings.duplicate_settings() if p_settings != null else NewGameSettings.new()
	info = p_info
	if is_inside_tree():
		_build_ui()

func _ready() -> void:
	layer = 200
	if settings != null and info != null and _holder == null:
		_build_ui()

func _build_ui() -> void:
	for child in get_children():
		child.queue_free()

	_font = UiKit.font_normal()

	# Transparent click blocker: swallows stray clicks while modal is open,
	# preserving full adventure map brightness as in DOS HOMM1.
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0)
	_dim.position = Vector2.ZERO
	_dim.size = Vector2(640, 480)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_holder = Control.new()
	_holder.position = PANEL_POS
	_holder.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_holder)

	var bg := UiKit.texture_rect(BG)
	_holder.add_child(bg)

	var scenario_name: String = info.name if info != null else ""
	UiKit.add_label_rect(_holder, scenario_name, RECT_SCENARIO, _font, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_TOP)

	var game_diff_idx: int = clampi(settings.game_difficulty, 0, 3) if settings != null else 1
	var setting_names := ["Easy", "Normal", "Hard", "Expert"]
	UiKit.add_label_rect(_holder, setting_names[game_diff_idx], RECT_SETTING, _font, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_TOP)

	var opponent_names := ["None", "Dumb", "Average", "Smart", "Genius"]
	var opp_lines: Array[String] = []
	if settings != null:
		var human_opponents := clampi(settings.human_player_count, 1, 4) - 1
		for i in range(3):
			if i < human_opponents:
				var h_diff := settings.human_difficulties[i] if i < settings.human_difficulties.size() else 1
				opp_lines.append("Human %s" % setting_names[clampi(h_diff, 0, 3)])
			else:
				var ai_idx := i - human_opponents
				var level := settings.opponent_levels[ai_idx] if ai_idx < settings.opponent_levels.size() else 0
				if int(level) > 0:
					opp_lines.append(opponent_names[clampi(int(level), 0, 4)])
	if opp_lines.is_empty():
		opp_lines.append("None")
	UiKit.add_label_rect(_holder, "\n".join(opp_lines), RECT_OPPONENTS, _font, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_TOP, "", 2)

	var color_idx: int = clampi(settings.player_color, 0, 3) if settings != null else 0
	var jewel := UiKit.texture_rect(NEWGAME_DIR + "%04d.png" % (10 + color_idx * 2), JEWEL_POS)
	_holder.add_child(jewel)

	var koth_text: String = "Yes" if (settings != null and settings.king_of_the_hill) else "No"
	UiKit.add_label_rect(_holder, koth_text, RECT_KOTH, _font, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_TOP)

	var rating_val: int = settings.rating(info) if (settings != null and info != null) else 60
	UiKit.add_label_rect(_holder, "%d%%" % rating_val, RECT_RATING, _font, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_TOP)

	var size_idx: int = clampi(info.size, 0, 2) if info != null else 0
	var size_names := ["Small", "Medium", "Large"]
	UiKit.add_label_rect(_holder, size_names[size_idx], RECT_SIZE, _font, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP)

	var map_diff_idx: int = clampi(info.map_difficulty, 0, 3) if info != null else 0
	var map_diff_names := ["Easy", "Normal", "Hard", "Impossible"]
	UiKit.add_label_rect(_holder, map_diff_names[map_diff_idx], RECT_DIFFICULTY, _font, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP)

	var desc_text: String = info.description if info != null else ""
	var wrapped_desc: String = _wrap_text_to_width(_font, desc_text, RECT_DESCRIPTION.size.x) if _font != null else desc_text
	UiKit.add_label_rect(_holder, wrapped_desc, RECT_DESCRIPTION, _font, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, "", 2)

	var okay := IcnButton.new()
	okay.setup(SCENINFO_DIR, 0, "okay")
	okay.position = OKAY_POS
	okay.pressed.connect(func(_action): _dismiss())
	_holder.add_child(okay)

static func _wrap_text_to_width(font: Font, text: String, max_width: float) -> String:
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
	return "\n".join(lines)

func _dismiss(was_cancelled: bool = false) -> void:
	if was_cancelled:
		cancelled.emit()
	else:
		confirmed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_dismiss(true)
	elif event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_O]:
		get_viewport().set_input_as_handled()
		_dismiss(false)


