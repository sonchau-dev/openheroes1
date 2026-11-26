# src/ui/system_menu.gd
extends CanvasLayer

## System options popup over the map, rendered on the authentic HOMM1 options
## panel art (cpanel.png = double frame + stone + baked NEW/LOAD/SAVE/QUIT
## buttons + the six toggle icons).
##
## Features authentic geometry from cpanel.bin (322x459):
## - NEW / LOAD / SAVE / QUIT (96x56, cpanel.icn 0..7)
## - OKAY / INFO at y=407 (96x27, cpanel.icn 8/9 and 25/26)
## - Six functional settings toggles (65x65, cpanel.icn 10..24):
##   Music, Effects, Speed, Auto Save, Show Path, View Enemy Movement
## - Confirmation dialogs for New Game, Quit, and Load Game
## - Authentic right-click help texts mined from heroes.exe
## - Keyboard hotkeys: N, L, S, Q, I, G, Enter, Space, Esc

const BG := UiKit.ART + "cpanel.png"       # baked options panel background (322x459)
const CPANEL := UiKit.ART + "cpanel/"      # cpanel.icn buttons (up=base, pressed=+1)

const CPANEL_NEW := 0
const CPANEL_LOAD := 2
const CPANEL_SAVE := 4
const CPANEL_QUIT := 6
const CPANEL_OKAY := 8
const CPANEL_INFO := 25

const PANEL_POS := Vector2(159, 10)  # centers the 322x459 panel on 640x480

# Confirmation dialog placement over the options panel (matches reference menu.png):

# Button anchors (panel-local, from cpanel.bin):
const BTN_L_X := 46.0
const BTN_R_X := 179.0
const BTN_ROW1_Y := 31.0
const BTN_ROW2_Y := 107.0
const OKAY_POS := Vector2(24, 407)
const INFO_POS := Vector2(201, 407)

# Toggle icon anchors (panel-local, 65x65):
const TOGGLE_ROW1_Y := 194.0
const TOGGLE_ROW2_Y := 314.0
const TOGGLE_COL_X := [36.0, 128.0, 220.0]

# Label geometry (panel-local, from cpanel.bin and smalfont):
const LABEL_W := 85.0
const LABEL_TITLE_ROW1_Y := 181.0
const LABEL_VAL_ROW1_Y := 259.0
const LABEL_TITLE_ROW2_Y := 301.0
const LABEL_VAL_ROW2_Y := 379.0

# Mined DOS right-click help texts (heroes.exe 0x10fac3-0x10fe36):
const HELP_TEXTS := {
	"new_game": "Start a single or multi-player game.",
	"load_game": "Load a previously saved game.",
	"save_game": "Save the current game.",
	"quit": "Quit Heroes of Might and Magic and return to the DOS prompt.",
	"okay": "Exit this menu without doing anything.",
	"info": "View information on the scenario you are currently playing.",
	"music": "Toggle ambient music on/off",
	"effects": "Toggle foreground sounds on/off",
	"speed": "Change the speed at which Heroes move on the main screen.",
	"auto_save": "Toggle 'Autosave' on/off.  'Autosave' saves your game automatically at the end of each turn to a special file, called 'AUTOSAVE'.",
	"show_path": "Toggle 'Show Path' on/off.  If 'Show Path' is on, your first click on a map location will show the path to get there, your second will start you moving. If this option is off, one click starts you moving immediately.",
	"view_enemy": "Toggle 'Show Enemy Moves' on/off.  If on, all enemies moving within your visible area will be shown.  If off, no computer movement will be shown.  Note that this option is automatically set to off during network and modem play.",
}

# Mined DOS volume texts (heroes.exe 0x10db44..0x10dbb6):
const VOLUME_TEXTS: Array[String] = [
	"Off",
	"On",
	"On\nVolume 9",
	"On\nVolume 8",
	"On\nVolume 7",
	"On\nVolume 6",
	"On\nVolume 5",
	"On\nVolume 4",
	"On\nVolume 3",
	"On\nVolume 2",
	"On\nVolume 1",
]

