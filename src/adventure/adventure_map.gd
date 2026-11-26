extends Node2D

## Adventure map: hero (click-to-move A*) + fog + camera + an interactive object
## layer (resources, mines, dwellings, neutral stacks, town) dispatched via
## MapObject.on_visit() when the hero steps on an object's action tile.
## Root script serves as wiring coordinator across domain subcomponents.

const MAP_PATH := "res://data/maps/skirmish01.json"
const REVEAL_RADIUS := 4

# Subcomponents
var _boot: AdventureBoot
var _hero_selection: HeroSelection
var _defeat_presenter: DefeatPresenter
var _seat_handoff: SeatHandoff
var _menus: MapMenus

func _init() -> void:
	_boot = load("res://src/adventure/control/adventure_boot.gd").new()
	_hero_selection = load("res://src/adventure/control/hero_selection.gd").new()
	_defeat_presenter = load("res://src/adventure/control/defeat_presenter.gd").new()
	_seat_handoff = load("res://src/adventure/control/seat_handoff.gd").new()
	_menus = load("res://src/adventure/control/map_menus.gd").new()

var _map: MapData
var _astar: PassabilityGrid
var _hero: Hero:
	get: return _hero_selection.hero if _hero_selection != null else null
	set(value):
		if _hero_selection != null:
			_hero_selection.hero = value
var _heroes: Array:
	get: return _hero_selection.heroes if _hero_selection != null else []
	set(value):
		if _hero_selection != null:
			_hero_selection.heroes = value
var _ai: AITurnRunner
var _ai_running := false   # true while the AI turn executes (blocks player input)
var _fog: FogLayer
var _cam: MapCamera
var _following := true   # camera auto-follows the hero until the player pans via the minimap
var _walk_prev_by_node: Dictionary = {}   # Hero node -> previous tile while walking (per-mover step cost)
var _world: AdventureWorldRenderer
var _objects: DynamicObjectProvider
var _boats: BoatLayer
var _input: AdventureInputController
var _turns: AdventureTurnController
var _spells := AdventureSpellController.new()
var _audio: AdventureAudio
var _pending_defeat_visuals: Array[Dictionary]:
	get: return _defeat_presenter.pending_defeat_visuals if _defeat_presenter != null else []
	set(value):
		if _defeat_presenter != null:
			_defeat_presenter.pending_defeat_visuals = value

var _hud: AdventureHud
var _quick_info := QuickInfoBox.new()
var _quick_hero_info := QuickHeroInfo.new()
var _quick_town_info := QuickTownInfo.new()
var _modal_cursor_active := false
var _end_turn_dialog: CanvasLayer
var _new_week_dialog_open := false
var _modal_dialog_queue: Array[Callable] = []
var _pending_level_up_dialogs: Array[Callable] = []
var _pending_game_over_message: String:
	get: return _menus.pending_game_over_message if _menus != null else ""
	set(value):
		if _menus != null:
			_menus.pending_game_over_message = value
var _active_modal: CanvasLayer = null

var _resolver := InteractionResolver.new()
var _pickup_busy: bool = false
## True while the map is held after a hero turns to face the hero it engages.
## The engage is already decided; input must not move the hero out of the shot.
var _engage_busy: bool = false
var _pending_attack_tile: Vector2i = Vector2i(-1, -1)
var _pending_attack_cost: int = 0
var _pending_board_tile: Vector2i = Vector2i(-1, -1)
var _pending_disembark_tile: Vector2i = Vector2i(-1, -1)
## The friendly hero the active hero is walking up to ("meet" action) and the
## tile the mover stops on: one cell carries one hero id, so the two heroes
## never share a tile. The exchange opens when the mover reaches that tile.
var _pending_meet_friend: Vector2i = Vector2i(-1, -1)
var _pending_meet_stop: Vector2i = Vector2i(-1, -1)
var _pending_meet_mover: Hero = null
var _game_over_shown: bool:
	get: return _menus.game_over_shown if _menus != null else false
	set(value):
		if _menus != null:
			_menus.game_over_shown = value

