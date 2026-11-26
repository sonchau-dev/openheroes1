class_name GameOverDialog
extends CanvasLayer

const DialogFrame := preload("res://src/ui/dialog_frame.gd")

## Modal end-of-game popup, following heroes.exe's game-end screen (0xcd700):
## 1. Scenario defeat: evntwin BUYBUILD frame (302px wide) + SYSTEM OKAY.
## 2. Standard victory: congrats.png with the congspre.bin score rows, then the
##    high score entry (dataentr.bin frame) or the message dialog.
## 3. Campaign mission complete: congrats.png with the mission text in
##    congrats.bin's box, then the SCENWN save prompt.
## 4. Campaign final victory: congrats.png with the High King text (the original
##    draws it over the WIN02 video), then the days high score.

const ART := UiKit.ART
const BUYBUILD := ART + "buybuild/"
const SYSTEM := ART + "system/"
const FONT := ART + "font/"
const CONGRATS := ART + "congrats.png"

const DIALOG_X := 169.0  # (640 - 302) / 2
const SCENARIO_WON_Y := 28.0

var _name_input: LineEdit = null
var _on_record_fn: Callable
var _is_campaign := false
var _is_campaign_defeat := false
var _is_scenario_won_prompt := false
var _is_campaign_mission_text := false
var _is_score_screen := false
var _after_score: Callable
var _campaign_has_next := false
var _campaign_result: Dictionary = {}
var _fade: ScreenFade = null
var _advancing := false

func open(message: String, qualifies_high_score: bool = false, default_name: String = "Player", on_record: Callable = Callable()) -> void:
	layer = 300
	_is_campaign = false
	_is_campaign_defeat = false
	_is_scenario_won_prompt = false
	_is_campaign_mission_text = false
	_is_score_screen = false
	_on_record_fn = on_record

	var blocker := ColorRect.new()
	blocker.name = "InputBlocker"
	blocker.color = Color.TRANSPARENT
	blocker.size = Vector2(640, 480)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)

	if qualifies_high_score:
		_build_data_entry(message, default_name)
	else:
		_build_info_dialog(message)

## A standard win: the score screen first, then the usual high score entry or
## message dialog once it is dismissed.
func open_standard_victory(message: String, days: int, rating: int, qualifies_high_score: bool = false,
		default_name: String = "Player", on_record: Callable = Callable()) -> void:
	layer = 300
	_is_campaign = false
	_is_campaign_defeat = false
	_is_scenario_won_prompt = false
	_is_campaign_mission_text = false
	_after_score = func() -> void:
		open(message, qualifies_high_score, default_name, on_record)
	_build_score_screen(days, rating)

func open_campaign(result: Dictionary) -> void:
	layer = 300
	_is_campaign = true
	_is_campaign_defeat = false
	_is_scenario_won_prompt = false
	_is_campaign_mission_text = false
	_is_score_screen = false
	_campaign_result = result
	var has_next: bool = bool(result.get("has_next", false))
	var is_complete: bool = bool(result.get("complete", false)) or not has_next
	_campaign_has_next = has_next and not is_complete

	if is_complete:
		_build_campaign_victory(result)
	else:
		_build_campaign_mission(result)
	# The screen fades in from black, as in the DOS capture.
	_fade = ScreenFade.new()
	add_child(_fade)
	_fade.set_black(true)
	_fade.fade(false)

func open_campaign_defeat(message: String = "") -> void:
	layer = 300
	_is_campaign = true
	_is_campaign_defeat = true
	_is_scenario_won_prompt = false
	_is_campaign_mission_text = false
	_is_score_screen = false
	_campaign_has_next = false

	var blocker := ColorRect.new()
	blocker.name = "InputBlocker"
	blocker.color = Color.TRANSPARENT
	blocker.size = Vector2(640, 480)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)

	_build_campaign_defeat(message)

