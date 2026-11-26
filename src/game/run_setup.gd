class_name RunSetup
extends RefCounted

## Manages game and scenario run configuration, map setup, and player/hero spawning.

var _game: Node = null

func _init(game_node: Node = null) -> void:
	_game = game_node

var game: Node:
	get:
		return _game if _game != null else Engine.get_main_loop().root.get_node_or_null("Game")

## The player's hero, created once and kept in sync with the live army.
func ensure_player_hero(army: ArmyData) -> HeroModel:
	var g := game
	if g == null:
		return null
	if g.state != null and not g.state.players.is_empty():
		var human: PlayerState = g.state.human()
		if human.heroes.is_empty():
			var h := HeroModel.sample()
			h.army = army
			h.crest_idx = human.crest_idx
			human.add_hero(h)
		else:
			human.active().army = army
		g.player_hero = human.active()
		return g.player_hero
	else:
		if g.player_hero == null:
			g.player_hero = HeroModel.sample()
		g.player_hero.army = army
		return g.player_hero

## Create one PlayerState + hero per configured map seat not built by
## _begin_new_game(). This includes additional local humans as well as AI.
## Idempotent — scene reloads (town/battle round-trips) call this every boot.
func ensure_ai_players(map: MapData) -> void:
	var g := game
	if g == null or g.state == null:
		return
	if map != null:
		apply_object_states(map.objects)
	for pspec: Dictionary in map.players:
		var side := int(pspec.get("side", g.state.players.size()))
		if g.state.player_of(side) != null:
			continue   # already created
		var color := int(pspec.get("color", 1))
		var is_ai := not bool(pspec.get("human", false))
		var starting: Dictionary = AIController.starting_resources() if is_ai else g.setup.starting_resources(side)
		var player: PlayerState = g.state.add_player(is_ai, color * 4,
				int(starting.get("gold", Game.START_GOLD)), {})
		player.side = side
		var default_team := (1 if (g.setup.king_of_the_hill and is_ai) else side)
		player.team = int(pspec.get("team", default_team))
		player.ai_level = int(pspec.get("ai_level", 2 if is_ai else 0))
		starting.erase("gold")
		player.resources = starting
		_initialize_owned_towns(player, map, is_ai)
		var owned_town := map.town_of_side(side)
		if owned_town != null:
			player.crest_idx = color * 4 + owned_town.town_type
		var starts: Array = pspec.get("heroes", [pspec.get("hero_start", Vector2i.ZERO)])
		var presets: Array = pspec.get("hero_presets", [])
		for i in starts.size():
			var start = starts[i]
			var hero_faction: int = owned_town.town_type if owned_town != null else g.campaign.ruler if g.campaign != null else 0
			var h: HeroModel = g.state.hero_pool.take_hero_for_faction(hero_faction, g.rng) if g.state.hero_pool != null else HeroFactory.create_for_faction(hero_faction, g.rng, player.heroes)
			if i < presets.size():
				h = apply_hero_preset(h, presets[i])
			h.crest_idx = player.crest_idx
			h.tile = Vector2i(start)
			player.add_hero(h)
		# KB ai.md §24.3: the AI always builds Mage Guild 1 in week one —
		# model that as built-from-start so its hero can cast in battle.
		if is_ai and player.town != null and player.town.mage_guild_level < 1:
			player.town.mage_guild_level = 1
	_roll_guilds()
	if g.state.hero_pool != null:
		var sides: Array = []
		for p: PlayerState in g.state.players:
			if p.alive:
				sides.append(p.side)
		g.state.hero_pool.fill_taverns(sides, g.rng)
	# Re-teaching on every map load refreshes AI charges
	for p: PlayerState in g.state.players:
		if p.is_ai and p.hero_model != null and p.town != null:
			p.town.teach_visiting_hero(p.hero_model)