func _ready() -> void:
	var boot_args := _boot.parse_cmdline_args()
	var state_err := _boot.ensure_game_state(boot_args)
	if state_err != "":
		push_error("AdventureMap: %s" % state_err)
		get_tree().quit(1)
		return

	_map = _boot.load_map(boot_args)
	if _map == null:
		var path := Game.selected_map_path if Game.selected_map_path != "" else MAP_PATH
		push_error("AdventureMap: failed to load %s" % path)
		get_tree().quit(1)
		return

	var setup_error := _boot.configure_run(_map)
	if setup_error != "":
		push_error("AdventureMap: %s" % setup_error)
		get_tree().quit(1)
		return

	_world = AdventureWorldRenderer.new()
	_world.name = "AdventureWorld"
	add_child(_world)
	_world.setup(_map, Game.state,
			Game.state.human() if Game.state != null else null,
			bool(boot_args.get("nofog", false)))
	_fog = _world.fog
	_objects = _world.objects
	_boats = _world.boats
	_audio = AdventureAudio.new()
	add_child(_audio)
	_audio.setup(_map, func() -> Hero: return _hero, func() -> bool: return _ai_running)

	# Wire the interaction resolver now (before resolve_post_battle below); late-bound
	# refs are closures that read null now and live values once _ready() finishes.
	_wire_resolver()

	_resolver.resolve_post_battle()

	_astar = Pathfinder.build(_map)

	# Resume the hero where it left off (town/battle/hero-screen round-trips reload
	# this scene); fall back to the map's start tile on a fresh game.
	_spawn_player_heroes()
	_ai = AITurnRunner.new()
	add_child(_ai)
	_ai.hero_defeated.connect(_on_ai_hero_defeated)
	_ai.setup(_world.actors, _map, _astar, _fog, _world,
		func() -> Hero: return _hero,
		_current_army,
		func() -> void:
			_persist_hero()
			if _ai != null:
				_ai.persist_heroes()
			_following = false,
		_resolver.capture_town,
		func() -> Array: return _heroes)
	_ai.spawn_ai_hero()

	_turns = AdventureTurnController.new()
	add_child(_turns)
	_turns.setup(_map, _ai,
		func() -> Hero: return _hero,
		_current_army,
		_persist_hero,
		_update_ui,
		_show_game_over,
		func() -> void: _following = true,
		func() -> Array: return _heroes)
	_ai.status_check_fn = _turns.check_game_over
	_ai.modal_fn = _is_modal_active
	_turns.ai_phase_changed.connect(func(r: bool):
		_ai_running = r
		if r:
			if _input != null:
				_input.show_sunclock_cursor()
		else:
			if _input != null:
				_input.refresh_cursor()
			if not _new_week_dialog_open and _hud != null:
				if _hud.turn_transition_panel != null \
						and _hud.turn_transition_panel.mode == TurnTransitionPanel.Mode.AI_TURN:
					_hud.hide_turn_transition())
	_turns.ai_player_started.connect(func(_side: int, color_index: int):
		if _hud != null:
			_hud.show_ai_turn(color_index))
	_turns.human_handoff_requested.connect(_on_human_handoff_requested)
	_turns.remote_handoff_requested.connect(_on_remote_handoff_requested)
	_turns.new_day_started.connect(func(day: int):
		if _hud != null:
			_hud.show_new_day(day)
		if Game.state != null:
			var first := Game.state.human().select_turn_start_hero()
			if first >= 0:
				_set_active_hero(first)
		if _input != null:
			_input.refresh_path()
		_update_ui())
	_turns.new_week_started.connect(_on_new_week_started)
	_turns.player_eliminated.connect(_on_player_eliminated)
	_turns.townless_warning.connect(func(side: int, _days_left: int, message: String):
		queue_modal_dialog(func() -> CanvasLayer:
			return MapDialogs.crest_info(self, _crest_of(side), message)
		)
	)
	_turns.townless_banished.connect(func(side: int, message: String):
		queue_modal_dialog(func() -> CanvasLayer:
			var dlg := MapDialogs.crest_info(self, _crest_of(side), message)
			_spawn_player_heroes()
			return dlg
		)
	)
	_turns.player_vanquished.connect(func(side: int, message: String):
		queue_modal_dialog(func() -> CanvasLayer:
			return MapDialogs.crest_info(self, _crest_of(side), message)
		)
	)

	var resume_ai_phase := Game.pending_day_advance
	_turns.check_game_over()

	# Draw whatever is still live.
	_objects.spawn_all()

	_cam = MapCamera.new()
	add_child(_cam)
	var active_side: int = Game.state.active_player_side if Game.state != null else 0
	_boot.setup_camera(_cam, _map, _hero, _pending_defeat_visuals, active_side, Game.town_tile)

	_build_ui()
	_hold_pending_defeat_roster()
	if Game.game_mode == &"hotseat" and Game.hotseat_handoff_pending \
			and Game.state != null:
		var seated := Game.state.human()
		_show_hotseat_handoff(seated.side, false, false)
	_attach_network_session()
	# Resume only after the HUD exists so an AI battle round-trip cannot miss the
	# next crest/hourglass (or the dawn card when no AI players remain).
	if resume_ai_phase:
		_turns.resume_ai_phase(_resolver.town_notice)

	_input = AdventureInputController.new()
	add_child(_input)
	_input.fog = _fog
	_input.setup(_map, _hero, _astar,
		func() -> Hero:
			var pointer := get_canvas_transform().affine_inverse() * Pointer.position(get_viewport())
			return _ai.hero_node_at(Vector2i(int(pointer.x) / _map.tile_size,
					int(pointer.y) / _map.tile_size)),
		func() -> bool: return _ai_running,
		func() -> bool: return _is_modal_active() or (_hero != null and _hero.is_moving()) or _pickup_busy,
		func() -> Array:
			var tiles := []
			for h in _heroes:
				if h != _hero and is_instance_valid(h):
					tiles.append(h.tile)
			# The AI hero blocks routing too: paths may END on it (attack) but
			# never pass through it (input controller exempts the destination).
			for ai_node: Hero in _ai.all_heroes():
				tiles.append(ai_node.tile)
			return tiles,
		func(world_position: Vector2) -> Vector2i:
			return _boats.boat_tile_at_world(world_position) if _boats != null \
					else Vector2i(-1, -1),
		func() -> GameState: return Game.state,
		_world.routes,
		func() -> int: return _hud.roster_panel.get_selected_kind() if (_hud != null and _hud.roster_panel != null) else 1)
	_input.hero_band_clicked.connect(func():
		if _hud != null and _hud.turn_transition_panel != null and _hud.turn_transition_panel.visible:
			_hud.hide_turn_transition()
			return
		if _hud != null and _hud.hero_panel != null:
			_hud.hero_panel.cycle_view())
	_input.end_turn_requested.connect(func(): _on_button("end_turn"))
	_input.pan_requested.connect(func(delta: Vector2):
		_following = false
		_cam.center_on(_cam.position + delta))
	_spells.setup(self, _map, func() -> Hero: return _hero, _current_army,
			teleport_hero, func():
				if _boats != null:
					_boats.refresh())
	_spells.spell_cast.connect(func(id: String, kind: String):
		if _audio != null:
			_audio.play_spell(id, kind))
	_input.spellbook_requested.connect(func():
		if _hero != null and not _is_modal_active():
			_spells.open_spellbook())
	_input.puzzle_map_requested.connect(func():
		if not _is_modal_active():
			_open_puzzle_map())
	_input.dig_requested.connect(func():
		if not _is_modal_active():
			_on_dig())
	_input.view_world_requested.connect(func():
		if not _is_modal_active():
			_open_view_world())
	_input.campaign_info_requested.connect(func():
		if not _is_modal_active():
			_open_campaign_info(true))
	_input.kingdom_overview_requested.connect(func():
		if not _is_modal_active():
			_open_kingdom_overview())
	_input.next_town_requested.connect(func():
		if not _is_modal_active():
			_on_next_town())
	_input.next_hero_requested.connect(func():
		if not _is_modal_active():
			_on_next_hero())
	_input.adventure_options_requested.connect(func():
		if not _is_modal_active():
			_open_adventure_options())
	_input.system_menu_requested.connect(func():
		if not _is_modal_active():
			_open_system_menu())
	_input.save_game_requested.connect(func():
		if not _is_modal_active():
			_open_save_dialog())
	_input.load_game_requested.connect(func():
		if not _is_modal_active():
			_open_load_dialog())
	_input.leave_game_requested.connect(func(action: String):
		if not _is_modal_active():
			load("res://src/ui/system_menu.gd").confirm_leave(self, action))
	_input.open_selected_requested.connect(func():
		if not _is_modal_active():
			_on_open_selected())
	_input.town_selected.connect(func(town: TownObject):
		if not _is_modal_active():
			_on_town_selected(town))
	_input.town_double_clicked.connect(func(town: TownObject):
		if not _is_modal_active():
			_on_town_double_clicked(town))
	_input.hero_double_clicked.connect(func():
		if not _is_modal_active():
			_on_hero_double_clicked())
	_input.hero_selected.connect(func():
		if not _is_modal_active():
			_on_hero_selected())
	_input.path_confirmed.connect(_confirm_path)
	_input.stop_hero_requested.connect(stop_active_hero)
	_input.route_changed.connect(_update_button_states)

	# heroes.exe 0x9610c reveals a radius of 100 around (30, 30) for each of
	# the four players (0x83998), so the whole map for everyone, silently.
	_input.cheat_reveal_map_requested.connect(func():
		if not _is_modal_active():
			if Game.state != null:
				for p: PlayerState in Game.state.players:
					p.explore_all()
			if _fog != null:
				_fog.explore_everything()
			if _hud != null:
				_hud.refresh()
	)

	_input.inspect_requested.connect(func(screen_pos: Vector2, world_pos: Vector2):
		if not _is_modal_active():
			var tile := Vector2i(int(world_pos.x) / _map.tile_size, int(world_pos.y) / _map.tile_size)
			var hero_info := _get_hero_at(tile)
			if not hero_info.is_empty():
				_quick_info.hide_info()
				_quick_town_info.hide_info()
				var is_own := bool(hero_info.get("is_own", false))
				var identify_active := false
				var local_active_side := Game.state.active_player_side if Game.state != null else 0
				if Game.state != null:
					var p := Game.state.player_of(local_active_side)
					if p != null and p.identify_hero_active:
						identify_active = true
				_quick_hero_info.show_hero(
					hero_info.get("model") as HeroModel,
					int(hero_info.get("side", 0)),
					is_own,
					screen_pos,
					identify_active
				)
				return

			var town := _get_town_at(tile)
			if town != null:
				_quick_info.hide_info()
				_quick_hero_info.hide_info()
				var owner := town.owner
				var local_active_side := Game.state.active_player_side if Game.state != null else 0
				var is_own := (owner == local_active_side)
				var town_name := String(town.params.get("name", ""))
				if town_name == "":
					town_name = BuildingCatalog.faction_for_type(town.town_type).capitalize()
				var has_castle := bool(town.params.get("has_castle", true))
				var garrison: ArmyData = null
				if owner >= 0 and Game.state != null:
					var p := Game.state.player_of(owner)
					if p != null:
						var tm: TownModel = p.town_by_object_id(town.id)
						if tm != null:
							garrison = tm.army
							has_castle = tm.has_castle
				if garrison == null and town.params.has("army") and town.params["army"] is ArmyData:
					garrison = town.params["army"] as ArmyData
				# One Thieves' Guild reveals the creature types in an enemy
				# garrison, two the approximate quantity (KB castles.md).
				var guilds := 0
				if Game.state != null:
					var viewer := Game.state.player_of(local_active_side)
					if viewer != null:
						guilds = viewer.thieves_guild_count()
				_quick_town_info.show_town(town_name, town.town_type, has_castle, owner,
						garrison, is_own, screen_pos, guilds)
				return

			_quick_hero_info.hide_info()
			_quick_town_info.hide_info()
			var info := AdventureInspector.inspect_tile(_map, _fog, tile)
			_quick_info.show_info(String(info.get("title", "")), String(info.get("body", "")), screen_pos)
	)
	_input.inspect_dismissed.connect(func():
		_quick_hero_info.hide_info()
		_quick_town_info.hide_info()
		_quick_info.hide_info()
	)
	_input.refresh_path()
	add_child(_quick_info)
	add_child(_quick_hero_info)
	add_child(_quick_town_info)
	if Game.fade_in_pending:
		Game.fade_in_pending = false
		var map_fade := ScreenFade.new()
		add_child(map_fade)
		map_fade.set_black(true)
		_fade_in_then_free(map_fade)
	if not _pending_defeat_visuals.is_empty():
		call_deferred("_play_pending_defeat_visuals")
	if Game.game_mode == &"campaign" and Game.campaign != null and Game.campaign_show_intro:
		Game.campaign_show_intro = false
		_open_campaign_info(false)
	_pump_dialog_queue()

	# Tool hooks: probe, smoke, shots, and frame time benchmarks
	var probe = DevFlags.tool("res://src/tools/probe_runner.gd", ["--probe="])
	if probe != null:
		await probe.start(self)
		return

	var smoke = DevFlags.smoke()
	if smoke != null:
		await smoke.map(self)
		return

	var shots = DevFlags.tool("res://src/tools/shots/adventure_map_shots.gd")
	if shots != null:
		await shots.run(self)
		return

	if _boot.run_benchmarks(self):
		return