func _build_campaign_defeat(message: String) -> void:
	var font := Homm1Font.load_font(FONT)

	var prompt_text := "Would you like to replay\nthis scenario?"
	if not message.is_empty() and not message.contains("replay"):
		prompt_text = message + "\n\nWould you like to replay this scenario?"

	var dialog := Control.new()
	dialog.name = "CampaignDefeatDialog"
	dialog.position = Vector2(DIALOG_X, 122.0)
	dialog.size = Vector2(302, 235)
	dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dialog)

	var shadow := ColorRect.new()
	shadow.name = "Shadow"
	shadow.color = Color(0, 0, 0, 0.45)
	shadow.position = Vector2(18, 42)
	shadow.size = Vector2(286, 195)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.add_child(shadow)

	DialogFrame.add_segment(dialog, BUYBUILD + "0000.png", 1.0, true)
	DialogFrame.add_segment(dialog, BUYBUILD + "0000.png", 1.0, false)
	DialogFrame.add_top_seam_fill(dialog)

	DialogFrame.add_segment(dialog, BUYBUILD + "0001.png", 78.0, true)
	DialogFrame.add_segment(dialog, BUYBUILD + "0001.png", 78.0, false)
	DialogFrame.add_segment(dialog, BUYBUILD + "0001.png", 123.0, true)
	DialogFrame.add_segment(dialog, BUYBUILD + "0001.png", 123.0, false)

	DialogFrame.add_segment(dialog, BUYBUILD + "0002.png", 168.0, true)
	DialogFrame.add_segment(dialog, BUYBUILD + "0002.png", 168.0, false)

	var lbl := Label.new()
	lbl.name = "Message"
	# Wrap before the text goes in: a Label's size is clamped up to its minimum,
	# which is the whole unwrapped line until autowrap is on.
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.text = prompt_text
	lbl.position = Vector2(31, 55)
	lbl.size = Vector2(240, 95)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if font != null:
		lbl.add_theme_font_override("font", font)
		lbl.add_theme_font_size_override("font_size", font.fixed_size)
	lbl.add_theme_constant_override("line_spacing", 2)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	dialog.add_child(lbl)

	var yes := IcnButton.new()
	yes.name = "Yes"
	yes.setup(SYSTEM, 5, "yes")
	yes.position = Vector2(36, 168)
	yes.pressed.connect(func(_action: String): _on_campaign_replay())
	dialog.add_child(yes)

	var no := IcnButton.new()
	no.name = "No"
	no.setup(SYSTEM, 7, "no")
	no.position = Vector2(170, 168)
	no.pressed.connect(func(_action: String): _on_campaign_exit())
	dialog.add_child(no)

