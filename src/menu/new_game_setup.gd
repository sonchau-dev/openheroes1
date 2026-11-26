# src/menu/new_game_setup.gd
extends Control

const ART := UiKit.ART
const BG := ART + "heroes.png"
const PANEL := ART + "newgame.png"
const FRAME := ART + "newgame/0025.png"

var _panel: TextureRect
var _difficulty_frame: TextureRect
var _opponent_rects: Array[TextureRect] = []
var _opponent_labels: Array[Label] = []
var _color_gem_rect: TextureRect
var _koth_rect: TextureRect
var _rating_label: Label
var _scenario_label: Label
var _catalog: Array[ScenarioInfo] = []
var _scenario: ScenarioInfo = null

# Interactive states
var _difficulty: int = 1 # 0=Easy, 1=Normal, 2=Hard, 3=Expert
var _opponent_settings: Array[int] = [2, 2, 2] # 0=None, 1=Dumb, 2=Average, 3=Smart, 4=Genius for each of the 3 opponents
var _human_difficulties: Array[int] = [1, 1, 1] # 0=Easy, 1=Normal, 2=Hard, 3=Expert for each human opponent
var _color: int = 0 # 0=Blue, 1=Green, 2=Red, 3=Yellow
var _koth: bool = false
var _launching := false # a second click during the fade out would start a second run

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Screenshot/development entry point for opening this scene directly in a
	# specific local-player mode. Normal menu flow has already populated setup.
	var autostart := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--hotseat="):
			Game.setup.human_player_count = clampi(arg.substr(10).to_int(), 1, 4)
		elif arg == "--net-autostart":
			# Dev hook for driving a two-machine remote game from the command
			# line: skip the setup screen and launch the default scenario.
			autostart = true
	_catalog = ScenarioCatalog.list_standard()
	var human_count := clampi(Game.setup.human_player_count, 1, 4)
	_catalog = _catalog.filter(func(info: ScenarioInfo):
		return info.supported_human_counts.is_empty() or info.supported_human_counts.has(human_count))
	_scenario = ScenarioCatalog.find_by_path(NewGameSettings.DEFAULT_MAP_PATH, _catalog)
	if _scenario == null and not _catalog.is_empty():
		_scenario = _catalog[0]
	if _scenario != null:
		var initial := _current_settings().normalize(_scenario)
		_color = initial.player_color
		_opponent_settings = initial.opponent_levels.duplicate()
		_human_difficulties = initial.human_difficulties.duplicate()

	# 1. Fullscreen backdrop
	var bg := UiKit.texture_rect(BG)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 2. Drop shadow for the panel (shifted down/right by 12px)
	var shadow := ColorRect.new()
	shadow.color = Color(0, 0, 0, 0.5)
	shadow.position = Vector2(311 + 12, 10 + 12)
	shadow.size = Vector2(322, 459)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shadow)

	# 3. Main Panel
	_panel = UiKit.texture_rect(PANEL, Vector2(311, 10))
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_panel)

	# 4. Fonts
	var font := UiKit.font_normal()
	var small_font := UiKit.font_small()

	# 4a. Static text labels
	var title_diff := Label.new()
	title_diff.text = "Choose Game Difficulty:"
	title_diff.position = Vector2(0, 18)
	title_diff.size = Vector2(322, 20)
	title_diff.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_diff.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_diff.add_theme_font_override("font", font)
	title_diff.add_theme_font_size_override("font_size", font.fixed_size)
	_panel.add_child(title_diff)

	var diff_labels := ["Easy", "Normal", "Hard", "Expert"]
	var diff_frame_x := [19, 90, 161, 232]
	for i in range(4):
		var lbl := Label.new()
		lbl.text = diff_labels[i]
		lbl.position = Vector2(diff_frame_x[i], 110)
		lbl.size = Vector2(71, 15)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_override("font", small_font)
		lbl.add_theme_font_size_override("font_size", small_font.fixed_size)
		_panel.add_child(lbl)

	var title_opp := Label.new()
	title_opp.text = "Customize Opponents:"
	title_opp.position = Vector2(0, 132)
	title_opp.size = Vector2(322, 20)
	title_opp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_opp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_opp.add_theme_font_override("font", font)
	title_opp.add_theme_font_size_override("font_size", font.fixed_size)
	_panel.add_child(title_opp)

	var title_color := Label.new()
	title_color.text = "Choose Color:"
	title_color.position = Vector2(15, 251)
	title_color.size = Vector2(130, 20)
	title_color.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_color.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_color.add_theme_font_override("font", font)
	title_color.add_theme_font_size_override("font_size", font.fixed_size)
	_panel.add_child(title_color)

	var title_koth := Label.new()
	title_koth.text = "King of the Hill:"
	title_koth.position = Vector2(155, 251)
	title_koth.size = Vector2(150, 20)
	title_koth.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_koth.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_koth.add_theme_font_override("font", font)
	title_koth.add_theme_font_size_override("font_size", font.fixed_size)
	_panel.add_child(title_koth)

	var title_scen := Label.new()
	title_scen.text = "Choose Scenario:"
	title_scen.position = Vector2(0, 340)
	title_scen.size = Vector2(322, 20)
	title_scen.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_scen.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_scen.add_theme_font_override("font", font)
	title_scen.add_theme_font_size_override("font_size", font.fixed_size)
	_panel.add_child(title_scen)

	# 4b. Difficulty Selection frame (71x71, overlayed)
	_difficulty_frame = UiKit.texture_rect(FRAME)
	_panel.add_child(_difficulty_frame)
	_update_difficulty_position()

	# 5. Opponent Setting Rects and Labels
	var opp_x := [55, 127, 199]
	for i in range(3):
		var tr := TextureRect.new()
		tr.position = Vector2(opp_x[i], 149)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(tr)
		_opponent_rects.append(tr)

		var lbl := Label.new()
		lbl.position = Vector2(opp_x[i], 216)
		lbl.size = Vector2(65, 28)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_override("font", small_font)
		lbl.add_theme_font_size_override("font_size", small_font.fixed_size)
		_panel.add_child(lbl)
		_opponent_labels.append(lbl)

		_update_opponent_box(i)

	# 6. Color Gem Rect (drawn exactly on top of background pre-drawn gem at (51, 270))
	_color_gem_rect = TextureRect.new()
	_color_gem_rect.position = Vector2(51, 270)
	_color_gem_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_color_gem_rect)
	_update_color_gem()

	# 7. KotH Checkbox Rect (drawn exactly on top of background pre-drawn checkbox at (210, 272))
	_koth_rect = TextureRect.new()
	_koth_rect.position = Vector2(210, 272)
	_koth_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_koth_rect)
	_update_koth()

	# 8. Scenario Name Display
	var arrow := UiKit.texture_rect(ART + "newgame/0019.png", Vector2(273, 352))
	_panel.add_child(arrow)

	_scenario_label = Label.new()
	_scenario_label.text = _scenario.name if _scenario != null else "No compatible scenario"
	_scenario_label.position = Vector2(24, 354)
	_scenario_label.size = Vector2(249, 20)
	_scenario_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scenario_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_scenario_label.add_theme_font_override("font", font)
	_scenario_label.add_theme_font_size_override("font_size", font.fixed_size)
	_scenario_label.add_theme_color_override("font_color", Color.WHITE)
	_panel.add_child(_scenario_label)

	# 9. Cover pre-drawn difficulty text and draw ours
	var cover_tex := AtlasTexture.new()
	cover_tex.atlas = _panel.texture
	cover_tex.region = Rect2(51, 115, 220, 25)
	var cover := TextureRect.new()
	cover.texture = cover_tex
	cover.position = Vector2(51, 380)
	_panel.add_child(cover)

	_rating_label = Label.new()
	_rating_label.position = Vector2(24, 382)
	_rating_label.size = Vector2(274, 20)
	_rating_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rating_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rating_label.add_theme_font_override("font", font)
	_rating_label.add_theme_font_size_override("font_size", font.fixed_size)
	_panel.add_child(_rating_label)
	_update_rating()

	# 10. OKAY and CANCEL buttons
	var btn_okay := IcnButton.new()
	btn_okay.setup(ART + "newgame/", 23, "okay") # OKAY is sprite 23
	btn_okay.position = Vector2(24, 412)
	btn_okay.pressed.connect(_on_action)
	_panel.add_child(btn_okay)

	var btn_cancel := IcnButton.new()
	btn_cancel.setup(ART + "newgame/", 21, "cancel") # CANCEL is sprite 21
	btn_cancel.position = Vector2(202, 412)
	btn_cancel.pressed.connect(_on_action)
	_panel.add_child(btn_cancel)

	# 11. Clickable areas (transparent Controls)
	# Difficulties
	var diff_x := [22, 93, 164, 235]
	for i in range(4):
		var ctrl := Control.new()
		ctrl.position = Vector2(diff_x[i], 36)
		ctrl.size = Vector2(64, 64)
		ctrl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		ctrl.gui_input.connect(func(event): _on_difficulty_input(i, event))
		_panel.add_child(ctrl)

	# Opponent boxes
	for i in range(3):
		var ctrl := Control.new()
		ctrl.position = Vector2(opp_x[i], 149)
		ctrl.size = Vector2(65, 65)
		ctrl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		ctrl.gui_input.connect(func(event): _on_opponent_input(i, event))
		_panel.add_child(ctrl)

	# Color gem (positioned exactly at (51, 270))
	var color_ctrl := Control.new()
	color_ctrl.position = Vector2(51, 270)
	color_ctrl.size = Vector2(59, 44)
	color_ctrl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	color_ctrl.gui_input.connect(_on_color_input)
	_panel.add_child(color_ctrl)

	# KotH checkbox (positioned exactly at (210, 272))
	var koth_ctrl := Control.new()
	koth_ctrl.position = Vector2(210, 272)
	koth_ctrl.size = Vector2(44, 39)
	koth_ctrl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	koth_ctrl.gui_input.connect(_on_koth_input)
	_panel.add_child(koth_ctrl)

	var scenario_ctrl := Control.new()
	scenario_ctrl.position = Vector2(24, 350)
	scenario_ctrl.size = Vector2(273, 28)
	scenario_ctrl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	scenario_ctrl.gui_input.connect(_on_scenario_input)
	_panel.add_child(scenario_ctrl)

	var shots = DevFlags.tool("res://src/tools/shots/menu_shots.gd")
	if shots != null and await shots.new_game_setup(self):
		return
	if autostart:
		_autostart()