func _process(delta: float) -> void:
	if _cam == null:
		return
	_sync_popup_cursor()
	# Edge scrolling
	var scroll_dir := _input.edge_scroll_direction()
	if scroll_dir != Vector2.ZERO:
		_following = false
		# A finger whose hold really moved the map loses its tap.
		TouchInput.pan_map(_cam, scroll_dir * MapCamera.PAN_SPEED * delta)

	if _world != null:
		_world.focus_hero = _hero
	# Auto-follow the hero unless the player panned away via the minimap or edge-scrolled.
	# KB adventure-screen.md 8: during computer turns the view holds, moving only
	# to visible computer steps; it returns to the hero when the human turn starts.
	if _following and _hero != null and not _ai_running:
		_cam.center_on(_hero.center())
	var visible_enemy_markers: Array[Dictionary] = []
	for ai_node: Hero in _ai.all_heroes():
		ai_node.visible = _fog.is_explored(ai_node.tile)
		if ai_node.visible:
			visible_enemy_markers.append({
				"tile": ai_node.tile,
				"owner": _ai.side_at(ai_node.tile),
			})
			if _ai_running and ai_node.is_moving():
				_cam.center_on(ai_node.center())
	if _hud != null and _hud.minimap != null:
		_hud.minimap.set_enemy_markers(visible_enemy_markers)
	if _hud != null:
		_hud.process_frame()

func queue_modal_dialog(dialog_factory: Callable) -> void:
	_modal_dialog_queue.append(dialog_factory)
	call_deferred("_pump_dialog_queue")

func queue_level_up(hero_model: HeroModel, events: Array[Dictionary], after_dialog: CanvasLayer = null) -> void:
	if hero_model == null or events.is_empty():
		return
	var factory := func() -> CanvasLayer:
		return MapDialogs.level_ups(self, hero_model, events)
	if after_dialog != null and is_instance_valid(after_dialog) and not after_dialog.is_queued_for_deletion():
		var on_after_closed := func():
			_pending_level_up_dialogs.append(factory)
			call_deferred("_pump_dialog_queue")
		if after_dialog.has_signal("closed"):
			after_dialog.connect("closed", on_after_closed, CONNECT_ONE_SHOT)
			return
		elif after_dialog.has_signal("chosen"):
			after_dialog.connect("chosen", func(_idx: int): on_after_closed.call(), CONNECT_ONE_SHOT)
			return
	_pending_level_up_dialogs.append(factory)
	call_deferred("_pump_dialog_queue")

func _active_modal_dialog() -> CanvasLayer:
	if _active_modal != null and is_instance_valid(_active_modal) and not _active_modal.is_queued_for_deletion():
		return _active_modal
	for child in get_children():
		if child is CanvasLayer and child != _hud \
				and child != _quick_info and child != _quick_hero_info and child != _quick_town_info \
				and child.visible and not child.is_queued_for_deletion():
			return child as CanvasLayer
	return null

func _attach_dialog_dismiss(dlg: CanvasLayer) -> void:
	if dlg == null or dlg.has_meta(&"_dismiss_listener_attached"):
		return
	dlg.set_meta(&"_dismiss_listener_attached", true)
	var on_dismiss := func():
		if _active_modal == dlg:
			_active_modal = null
		_sync_popup_cursor()
		_update_ui()
		call_deferred("_pump_dialog_queue")
	if dlg.has_signal("closed"):
		dlg.connect("closed", on_dismiss, CONNECT_ONE_SHOT)
	elif dlg.has_signal("chosen"):
		dlg.connect("chosen", func(_idx: int): on_dismiss.call(), CONNECT_ONE_SHOT)
	elif dlg.has_signal("tree_exited"):
		dlg.connect("tree_exited", on_dismiss, CONNECT_ONE_SHOT)

func _pump_dialog_queue() -> void:
	var current := _active_modal_dialog()
	if current != null:
		_active_modal = current
		_attach_dialog_dismiss(current)
		_sync_popup_cursor()
		return
	_active_modal = null

	# 1. Event dialogs (vanquished, townless warning, etc.) show first, one after another
	if not _modal_dialog_queue.is_empty():
		var factory: Callable = _modal_dialog_queue.pop_front()
		var dlg: CanvasLayer = factory.call() as CanvasLayer
		if dlg != null and is_instance_valid(dlg):
			_active_modal = dlg
			_attach_dialog_dismiss(dlg)
			_sync_popup_cursor()
			return

	# 2. When events happen at the same time, show hero gain skill last!
	if not _pending_level_up_dialogs.is_empty():
		var factory: Callable = _pending_level_up_dialogs.pop_front()
		var dlg: CanvasLayer = factory.call() as CanvasLayer
		if dlg != null and is_instance_valid(dlg):
			_active_modal = dlg
			_attach_dialog_dismiss(dlg)
			_sync_popup_cursor()
			return

	# 3. If game over was pending, show it after all dialogue panels are dismissed
	if _pending_game_over_message != "":
		var msg := _pending_game_over_message
		_pending_game_over_message = ""
		_show_game_over_immediate(msg)