func _build_data_entry(message: String, default_name: String) -> void:
	var font := Homm1Font.load_font(FONT)
	var dialog := Control.new()
	dialog.name = "DataEntryDialog"
	dialog.position = Vector2(DIALOG_X, 122.0)
	dialog.size = Vector2(302, 235)
	dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dialog)

	var shadow := ColorRect.new()
	shadow.name = "Shadow"
	shadow.color = Color(0, 0, 0, 0.45)
	shadow.position = Vector2(18, 42)
	shadow.size = Vector2(286, 195)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.add_child(shadow)

	# Top header frame (BUYBUILD 0000 at y=1 matches native oy=1)
	DialogFrame.add_segment(dialog, BUYBUILD + "0000.png", 1.0, true)
	DialogFrame.add_segment(dialog, BUYBUILD + "0000.png", 1.0, false)
	DialogFrame.add_top_seam_fill(dialog)

	# Middle rows (y=78, y=123)
	DialogFrame.add_segment(dialog, BUYBUILD + "0001.png", 78.0, true)
	DialogFrame.add_segment(dialog, BUYBUILD + "0001.png", 78.0, false)
	DialogFrame.add_segment(dialog, BUYBUILD + "0001.png", 123.0, true)
	DialogFrame.add_segment(dialog, BUYBUILD + "0001.png", 123.0, false)

	# Bottom cap (y=168)
	DialogFrame.add_segment(dialog, BUYBUILD + "0002.png", 168.0, true)
	DialogFrame.add_segment(dialog, BUYBUILD + "0002.png", 168.0, false)

	# Victory message / status
	var msg_label := Label.new()
	msg_label.name = "VictoryMessage"
	# Wrap before the size goes in: set_size clamps a non-wrapping label to its unwrapped width.
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.text = message
	msg_label.position = Vector2(31, 46)
	msg_label.size = Vector2(240, 42)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg_label.add_theme_color_override("font_color", Color8(255, 234, 120))
	if font != null:
		msg_label.add_theme_font_override("font", font)
		msg_label.add_theme_font_size_override("font_size", font.fixed_size)
	msg_label.add_theme_constant_override("line_spacing", 2)
	dialog.add_child(msg_label)

	# Prompt (measured from dataentr.bin)
	var prompt := Label.new()
	prompt.name = "Prompt"
	prompt.text = "Please enter your name\nfor the high score list."
	prompt.position = Vector2(31, 90)
	prompt.size = Vector2(240, 38)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt.add_theme_color_override("font_color", Color.WHITE)
	if font != null:
		prompt.add_theme_font_override("font", font)
		prompt.add_theme_font_size_override("font_size", font.fixed_size)
	prompt.add_theme_constant_override("line_spacing", 2)
	dialog.add_child(prompt)

	# Recessed text slot (BUYBUILD 0003.png is 251x20)
	var slot_bg := TextureRect.new()
	slot_bg.name = "SlotBg"
	var slot_tex := load(BUYBUILD + "0003.png") as Texture2D
	slot_bg.texture = slot_tex
	slot_bg.position = Vector2(25, 134)
	slot_bg.size = Vector2(251, 20)
	slot_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.add_child(slot_bg)

	_name_input = LineEdit.new()
	_name_input.name = "NameInput"
	_name_input.text = default_name
	# Offset y by -4 to vertically center font glyphs inside the 20px recessed slot (LineEdit default minimum height is 31px)
	_name_input.position = Vector2(25, 130)
	_name_input.custom_minimum_size = Vector2(251, 20)
	_name_input.size = Vector2(251, 20)
	_name_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_input.max_length = 24
	_name_input.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_name_input.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_name_input.add_theme_color_override("font_color", Color.WHITE)
	_name_input.add_theme_color_override("caret_color", Color8(255, 234, 120))
	if font != null:
		_name_input.add_theme_font_override("font", font)
		_name_input.add_theme_font_size_override("font_size", font.fixed_size)
	_name_input.text_submitted.connect(func(_t: String): _on_ok())
	dialog.add_child(_name_input)
	if _name_input.is_inside_tree():
		_name_input.grab_focus()
	else:
		_name_input.ready.connect(func(): _name_input.grab_focus())

	# OKAY button
	var okay := IcnButton.new()
	okay.name = "Okay"
	okay.setup(SYSTEM, 1, "okay")
	okay.position = Vector2(102, 168)
	okay.pressed.connect(func(_action: String): _on_ok())
	dialog.add_child(okay)