func _update_difficulty_position() -> void:
	var diff_frame_x := [19, 90, 161, 232]
	_difficulty_frame.position = Vector2(diff_frame_x[_difficulty], 36)

func _update_opponent_box(idx: int) -> void:
	var human_opponents := clampi(Game.setup.human_player_count, 1, 4) - 1
	if idx < human_opponents:
		_opponent_rects[idx].texture = UiKit.load_texture(ART + "newgame/0026.png")
		if idx < _opponent_labels.size():
			var diff_names := ["Easy", "Normal", "Hard", "Expert"]
			var h_diff := _human_difficulties[idx] if idx < _human_difficulties.size() else 1
			_opponent_labels[idx].text = "Human\n%s" % diff_names[clampi(h_diff, 0, 3)]
	else:
		var ai_idx := idx - human_opponents
		var setting: int = _opponent_settings[ai_idx] if ai_idx < _opponent_settings.size() else 0
		var spr_id: int = setting + 5
		_opponent_rects[idx].texture = UiKit.load_texture(ART + "newgame/%04d.png" % spr_id)
		if idx < _opponent_labels.size():
			var texts := ["None", "Dumb", "Average", "Smart", "Genius"]
			_opponent_labels[idx].text = texts[setting]

func _update_color_gem() -> void:
	var spr_id = 11 + _color * 2
	_color_gem_rect.texture = UiKit.load_texture(ART + "newgame/%04d.png" % spr_id)