## Roll every not-yet-rolled town's mage guild spell pool.
func _roll_guilds() -> void:
	var g := game
	if g == null or g.state == null:
		return
	if g.game_mode != &"campaign" and (g.setup == null or g.setup.fixed_seed == 0):
		g.rng.randomize()
	for p: PlayerState in g.state.players:
		for t: TownModel in p.towns:
			if t.guild_spells.is_empty():
				t.roll_guild(g.rng)

func new_game(settings: NewGameSettings = null) -> String:
	var g := game
	var requested: NewGameSettings = settings if settings != null else g.setup
	if requested.network:
		g.game_mode = &"network"
	else:
		g.game_mode = &"hotseat" if requested.human_player_count > 1 else &"standard"
	g.campaign = null
	return _begin_new_game(settings, false)

func new_campaign(ruler: int) -> String:
	var g := game
	g.game_mode = &"campaign"
	g.campaign = CampaignState.create(ruler)
	g.campaign_objective_event = &""
	return _begin_campaign_mission()

func restart_campaign_mission() -> String:
	var g := game
	if g.campaign == null or g.campaign.completed:
		return "No campaign mission is active"
	return _begin_campaign_mission()

func _begin_campaign_mission() -> String:
	var g := game
	var requested := NewGameSettings.new()
	requested.map_path = g.campaign.mission().map_path
	requested.player_color = CampaignCatalog.color_for(g.campaign.ruler)
	requested.opponent_levels = [3, 3, 3]
	var err := _begin_new_game(requested, true)
	g.campaign_show_intro = err == ""
	return err

func _begin_new_game(settings: NewGameSettings = null, campaign_run: bool = false) -> String:
	var g := game
	var requested: NewGameSettings = settings.duplicate_settings() if settings != null else g.setup.duplicate_settings()
	g.game_name = SaveGame.NEW_GAME_NAME
	var info := ScenarioCatalog.find_by_path(requested.map_path)
	if info == null and not campaign_run:
		return "Map file missing or invalid: %s" % requested.map_path
	requested.normalize(info)
	var map := MapLoaderJson.load_map(requested.map_path)
	if map == null:
		return "Unable to load scenario: %s" % requested.map_path
	g.setup = requested
	g.selected_map_path = g.setup.map_path
	var configure_error := configure_map_for_run(map)
	if configure_error != "":
		return configure_error
	if campaign_run:
		g.rng.seed = g.campaign.mission_seed
	elif requested.fixed_seed != 0:
		g.rng.seed = requested.fixed_seed
	else:
		g.rng.randomize()
	g.map_object_state = {}
	_resolve_random_objects(map)
	g.state = GameState.new()
	g.state.king_of_the_hill = g.setup.king_of_the_hill
	var starting: Dictionary = g.setup.starting_resources()
	g.state.setup(int(starting.gold), {}, -1, g.rng)
	if campaign_run:
		g.state.day = g.campaign.mission_start_day
	for boat: Dictionary in map.starting_boats:
		g.state.create_boat(
				Vector2i(boat.get("tile", Vector2i(-1, -1))),
				int(boat.get("owner", -1)),
				int(boat.get("direction", Direction.E)))
	starting.erase("gold")
	g.state.human().resources = starting
	var human_spec: Dictionary = map.players[0]
	var human_color := int(human_spec.get("color", g.setup.player_color))
	var human_town := map.town_of_side(0)
	var faction := human_town.town_type if human_town != null else 0
	g.state.human().crest_idx = human_color * 4 + faction
	g.state.human().town.town_type = faction
	g.state.human().team = 0
	_initialize_owned_towns(g.state.human(), map, false)
	var starting_hero: HeroModel = g.state.hero_pool.take_hero_for_faction(faction, g.rng) if g.state != null and g.state.hero_pool != null else HeroFactory.create_for_faction(faction, g.rng)
	var human_presets: Array = human_spec.get("hero_presets", [])
	if not human_presets.is_empty():
		starting_hero = apply_hero_preset(starting_hero, human_presets[0])
	starting_hero.crest_idx = g.state.human().crest_idx
	starting_hero.tile = map.hero_start
	g.state.human().add_hero(starting_hero)
	_bury_ultimate(map)
	g.player_army = starting_hero.army
	g.enemy_army = null
	g.enemy_hero = null
	if g.battle != null:
		g.battle.reset()
	g.player_hero = starting_hero
	g.visiting_hero = null
	g.hero_tile = Vector2i(-1, -1)
	g.hero_move_points = -1
	g.town_tile = Vector2i(-1, -1)
	g.town_gate_ids.clear()
	g.hotseat_handoff_pending = g.game_mode == &"hotseat"
	_roll_guilds()
	return ""

