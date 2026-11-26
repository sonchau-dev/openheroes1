class_name SaveGlue
extends RefCounted

## Save, load, autosave, envelope creation, and save-version migration glue.

var _game: Node = null

func _init(game_node: Node = null) -> void:
	_game = game_node

var game: Node:
	get:
		return _game if _game != null else Engine.get_main_loop().root.get_node_or_null("Game")

## The run as a save envelope.
func build_envelope(save_name: String) -> Dictionary:
	var g := game
	if g == null or g.state == null:
		return {}
	return SaveGame.build_envelope(g.state, g.map_object_state, g.selected_map_path,
			g.town_tile, save_name, g.setup, g.game_mode, g.campaign)

## Serialize the current run into slot `save_name`. Returns "" or an error message.
func save_game(save_name: String, dir: String = SaveGame.SAVE_DIR) -> String:
	var g := game
	if g == null or g.state == null:
		return "No game in progress"
	var err := SaveGame.write_slot(save_name, build_envelope(save_name), dir)
	# The original renames the run to each save but AUTOSAVE and PLYREXIT (0x77836).
	if err == "" and not save_name.to_upper() in [SaveGame.AUTOSAVE_SLOT, SaveGame.CAMPAIGN_AUTOSAVE_SLOT,
			SaveGame.HOTSEAT_AUTOSAVE_SLOT, SaveGame.NETWORK_AUTOSAVE_SLOT, SaveGame.PLYREXIT_SLOT]:
		g.game_name = save_name
	return err

## Silent daily autosave (written at each day rollover from the map).
func autosave() -> void:
	var g := game
	if g == null or g.state == null or not g.autosave_enabled:
		return
	var slot := SaveGame.AUTOSAVE_SLOT
	match g.game_mode:
		&"campaign": slot = SaveGame.CAMPAIGN_AUTOSAVE_SLOT
		&"hotseat": slot = SaveGame.HOTSEAT_AUTOSAVE_SLOT
		&"network": slot = SaveGame.NETWORK_AUTOSAVE_SLOT
	var err := SaveGame.write_slot(slot, build_envelope(SaveGame.AUTOSAVE_SLOT), g.autosave_dir)
	if err != "":
		push_warning("Autosave failed: %s" % err)

## Rebuild the whole run from a validated envelope.
func load_from_envelope(env: Dictionary) -> void:
	var g := game
	if g == null:
		return
	g.reset()
	g.game_mode = StringName(String(env.get("game_mode", "standard")))
	var campaign_data: Variant = env.get("campaign", null)
	g.campaign = CampaignState.from_dict(campaign_data) if g.game_mode == &"campaign" and campaign_data is Dictionary else null
	var setup_data: Variant = env.get("setup", null)
	if setup_data is Dictionary:
		g.setup = NewGameSettings.from_dict(setup_data)
	else:
		# v1: reconstruct the settings that existed before setup persistence.
		g.setup = NewGameSettings.new()
		g.setup.map_path = String(env.get("map_path", g.setup.map_path))
	var state_dict := {
		"day": env.get("day", 1),
		"players": env.get("players", []),
		"active_player_side": env.get("active_player_side", 0),
		"boats": env.get("boats", []),
		"next_boat_id": env.get("next_boat_id", 1),
	}
	for key: String in SaveGame.OPTIONAL_STATE_KEYS:
		if env.has(key):
			state_dict[key] = env[key]
	g.state = GameState.from_dict(state_dict)
	g.selected_map_path = String(env.get("map_path", g.setup.map_path))
	g.setup.map_path = g.selected_map_path
	g.map_object_state = {}
	var objs: Dictionary = env.get("map_object_state", {})
	for k in objs:
		g.map_object_state[int(k)] = objs[k]
	if int(env.get("version", 1)) < 4:
		_migrate_artifacts_v4(env)
	if int(env.get("version", 1)) < 7:
		_migrate_visit_ids_v7()
	var g_dict: Dictionary = env.get("game", {})
	g.town_tile = _dict_v2i(g_dict, "town_tile")
	# v1 kept the first AI position outside its hero model. Migrate it once;
	# v2 positions already live in every serialized HeroModel.
	if int(env.get("version", 1)) == 1:
		var v1_ai_tile := _dict_v2i(g_dict, "ai_hero_tile")
		var v1_ai_mp := int(g_dict.get("ai_hero_move_points", -1))
		if v1_ai_tile != Vector2i(-1, -1):
			for p: PlayerState in g.state.players:
				if p.is_ai and p.hero_model != null:
					p.hero_model.tile = v1_ai_tile
					p.hero_model.move_points = v1_ai_mp
					break
	var human: PlayerState = g.state.human()
	g.player_hero = human.active()
	g.player_army = g.player_hero.army if g.player_hero != null else ArmyData.new()
	if human.heroes.is_empty():
		g.hero_tile = g.town_tile
	g.hotseat_handoff_pending = g.game_mode == &"hotseat"

