class_name AICastleTurn
extends RefCounted

## Manages castle economy and buying decisions for computer players (AIBuyer),
## tavern hiring, boat purchases, and garrison army rebalancing.

var _map: MapData
var _world: AdventureWorldRenderer
var _roster: AIHeroRoster
var _turn_economy: Dictionary = {}
var _capture_town_fn: Callable
var _refresh_boats_fn: Callable

func setup(map: MapData, world: AdventureWorldRenderer, roster: AIHeroRoster,
		turn_economy: Dictionary, capture_town_fn: Callable,
		refresh_boats_fn: Callable = Callable()) -> void:
	_map = map
	_world = world
	_roster = roster
	_turn_economy = turn_economy
	_capture_town_fn = capture_town_fn
	_refresh_boats_fn = refresh_boats_fn

func buy(ai: PlayerState) -> void:
	if Game.state == null or ai == null:
		return
	var ctx := AIBuyer.Context.new()
	ctx.econ = _turn_economy.get(ai.side, {})
	if ctx.econ.is_empty():
		var current_day := Game.state.day if Game.state != null else 1
		ctx.econ = AIBuyer.economy(ai, AIBuyer.income_of(ai, _map.objects if _map != null else [], current_day), current_day)
		_turn_economy[ai.side] = ctx.econ
	ctx.roll = func(lo: int, hi: int) -> int: return Game.rng.randi_range(lo, hi)
	ctx.hero_at = func(town_index: int) -> HeroModel: return hero_in_town(ai, town_index)
	ctx.gate_taken = func(town_index: int) -> bool:
		var castle := castle_object(ai, town_index)
		return castle != null and _roster.hero_stands_at(castle.action_tile)
	ctx.tavern = func() -> Array:
		return HeroPool.candidates(Game.rng, ai.heroes, 0, ai.returning_heroes, ai.side)
	ctx.hire = func(town_index: int, hero: HeroModel) -> bool: return hire_at(ai, town_index, hero)
	ctx.rebalance = func(town_index: int) -> void:
		var hero := hero_in_town(ai, town_index)
		var town: TownModel = ai.towns[town_index]
		if hero == null:
			return
		if not AIController.castle_guild(hero, town):
			_roster.stop_hero(ai, hero)
		if AIController.castle_swap(hero.army, hero.effective_attack(), hero.effective_defense(),
				town.army, town.has_castle, town_index) != 0:
			_roster.refresh_max_move(ai, hero)
	ctx.buy_boat = func(town_index: int) -> bool: return buy_boat_at(ai, town_index)
	ctx.hired_today = ai.ai_hires_on(Game.state.day) > 0
	ctx.players_left = 0
	for p: PlayerState in Game.state.players:
		if p.alive:
			ctx.players_left += 1
	var original_town := ai.active_town
	var original_hero := ai.active_hero
	for town_index in ai.towns.size():
		var gate := castle_object(ai, town_index)
		if gate != null:
			var town_model: TownModel = ai.towns[town_index]
			town_model.ship_launch_tile = gate.action_tile + Vector2i(-1, 1)
			town_model.sea_access = _map.is_water(town_model.ship_launch_tile) if _map != null else false
	AIBuyer.run(ai, ctx)
	for town_index in ai.towns.size():
		var built_gate := castle_object(ai, town_index)
		if built_gate != null and _world != null:
			_world.refresh_object(built_gate.id)
	ai.active_town = clampi(original_town, 0, max(0, ai.towns.size() - 1))
	ai.active_hero = clampi(original_hero, 0, max(0, ai.heroes.size() - 1))

func capture_town(town: TownObject, side: int) -> void:
	var notice: Variant = _capture_town_fn.call(town, side) if _capture_town_fn.is_valid() else null
	if notice is CanvasLayer and is_instance_valid(notice) \
			and DisplayServer.get_name() != "headless":
		await (notice as CanvasLayer).closed

func buy_boat_at(ai: PlayerState, town_index: int) -> bool:
	var castle := castle_object(ai, town_index)
	var town: TownModel = ai.towns[town_index]
	if castle == null or Game.state == null:
		return false
	var bought := town.buy_boat(ai, Game.state) != null
	if bought and _refresh_boats_fn.is_valid():
		_refresh_boats_fn.call()
	return bought