## Overlay a map-authored hero preset (keys of HeroModel.to_dict) on a newly
## rolled hero. An empty preset returns the hero unchanged.
static func apply_hero_preset(hero: HeroModel, preset: Dictionary) -> HeroModel:
	if preset.is_empty():
		return hero
	var d := hero.to_dict()
	d.merge(preset, true)
	return HeroModel.from_dict(d)

func _initialize_owned_towns(player: PlayerState, map: MapData, is_ai: bool) -> void:
	var g := game
	if player == null or g == null:
		return
	var owned: Array[TownObject] = []
	for object: MapObject in map.objects:
		if object is TownObject and object.owner == player.side:
			owned.append(object as TownObject)
	player.towns.clear()
	for town_object: TownObject in owned:
		var model := TownModel.new()
		model.object_id = town_object.id
		model.town_name = String(town_object.params.get("name", ""))
		model.setup(0, {}, ArmyData.new(), town_object.town_type)
		model.init_start_buildings(g.rng, is_ai)
		if not bool(town_object.params.get("has_castle", true)):
			model.has_castle = false
		model.ship_launch_tile = town_object.action_tile + Vector2i(-1, 1)
		model.sea_access = map.is_water(model.ship_launch_tile) if map != null else false
		player.add_town(model)
	player.active_town = 0
	player.owns_town = not player.towns.is_empty()

## The scenario's own Ultimate Artifact, or one buried by the original's rule
## (UltimatePlacement) when it names none; kept in the game state.
func _bury_ultimate(map: MapData) -> void:
	var g := game
	if g == null or g.state == null:
		return
	if not map.ultimate_artifact.has("tile"):
		var start := map.hero_start
		g.state.ultimate_artifact = UltimatePlacement.roll(map, g.rng, start, g.setup.human_player_count == 1)
		# Campaign 3 names its buried artifact (the Eye of Goros) but not where it lies.
		if map.ultimate_artifact.has("artifact") and not g.state.ultimate_artifact.is_empty():
			g.state.ultimate_artifact["artifact"] = map.ultimate_artifact["artifact"]
	else:
		g.state.ultimate_artifact = map.ultimate_artifact.duplicate(true)
	g.state.ultimate_set = true
	apply_run_state(map)

## What the game state holds about the map itself: the buried Ultimate
## Artifact. Called after every map load, beside apply_object_states().
func apply_run_state(map: MapData) -> void:
	var g := game
	if g != null and g.state != null and g.state.ultimate_set and map != null:
		map.ultimate_artifact = g.state.ultimate_artifact.duplicate(true)

func _resolve_random_objects(map: MapData) -> void:
	var g := game
	if g == null:
		return
	for artifact_object: MapObject in ArtifactAllocator.resolve(map, g.rng):
		record_object_state(artifact_object)
	_resolve_random_towns(map)
	_roll_neutral_garrisons(map)
	for obj: MapObject in map.objects:
		if obj is NeutralStack:
			var stack := obj as NeutralStack
			stack.resolve_random(g.rng)
			if stack.is_armed():
				record_object_state(stack)
		elif obj is ResourcePile:
			# Pin the loader's roll so a later loader change cannot alter it.
			record_object_state(obj)