func _build_info_dialog(message: String) -> void:
	var font := Homm1Font.load_font(FONT)

	var total_lines := 0
	for p: String in message.split("\n"):
		if font != null and p != "":
			var line_w := font.get_string_size(p).x
			total_lines += maxi(1, int(ceil(line_w / 240.0)))
		else:
			total_lines += 1

	var middle_rows: Array[float] = [78.0]
	var cap_y := 123.0
	var dialog_h := 190.0
	var shadow_h := 150.0
	var text_h := 63.0
	var btn_y := 123.0

	if total_lines > 6:
		middle_rows = [78.0, 123.0, 168.0]
		cap_y = 213.0
		dialog_h = 280.0
		shadow_h = 240.0
		text_h = 153.0
		btn_y = 213.0
	elif total_lines > 3:
		middle_rows = [78.0, 123.0]
		cap_y = 168.0
		dialog_h = 235.0
		shadow_h = 195.0
		text_h = 108.0
		btn_y = 168.0

	var dialog := Control.new()
	dialog.name = "InfoDialog"
	dialog.position = Vector2(DIALOG_X, (480.0 - dialog_h) / 2.0)
	dialog.size = Vector2(302, dialog_h)
	dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dialog)

	var shadow := ColorRect.new()
	shadow.name = "Shadow"
	shadow.color = Color(0, 0, 0, 0.45)
	shadow.position = Vector2(18, 42)
	shadow.size = Vector2(286, shadow_h)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.add_child(shadow)

	DialogFrame.add_segment(dialog, BUYBUILD + "0000.png", 1.0, true)
	DialogFrame.add_segment(dialog, BUYBUILD + "0000.png", 1.0, false)
	DialogFrame.add_top_seam_fill(dialog)

	for y: float in middle_rows:
		DialogFrame.add_segment(dialog, BUYBUILD + "0001.png", y, true)
		DialogFrame.add_segment(dialog, BUYBUILD + "0001.png", y, false)

	DialogFrame.add_segment(dialog, BUYBUILD + "0002.png", cap_y, true)
	DialogFrame.add_segment(dialog, BUYBUILD + "0002.png", cap_y, false)

	var lbl := Label.new()
	lbl.name = "Message"
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.text = message
	lbl.position = Vector2(31, 55)
	lbl.size = Vector2(240, text_h)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if font != null:
		lbl.add_theme_font_override("font", font)
		lbl.add_theme_font_size_override("font_size", font.fixed_size)
	lbl.add_theme_constant_override("line_spacing", 2)
	lbl.add_theme_color_override("font_color", Color8(255, 234, 120) if (message.begins_with("Victory") or message.contains("victorious")) else Color.WHITE)
	dialog.add_child(lbl)

	var okay := IcnButton.new()
	okay.name = "Okay"
	okay.setup(SYSTEM, 1, "okay")
	okay.position = Vector2(102, btn_y)
	okay.pressed.connect(func(_action: String): _on_ok())
	dialog.add_child(okay)

## heroes.exe 0xcd98d: a won mission shows congrats.bmp with the mission's
## completion text (table data 0x217c0) in congrats.bin's single bigfont box,
## left aligned at (309, 136) 282x100. Any click or key moves on.
func _build_campaign_mission(result: Dictionary) -> void:
	_is_campaign_mission_text = true
	var font := Homm1Font.load_font(FONT)

	var bg := TextureRect.new()
	bg.name = "CongratsBg"
	bg.texture = load(CONGRATS) as Texture2D
	MusicPlayer.play_on_game(MusicPlayer.CONGRATULATIONS)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_dismiss_campaign_mission_text()
	)
	add_child(bg)

	var text := Label.new()
	text.name = "MissionText"
	text.position = Vector2(309, 136)
	text.size = Vector2(282, 100)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_color_override("font_color", Color.WHITE)
	var message := String(result.get("message", ""))
	if font != null:
		text.add_theme_font_override("font", font)
		text.add_theme_font_size_override("font_size", font.fixed_size)
		message = Homm1Font.wrap(font, message, text.size.x)
	text.text = message
	add_child(text)

## The save prompt opens over the congratulation screen; the mission text stays
## visible behind it, as in the DOS capture.
func _dismiss_campaign_mission_text() -> void:
	if not _is_campaign_mission_text:
		return
	_is_campaign_mission_text = false
	var bg := get_node_or_null("CongratsBg") as Control
	if bg != null:
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_show_scenario_won_prompt()