## The map fades in from black after a campaign briefing. The fade is a
## CanvasLayer, which _active_modal_dialog takes for an open dialog, so it
## must go once the map is in view or the map ignores all input.
func _fade_in_then_free(fade: ScreenFade) -> void:
	# Skip the frame that built the map and the first draw: their long deltas
	# would finish the tween in one step on a slow device.
	for i in 3:
		await get_tree().process_frame
	await fade.fade(false)
	fade.queue_free()

func _is_modal_active() -> bool:
	if _active_modal_dialog() != null:
		return true
	if not _modal_dialog_queue.is_empty() or not _pending_level_up_dialogs.is_empty():
		return true
	return false

## Adventure hover cursors (horse, sword, ship) must not leak through popups.
func _sync_popup_cursor() -> void:
	if _input == null:
		return
	var modal_active := _is_modal_active()
	if modal_active:
		_input.show_pointer_cursor()
	elif _modal_cursor_active:
		_input.refresh_cursor()
	_modal_cursor_active = modal_active

func _exit_tree() -> void:
	Game.set_cursor_visible(true)
	Game.set_default_cursor()   # restore the HOMM1 pointer for other scenes

func _start_pickup_sequence() -> void:
	if _pickup_busy:
		return
	var tree := get_tree()
	if tree == null:
		return
	_pickup_busy = true
	Game.set_cursor_visible(false)
	var timer := tree.create_timer(DynamicObjectProvider.PICKUP_TOTAL_DURATION)
	timer.timeout.connect(func():
		_pickup_busy = false
		Game.set_cursor_visible(true)
		if _input != null:
			_input.refresh_cursor()
	)

## Halt the moving active hero after completing the current tile step, cancelling
## the remaining walk run and any pending interactions (heroes.exe 0x93059).
func stop_active_hero() -> void:
	if _ai_running or _hero == null or not is_instance_valid(_hero) or not _hero.is_moving():
		return
	_pending_board_tile = Vector2i(-1, -1)
	_pending_disembark_tile = Vector2i(-1, -1)
	_pending_meet_friend = Vector2i(-1, -1)
	_pending_meet_stop = Vector2i(-1, -1)
	_pending_meet_mover = null
	_pending_attack_tile = Vector2i(-1, -1)
	_pending_attack_cost = 0
	if _resolver != null:
		_resolver.clear_pending()
	_hero.stop_movement()

## Walk only the portion of the path the hero can afford this turn; spend points.
func _confirm_path(path: Array) -> void:
	if _pickup_busy:
		return
	if _hud != null and _hud.turn_transition_panel != null \
			and _hud.turn_transition_panel.mode == TurnTransitionPanel.Mode.NEW_DAY:
		_hud.hide_turn_transition()
	_resolver.clear_pending()
	_pending_attack_tile = Vector2i(-1, -1)
	_pending_attack_cost = 0
	_pending_board_tile = Vector2i(-1, -1)
	_pending_disembark_tile = Vector2i(-1, -1)
	if path.size() < 2:
		return

	# A friendly hero on the destination tile is a "meet", not a step: the
	# mover halts on the tile before him (one cell carries one hero id, so
	# the two heroes never share a tile) and the exchange opens from there.
	var walk_path: Array = path
	var meet_friend := _friendly_hero_at(path[path.size() - 1])
	if meet_friend != null:
		walk_path = path.slice(0, path.size() - 1)
		_pending_meet_friend = path[path.size() - 1]
		_pending_meet_stop = walk_path[walk_path.size() - 1]
		_pending_meet_mover = _hero
		if _hero != null:
			# The route still ends on the friend's tile; the hero stops short.
			_hero.planned_dest = _pending_meet_friend
	else:
		_pending_meet_friend = Vector2i(-1, -1)
		_pending_meet_stop = Vector2i(-1, -1)
		_pending_meet_mover = null
	if meet_friend != null and walk_path.size() < 2:
		# Already next to him: the exchange opens without a step.
		_pending_meet_friend = Vector2i(-1, -1)
		_pending_meet_stop = Vector2i(-1, -1)
		_pending_meet_mover = null
		if _hero != null:
			_hero.planned_dest = Vector2i(-1, -1)
			_hero.face_towards(meet_friend.tile)
			if _input != null:
				_input.cancel_route()
		_update_ui()
		_open_exchange(_hero, meet_friend)
		return

	var prefix: Array = [walk_path[0]]
	var remaining := _hero.move_points
	var step_charges: Array[int] = []
	for i in range(1, walk_path.size()):
		var kind := TravelRules.step_kind(_map, _astar, Game.state,
				_hero.travel_mode, walk_path[i - 1], walk_path[i])
		if kind == TravelRules.INVALID and i == walk_path.size() - 1 \
				and _hero.travel_mode == &"land" \
				and _active_object_at_action(walk_path[i]) != null:
			kind = TravelRules.MOVE
		if kind == TravelRules.INVALID:
			break
		if not TravelRules.is_walk(kind):
			if remaining <= 0:
				break
			prefix.append(walk_path[i])
			step_charges.append(remaining)
			break
		var raw_cost := TravelRules.step_cost(kind, walk_path[i - 1], walk_path[i], _map,
				_hero.hero_class)
		var straight_cost := Hero.step_cost(walk_path[i - 1],
				walk_path[i - 1] + Vector2i.RIGHT, _map,
				_hero.travel_mode == &"sea", _hero.hero_class)
		if not Pathfinder.can_take_today(raw_cost, straight_cost, remaining):
			break
		var charged_cost := Pathfinder.current_day_step_cost(
				raw_cost, straight_cost, remaining)
		remaining -= charged_cost
		prefix.append(walk_path[i])
		step_charges.append(charged_cost)
	if prefix.size() < 2:
		if _input != null:
			_input.refresh_path()
		return

	var last_tile: Vector2i = prefix[-1]
	if _hero.travel_mode == &"land" and TravelRules.step_kind(_map, _astar,
			Game.state, _hero.travel_mode, prefix[-2], last_tile) == TravelRules.BOARD:
		_pending_board_tile = last_tile
		prefix.remove_at(prefix.size() - 1)
		if prefix.size() < 2:
			_board_pending_boat()
			return
		_walk_prev_by_node[_hero] = _hero.tile
		_following = true
		_update_ui()
		_hero.move_along(prefix)
		return
	if _hero.travel_mode == &"sea" and TravelRules.step_kind(_map, _astar,
			Game.state, _hero.travel_mode, prefix[-2], last_tile) == TravelRules.DISEMBARK:
		_pending_disembark_tile = last_tile
		prefix.remove_at(prefix.size() - 1)
		if prefix.size() < 2:
			_disembark_pending_boat()
			return
		_walk_prev_by_node[_hero] = _hero.tile
		_following = true
		_update_ui()
		_hero.move_along(prefix)
		return
	var last_obj := _active_object_at_action(last_tile)
	var protecting_stack: NeutralStack = _astar.protecting_stack_at(last_tile)
	var local_side := Game.state.active_player_side if Game.state != null else 0
	var enemy_side_at_dest := _enemy_side_at_tile(last_tile)

	if last_obj != null and last_obj.is_walk_on_pickup():
		_resolver.set_pending(last_obj, step_charges[-1], last_tile)
		prefix.remove_at(prefix.size() - 1)
	elif enemy_side_at_dest >= 0:
		_pending_attack_tile = last_tile
		_pending_attack_cost = step_charges[-1]
		prefix.remove_at(prefix.size() - 1)
	elif last_obj is TownObject:
		if (last_obj as TownObject).is_guarded_against(local_side, _map):
			_resolver.set_pending(last_obj, step_charges[-1], last_tile)
			prefix.remove_at(prefix.size() - 1)
	elif last_obj != null and last_obj.is_armed():
		_resolver.set_pending(last_obj, step_charges[-1], last_tile)
		prefix.remove_at(prefix.size() - 1)
	elif protecting_stack != null:
		_resolver.set_pending(protecting_stack, 0, protecting_stack.action_tile)

	if prefix.size() < 2:
		_resolver.collect_pending()
		_engage_pending_attack()
		if _hero != null:
			_hero.planned_dest = Vector2i(-1, -1)
			if _input != null:
				_input.cancel_route()
		return

	_walk_prev_by_node[_hero] = _hero.tile
	_following = true
	_update_ui()
	_hero.move_along(prefix)