## Neutral towns and castles defend themselves with 4 stacks of level 1-4
## creatures of their own faction (KB calendar-economy.md §6.1, the exe
## routine at 0x7968c). The roll happens when the map starts, because a
## "random" town only learns its faction then — rolling earlier garrisoned
## it with the wrong faction's creatures.
func _roll_neutral_garrisons(map: MapData) -> void:
	var g := game
	if g == null or map == null:
		return
	for object: MapObject in map.objects:
		if object is TownObject:
			var town := object as TownObject
			if town.owner >= 0:
				continue
			if town.town_type < 0 or town.town_type > 3:
				continue
			if town.neutral_built.is_empty():
				town.neutral_built = TownModel.start_dwellings(
						BuildingCatalog.faction_for_type(town.town_type), g.rng, true)
			if town.garrison == null or town.garrison.is_empty():
				town.garrison = TownObject.roll_initial_neutral_garrison(town.town_type, g.rng)
				town.params["army"] = town.garrison
			record_object_state(town)

func _resolve_random_towns(map: MapData) -> void:
	var g := game
	if map == null or g == null:
		return
	var player_towns_by_owner: Dictionary = {}
	var neutral_random_towns: Array[TownObject] = []
	# Start castles whose seat is not in play this run.
	var unseated_random_castles: Array[TownObject] = []

	for obj: MapObject in map.objects:
		if obj is TownObject:
			var town := obj as TownObject
			if town.owner >= 0:
				if not player_towns_by_owner.has(town.owner):
					player_towns_by_owner[town.owner] = []
				player_towns_by_owner[town.owner].append(town)
			elif town.town_type == 4 and town.authored_owner >= 0:
				unseated_random_castles.append(town)
			elif town.town_type == 4:
				neutral_random_towns.append(town)

	var owners_needing_faction: Array[int] = []

	var owners: Array = player_towns_by_owner.keys()
	owners.sort()

	for owner: int in owners:
		var towns: Array = player_towns_by_owner[owner]
		var fixed_faction: int = -1
		for town: TownObject in towns:
			if town.town_type >= 0 and town.town_type < 4:
				fixed_faction = town.town_type
				break
		if fixed_faction >= 0:
			for town: TownObject in towns:
				if town.town_type == 4:
					town.town_type = fixed_faction
					record_object_state(town)
		else:
			owners_needing_faction.append(owner)

	# Random start castles never share a class with each other, though they
	# may match a fixed castle: heroes.exe 0x82520 rerolls rand(0,3) until no
	# other random start castle holds the class (0x826b2, KB towns.md).
	var taken: Array[int] = []
	for owner: int in owners_needing_faction:
		var chosen_faction := _roll_untaken_faction(taken)
		for town: TownObject in player_towns_by_owner[owner]:
			if town.town_type == 4:
				town.town_type = chosen_faction
				record_object_state(town)
	for town: TownObject in unseated_random_castles:
		town.town_type = _roll_untaken_faction(taken)
		record_object_state(town)

	for town: TownObject in neutral_random_towns:
		town.town_type = g.rng.randi_range(0, 3)
		record_object_state(town)
	TownNames.assign(map.objects, g.rng)
	for o: MapObject in map.objects:
		if o is TownObject:
			record_object_state(o)

## rand(0,3), rerolled while `taken` holds it, then marked taken. The original
## keeps four slots, so a fifth random castle takes a plain roll.
func _roll_untaken_faction(taken: Array[int]) -> int:
	var g := game
	var faction: int = g.rng.randi_range(0, 3)
	while taken.has(faction) and taken.size() < 4:
		faction = g.rng.randi_range(0, 3)
	taken.append(faction)
	return faction