func _update_koth() -> void:
	var spr_id = 28 if _koth else 27
	_koth_rect.texture = UiKit.load_texture(ART + "newgame/%04d.png" % spr_id)

func _update_rating() -> void:
	var rating := _current_settings().rating(_scenario)

	if _rating_label != null:
		_rating_label.text = "Difficulty Rating: %d%%" % rating

func _on_difficulty_input(idx: int, event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_difficulty = idx
		_update_difficulty_position()
		_update_rating()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()

func _on_opponent_input(idx: int, event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var human_opponents := clampi(Game.setup.human_player_count, 1, 4) - 1
		if idx < human_opponents:
			if idx < _human_difficulties.size():
				_human_difficulties[idx] = (_human_difficulties[idx] + 1) % 4
				_update_opponent_box(idx)
				_update_rating()
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
			return
		var ai_idx := idx - human_opponents
		var capacity := maxi(0, _scenario.seat_count \
				- clampi(Game.setup.human_player_count, 1, 4)) if _scenario != null else 0
		if ai_idx >= capacity:
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
			return
		_opponent_settings[ai_idx] = (_opponent_settings[ai_idx] + 1) % 5
		_update_opponent_box(idx)
		_update_rating()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()

func _on_color_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var colors: Array[int] = _scenario.available_colors if _scenario != null else [0, 1, 2, 3]
		var idx := colors.find(_color)
		_color = colors[(maxi(0, idx) + 1) % colors.size()]
		_update_color_gem()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()

func _on_koth_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_koth = not _koth
		_update_koth()
		_update_rating()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()

func _on_scenario_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_open_scenario_picker()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()

func _open_scenario_picker() -> void:
	var picker := ScenarioPicker.new()
	picker.open(_catalog, _scenario.path if _scenario != null else "")
	add_child(picker)
	picker.confirmed.connect(func(info: ScenarioInfo):
		_scenario = info
		var normalized := _current_settings().normalize(info)
		_color = normalized.player_color
		_opponent_settings = normalized.opponent_levels.duplicate()
		_human_difficulties = normalized.human_difficulties.duplicate()
		_scenario_label.text = info.name
		_update_color_gem()
		for i in 3:
			_update_opponent_box(i)
		_update_rating())

## Deferred so the scenario list and every widget exist first.
func _autostart() -> void:
	await get_tree().process_frame
	_start_selected_scenario()

func _current_settings() -> NewGameSettings:
	var settings := NewGameSettings.new()
	settings.map_path = _scenario.path if _scenario != null else NewGameSettings.DEFAULT_MAP_PATH
	settings.game_difficulty = _difficulty
	settings.opponent_levels = _opponent_settings.duplicate()
	settings.human_difficulties = _human_difficulties.duplicate()
	settings.player_color = _color
	settings.king_of_the_hill = _koth
	settings.human_player_count = clampi(Game.setup.human_player_count, 1, 4)
	settings.network = Game.setup.network
	return settings

func _open_summary() -> void:
	if _scenario == null:
		return
	var settings := _current_settings().normalize(_scenario)
	var summary := ScenarioSummary.new()
	summary.open(settings, _scenario)
	add_child(summary)
	summary.cancelled.connect(func(): pass)
	summary.confirmed.connect(func(): _launch(settings))

func _on_action(action: String) -> void:
	match action:
		"okay":
			_start_selected_scenario()
		"cancel":
			Game.to_menu()

func _start_selected_scenario() -> void:
	if _scenario == null:
		return
	_launch(_current_settings().normalize(_scenario))

## Start the configured run. In remote play the map ships the opening position
## to the guest once it has built both kingdoms.
func _launch(settings: NewGameSettings) -> void:
	if _launching:
		return
	if settings.network and not Net.is_active():
		# The guest kingdom is seated by the map, so there is nothing to hand
		# to a computer player yet; the menu closes the dead session.
		push_warning("The network link dropped before the game started.")
		Game.to_menu()
		return
	var err := Game.new_game(settings)
	if err != "":
		push_error(err)
		return
	_launching = true
	var fade := ScreenFade.new()
	add_child(fade)
	await fade.fade(true)
	Game.fade_in_pending = true
	Game.to_map()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_start_selected_scenario()
	elif event.keycode == KEY_ESCAPE:
		Game.to_menu()