# Panel-local hit rects for right-click inspection:
const HIT_RECTS := {
	"new_game": Rect2(46, 31, 96, 56),
	"load_game": Rect2(179, 31, 96, 56),
	"save_game": Rect2(46, 107, 96, 56),
	"quit": Rect2(179, 107, 96, 56),
	"okay": Rect2(24, 407, 96, 27),
	"info": Rect2(201, 407, 96, 27),
	"music": Rect2(26, 181, 85, 106),
	"effects": Rect2(118, 181, 85, 106),
	"speed": Rect2(210, 181, 85, 92),
	"auto_save": Rect2(26, 301, 85, 92),
	"show_path": Rect2(118, 301, 85, 92),
	"view_enemy": Rect2(210, 289, 85, 104),
}

class ToggleButton extends TextureButton:
	var action_name: String = ""

signal closed
signal info_requested

## Persists hero tiles before a save (adventure_map's _persist_all_heroes).
var persist_heroes_fn: Callable = Callable()

var _dim: ColorRect
var _holder: Control
var _font: Font

var _btn_toggles: Dictionary = {}
var _lbl_vals: Dictionary = {}

func open() -> void:
	layer = 200
	_font = UiKit.small_font()

	# Transparent click-blocker (no dimming — matches the DOS options screen,
	# which leaves the map + HUD at full brightness). Swallows stray clicks.
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0)
	_dim.position = Vector2.ZERO
	_dim.size = Vector2(640, 480)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	var holder := Control.new()
	holder.position = PANEL_POS
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(holder)
	_holder = holder

	UiKit.add_tex(holder, BG, Vector2.ZERO)

	# Action buttons push down on click (IcnButton up/pressed art).
	_add_button(holder, CPANEL_NEW, "new_game", Vector2(BTN_L_X, BTN_ROW1_Y))
	_add_button(holder, CPANEL_LOAD, "load_game", Vector2(BTN_R_X, BTN_ROW1_Y))
	_add_button(holder, CPANEL_SAVE, "save_game", Vector2(BTN_L_X, BTN_ROW2_Y))
	_add_button(holder, CPANEL_QUIT, "quit", Vector2(BTN_R_X, BTN_ROW2_Y))
	_add_button(holder, CPANEL_OKAY, "okay", OKAY_POS)
	_add_button(holder, CPANEL_INFO, "info", INFO_POS)

	# 6 Toggle buttons (65x65 each, cpanel.icn frames 10..24)
	_btn_toggles["music"] = _add_toggle(holder, "music", Vector2(TOGGLE_COL_X[0], TOGGLE_ROW1_Y))
	_btn_toggles["effects"] = _add_toggle(holder, "effects", Vector2(TOGGLE_COL_X[1], TOGGLE_ROW1_Y))
	_btn_toggles["speed"] = _add_toggle(holder, "speed", Vector2(TOGGLE_COL_X[2], TOGGLE_ROW1_Y))
	_btn_toggles["auto_save"] = _add_toggle(holder, "auto_save", Vector2(TOGGLE_COL_X[0], TOGGLE_ROW2_Y))
	_btn_toggles["show_path"] = _add_toggle(holder, "show_path", Vector2(TOGGLE_COL_X[1], TOGGLE_ROW2_Y))
	_btn_toggles["view_enemy"] = _add_toggle(holder, "view_enemy", Vector2(TOGGLE_COL_X[2], TOGGLE_ROW2_Y))

	# Toggle titles
	UiKit.add_label(holder, "Music", Vector2(26, LABEL_TITLE_ROW1_Y), Vector2(LABEL_W, 14.0), _font, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, "", 0, Color.BLACK, 0)
	UiKit.add_label(holder, "Effects", Vector2(118, LABEL_TITLE_ROW1_Y), Vector2(LABEL_W, 14.0), _font, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, "", 0, Color.BLACK, 0)
	UiKit.add_label(holder, "Speed", Vector2(210, LABEL_TITLE_ROW1_Y), Vector2(LABEL_W, 14.0), _font, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, "", 0, Color.BLACK, 0)
	UiKit.add_label(holder, "Auto Save", Vector2(26, LABEL_TITLE_ROW2_Y), Vector2(LABEL_W, 14.0), _font, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, "", 0, Color.BLACK, 0)
	UiKit.add_label(holder, "Show Path", Vector2(118, LABEL_TITLE_ROW2_Y), Vector2(LABEL_W, 14.0), _font, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, "", 0, Color.BLACK, 0)
	UiKit.add_label(holder, "View Enemy\nMovement", Vector2(210, 289), Vector2(LABEL_W, 24.0), _font, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, "", 0, Color.BLACK, 0)

	# Toggle value labels (x=29/121, w=81, h=28 for 100% pixel match with DOS)
	_lbl_vals["music"] = UiKit.add_label(holder, "", Vector2(29, LABEL_VAL_ROW1_Y), Vector2(81.0, 28.0), _font, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, "", 0, Color.BLACK, 0)
	_lbl_vals["effects"] = UiKit.add_label(holder, "", Vector2(121, LABEL_VAL_ROW1_Y), Vector2(81.0, 28.0), _font, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, "", 0, Color.BLACK, 0)
	_lbl_vals["speed"] = UiKit.add_label(holder, "", Vector2(210, LABEL_VAL_ROW1_Y), Vector2(LABEL_W, 14.0), _font, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, "", 0, Color.BLACK, 0)
	_lbl_vals["auto_save"] = UiKit.add_label(holder, "", Vector2(26, LABEL_VAL_ROW2_Y), Vector2(LABEL_W, 14.0), _font, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, "", 0, Color.BLACK, 0)
	_lbl_vals["show_path"] = UiKit.add_label(holder, "", Vector2(118, LABEL_VAL_ROW2_Y), Vector2(LABEL_W, 14.0), _font, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, "", 0, Color.BLACK, 0)
	_lbl_vals["view_enemy"] = UiKit.add_label(holder, "", Vector2(210, LABEL_VAL_ROW2_Y), Vector2(LABEL_W, 14.0), _font, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, "", 0, Color.BLACK, 0)

	_update_toggles()