func hero_in_town(ai: PlayerState, town_index: int) -> HeroModel:
	var castle := castle_object(ai, town_index)
	if castle == null:
		return null
	for hero: HeroModel in ai.heroes:
		if hero.tile == castle.action_tile:
			return hero
	return null

func hire_at(ai: PlayerState, town_index: int, hero: HeroModel) -> bool:
	var castle := castle_object(ai, town_index)
	if castle == null or hero == null:
		return false
	ai.active_town = town_index
	hero.crest_idx = (ai.crest_idx / 4) * 4 + (hero.crest_idx % 4)
	if not ai.hire(hero, castle.action_tile, Game.state.hero_pool, Game.rng):
		return false
	ai.note_ai_hire(Game.state.day)
	var node := _roster.make_hero_node(ai, hero)
	hero.max_move_points = node.max_move_points
	hero.move_points = node.move_points
	var nodes: Array = _roster.ai_heroes.get(ai.side, [])
	nodes.append(node)
	_roster.ai_heroes[ai.side] = nodes
	return true

func castle_object(ai: PlayerState, town_index: int) -> TownObject:
	if _map == null or town_index < 0 or town_index >= ai.towns.size():
		return null
	var model: TownModel = ai.towns[town_index]
	for o: MapObject in _map.objects:
		if o is TownObject and o.id == model.object_id and o.owner == ai.side:
			return o as TownObject
	return _map.town_of_side(ai.side) if town_index == 0 else null

func home_town(ai: PlayerState) -> TownModel:
	if _map == null or ai == null:
		return null
	var castle := _map.town_of_side(ai.side)
	var model := ai.town_by_object_id(castle.id) if castle != null else null
	if model == null and not ai.towns.is_empty():
		model = ai.towns[0]
	return model

func town_entrance(side: int) -> Vector2i:
	if _map == null:
		return Vector2i(-1, -1)
	var t := _map.town_of_side(side)
	return t.action_tile if t != null else Vector2i(-1, -1)

func visit_own_castle(ai: PlayerState, town: TownModel) -> void:
	var model := ai.active()
	if model == null or town == null:
		return
	var town_index := ai.towns.find(town)
	var castle := castle_object(ai, town_index)
	if castle == null and _map != null:
		var obj := _map.object_by_id(town.object_id)
		if obj is TownObject:
			castle = obj as TownObject
	if castle == null or model.tile != castle.action_tile:
		return
	var home_hero := _roster.hero_for_side(ai.side)
	if home_hero != null:
		home_hero.move_points = 0
	model.move_points = 0
	AIController.castle_guild(model, town)
	if AIController.castle_swap(model.army, model.effective_attack(), model.effective_defense(),
			town.army, town.has_castle) != 0:
		if home_hero != null:
			home_hero.max_move_points = Hero.calculate_model_max_move(model, _map.objects if _map != null else [], ai.side, ai.ai_level)
	buy(ai)

func hostile_town_targets(ai: PlayerState) -> Array:
	var out: Array = []
	if _map == null or Game.state == null:
		return out
	var active_side := Game.state.active_player_side
	for object: MapObject in _map.objects:
		if not (object is TownObject) or object.owner == ai.side:
			continue
		if object.owner < 0:
			var garrison: ArmyData = (object as TownObject).garrison
			var garrison_power: float = ArmyStrength.of(garrison) if garrison != null else 0.0
			out.append({"tile": object.action_tile, "strength": garrison_power,
				"side": -1, "object": object})
			continue
		var opponent := Game.state.player_of(object.owner)
		if not ai.is_hostile_to(opponent):
			continue
		var model := opponent.town_by_object_id(object.id)
		# Every town of the human's, not only the first: the castle-less rule
		# picks among these, and the nearest may be any of them.
		out.append({"tile": object.action_tile,
			"strength": ArmyStrength.of(model.army) if model != null else 0.0,
			"side": opponent.side, "object": object,
			"kind": "player_town" if opponent.side == active_side else "enemy_town"})
	return out