## Select the authored color seat as the first local player, append the other
## requested hot-seat humans, then enabled computers.
func configure_map_for_run(map: MapData) -> String:
	var g := game
	if map == null:
		return "Scenario map is unavailable"
	if g != null and g.game_mode == &"campaign" and g.campaign != null:
		return _configure_campaign_map(map)
	var seats: Array = map.players.duplicate(true)
	seats.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("color", 0)) < int(b.get("color", 0)))
	var human_seat: Dictionary = {}
	for seat: Dictionary in seats:
		if int(seat.get("color", -1)) == g.setup.player_color:
			human_seat = seat
			break
	if human_seat.is_empty():
		return "The selected color is not available in this scenario"
	var human_seats: Array = [human_seat]
	for seat: Dictionary in seats:
		if seat != human_seat and human_seats.size() < g.setup.human_player_count:
			human_seats.append(seat)
	if human_seats.size() < g.setup.human_player_count:
		return "This scenario does not have enough player seats"
	var active: Array = []
	var side_map := {}
	for seat: Dictionary in human_seats:
		var human_side := active.size()
		side_map[int(seat.get("authored_side", seat.side))] = human_side
		seat.side = human_side
		seat.human = true
		seat.ai_level = 0
		seat.team = human_side
		active.append(seat)
	var level_index := 0
	var ai_team := human_seats.size()
	for seat: Dictionary in seats:
		if human_seats.has(seat):
			continue
		var level := int(g.setup.opponent_levels[level_index]) if level_index < 3 else 0
		level_index += 1
		if level <= 0:
			continue
		var runtime_side := active.size()
		side_map[int(seat.get("authored_side", seat.side))] = runtime_side
		seat.side = runtime_side
		seat.human = false
		seat.ai_level = level
		seat.team = ai_team if g.setup.king_of_the_hill else runtime_side
		active.append(seat)
	map.players = active
	map.hero_start = Vector2i(human_seat.get("hero_start", Vector2i.ZERO))
	for obj: MapObject in map.objects:
		if obj is TownObject:
			var town := obj as TownObject
			var source_owner := town.authored_owner if town.authored_owner != -2 else town.owner
			town.owner = int(side_map.get(source_owner, -1))
	for boat: Dictionary in map.starting_boats:
		boat.owner = int(side_map.get(int(boat.get("owner", -1)), -1))
	return ""

func _configure_campaign_map(map: MapData) -> String:
	var g := game
	var mission_id: int = g.campaign.mission_id()
	var leader: int = g.campaign.ruler
	var start_town_by_owner := {}
	for object: MapObject in map.objects:
		if object is TownObject and object.owner >= 0:
			start_town_by_owner[object.owner] = object
	var human_owner := -1
	for owner in start_town_by_owner:
		var town_object: TownObject = start_town_by_owner[owner]
		if (mission_id >= 5 and mission_id <= 8 and town_object.town_type == 4) \
				or (not (mission_id >= 5 and mission_id <= 8) and town_object.town_type == leader):
			human_owner = int(owner)
			break
	if human_owner < 0:
		return "Campaign map has no starting castle for %s" % CampaignCatalog.LEADER_NAMES[leader]
	var source_players := {}
	for spec: Dictionary in map.players:
		source_players[int(spec.get("authored_side", spec.side))] = spec
	var human_spec: Dictionary = source_players[human_owner].duplicate(true)
	human_spec.side = 0; human_spec.human = true; human_spec.color = CampaignCatalog.color_for(leader); human_spec.team = 0
	var configured: Array = [human_spec]
	var owner_to_side := {human_owner: 0}
	if mission_id >= 5 and mission_id <= 8:
		var enemy_heroes: Array = []
		for owner in source_players:
			if int(owner) == human_owner:
				continue
			owner_to_side[int(owner)] = 1
			enemy_heroes.append_array(source_players[owner].get("heroes", []))
		var enemy_spec := {"side": 1, "authored_side": 1, "human": false,
			"heroes": enemy_heroes, "hero_start": enemy_heroes[0] if not enemy_heroes.is_empty() else Vector2i.ZERO,
			"color": CampaignCatalog.color_for(g.campaign.mission().target_faction), "team": 1,
			"ai_level": CampaignCatalog.ai_level(mission_id)}
		configured.append(enemy_spec)
	else:
		for owner in source_players:
			if int(owner) == human_owner:
				continue
			var spec: Dictionary = source_players[owner].duplicate(true)
			var side := configured.size()
			owner_to_side[int(owner)] = side
			spec.side = side; spec.human = false; spec.ai_level = CampaignCatalog.ai_level(mission_id)
			var start_town: TownObject = start_town_by_owner.get(owner)
			spec.color = CampaignCatalog.color_for(start_town.town_type) if start_town != null and start_town.town_type < 4 else side
			spec.team = 1 if mission_id == 9 else side
			configured.append(spec)
	map.players = configured
	map.hero_start = Vector2i(human_spec.hero_start)
	for object: MapObject in map.objects:
		if object is TownObject:
			var town_object := object as TownObject
			town_object.owner = int(owner_to_side.get(town_object.authored_owner, -1))
			if town_object.town_type == 4 and town_object.owner == 0:
				# The ruler's own start castle (the homeland missions place the
				# player at a random town). heroes.exe 0x82520 gives player 0's
				# random town in missions 5 to 8 the ruler's faction (table
				# 0x20810); every other random town is rolled when the map
				# starts (KB towns.md).
				town_object.town_type = leader
	for boat: Dictionary in map.starting_boats:
		boat.owner = int(owner_to_side.get(int(boat.get("owner", -1)), -1))
	return ""