func _build_ui() -> void:
	_hud = AdventureHud.new()
	add_child(_hud)
	var hero_model: HeroModel = null
	if Game.state != null and not Game.state.players.is_empty():
		hero_model = Game.state.human().active()
	if hero_model == null:
		hero_model = Game.player_hero
	var h_name: String = hero_model.hero_name if hero_model != null else ""
	var h_army: ArmyData = hero_model.army if hero_model != null else null
	var h_crest: int = hero_model.crest_idx if hero_model != null else 0
	var marker := Vector2i(-1, -1)
	var human = Game.state.human() if Game.state != null else null
	var town_type := 0
	var has_town := false
	if human != null:
		has_town = human.owns_town and human.town != null
		if has_town:
			town_type = human.town.town_type
	else:
		for o: MapObject in _map.objects:
			if o is TownObject:
				town_type = (o as TownObject).town_type
				has_town = true
				break
	for o: MapObject in _map.objects:
		if o is NeutralStack and not (o as NeutralStack).consumed and marker == Vector2i(-1, -1):
			marker = o.tile
			break
	var heroes_nodes_fn := func() -> Array: return _heroes
	_hud.setup(_map, human, heroes_nodes_fn, _hero, _cam, Vector2(448, 448), marker, h_name, h_army, h_crest, town_type, has_town, _fog)
	_hud.button_action.connect(_on_button)
	_hud.inspect_button_requested.connect(func(slot: int, pos: Vector2):
		if not _is_modal_active():
			var info := AdventureInspector.button_hint(slot)
			_quick_info.show_info(String(info.get("title", "")), String(info.get("body", "")), pos)
	)
	_hud.inspect_dismissed.connect(func():
		_quick_hero_info.hide_info()
		_quick_town_info.hide_info()
		_quick_info.hide_info()
	)
	_hud.pan_requested.connect(_on_minimap_pan)
	_hud.hero_selected.connect(_set_active_hero)
	_hud.town_selected.connect(_on_roster_town_selected)
	_update_button_states()

func _current_army() -> ArmyData:
	if Game.state != null and not Game.state.players.is_empty():
		var active_model := Game.state.human().active()
		if active_model != null and active_model.army != null:
			return active_model.army
	return Game.player_army if Game.player_army != null else _fallback_army()

func _update_ui() -> void:
	_update_button_states()
	if _hud != null:
		_hud.refresh()

func _update_button_states() -> void:
	if _hud == null or _hud.button_bar == null:
		return
	var next_hero_ok := heroes_may_still_move()
	var move_ok := false
	if _hero != null and is_instance_valid(_hero) and not _hero.is_moving():
		if _hero.has_enough_movement_to_move() and _hero.planned_dest != Vector2i(-1, -1) and _hero.planned_dest != _hero.tile:
			move_ok = true
	_hud.set_button_enabled(0, next_hero_ok)
	_hud.set_button_enabled(1, move_ok)

func _on_button(action_name: String) -> void:
	if _ai_running or _pickup_busy or _engage_busy:
		return
	if _hero != null and _hero.is_moving():
		stop_active_hero()
		return
	if _hud != null and _hud.turn_transition_panel != null \
			and _hud.turn_transition_panel.mode == TurnTransitionPanel.Mode.NEW_DAY:
		_hud.hide_turn_transition()
	if _hud != null:
		_hud.dismiss_resource_popup()
	match action_name:
		"end_turn":
			if _ai_running or (_hero != null and _hero.is_moving()):
				return
			if _end_turn_dialog != null and is_instance_valid(_end_turn_dialog):
				return
			if heroes_may_still_move():
				_end_turn_dialog = MapDialogs.end_turn_confirm(self, func(idx: int):
					if idx == 0:
						call_deferred("_commit_end_turn"))
				_end_turn_dialog.connect("closed", func(): _end_turn_dialog = null)
			else:
				_commit_end_turn()
		"kingdom", "town": _open_kingdom_overview()
		"next_hero": _on_next_hero()
		"move":
			if _hero != null and is_instance_valid(_hero) and not _hero.is_moving() and _hero.has_enough_movement_to_move():
				_input.commit_pending()
		"flag": _open_adventure_options()
		"system": _open_system_menu()
		_: pass

func _commit_end_turn() -> void:
	if _ai_running or _engage_busy:
		return
	if _hud != null:
		_hud.dismiss_resource_popup()
	if _input != null:
		_input.clear_path()
		_input.show_sunclock_cursor()
	if _turns != null:
		_turns.end_turn()

func _on_new_week_started(event: Dictionary) -> void:
	if Game.state != null and not Game.state.last_spawned_neutrals.is_empty():
		for s: NeutralStack in Game.state.last_spawned_neutrals:
			_objects.refresh_object(s.id)
		if _astar != null:
			_astar.rebuild()
	_new_week_dialog_open = true
	var dialog := MapDialogs.new_week(self, GameState.week_message(event))
	dialog.connect("closed", func():
		_new_week_dialog_open = false
		if not _ai_running and _hud != null:
			_hud.hide_turn_transition())

func _on_minimap_pan(world_pos: Vector2) -> void:
	if _hero != null and _hero.is_moving():
		stop_active_hero()
		return
	if _hud != null and _hud.turn_transition_panel != null \
			and _hud.turn_transition_panel.mode == TurnTransitionPanel.Mode.NEW_DAY:
		_hud.hide_turn_transition()
	_following = false
	_cam.center_on(world_pos)
	_hud.refresh()