func _update_toggles() -> void:
	# Music: sprite 10 (Off) / 11 (On)
	_set_toggle_art("music", 11 if Game.music_setting != 0 else 10)
	var music_idx: int = clampi(Game.music_setting, 0, 10)
	(_lbl_vals["music"] as Label).text = VOLUME_TEXTS[music_idx]

	# Effects: sprite 12 (Off) / 13 (On)
	_set_toggle_art("effects", 13 if Game.sfx_setting != 0 else 12)
	var sfx_idx: int = clampi(Game.sfx_setting, 0, 10)
	(_lbl_vals["effects"] as Label).text = VOLUME_TEXTS[sfx_idx]

	# Speed: sprites 14 (Walk), 15 (Trot), 16 (Canter), 17 (Gallop), 18 (Jump)
	var spd: int = clampi(Game.movement_speed, 0, 4)
	_set_toggle_art("speed", 14 + spd)
	var speed_names := ["Walk", "Trot", "Canter", "Gallop", "Jump"]
	(_lbl_vals["speed"] as Label).text = speed_names[spd]

	# Auto Save: sprite 19 (Off) / 20 (On)
	_set_toggle_art("auto_save", 20 if Game.autosave_enabled else 19)
	(_lbl_vals["auto_save"] as Label).text = "On" if Game.autosave_enabled else "Off"

	# Show Path: sprite 21 (Off) / 22 (On)
	_set_toggle_art("show_path", 22 if Game.show_path else 21)
	(_lbl_vals["show_path"] as Label).text = "On" if Game.show_path else "Off"

	# View Enemy Movement: sprite 23 (Off) / 24 (On). Forced Off in network mode.
	var enemy_on: bool = Game.view_enemy_movement and Game.game_mode != &"network"
	_set_toggle_art("view_enemy", 24 if enemy_on else 23)
	(_lbl_vals["view_enemy"] as Label).text = "On" if enemy_on else "Off"
	if Game.game_mode == &"network":
		var btn: ToggleButton = _btn_toggles.get("view_enemy")
		if btn != null:
			btn.disabled = true

func _set_toggle_art(action: String, frame: int) -> void:
	var btn: ToggleButton = _btn_toggles.get(action)
	if btn != null:
		btn.texture_normal = load(CPANEL + "%04d.png" % frame) as Texture2D

func _add_button(parent: Control, base: int, action: String, pos: Vector2) -> IcnButton:
	var btn := IcnButton.new()
	btn.name = action
	btn.setup(CPANEL, base, action)
	btn.position = pos
	btn.pressed.connect(_on_action)
	parent.add_child(btn)
	return btn