func _show_scenario_won_prompt() -> void:
	_is_scenario_won_prompt = true

	var g := _game()
	var scen_num: int = int(_campaign_result.get("scenario_index", 0)) + 1
	var slot_name := "SCENWN%02d" % scen_num
	if g != null:
		g.save_game(slot_name)

	var font := Homm1Font.load_font(FONT)

	var blocker := ColorRect.new()
	blocker.name = "InputBlocker"
	blocker.color = Color.TRANSPARENT
	blocker.size = Vector2(640, 480)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)

	# The DOS capture hangs this box from y 28, with no drop shadow.
	var dialog := Control.new()
	dialog.name = "ScenarioWonDialog"
	dialog.position = Vector2(DIALOG_X, SCENARIO_WON_Y)
	dialog.size = Vector2(302, 235)
	dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dialog)

	DialogFrame.add_segment(dialog, BUYBUILD + "0000.png", 1.0, true)
	DialogFrame.add_segment(dialog, BUYBUILD + "0000.png", 1.0, false)
	DialogFrame.add_top_seam_fill(dialog)

	DialogFrame.add_segment(dialog, BUYBUILD + "0001.png", 78.0, true)
	DialogFrame.add_segment(dialog, BUYBUILD + "0001.png", 78.0, false)
	DialogFrame.add_segment(dialog, BUYBUILD + "0001.png", 123.0, true)
	DialogFrame.add_segment(dialog, BUYBUILD + "0001.png", 123.0, false)

	DialogFrame.add_segment(dialog, BUYBUILD + "0002.png", 168.0, true)
	DialogFrame.add_segment(dialog, BUYBUILD + "0002.png", 168.0, false)

	var prompt_text := "Your campaign has been saved as %s.  Would you like to start the next scenario?" % slot_name

	var lbl := Label.new()
	lbl.name = "Message"
	# Wrap before the text goes in: a Label's size is clamped up to its minimum,
	# which is the whole unwrapped line until autowrap is on.
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.text = prompt_text
	lbl.position = Vector2(31, 55)
	lbl.size = Vector2(240, 95)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if font != null:
		lbl.add_theme_font_override("font", font)
		lbl.add_theme_font_size_override("font_size", font.fixed_size)
	lbl.add_theme_constant_override("line_spacing", 2)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	dialog.add_child(lbl)

	var yes := IcnButton.new()
	yes.name = "Yes"
	yes.setup(SYSTEM, 5, "yes")
	yes.position = Vector2(36, 168)
	yes.pressed.connect(func(_action: String): _on_campaign_advance())
	dialog.add_child(yes)

	var no := IcnButton.new()
	no.name = "No"
	no.setup(SYSTEM, 7, "no")
	no.position = Vector2(170, 168)
	no.pressed.connect(func(_action: String): _on_campaign_exit())
	dialog.add_child(no)

func _build_campaign_victory(result: Dictionary) -> void:
	var font := Homm1Font.load_font(FONT)

	var bg := TextureRect.new()
	bg.name = "CongratsBg"
	bg.texture = load(CONGRATS) as Texture2D
	MusicPlayer.play_on_game(MusicPlayer.CONGRATULATIONS)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var container := Control.new()
	container.name = "VictoryContainer"
	# The original draws this text over the WIN02 video, so congrats.bin's
	# 282x100 box is too short for it; use the whole red panel instead.
	container.position = Vector2(300, 130)
	container.size = Vector2(300, 122)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	var days: int = int(result.get("days", 0))
	var body_text := "My heroes, our foes have been scattered, their castles broken and laid bare.  The great campaign is now complete, and I stand before you as the undisputed High King!\n\nOur victory was achieved in %d days!" % days

	var body := Label.new()
	body.name = "VictoryBody"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = body_text
	body.position = Vector2.ZERO
	body.size = Vector2(300, 122)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body.add_theme_color_override("font_color", Color.WHITE)
	if font != null:
		body.add_theme_font_override("font", font)
		body.add_theme_font_size_override("font_size", font.fixed_size)
	body.add_theme_constant_override("line_spacing", 0)
	container.add_child(body)

	var okay := IcnButton.new()
	okay.name = "Okay"
	okay.setup(SYSTEM, 1, "okay")
	okay.position = Vector2(400, 258)
	okay.pressed.connect(func(_action: String): _on_campaign_victory_okay())
	add_child(okay)