func register_town_gate(object_id: int, tile: Vector2i) -> void:
	var g := game
	if g != null:
		g.town_gate_ids[tile] = object_id

## Resolve the portrait/army shown by the town screen and select the town whose
## gate the hero occupies.
func resolve_town_visitor(hero: HeroModel = null, keep_active_town: bool = false) -> HeroModel:
	var g := game
	if g == null:
		return null
	var explicit_visit := hero != null
	var candidate: HeroModel = hero if explicit_visit else g.player_hero
	if candidate == null:
		return null

	if (keep_active_town or g.prefer_active_town) and g.state != null and not g.state.players.is_empty():
		g.prefer_active_town = false
		var human: PlayerState = g.state.human()
		if human != null and human.town != null:
			if explicit_visit:
				return candidate
			var target_id: int = human.town.object_id
			for gate in g.town_gate_ids:
				if int(g.town_gate_ids[gate]) == target_id:
					for h: HeroModel in human.heroes:
						if h.tile == gate:
							return h
			return null

	var gate_tile: Vector2i = candidate.tile
	if gate_tile == Vector2i(-1, -1):
		gate_tile = g.hero_tile
	if g.town_gate_ids.has(gate_tile) and g.state != null and not g.state.players.is_empty():
		var human: PlayerState = g.state.human()
		if human.select_town(int(g.town_gate_ids[gate_tile])) != null:
			g.town_tile = gate_tile
			return candidate

	if explicit_visit:
		return candidate
	if g.town_tile != Vector2i(-1, -1) and gate_tile == g.town_tile:
		return candidate
	return null

## Teach the visiting hero every guild spell up to the town's built guild level.
func teach_hero_at_town(p: PlayerState, hero: HeroModel) -> void:
	if p != null and p.town != null and hero != null:
		p.town.teach_visiting_hero(hero)

## Seat a local player without changing any kingdom identity.
func activate_local_player(side: int) -> bool:
	var g := game
	if g == null or g.state == null:
		return false
	var player: PlayerState = g.state.player_of(side)
	if player == null or player.is_ai or not player.alive:
		return false
	g.state.active_player_side = side
	g.player_hero = player.active()
	g.player_army = g.player_hero.army if g.player_hero != null else ArmyData.new()
	g.hero_tile = g.player_hero.tile if g.player_hero != null else Vector2i(-1, -1)
	g.hero_move_points = g.player_hero.move_points if g.player_hero != null else -1
	g.visiting_hero = null
	g.town_tile = Vector2i(-1, -1)
	if player.town != null:
		for gate: Variant in g.town_gate_ids:
			if int(g.town_gate_ids[gate]) == player.town.object_id:
				g.town_tile = Vector2i(gate)
				break
	if g.battle != null:
		g.battle.pending_defeat = false
		g.battle.pending_defeat_message = ""
	return true