func _on_hero_entered(t: Vector2i, node: Hero) -> void:
	var prev_tile: Vector2i = _walk_prev_by_node.get(node, Vector2i(-1, -1))
	var transition := TravelRules.MOVE
	if prev_tile != Vector2i(-1, -1) and Game.state != null and _astar != null:
		transition = TravelRules.step_kind(_map, _astar, Game.state,
				node.travel_mode, prev_tile, t)

	# Same-player exchange: the mover stepped onto another friendly hero.
	# The route stops before the other hero, so this is a safety net: put the
	# mover back on the tile it came from and open the exchange there.
	var other_hero: Hero = null
	for h in _heroes:
		if h != node and is_instance_valid(h) and h.tile == t:
			other_hero = h
			break
	if other_hero != null:
		if prev_tile != Vector2i(-1, -1):
			node.tile = prev_tile
			node.position = Vector2(prev_tile.x * _map.tile_size, prev_tile.y * _map.tile_size)
		node.planned_dest = Vector2i(-1, -1)
		node._path.clear()
		node._moving = false
		node._sprite.stop()
		_walk_prev_by_node.erase(node)
		_pending_meet_friend = Vector2i(-1, -1)
		_pending_meet_stop = Vector2i(-1, -1)
		_pending_meet_mover = null
		_persist_mover(node)
		_update_ui()
		if _input != null and node == _hero:
			_input.cancel_route()
		node.emit_signal("arrived")

		_open_exchange(node, other_hero)
		return

	if prev_tile != Vector2i(-1, -1):
		if transition == TravelRules.BOARD:
			var boarded := Game.state.boat_at(t)
			if boarded != null:
				Game.state.take_boat(boarded.id)
				node.set_travel_mode(&"sea", boarded.id, boarded.direction)
				node.move_points = 0
				if _boats != null:
					_boats.refresh()
		elif transition == TravelRules.DISEMBARK:
			Game.state.place_boat(node.carried_boat_id, prev_tile,
					_side_for_hero_node(node), Hero.landing_facing(prev_tile, t))
			node.set_travel_mode(&"land")
			node.move_points = 0
			if _boats != null:
				_boats.refresh()
		else:
			var raw_cost := Hero.step_cost(prev_tile, t, _map,
					node.travel_mode == &"sea", node.hero_class)
			var straight_cost := Hero.step_cost(prev_tile,
					prev_tile + Vector2i.RIGHT, _map,
					node.travel_mode == &"sea", node.hero_class)
			var charged_cost := Pathfinder.current_day_step_cost(
					raw_cost, straight_cost, node.move_points)
			node.move_points = maxi(0, node.move_points - charged_cost)
	_walk_prev_by_node[node] = t
	if _fog != null:
		var model: HeroModel = Game.state.human().active() if Game.state != null else Game.player_hero
		_fog.reveal(t, REVEAL_RADIUS + (model.sight_bonus if model != null else 0))
	_persist_mover(node)
	_update_ui()

	if _ai != null:
		var enemy_side := _ai.side_at(t)
		if enemy_side >= 0:
			# The hero walked onto the enemy hero's tile (the stop-before rule
			# normally prevents this): hold the map for a beat as on a
			# stop-before engage, so the fight does not cut in instantly.
			if node == _hero:
				_begin_engage_hold()
			if _launch_ai_hero_battle(enemy_side, t, Hero.ENGAGE_FACE_DELAY):
				return
			if node == _hero:
				_end_engage_hold()
	var obj := _active_object_at_action(t)
	if obj is Mine and node == _hero and _astar != null \
			and _resolver.pending_resource is NeutralStack \
			and _astar.protecting_stack_at(t) == _resolver.pending_resource:
		Game.pending_followup_object_id = obj.id
		return
	if obj != null:
		_resolver.visit(obj)

## Launch the battle against the hero on `at_tile`. `delay` holds the map on
## screen for that long before the battle screen takes over, so the hero's
## turn to face its opponent is on screen (see Hero.ENGAGE_FACE_DELAY).
func _launch_ai_hero_battle(side: int = -1, at_tile: Vector2i = Vector2i(-1, -1),
		delay: float = 0.0) -> bool:
	var ai_player := Game.state.player_of(side) if side >= 0 and Game.state != null else _ai.first_ai()
	if ai_player == null or ai_player.hero_model == null:
		return false
	if _ai != null:
		_ai.persist_heroes()
	var defender := ai_player.hero_model
	var at_index := 0
	var at_model := _ai.hero_model_at(at_tile) if _ai != null else null
	var found := ai_player.heroes.find(at_model) if at_model != null else -1
	if found < 0:
		for i in ai_player.heroes.size():
			if ai_player.heroes[i].tile == at_tile:
				found = i
				break
	if found >= 0:
		defender = ai_player.heroes[found]
		at_index = found
	ai_player.active_hero = at_index
	if at_tile != Vector2i(-1, -1):
		defender.tile = at_tile
	Game.pending_ai_battle = true
	Game.pending_ai_side = ai_player.side
	if Game.mark_hero_defended_town(_map, at_tile, ai_player.side):
		Game.join_gate_garrison(defender.army)
	Game.pending_day_advance = false
	Game.battle_return = "map"
	if _audio != null:
		_audio.play_one_shot("res://assets/art/KILLFADE.wav")
	_following = false
	Game.battle_terrain = _map.terrain_at(_hero.tile) if _map != null and _hero != null else "grass"
	Game.to_battle(_current_army(), defender.army, defender, &"hero",
			not ai_player.is_ai and Game.pvp_control_allowed(), ai_player.side, delay)
	return true

func _enemy_side_at_tile(tile: Vector2i) -> int:
	if _ai != null:
		var s := _ai.side_at(tile)
		if s >= 0:
			return s
	if Game.state != null:
		var local_side := Game.state.active_player_side
		for p: PlayerState in Game.state.players:
			if p.side != local_side and p.alive:
				for h: HeroModel in p.heroes:
					if h.tile == tile:
						return p.side
	return -1

func _engage_pending_attack() -> void:
	if _pending_attack_tile == Vector2i(-1, -1):
		return
	var target := _pending_attack_tile
	var cost := _pending_attack_cost
	_pending_attack_tile = Vector2i(-1, -1)
	_pending_attack_cost = 0
	var enemy_side := _enemy_side_at_tile(target)
	if enemy_side < 0:
		return
	_hero.face_towards(target)
	_hero.move_points = maxi(0, _hero.move_points - cost)
	_persist_hero()
	# The turn to face the opponent is one frame of sprite swap, and the
	# battle screen would take over on the very next frame. Hold the map for
	# a beat so the player actually sees the hero square off with the hero it
	# engages. Input is blocked meanwhile: the engage is already decided, and
	# a click in the middle of it would move the hero out of the shot.
	_begin_engage_hold()
	if not _launch_ai_hero_battle(enemy_side, target, Hero.ENGAGE_FACE_DELAY):
		_end_engage_hold()

## Block map input for the length of the engage hold. The map is freed when
## the battle scene takes over, so the block normally lives until then.
func _begin_engage_hold() -> void:
	_engage_busy = true
	if _input != null:
		_input.cancel_route()
		_input.block_input()

func _end_engage_hold() -> void:
	_engage_busy = false
	if _input != null:
		_input.unblock_input()

func _board_pending_boat() -> void:
	var boat_tile := _pending_board_tile
	_pending_board_tile = Vector2i(-1, -1)
	if _hero != null:
		_hero.planned_dest = Vector2i(-1, -1)
		if _input != null:
			_input.cancel_route()
	var boat := Game.state.boat_at(boat_tile) if Game.state != null else null
	if _hero == null or boat == null or TravelRules.step_kind(_map, _astar,
			Game.state, _hero.travel_mode, _hero.tile, boat_tile) != TravelRules.BOARD:
		return
	Game.state.take_boat(boat.id)
	var fade := _hero.board(boat_tile, boat.id, boat.direction)
	_hero.move_points = 0
	_walk_prev_by_node[_hero] = boat_tile
	if fade != null and _boats != null:
		fade.tween_callback(_boats.refresh)
	elif _boats != null:
		_boats.refresh()
	if _fog != null:
		var model: HeroModel = Game.state.human().active()
		_fog.reveal(boat_tile, REVEAL_RADIUS + (model.sight_bonus if model != null else 0))
	_persist_mover(_hero)
	_update_ui()