## The finished campaign skips the score screen (state 2 jumps past it at
## 0xcd988) and goes straight to the days high score, 0xd3744 mode 0.
func _on_campaign_victory_okay() -> void:
	for node_name in ["VictoryContainer", "Okay"]:
		var node := get_node_or_null(node_name)
		if node != null:
			remove_child(node)
			node.queue_free()

	var days: int = int(_campaign_result.get("days", 0))
	if days <= 0:
		var g := _game()
		if g != null and g.campaign != null:
			days = g.campaign.total_days
	var ruler: int = int(_campaign_result.get("ruler", -1))
	if ruler < 0:
		var g := _game()
		if g != null and g.campaign != null:
			ruler = g.campaign.ruler
		else:
			ruler = 0
	ruler = clampi(ruler, 0, 3)

	if HighScoreStore.qualifies_campaign(days):
		_is_campaign = false
		_on_record_fn = func(entered_name: String) -> void:
			HighScoreStore.record_campaign(entered_name, ruler, days)
			var g := _game()
			if g != null:
				g.high_scores_mode = &"campaign"
		_build_data_entry("Victory in %d days!" % days, CampaignCatalog.LEADER_NAMES[ruler])
	else:
		_on_campaign_exit()

## heroes.exe 0xcd98d..0xcde3b: a standard win shows congrats.bmp with
## congspre.bin's title and five label/value rows. Base score is 0x86318 of the
## day, the rating is the world's difficulty word, final score is
## base * rating / 100 truncated, and the ranking is the standard table
## (0xcdca8 hard-wires it) looked up by final score.
func _build_score_screen(days: int, rating: int) -> void:
	_is_score_screen = true
	var font := Homm1Font.load_font(FONT)

	var bg := TextureRect.new()
	bg.name = "CongratsBg"
	bg.texture = load(CONGRATS) as Texture2D
	MusicPlayer.play_on_game(MusicPlayer.CONGRATULATIONS)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var container := Control.new()
	container.name = "SummaryContainer"
	container.position = Vector2.ZERO
	container.size = Vector2(640, 480)
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	container.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_dismiss_score_screen()
	)
	add_child(container)

	var title := Label.new()
	title.name = "SummaryTitle"
	title.text = "A Glorious Victory!"
	title.position = Vector2(309, 136)
	title.size = Vector2(282, 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color.WHITE)
	if font != null:
		title.add_theme_font_override("font", font)
		title.add_theme_font_size_override("font_size", font.fixed_size)
	container.add_child(title)

	var base_score := ScenarioScore.points(days)
	var final_score := ScenarioScore.calculate(days, rating)
	var ranking := HighScoreStore.creature_for_score(final_score)

	var rows: Array[Dictionary] = [
		{"label": "Days Spent:", "val": "%d" % days, "y": 162.0},
		{"label": "Base Score:", "val": "%d" % base_score, "y": 178.0},
		{"label": "Difficulty Rating:", "val": "%d%%" % rating, "y": 194.0},
		{"label": "Final Score:", "val": "%d" % final_score, "y": 210.0},
		{"label": "Ranking:", "val": ranking.capitalize(), "y": 226.0},
	]

	for i in rows.size():
		var r: Dictionary = rows[i]
		var lbl := Label.new()
		lbl.name = "Label%d" % i
		lbl.text = String(r.label)
		lbl.position = Vector2(309, float(r.y))
		lbl.size = Vector2(150, 16)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		if font != null:
			lbl.add_theme_font_override("font", font)
			lbl.add_theme_font_size_override("font_size", font.fixed_size)
		container.add_child(lbl)

		var val_lbl := Label.new()
		val_lbl.name = "Value%d" % i
		val_lbl.text = String(r.val)
		val_lbl.position = Vector2(479, float(r.y))
		val_lbl.size = Vector2(111, 16)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_lbl.add_theme_color_override("font_color", Color.WHITE)
		if font != null:
			val_lbl.add_theme_font_override("font", font)
			val_lbl.add_theme_font_size_override("font_size", font.fixed_size)
		container.add_child(val_lbl)

