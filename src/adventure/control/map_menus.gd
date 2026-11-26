class_name MapMenus
extends RefCounted

## Manages modal screens, options, puzzle map, view world, kingdom overview,
## system menu, save/load dialogs, scenario/campaign info, and game over.

var game_over_shown := false
var pending_game_over_message: String = ""

func open_puzzle_map(map_root: Node2D, map_data: MapData,
		animate_latest_visit: bool = false) -> void:
	var human: PlayerState = Game.state.human() if Game.state != null else null
	if human == null:
		return
	var pm = load("res://src/ui/puzzle_map.gd").new()
	map_root.add_child(pm)
	var previous_visited := maxi(human.puzzle_pieces.size() - 1, 0) \
			if animate_latest_visit else -1
	pm.open(map_data, human, count_obelisks(map_data), previous_visited)

func count_obelisks(map_data: MapData) -> int:
	return Dig.count_obelisks(map_data)

func on_dig(map_root: Node2D, map_data: MapData, hero: Hero, audio: AdventureAudio,
		turns: AdventureTurnController, persist_hero_fn: Callable,
		update_ui_fn: Callable) -> void:
	if Game.state == null or Game.state.players.is_empty() or hero == null:
		return
	var human := Game.state.human()
	var model: HeroModel = human.active()
	if model == null:
		return
	persist_hero_fn.call()
	Dig.perform_dig(hero, model, human, map_data, map_root, audio)
	persist_hero_fn.call()
	update_ui_fn.call()
	if Game.campaign_objective_complete(map_data) and turns != null:
		turns.check_game_over()

func open_adventure_options(map_root: Node2D, open_puzzle_fn: Callable,
		open_world_fn: Callable, open_spells_fn: Callable,
		on_dig_fn: Callable) -> CanvasLayer:
	var dlg = load("res://src/ui/adventure_options_dialog.gd").new()
	map_root.add_child(dlg)
	dlg.puzzle_requested.connect(open_puzzle_fn)
	dlg.world_requested.connect(open_world_fn)
	dlg.spell_requested.connect(open_spells_fn)
	dlg.dig_requested.connect(on_dig_fn)
	dlg.open()
	return dlg

func open_view_world(map_root: Node2D, map_data: MapData, fog: FogLayer,
		hero: Hero) -> CanvasLayer:
	var vw = load("res://src/ui/view_world.gd").new()
	map_root.add_child(vw)
	vw.open(map_data, map_data.objects, Game.state.players if Game.state != null else [], "world", fog, hero)
	return vw

func open_view_world_for_bench(map_root: Node2D, map_data: MapData, fog: FogLayer,
		hero: Hero) -> CanvasLayer:
	return open_view_world(map_root, map_data, fog, hero)

func open_kingdom_overview(map_root: Node2D, map_data: MapData) -> CanvasLayer:
	var ko = load("res://src/ui/kingdom_overview.gd").new()
	map_root.add_child(ko)
	ko.open(Game.state, map_data)
	return ko

func open_system_menu(map_root: Node2D, campaign_info_fn: Callable,
		persist_heroes_fn: Callable = Callable()) -> CanvasLayer:
	var sm = load("res://src/ui/system_menu.gd").new()
	map_root.add_child(sm)
	sm.info_requested.connect(campaign_info_fn)
	sm.persist_heroes_fn = persist_heroes_fn
	sm.open()
	return sm

func open_save_dialog(map_root: Node2D, persist_heroes_fn: Callable) -> CanvasLayer:
	return save_dialog(map_root, persist_heroes_fn)

## The in-game save dialog, shared by the S hotkey and the options panel.
## Hero tiles are persisted first so the slot never holds stale positions.
## `on_closed` runs when the dialog is cancelled or the success notice is dismissed.
static func save_dialog(parent: Node, persist_heroes_fn: Callable,
		on_closed: Callable = Callable()) -> SaveLoadDialog:
	var dlg := SaveLoadDialog.new()
	parent.add_child(dlg)
	dlg.open(SaveLoadDialog.Mode.SAVE, SaveGame.SAVE_DIR, String(Game.game_mode))
	dlg.set_name_text(Game.game_name)
	if on_closed.is_valid():
		dlg.closed.connect(on_closed)
	dlg.confirmed.connect(func(slot: String):
		if persist_heroes_fn.is_valid():
			persist_heroes_fn.call()
		var err: String = Game.save_game(slot)
		if err == "":
			# A successful save frees the dialog without emitting `closed`.
			dlg.queue_free()
			MapDialogs.info(parent, {"text": "Game saved successfully.", "centered": true,
					"on_close": on_closed})
		else:
			dlg.show_error(err)
	)
	return dlg