func _disembark_pending_boat() -> void:
	var shore_tile := _pending_disembark_tile
	_pending_disembark_tile = Vector2i(-1, -1)
	if _hero != null:
		_hero.planned_dest = Vector2i(-1, -1)
		if _input != null:
			_input.cancel_route()
	if _hero == null or TravelRules.step_kind(_map, _astar,
			Game.state, _hero.travel_mode, _hero.tile, shore_tile) != TravelRules.DISEMBARK:
		return
	var water_tile := _hero.tile
	var boat_facing := Hero.landing_facing(water_tile, shore_tile)
	var boat_id := _hero.carried_boat_id
	Game.state.place_boat(boat_id, water_tile,
			_side_for_hero_node(_hero), boat_facing)
	if _boats != null:
		_boats.refresh()
	var fade := _hero.disembark(shore_tile)
	_hero.move_points = 0
	_walk_prev_by_node[_hero] = shore_tile
	if _fog != null:
		var model: HeroModel = Game.state.human().active() if (Game.state != null and not Game.state.players.is_empty()) else Game.player_hero
		_fog.reveal(shore_tile, REVEAL_RADIUS + (model.sight_bonus if model != null else 0))
	_persist_mover(_hero)
	_update_ui()
	var obj := _active_object_at_action(shore_tile)
	if obj != null:
		_resolver.visit(obj)

func _on_hero_arrived() -> void:
	if _pending_board_tile != Vector2i(-1, -1):
		_board_pending_boat()
		return
	if _pending_disembark_tile != Vector2i(-1, -1):
		_disembark_pending_boat()
		return
	if _meet_reached():
		return
	if _resolver.pending_resource != null:
		_resolver.collect_pending()
		if _hero != null:
			_hero.planned_dest = Vector2i(-1, -1)
			if _input != null:
				_input.cancel_route()
		return
	if _pending_attack_tile != Vector2i(-1, -1):
		_engage_pending_attack()
		if _hero != null:
			_hero.planned_dest = Vector2i(-1, -1)
			if _input != null:
				_input.cancel_route()
		return
	if _hero != null:
		if _hero.planned_dest == _hero.tile:
			_hero.planned_dest = Vector2i(-1, -1)
			if _input != null:
				_input.cancel_route()
		elif _hero.planned_dest != Vector2i(-1, -1):
			if _input != null:
				_input.refresh_path()

## The mover reached the tile next to the hero he was walking up to: the
## exchange opens there. True when the meeting was resolved.
func _meet_reached() -> bool:
	if _pending_meet_stop == Vector2i(-1, -1) or _hero == null:
		return false
	if _hero != _pending_meet_mover:
		return false   # another hero is active now
	if _hero.tile != _pending_meet_stop:
		return false
	if _hero.planned_dest != _pending_meet_friend:
		return false   # the meet route was cancelled or re-planned
	var friend := _friendly_hero_at(_pending_meet_friend)
	_pending_meet_friend = Vector2i(-1, -1)
	_pending_meet_stop = Vector2i(-1, -1)
	_pending_meet_mover = null
	if friend == null:
		return false
	if _hero.planned_dest != Vector2i(-1, -1):
		_hero.planned_dest = Vector2i(-1, -1)
	if _input != null:
		_input.cancel_route()
	_persist_hero()
	_update_ui()
	_open_exchange(_hero, friend)
	return true

## The player's own hero standing on `tile`, if any. Only a friendly hero can
## be met; an enemy hero on that tile is an attack.
func _friendly_hero_at(tile: Vector2i) -> Hero:
	for h in _heroes:
		if h == null or not is_instance_valid(h) or h == _hero:
			continue
		if h.tile == tile:
			return h
	return null

## Open the hero exchange screen (heroes.exe, swapwin.bin). `mover` is the
## hero who walked up to `other`; it is the left half of the window.
func _open_exchange(mover: Hero, other: Hero) -> void:
	if mover == null or other == null:
		return
	var ep_class = load("res://src/adventure/ui/exchange_panel.gd")
	if ep_class == null:
		return
	var human := Game.state.human() if Game.state != null else null
	if human == null:
		return
	var mover_idx := _heroes.find(mover)
	var other_idx := _heroes.find(other)
	if mover_idx < 0 or other_idx < 0:
		return
	var ep = ep_class.new()
	add_child(ep)
	ep.tree_exited.connect(_update_ui)
	ep.tree_exited.connect(_on_exchange_closed)
	ep.open(human.heroes[mover_idx], human.heroes[other_idx])

## The exchange window shows the plain HOMM1 pointer; once it closes the
## map's own hover cursors (horse, sword, the two arrows of a friendly hero)
## take over again.
func _on_exchange_closed() -> void:
	if _input != null:
		_input.refresh_cursor()

func _fallback_army() -> ArmyData:
	var a := ArmyData.new()
	a.add("swordsman", 20)
	a.add("archer", 10)
	a.add("pikeman", 15)
	return a


func _wire_resolver() -> void:
	if not _resolver.interaction_resolved.is_connected(_on_interaction_resolved):
		_resolver.interaction_resolved.connect(_on_interaction_resolved)
	_resolver.setup(self, _map,
		func() -> PassabilityGrid: return _astar,
		_world,
		func() -> Hero: return _hero,
		_current_army,
		_fallback_army,
		_persist_hero,
		func() -> void:
			_persist_hero()
			if _ai != null:
				_ai.persist_heroes()
			_following = false
			_input.clear_path(),
		func() -> void:
			_following = false
			_input.clear_path(),
		func() -> AdventureHud: return _hud,
		_update_ui,
		func() -> void:
			if _turns != null:
				_turns.check_game_over(),
		_handle_player_hero_death,
		func() -> PlayerState:
			if Game.state == null:
				return null
			if Game.pending_ai_side >= 0:
				return Game.state.player_of(Game.pending_ai_side)
			if Game.pending_town_battle_side > 0:
				return Game.state.player_of(Game.pending_town_battle_side)
			for p: PlayerState in Game.state.players:
				if p.is_ai and p.alive:
					return p
			return null,
		func(p: PlayerState) -> void:
			if _ai != null:
				_ai.handle_ai_hero_death(p)
			else:
				var deferred_effect_queued := _queue_defeat_visual(p.active(), p.side)
				if not deferred_effect_queued and _audio != null:
					_audio.play_one_shot("res://assets/art/KILLFADE.wav")
				if p.active() != null:
					p.defeat_hero(p.active(), Game.rng, Game.state.hero_pool if Game.state != null else null),
		teleport_hero,
		occupied_hero_tiles,
		func() -> void: pass,
		func() -> void:
			if Game.state == null:
				return
			var human := Game.state.human()
			var human_side := human.side if human != null else 0
			var oracle := OracleScreen.new()
			add_child(oracle)
			oracle.open(Game.state.players, human_side),
		func() -> void:
			_open_puzzle_map(true))

func _on_interaction_resolved(obj: MapObject, result: VisitResult) -> void:
	if _audio != null:
		_audio.play_visit(obj, result)
	if _resolver != null and _resolver.should_dissolve_pickup(obj, result):
		_start_pickup_sequence()

func _active_object_at_action(t: Vector2i) -> MapObject:
	return _map.active_object_at_action(t)

func _crest_of(side: int) -> int:
	var player: PlayerState = Game.state.player_of(side) if Game.state != null else null
	return clampi(player.crest_idx / 4, 0, 3) if player != null else 0

func _on_player_eliminated(side: int) -> void:
	if _map != null and _objects != null:
		for obj: MapObject in _map.objects:
			if (obj is Mine or obj is DragonCity or obj is Lighthouse or obj is TownObject) and obj.owner == -1:
				_objects.refresh_object(obj.id)
	if _boats != null:
		_boats.refresh()
	if _ai != null:
		_ai.remove_all_heroes_for_side(side)
	if Game.state != null and side == Game.state.active_player_side:
		_spawn_player_heroes()

# -----------------------------------------------------------------------------
# Delegation Facades: HeroSelection
# -----------------------------------------------------------------------------

func _spawn_player_heroes() -> void:
	_hero = _hero_selection.spawn_player_heroes(_map, _world, _fog, _current_army,
			_on_hero_entered, _on_hero_arrived, self)