## Versions 1-3 had generic artifact objects with no resolved identity/mode.
func _migrate_artifacts_v4(_env: Dictionary) -> void:
	var g := game
	if g == null:
		return
	var map := MapLoaderJson.load_map(g.selected_map_path)
	if map == null:
		return
	g.configure_map_for_run(map)
	g.apply_object_states(map.objects)
	g.apply_run_state(map)
	var owned: Array = []
	if g.state != null:
		for player: PlayerState in g.state.players:
			for hero: HeroModel in player.heroes:
				owned.append_array(hero.artifacts)
	var migration_rng := RandomNumberGenerator.new()
	migration_rng.seed = map.seed
	for object: MapObject in ArtifactAllocator.resolve(map, migration_rng, owned):
		var generated := object.save_state()
		var existing: Dictionary = g.map_object_state.get(object.id, {}).duplicate(true)
		for key: Variant in generated:
			if not existing.has(key):
				existing[key] = generated[key]
		g.map_object_state[object.id] = existing

## Versions 1-6 keyed per-hero object visits by roster slot (side * 100 + slot).
func _migrate_visit_ids_v7() -> void:
	var g := game
	if g == null or g.state == null:
		return
	var by_slot: Dictionary = {}
	for player: PlayerState in g.state.players:
		for idx in player.heroes.size():
			by_slot[VisitContext.legacy_hero_id(player.side, idx)] = player.heroes[idx].visit_id()
	for object_id: int in g.map_object_state:
		var saved: Dictionary = g.map_object_state[object_id]
		var raw: Variant = saved.get("visited_by", null)
		if not raw is Array:
			continue
		var visits: Array = []
		for old: Variant in raw:
			var key := int(old)
			if key < HeroModel.VISIT_ID_BASE:
				if not by_slot.has(key):
					continue
				key = int(by_slot[key])
			if not visits.has(key):
				visits.append(key)
		if visits.is_empty():
			saved.erase("visited_by")
		else:
			saved["visited_by"] = visits
	for player: PlayerState in g.state.players:
		for hero: HeroModel in player.heroes:
			for visit: Dictionary in hero.battle_booster_visits:
				var key := int(visit.get("hero_id", -1))
				if by_slot.has(key):
					visit["hero_id"] = int(by_slot[key])

## Read + validate slot, rebuild state, enter the adventure map.
func load_game(slot: String, dir: String = SaveGame.SAVE_DIR) -> String:
	var g := game
	if g == null:
		return "Game instance unavailable"
	var env := SaveGame.read_slot(slot, dir)
	if env.has("error"):
		return String(env["error"])
	load_from_envelope(env)
	g.game_name = String(env.get("save_name", slot))
	if g.game_mode == &"campaign" and _campaign_mission_needs_start(g.campaign, g.selected_map_path):
		# A won mission advances the campaign and writes SCENWNnn before the next
		# map has been generated, so the save still names the map just won. Start
		# the mission the campaign now points at; playing the stale map with the
		# next mission's objective would make the campaign unwinnable.
		var restart_err: String = g.restart_campaign_mission()
		if restart_err != "":
			return restart_err
	if g.game_mode == &"network" and not _is_net_active():
		fill_absent_humans_with_ai()
	g.fade_in_pending = true
	g.to_map()
	return ""

static func _campaign_mission_needs_start(campaign: CampaignState, map_path: String) -> bool:
	if campaign == null or campaign.completed:
		return false
	var mission: CampaignMission = campaign.mission()
	return mission != null and map_path != mission.map_path

func _is_net_active() -> bool:
	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree:
		var net_node: Node = (main_loop as SceneTree).root.get_node_or_null("Net")
		if net_node != null and net_node.has_method("is_active"):
			return bool(net_node.call("is_active"))
	return false

## A network save opened without a live link hands other humans to AI.
func fill_absent_humans_with_ai() -> int:
	var g := game
	if g == null or g.state == null:
		return 0
	var local: PlayerState = g.state.player_of(g.state.active_player_side)
	if local == null or local.is_ai:
		local = g.state.first_human()
	if local == null:
		return 0
	var filled := 0
	for player: PlayerState in g.state.players:
		if player.is_ai or player.side == local.side:
			continue
		player.is_ai = true
		if player.ai_level <= 0:
			player.ai_level = 2
		filled += 1
	g.state.active_player_side = local.side
	return filled

static func _dict_v2i(d: Dictionary, key: String) -> Vector2i:
	var v: Variant = d.get(key, null)
	if v is Array and (v as Array).size() == 2:
		return Vector2i(int(v[0]), int(v[1]))
	return Vector2i(-1, -1)