func notify_campaign_event(event: StringName) -> void:
	var g := game
	if g != null and g.game_mode == &"campaign":
		g.campaign_objective_event = event

func campaign_objective_complete(map: MapData) -> bool:
	var g := game
	if g == null or g.game_mode != &"campaign" or g.campaign == null or map == null:
		return false
	match g.campaign.mission().objective:
		&"capture_gateway":
			for object: MapObject in map.objects:
				if object is TownObject and (object as TownObject).authored_owner == -1 and object.owner == 0:
					return true
		&"dig_eye":
			return g.campaign_objective_event == &"dig_eye"
		&"capture_home":
			var targets := {5: Vector2i(13, 10), 6: Vector2i(62, 20),
				7: Vector2i(8, 8), 8: Vector2i(66, 69)}
			for object: MapObject in map.objects:
				if object is TownObject and object.tile == targets.get(g.campaign.mission_id(), Vector2i(-1, -1)):
					return object.owner == 0
		&"capture_dragon_city":
			for object: MapObject in map.objects:
				if object is DragonCity and object.owner == 0:
					return true
		&"eliminate":
			for player: PlayerState in g.state.players:
				if player.is_ai and not player.is_eliminated():
					return false
			return true
	return false

func campaign_objective_failed(map: MapData) -> bool:
	var g := game
	if g == null or g.game_mode != &"campaign" or g.campaign == null or map == null:
		return false
	match g.campaign.mission().objective:
		&"capture_gateway":
			for object: MapObject in map.objects:
				if object is TownObject and (object as TownObject).authored_owner == -1 and object.owner > 0:
					return true
		&"dig_eye":
			return g.campaign_objective_event == &"ai_dug_eye"
		&"capture_dragon_city":
			for object: MapObject in map.objects:
				if object is DragonCity and object.owner > 0:
					return true
	return false

func complete_campaign_mission() -> Dictionary:
	var g := game
	if g == null or g.campaign == null:
		return {}
	var finished: CampaignMission = g.campaign.mission()
	if finished == null:
		return {}
	var finished_index: int = g.campaign.route_index
	var has_next: bool = g.campaign.advance(g.state.day if g.state != null else g.campaign.total_days)
	if g.save_glue != null:
		g.save_glue.autosave()
	# scenario_index is the mission just won, so the dialog names its save
	# SCENWN01, SCENWN02, ... (heroes.exe 0x43ddb counts missions won).
	return {"title": finished.title, "message": finished.completion_text,
		"has_next": has_next, "complete": g.campaign.completed, "days": g.campaign.total_days,
		"ruler": g.campaign.ruler, "scenario_index": finished_index}

## Persist one object's mutable state under its id.
func record_object_state(obj: MapObject) -> void:
	var g := game
	if g != null and obj != null:
		g.map_object_state[obj.id] = obj.save_state()

## Re-apply persisted state onto a freshly-loaded object list (after a scene reload).
func apply_object_states(objects: Array) -> void:
	var g := game
	if g == null:
		return
	for o: MapObject in objects:
		if g.map_object_state.has(o.id):
			o.apply_state(g.map_object_state[o.id])
	TownNames.assign(objects, g.rng)
	for o: MapObject in objects:
		if o is TownObject:
			record_object_state(o)
		elif o is ResourcePile and not g.map_object_state.has(o.id):
			# A save from before piles were pinned at the start of a run.
			record_object_state(o)