func open_campaign_info(map_root: Node2D, map_data: MapData,
		allow_restart: bool) -> void:
	if Game.game_mode == &"campaign" and Game.campaign != null:
		var dialog := CampaignInfoDialog.new()
		map_root.add_child(dialog)
		dialog.open(Game.campaign.mission(), allow_restart)
		return
	open_scenario_info(map_root, map_data)

func open_scenario_info(map_root: Node2D, map_data: MapData) -> void:
	var info: ScenarioInfo = null
	if Game.selected_map_path != "":
		info = ScenarioCatalog.find_by_path(Game.selected_map_path)
	if info == null and Game.setup != null and Game.setup.map_path != "":
		info = ScenarioCatalog.find_by_path(Game.setup.map_path)
	if info == null and map_data != null:
		info = ScenarioInfo.new()
		info.path = Game.selected_map_path
		info.name = map_data.name
		info.description = map_data.description
		info.map_difficulty = map_data.map_difficulty
		info.size = map_data.size
	if info == null:
		return
	var settings: NewGameSettings = Game.setup.duplicate_settings() if Game.setup != null else NewGameSettings.new()
	var dlg := ScenarioSummary.new()
	map_root.add_child(dlg)
	dlg.open(settings, info)

func show_game_over(map_root: Node2D, map_data: MapData, message: String,
		is_modal_active_fn: Callable,
		freeze_fn: Callable = Callable(),
		hide_net_wait_fn: Callable = Callable()) -> void:
	if game_over_shown:
		return
	game_over_shown = true
	if freeze_fn.is_valid():
		freeze_fn.call()
	if hide_net_wait_fn.is_valid():
		hide_net_wait_fn.call()
	if Game.game_mode == &"network" and Net.link_up:
		Net.send_state(Net.remote_side(), NetProtocol.KIND_FINAL, message)
	if is_modal_active_fn.call():
		pending_game_over_message = message
		return
	show_game_over_immediate(map_root, map_data, message)

func show_game_over_immediate(map_root: Node2D, map_data: MapData,
		message: String) -> void:
	var videos: Array[String] = []
	var is_campaign_win := false
	var campaign_res: Dictionary = {}
	if Game.game_mode == &"campaign" and Game.campaign != null:
		if Game.campaign_objective_complete(map_data):
			campaign_res = Game.complete_campaign_mission()
			is_campaign_win = true
			if bool(campaign_res.get("complete", false)):
				videos = CinematicPlayer.campaign_win_sequence()
		else:
			videos = CinematicPlayer.defeat_sequence()
	elif not message.begins_with("Victory"):
		videos = CinematicPlayer.defeat_sequence()

	if not videos.is_empty():
		var player := CinematicPlayer.new()
		map_root.add_child(player)
		player.play_sequence(videos)
		await player.playback_finished
		player.queue_free()

	var dlg := GameOverDialog.new()
	map_root.add_child(dlg)
	if Game.game_mode == &"campaign" and Game.campaign != null:
		if is_campaign_win:
			dlg.open_campaign(campaign_res)
		else:
			dlg.open_campaign_defeat(message)
	else:
		if message.begins_with("Victory") and Game.state != null:
			var winner := Game.state.human().active()
			var info := ScenarioInfo.new()
			info.map_difficulty = map_data.map_difficulty
			info.size = map_data.size
			var rating := Game.setup.rating(info)
			var final_score := ScenarioScore.calculate(Game.state.day, rating)
			var hero_title := winner.hero_class.capitalize() if winner != null else "Hero"
			var hero_name := winner.hero_name if winner != null else "Player"
			var qualifies := HighScoreStore.qualifies_standard(final_score)
			var on_record := Callable()
			if qualifies:
				on_record = func(name_entered: String) -> void:
					if Game != null:
						Game.high_scores_mode = &"standard"
					HighScoreStore.record_standard(name_entered, map_data.name, final_score, hero_title)
			dlg.open_standard_victory(message + "\nFinal Score: %d" % final_score, Game.state.day,
					rating, qualifies, hero_name, on_record)
		else:
			dlg.open(message)