func _dismiss_score_screen() -> void:
	if not _is_score_screen:
		return
	_is_score_screen = false
	for node_name in ["SummaryContainer", "CongratsBg"]:
		var node := get_node_or_null(node_name)
		if node != null:
			remove_child(node)
			node.queue_free()
	if _after_score.is_valid():
		var next := _after_score
		_after_score = Callable()
		next.call()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _is_scenario_won_prompt:
		if event.keycode in [KEY_Y, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_on_campaign_advance()
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_N, KEY_ESCAPE]:
			_on_campaign_exit()
			get_viewport().set_input_as_handled()
		return
	if _is_campaign_defeat:
		if event.keycode in [KEY_Y, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_on_campaign_replay()
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_N, KEY_ESCAPE]:
			_on_campaign_exit()
			get_viewport().set_input_as_handled()
		return
	if _is_campaign_mission_text:
		_dismiss_campaign_mission_text()
		get_viewport().set_input_as_handled()
		return
	if _is_score_screen:
		_dismiss_score_screen()
		get_viewport().set_input_as_handled()
		return
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		if _name_input != null and _name_input.has_focus():
			return
		_handle_confirm()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_SPACE or event.keycode == KEY_ESCAPE:
		if _name_input != null and _name_input.has_focus() and event.keycode != KEY_ESCAPE:
			return
		_handle_confirm()
		get_viewport().set_input_as_handled()

func _handle_confirm() -> void:
	if _is_scenario_won_prompt:
		_on_campaign_advance()
	elif _is_campaign_mission_text:
		_dismiss_campaign_mission_text()
	elif _is_score_screen:
		_dismiss_score_screen()
	elif _is_campaign:
		if _campaign_has_next:
			_show_scenario_won_prompt()
		else:
			_on_campaign_victory_okay()
	else:
		_on_ok()

func _game() -> Node:
	if Engine.has_singleton("Game"):
		return Engine.get_singleton("Game")
	if is_inside_tree():
		var tree := get_tree()
		if tree != null and tree.root != null and tree.root.has_node("Game"):
			return tree.root.get_node("Game")
	return null

func _on_campaign_replay() -> void:
	var g := _game()
	if g != null:
		var err: String = g.restart_campaign_mission()
		if err == "":
			g.to_map()
			queue_free()
			return
	_on_campaign_exit()

## Yes fades to black, starts the next mission, and fades the briefing in over
## its backdrop; the panel appears once the fade is done. OKAY fades out again
## and the map fades in. The original never shows the map under the briefing.
func _on_campaign_advance() -> void:
	if _advancing:
		return
	_advancing = true
	var g := _game()
	if g == null or _fade == null or not is_inside_tree():
		_on_campaign_exit()
		return
	await _fade.fade(true)
	await get_tree().create_timer(ScreenFade.HOLD_BRIEFING).timeout
	var err: String = g.restart_campaign_mission()
	if err != "" or g.campaign == null:
		_on_campaign_exit()
		return
	g.campaign_show_intro = false
	_is_scenario_won_prompt = false
	var mission: CampaignMission = g.campaign.mission()
	var briefing := await CampaignBriefing.show(self, mission, _fade)
	briefing.closed.connect(func() -> void: _leave_briefing(g))

func _leave_briefing(g: Node) -> void:
	await CampaignBriefing.leave(g, _fade)
	queue_free()

func _on_campaign_exit() -> void:
	var g := _game()
	if g != null:
		g.reset()
		g.to_menu()
	queue_free()

func _on_ok() -> void:
	var qualified := false
	if _name_input != null and _on_record_fn.is_valid():
		var player_name := _name_input.text.strip_edges()
		if player_name.is_empty():
			player_name = "Player"
		_on_record_fn.call(player_name)
		qualified = true
	var g := _game()
	if g != null:
		g.reset()
		if qualified and ResourceLoader.exists("res://src/menu/high_scores.tscn"):
			if is_inside_tree() and get_tree() != null:
				get_tree().change_scene_to_file("res://src/menu/high_scores.tscn")
		else:
			g.to_menu()