func _add_toggle(parent: Control, action: String, pos: Vector2) -> ToggleButton:
	var btn := ToggleButton.new()
	btn.name = action
	btn.action_name = action
	btn.position = pos
	btn.custom_minimum_size = Vector2(65, 65)
	btn.size = Vector2(65, 65)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.pressed.connect(_on_toggle_clicked.bind(action))
	parent.add_child(btn)
	return btn

func _on_toggle_clicked(action: String) -> void:
	match action:
		"music":
			Game.music_setting = (Game.music_setting + 1) % 11
			Game.save_settings()
			Game.music.refresh_volume()
		"effects":
			Game.sfx_setting = (Game.sfx_setting + 1) % 11
			Game.save_settings()
		"speed":
			Game.movement_speed = (Game.movement_speed + 1) % 5
			Game.save_settings()
		"auto_save":
			Game.autosave_enabled = not Game.autosave_enabled
			Game.save_settings()
		"show_path":
			Game.show_path = not Game.show_path
			Game.save_settings()
		"view_enemy":
			if Game.game_mode != &"network":
				Game.view_enemy_movement = not Game.view_enemy_movement
				Game.save_settings()
	_update_toggles()

func _on_action(action: String) -> void:
	match action:
		"new_game", "quit":
			confirm_leave(self, action)
		"save_game":
			_open_save_dialog()
		"load_game":
			confirm_leave(self, action)
		"okay":
			hide()
			queue_free()
			closed.emit()
		"info":
			hide()
			queue_free()
			info_requested.emit()

## The restart, load and quit prompts, shared with the adventure map's own N,
## L and Q keys (heroes.exe 0x96cec and 0x96d48 raise the restart and quit
## questions). Load, as in the original, asks first and then returns to the
## main menu's Load panel rather than opening the file list over the map.
static func confirm_leave(parent: Node, action: String) -> void:
	var text := "Are you sure you want to load a new game?  (Your current game will be lost)" if action == "load_game" \
			else "Are you sure you want to %s (Your current game will be lost)" % ("restart?" if action == "new_game" else "quit?")
	MapDialogs.confirm(parent, text, func(idx: int):
		if idx == 0:
			Game.reset()
			Game.to_menu(action == "load_game")
	)

## True when any modal dialog (SaveLoadDialog, confirm prompt, info box) is active.
func _has_open_dialog() -> bool:
	for c in get_children():
		if c != _dim and c != _holder and is_instance_valid(c) and not c.is_queued_for_deletion() and c is CanvasLayer and c.visible:
			return true
	return false

## Only one popup at a time (matches HOMM1): opening the file dialog hides the
## options panel.
func _set_menu_visible(v: bool) -> void:
	if _dim != null:
		_dim.visible = v
	if _holder != null:
		_holder.visible = v

## Save: write the slot, show result, then back to the adventure map. As in
## heroes.exe 0xa1780, which closes the panel and then runs the save (0xa1c2c):
## the panel does not come back after a save or a cancel.
func _open_save_dialog() -> void:
	_set_menu_visible(false)
	MapMenus.save_dialog(self, persist_heroes_fn, _on_action.bind("okay"))

func get_help_action_at(panel_local_pos: Vector2) -> String:
	for action: String in HIT_RECTS:
		if (HIT_RECTS[action] as Rect2).has_point(panel_local_pos):
			return action
	return ""

func get_help_text_at(panel_local_pos: Vector2) -> String:
	var action := get_help_action_at(panel_local_pos)
	return HELP_TEXTS.get(action, "")

func _input(event: InputEvent) -> void:
	if _has_open_dialog():
		return

	# Right-click inspection on options panel items
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var mb := event as InputEventMouseButton
		var local_pos: Vector2 = mb.position - PANEL_POS
		var help := get_help_text_at(local_pos)
		if help != "":
			MapDialogs.info(self, {"text": help, "centered": true})
		get_viewport().set_input_as_handled()
		return

	# cpanel.bin: New N, Load L, Save S, Quit Q, Info I, Okay Esc.
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				_on_action("okay")
				get_viewport().set_input_as_handled()
			KEY_N:
				_on_action("new_game")
				get_viewport().set_input_as_handled()
			KEY_L:
				_on_action("load_game")
				get_viewport().set_input_as_handled()
			KEY_S:
				_on_action("save_game")
				get_viewport().set_input_as_handled()
			KEY_Q:
				_on_action("quit")
				get_viewport().set_input_as_handled()
			KEY_I:
				_on_action("info")
				get_viewport().set_input_as_handled()

