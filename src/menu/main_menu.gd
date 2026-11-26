# src/menu/main_menu.gd
extends Control

## HOMM1 title screen. heroes.png backdrop + a vertical stack of IcnButtons.
## Two in-place states: MAIN (New/Load/Scores/Credits/Quit) and GAME_TYPE
## (Standard/Campaign/Multiplayer/Cancel). Standard starts a new game.

const ART := UiKit.ART
const BG := ART + "heroes.png"
const BTNMAIN := ART + "btnmain/"
const BTNNEWGM := ART + "btnnewgm/"
const BTNMP := ART + "btnmp/"
const BTNHOTST := ART + "btnhotst/"
const PANEL := ART + "redback.png"


enum State { MAIN, GAME_TYPE, CAMPAIGN, LOAD_TYPE, MULTIPLAYER, PLAYER_COUNT }

var _state: State = State.MAIN
var _panel: TextureRect
var _shadow: ColorRect
var _buttons: Array[IcnButton] = []     # live IcnButton nodes
var _briefing_open := false              # the campaign briefing owns the screen

static func menu_defs(state: State) -> Array:
	if state == State.PLAYER_COUNT:
		return [
			{"action": "players_2", "dir": BTNHOTST, "base": 0, "disabled": false, "slot": 0, "key": KEY_2},
			{"action": "players_3", "dir": BTNHOTST, "base": 2, "disabled": false, "slot": 1, "key": KEY_3},
			{"action": "players_4", "dir": BTNHOTST, "base": 4, "disabled": false, "slot": 2, "key": KEY_4},
			{"action": "cancel_players", "dir": BTNHOTST, "base": 6, "disabled": false, "slot": 4, "key": KEY_ESCAPE},
		]
	if state == State.MULTIPLAYER:
		return [
			{"action": "hot_seat", "dir": BTNMP, "base": 0, "disabled": false, "slot": 0, "key": KEY_H},
			{"action": "network", "dir": BTNMP, "base": 2, "disabled": false, "slot": 1, "key": KEY_N},
			{"action": "modem", "dir": BTNMP, "base": 4, "disabled": true, "slot": 2, "key": KEY_M},
			{"action": "direct_connect", "dir": BTNMP, "base": 6, "disabled": true, "slot": 3, "key": KEY_D},
			{"action": "cancel_multiplayer", "dir": BTNMP, "base": 8, "disabled": false, "slot": 4, "key": KEY_ESCAPE},
		]
	if state == State.LOAD_TYPE:
		return [
			{"action": "load_standard", "dir": BTNNEWGM, "base": 0, "disabled": false, "slot": 0, "key": KEY_S},
			{"action": "load_campaign", "dir": BTNNEWGM, "base": 2, "disabled": false, "slot": 1, "key": KEY_C},
			{"action": "load_multiplayer", "dir": BTNNEWGM, "base": 4, "disabled": false, "slot": 2, "key": KEY_M},
			{"action": "cancel_load", "dir": BTNNEWGM, "base": 6, "disabled": false, "slot": 4, "key": KEY_ESCAPE},
		]
	if state == State.CAMPAIGN:
		return [
			{"action": "leader_0", "dir": ART + "btncmpgn/", "base": 0, "disabled": false, "slot": 0, "key": KEY_I},
			{"action": "leader_1", "dir": ART + "btncmpgn/", "base": 2, "disabled": false, "slot": 1, "key": KEY_S},
			{"action": "leader_2", "dir": ART + "btncmpgn/", "base": 4, "disabled": false, "slot": 2, "key": KEY_L},
			{"action": "leader_3", "dir": ART + "btncmpgn/", "base": 6, "disabled": false, "slot": 3, "key": KEY_A},
			{"action": "cancel", "dir": ART + "btncmpgn/", "base": 8, "disabled": false, "slot": 4, "key": KEY_ESCAPE},
		]
	if state == State.GAME_TYPE:
		return [
			{"action": "standard", "dir": BTNNEWGM, "base": 0, "disabled": false, "slot": 0, "key": KEY_S},
			{"action": "campaign", "dir": BTNNEWGM, "base": 2, "disabled": false, "slot": 1, "key": KEY_C},
			{"action": "multiplayer", "dir": BTNNEWGM, "base": 4, "disabled": false, "slot": 2, "key": KEY_M},
			{"action": "cancel", "dir": BTNNEWGM, "base": 6, "disabled": false, "slot": 4, "key": KEY_ESCAPE},
		]
	return [
		{"action": "new_game", "dir": BTNMAIN, "base": 2, "disabled": false, "slot": 0, "key": KEY_N},
		{"action": "load_game", "dir": BTNMAIN, "base": 0, "disabled": false, "slot": 1, "key": KEY_L},
		{"action": "high_scores", "dir": BTNMAIN, "base": 4, "disabled": false, "slot": 2, "key": KEY_H},
		{"action": "credits", "dir": BTNMAIN, "base": 6, "disabled": false, "slot": 3, "key": KEY_C},
		{"action": "quit", "dir": BTNMAIN, "base": 8, "disabled": false, "slot": 4, "key": KEY_Q},
	]

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# No flow reaches the menu while a link must survive; a stale one would
	# let a "network" game start with nobody to hand the turn to.
	Net.close()
	if not ResourceLoader.exists(BG):
		var note := Label.new()
		note.text = "Game data not built. Run: godot --headless --path . --script tools/setup.gd  (see README.md)"
		note.set_anchors_preset(Control.PRESET_FULL_RECT)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD
		add_child(note)
		return
	var bg := UiKit.texture_rect(BG)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_shadow = ColorRect.new()
	_shadow.color = Color(0, 0, 0, 0.5)
	_shadow.position = Vector2(399 + 12, 35 + 12)
	_shadow.size = Vector2(194, 410)
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shadow)

	_panel = UiKit.texture_rect(PANEL, Vector2(399, 35))
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_panel)

	# Compiling the map's scripts takes about 0.9 s on a low-end phone; do it
	# while the player is still choosing, so the scene change finds it cached.
	if DisplayServer.get_name() != "headless":
		ResourceLoader.load_threaded_request("res://src/adventure/adventure_map.tscn", "", true)

	var args := OS.get_cmdline_user_args()
	if "--bench-menu" in args or "--bench-launch" in args:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
		var ticks_ms := Time.get_ticks_usec() / 1000.0
		print("BENCH_FIRST_MENU_MS: %.2f" % ticks_ms)
		get_tree().quit()
		return

	for a in args:
		if a == "--":
			continue
		var clean_a := a.trim_prefix("--")
		if clean_a.begins_with("map=") or clean_a.begins_with("probe=") \
				or clean_a == "bench" or clean_a.begins_with("bench-"):
			get_tree().change_scene_to_file.call_deferred("res://src/adventure/adventure_map.tscn")
			return

	var shots = DevFlags.tool("res://src/tools/shots/menu_shots.gd")
	if "--intro" in args:
		play_intro()
	else:
		# The shot hook may need to wait for a screen to settle, so it is
		# awaited before the menu falls back to its own panel.
		var handled := false
		if shots != null:
			handled = await shots.main_menu_state(self)
		if not handled:
			_show_state(State.LOAD_TYPE if Game.menu_opens_load else State.MAIN)
		Game.menu_opens_load = false

	var smoke = DevFlags.smoke()
	if smoke != null:
		await smoke.menu(self)
		return

	if shots != null:
		await shots.capture(self)

