class_name BattleGeneralOptions
extends CanvasLayer

## Native hero combat-options window reconstructed from vgenwin.bin.
## The BIN is 266x218 including its 8px external margin; viewgen/0000.png is
## the source-sized 250x202 drawable placed at the centered inner rectangle.

signal action_selected(action: StringName)
## The combat bar text for what the mouse is over (heroes.exe 0xc4c48).
signal status_changed(text: String)

## Morale and luck words for -3..3 (heroes.exe data 0x20fd4 and 0x20fb8).
const MORALE_WORDS := ["Treason", "Awful", "Poor", "Normal", "Good", "Great", "Blood!"]
const LUCK_WORDS := ["Cursed", "Awful", "Bad", "Normal", "Good", "Great", "Irish"]
const HOVER_TEXT := {
	&"cast": "Cast Spell",
	&"retreat": "Retreat",
	&"surrender": "Surrender",
	&"cancel": "Cancel",
}
const TITLE_HOVER := "General's Options"

const VIEWGEN := UiKit.ART + "viewgen/"
const PORT := UiKit.ART + "port%04d/0000.png"
const DIALOG_POS := Vector2(195, 139)
const DIALOG_SIZE := Vector2(250, 202)
const PORTRAIT_POS := Vector2(12, 42)
const PORTRAIT_SIZE := Vector2(101, 93)
const STATS_POS := Vector2(133, 36)
const BUTTON_POS := {
	&"cast": Vector2(15, 148),
	&"retreat": Vector2(74, 148),
	&"surrender": Vector2(133, 148),
	&"cancel": Vector2(192, 148),
}
const BUTTON_FRAMES := {
	&"cast": [7, 8],
	&"retreat": [9, 10],
	&"surrender": [11, 12],
	&"cancel": [13, 14],
}

var _available := {}
var _panel: Control

func setup(hero: HeroModel, cast_enabled: bool, retreat_enabled: bool,
		surrender_enabled: bool) -> void:
	layer = 280
	_available = {
		&"cast": cast_enabled,
		&"retreat": retreat_enabled,
		&"surrender": surrender_enabled,
		&"cancel": true,
	}
	var blocker := ColorRect.new()
	blocker.name = "Blocker"
	blocker.color = Color(0, 0, 0, 0)
	blocker.size = Vector2(640, 480)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)

	_panel = Control.new()
	_panel.name = "Panel"
	_panel.position = DIALOG_POS
	_panel.size = DIALOG_SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	UiKit.add_texture(_panel, VIEWGEN + "0000.png", Vector2.ZERO)

	if hero == null:
		hero = HeroModel.sample()
	var color_frame := clampi(hero.crest_idx / 4, 0, 3) + 1
	UiKit.add_texture(_panel, VIEWGEN + "%04d.png" % color_frame, STATS_POS)
	UiKit.add_texture(_panel, PORT % hero.portrait_idx, PORTRAIT_POS)

	var font := UiKit.font()
	var small := UiKit.small_font()
	UiKit.add_label(_panel, "%s the %s" % [hero.hero_name, hero.hero_class.capitalize()],
			Vector2(6, 5), Vector2(238, 20), font, Color8(240, 240, 240),
			HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)
	var morale_word := morale_word(hero.total_morale())
	var luck_word := luck_word(hero.effective_luck())
	var rows := [
		"Attack: %d" % hero.effective_attack(),
		"Defense: %d" % hero.effective_defense(),
		"Spell Power: %d" % hero.effective_spell_power(),
		"Knowledge: %d" % hero.effective_knowledge(),
		"Morale: %s" % morale_word,
		"Luck: %s" % luck_word,
	]
	for i in rows.size():
		UiKit.add_label(_panel, rows[i], Vector2(134, 40 + i * 15), Vector2(109, 13),
				small, Color8(240, 240, 240), HORIZONTAL_ALIGNMENT_CENTER,
				VERTICAL_ALIGNMENT_CENTER)

	for action: StringName in [&"cast", &"retreat", &"surrender", &"cancel"]:
		_button(action)

static func morale_word(morale: int) -> String:
	return MORALE_WORDS[clampi(morale, -3, 3) + 3]

static func luck_word(luck: int) -> String:
	return LUCK_WORDS[clampi(luck, -3, 3) + 3]

## What the bar reads with the mouse at `pos`: a button's name, or the
## window's title anywhere else.
func hover_text(pos: Vector2) -> String:
	for action: StringName in HOVER_TEXT:
		if button_rect(action).has_point(pos):
			return HOVER_TEXT[action]
	return TITLE_HOVER

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		status_changed.emit(hover_text((event as InputEventMouseMotion).position))

func dialog_rect() -> Rect2:
	return Rect2(DIALOG_POS, DIALOG_SIZE)

func portrait_rect() -> Rect2:
	return Rect2(DIALOG_POS + PORTRAIT_POS, PORTRAIT_SIZE)

func button_rect(action: StringName) -> Rect2:
	if not BUTTON_POS.has(action):
		return Rect2()
	return Rect2(DIALOG_POS + (BUTTON_POS[action] as Vector2), Vector2(43, 48))

func choose(action: StringName) -> void:
	if not bool(_available.get(action, false)):
		return
	action_selected.emit(action)
	queue_free()

func _button(action: StringName) -> void:
	var frames: Array = BUTTON_FRAMES[action]
	var button := TextureButton.new()
	button.name = String(action).capitalize()
	button.texture_normal = load(VIEWGEN + "%04d.png" % int(frames[0])) as Texture2D
	button.texture_pressed = load(VIEWGEN + "%04d.png" % int(frames[1])) as Texture2D
	button.position = BUTTON_POS[action]
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = not bool(_available[action])
	if button.disabled:
		button.modulate = Color(0.75, 0.75, 0.75, 1.0)
	button.pressed.connect(choose.bind(action))
	_panel.add_child(button)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		choose(&"cancel")
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE: choose(&"cancel")
			KEY_C: choose(&"cast")
			KEY_R: choose(&"retreat")
			KEY_S: choose(&"surrender")
			_: return
		get_viewport().set_input_as_handled()