func _set_active_hero(idx: int) -> void:
	if _engage_busy:
		return   # the engage is decided; a new active hero would change the army
	if _hero != null and _hero.is_moving():
		stop_active_hero()
		return
	_hero = _hero_selection.set_active_hero(idx, _hud, _input, _cam, _persist_hero, _update_ui)

func _on_next_hero() -> void:
	if _hud != null and _hud.turn_transition_panel != null \
			and _hud.turn_transition_panel.mode == TurnTransitionPanel.Mode.NEW_DAY:
		_hud.hide_turn_transition()
	if _hero != null and _hero.is_moving():
		stop_active_hero()
		return
	if not heroes_may_still_move():
		return
	_cycle_next_hero()

func _cycle_next_hero() -> void:
	if _hero_selection.cycle_next_hero(_cam, _hud, _input, _persist_hero, _update_ui):
		_following = true

func _on_next_town() -> void:
	_cycle_next_town()

func _cycle_next_town() -> void:
	if _hero_selection.cycle_next_town(_map, _hud, _cam):
		_following = false

func _on_town_selected(town: TownObject) -> void:
	_hero_selection.on_town_selected(town, _hud, _on_town_double_clicked)

func _on_town_double_clicked(town: TownObject) -> void:
	_following = false
	_hero_selection.on_town_double_clicked(town, _hud, _input, _get_hero_at, _current_army, _persist_hero)

func _on_hero_double_clicked() -> void:
	_hero_selection.on_hero_double_clicked(_current_army)

func _on_hero_selected() -> void:
	_hero_selection.on_hero_selected(_hud)

func _on_roster_town_selected() -> void:
	if _engage_busy:
		return
	if _hero != null and _hero.is_moving():
		stop_active_hero()
		return
	if _hero_selection.on_roster_town_selected(_map, _hud, _cam):
		_following = false

func _on_open_selected() -> void:
	_hero_selection.on_open_selected(_hud, _current_army)

func _persist_hero() -> void:
	_hero_selection.persist_hero(_hero)

func _persist_mover(node: Hero) -> void:
	_hero_selection.persist_mover(node, _hero)

func _get_hero_at(tile: Vector2i) -> Dictionary:
	return _hero_selection.get_hero_at(tile, _fog, _ai)

func _get_town_at(tile: Vector2i) -> TownObject:
	return _hero_selection.get_town_at(tile, _map, _fog)

func occupied_hero_tiles() -> Array:
	return _hero_selection.occupied_hero_tiles(_ai)

func _side_for_hero_node(node: Hero) -> int:
	return _hero_selection.side_for_hero_node(node, _ai)

func teleport_hero(tile: Vector2i) -> void:
	_hero_selection.teleport_hero(tile, _map, _fog, _cam, _input, _walk_prev_by_node, _update_ui)
	if _world != null:
		_world._update_actor_depths()   # a teleport is not a walk, so _process skips it
	_following = true
	if Game.campaign_objective_complete(_map):
		_turns.check_game_over()

func heroes_may_still_move() -> bool:
	return _hero_selection.heroes_may_still_move()

# -----------------------------------------------------------------------------
# Delegation Facades: DefeatPresenter
# -----------------------------------------------------------------------------

func _handle_player_hero_death() -> void:
	_defeat_presenter.handle_player_hero_death(_hero_selection, _hud, _audio, self, _set_active_hero)
	_hero = _hero_selection.hero

func _queue_defeat_visual(model: HeroModel, side: int) -> bool:
	return _defeat_presenter.queue_defeat_visual(model, side)

func _hold_pending_defeat_roster() -> void:
	_defeat_presenter.hold_pending_defeat_roster(_hud)


func _play_pending_defeat_visuals() -> void:
	_defeat_presenter.play_pending_defeat_visuals(_map, _world, _fog, _audio, _hud, self)


func _on_ai_hero_defeated(hero_node: Hero) -> void:
	_defeat_presenter.on_ai_hero_defeated(hero_node, _audio, self)

# -----------------------------------------------------------------------------
# Delegation Facades: SeatHandoff
# -----------------------------------------------------------------------------

func _show_hotseat_handoff(side: int, new_day: bool, reload_on_confirm: bool) -> void:
	_seat_handoff.show_hotseat_handoff(self, _hud, side, new_day, reload_on_confirm,
			func(): _ai_running = true,
			func(): _ai_running = false)

func _on_human_handoff_requested(side: int, _color_index: int, new_day: bool) -> void:
	if _hud != null:
		_hud.dismiss_resource_popup()
	_show_hotseat_handoff(side, new_day, true)

func _attach_network_session() -> void:
	_seat_handoff.attach_network_session(self, _show_game_over,
			func(): _ai_running = true,
			_update_ui,
			func(): _ai_running = false)

func _on_remote_handoff_requested(side: int, new_day: bool) -> void:
	_seat_handoff.on_remote_handoff_requested(self, side, new_day,
			func(): _ai_running = true,
			func(): _ai_running = false)


func _hide_network_wait() -> void:
	_seat_handoff.hide_network_wait()


# -----------------------------------------------------------------------------
# Delegation Facades: MapMenus
# -----------------------------------------------------------------------------

func _open_puzzle_map(animate_latest_visit: bool = false) -> void:
	if _audio != null:
		_audio.play_sting(MusicPlayer.PUZZLE)
	_menus.open_puzzle_map(self, _map, animate_latest_visit)

func _count_obelisks() -> int:
	return _menus.count_obelisks(_map)

func _on_dig() -> void:
	_menus.on_dig(self, _map, _hero, _audio, _turns, _persist_hero, _update_ui)

func _open_adventure_options() -> void:
	if _is_modal_active():
		return
	_menus.open_adventure_options(self,
		func(): _open_puzzle_map(),
		func(): _open_view_world(),
		func(): if _spells != null: _spells.open_spellbook(),
		func(): _on_dig())

func _open_view_world() -> void:
	if _is_modal_active():
		return
	_menus.open_view_world(self, _map, _fog, _hero)

func open_view_world_for_bench() -> CanvasLayer:
	return _menus.open_view_world_for_bench(self, _map, _fog, _hero)

func _open_kingdom_overview() -> void:
	if _is_modal_active():
		return
	_menus.open_kingdom_overview(self, _map)

func _open_system_menu() -> void:
	_menus.open_system_menu(self, func(): _open_campaign_info(true), _persist_all_heroes)

func _open_save_dialog() -> void:
	if _is_modal_active():
		return
	_menus.open_save_dialog(self, _persist_all_heroes)

func _persist_all_heroes() -> void:
	_persist_hero()
	if _ai != null:
		_ai.persist_heroes()

func _open_load_dialog() -> void:
	if _is_modal_active():
		return
	load("res://src/ui/system_menu.gd").confirm_leave(self, "load_game")

func _open_campaign_info(allow_restart: bool) -> void:
	_menus.open_campaign_info(self, _map, allow_restart)

func _open_scenario_info() -> void:
	if _is_modal_active():
		return
	_menus.open_scenario_info(self, _map)

func _show_game_over(message: String) -> void:
	_menus.show_game_over(self, _map, message, _is_modal_active,
			func(): _ai_running = true,
			_hide_network_wait)
	# A deferred game over waits for the open dialog to close; a dialog opened
	# outside the queue (the dig result) has no dismiss hook until the pump adds one.
	call_deferred("_pump_dialog_queue")

func _show_game_over_immediate(message: String) -> void:
	_menus.show_game_over_immediate(self, _map, message)