func _show_state(state: State) -> void:
	_state = state
	Game.music.play(MusicPlayer.MAIN_MENU)
	if _panel != null:
		_panel.visible = true
	if _shadow != null:
		_shadow.visible = true
	for b in _buttons:
		b.queue_free()
	_buttons.clear()
	var defs := menu_defs(state)
	for d: Dictionary in defs:
		var btn := IcnButton.new()
		btn.setup(d["dir"], int(d["base"]), String(d["action"]))
		btn.disabled = bool(d["disabled"])
		var sz := btn.texture_normal_size()
		var x_local: float = round((194.0 - sz.x) * 0.5)
		var y_local: float = 33.0 + int(d["slot"]) * 70.0
		btn.position = Vector2(x_local, y_local)
		btn.pressed.connect(_on_action)
		_panel.add_child(btn)
		_buttons.append(btn)

func _on_action(action: String) -> void:
	if _briefing_open:
		return
	match action:
		"new_game": _show_state(State.GAME_TYPE)
		"high_scores": get_tree().change_scene_to_file("res://src/menu/high_scores.tscn")
		"credits": get_tree().change_scene_to_file("res://src/menu/credits.tscn")
		"quit": get_tree().quit()
		"standard":
			Game.setup = NewGameSettings.new()
			get_tree().change_scene_to_file("res://src/menu/new_game_setup.tscn")
		"campaign": _show_state(State.CAMPAIGN)
		"multiplayer": _show_state(State.MULTIPLAYER)
		"hot_seat": _show_state(State.PLAYER_COUNT)
		# Modem and Direct Connect stay disabled: those transports no longer
		# exist. Network now means TCP/IP (see the remote-multiplayer spec).
		"network": get_tree().change_scene_to_file("res://src/menu/network_setup.tscn")
		"players_2", "players_3", "players_4":
			Game.setup = NewGameSettings.new()
			Game.setup.human_player_count = action.trim_prefix("players_").to_int()
			get_tree().change_scene_to_file("res://src/menu/new_game_setup.tscn")
		"cancel_players": _show_state(State.MULTIPLAYER)
		"cancel_multiplayer": _show_state(State.GAME_TYPE)
		"cancel": _show_state(State.GAME_TYPE if _state == State.CAMPAIGN else State.MAIN)
		"leader_0", "leader_1", "leader_2", "leader_3":
			var ruler := action.trim_prefix("leader_").to_int()
			_briefing_open = true
			_panel.visible = false
			_shadow.visible = false
			# The campaign opens with the same full-screen briefing the
			# original shows between missions, never over the title menu.
			var started: bool = await CampaignBriefing.begin(self, Game, ruler)
			if not started:
				_briefing_open = false
				_panel.visible = true
				_shadow.visible = true
		"load_game": _show_state(State.LOAD_TYPE)
		"cancel_load": _show_state(State.MAIN)
		"load_standard", "load_campaign", "load_multiplayer":
			var dlg := SaveLoadDialog.new()
			add_child(dlg)
			# The original clears the menu panel while the file list is up.
			_panel.visible = false
			_shadow.visible = false
			dlg.closed.connect(func():
				_panel.visible = true
				_shadow.visible = true)
			# Multiplayer lists both local hot-seat and remote network saves.
			dlg.open(SaveLoadDialog.Mode.LOAD, SaveGame.SAVE_DIR,
					"campaign" if action == "load_campaign" else (
					"hotseat,network" if action == "load_multiplayer" else "standard"))
			dlg.confirmed.connect(func(slot: String):
				# Load needs a Game run context; load_game builds it from the envelope.
				var err: String = Game.load_game(slot)
				if err != "":
					dlg.show_error(err))
		_: pass

func play_intro() -> void:
	var sequence := CinematicPlayer.intro_sequence()
	if sequence.is_empty():
		return
	var player := CinematicPlayer.new()
	add_child(player)
	player.play_sequence(sequence)
	await player.playback_finished
	player.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if _briefing_open:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: Key = event.keycode
	# Each button's hotkey is the scancode its stp*.bin widget record carries.
	for def in menu_defs(_state):
		if def["key"] == key and not def["disabled"]:
			get_viewport().set_input_as_handled()
			_on_action(def["action"])
			return
