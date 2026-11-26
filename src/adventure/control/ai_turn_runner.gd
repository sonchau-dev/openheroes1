class_name AITurnRunner
extends Node

## Executes one AI player's adventure-map day: buy (AICastleTurn), pick targets,
## march, resolve arrivals (AIArrival: pickups, mine grabs, battles).
## Owns AI hero tracking via AIHeroRoster.

signal hero_defeated(hero: Hero)
signal planning_iteration_completed(info: Dictionary)
signal hero_turn_completed(info: Dictionary)
signal ai_turn_completed(info: Dictionary)

var roster: AIHeroRoster
var castle_turn: AICastleTurn
var arrival: AIArrival

var ai_heroes: Dictionary:
	get:
		return roster.ai_heroes if roster != null else {}
	set(v):
		if roster != null:
			roster.ai_heroes = v

var ai_hero: Hero:
	get:
		var ai := first_ai()
		return hero_for_side(ai.side) if ai != null else null
	set(value):
		var ai := first_ai()
		if roster != null:
			roster.ai_heroes[ai.side if ai != null else 1] = [value]

var _root: Node2D:
	set(v):
		_root = v
		if roster != null: roster._root = v
		if arrival != null: arrival._root = v
	get:
		return _root

var _map: MapData:
	set(v):
		_map = v
		if roster != null: roster._map = v
		if castle_turn != null: castle_turn._map = v
		if arrival != null: arrival._map = v
	get:
		return _map

var _astar: PassabilityGrid:
	set(v):
		_astar = v
		if arrival != null: arrival._astar = v
	get:
		return _astar

var _fog: FogLayer:
	set(v):
		_fog = v
		if roster != null: roster._fog = v
	get:
		return _fog

var _world: AdventureWorldRenderer:
	set(v):
		_world = v
		if castle_turn != null: castle_turn._world = v
		if arrival != null: arrival._world = v
	get:
		return _world

var _player_hero_fn: Callable
var _player_heroes_fn: Callable
var _player_army_fn: Callable
var _prepare_for_battle_fn: Callable
var _capture_town_fn: Callable
## The kingdom status check (TurnController.check_game_over) and whether a
## modal message is up or queued; set by the adventure map.
var status_check_fn: Callable
var modal_fn: Callable

## side -> AIBuyer.economy() snapshot taken at the start of that side's turn.
var _turn_economy: Dictionary = {}
## A hero hidden in fog teleports instead of walking, so nothing in its march
## would let a frame draw. Planning longer than this hands the frame back.
const FRAME_BUDGET_USEC := 12000
var _budget_frame := -1
var _budget_start_usec := 0
## Whether the human sees what this computer turn does (heroes.exe data
## 0x41154): off at the start of a computer turn, then set at every march
## from Show Enemy Moves and the fog at both ends of the step (0xa7ac2). A
## computer hero that dies plays killfade and fades out only while it is set
## (0xb5d88); otherwise the hero is just removed, without a sound.
var shown_to_human: bool:
	get:
		return arrival.shown_to_human if arrival != null else _shown_to_human
	set(v):
		_shown_to_human = v
		if arrival != null:
			arrival.shown_to_human = v
var _shown_to_human := false

func _init() -> void:
	roster = AIHeroRoster.new()
	roster.hero_defeated.connect(func(h: Hero) -> void: hero_defeated.emit(h))
	castle_turn = AICastleTurn.new()
	arrival = AIArrival.new()
	castle_turn._roster = roster
	castle_turn._turn_economy = _turn_economy
	arrival._roster = roster
	arrival._castle_turn = castle_turn
	arrival._turn_economy = _turn_economy

func setup(root: Node2D, map: MapData, astar: PassabilityGrid, fog: FogLayer,
		world: AdventureWorldRenderer, player_hero_fn: Callable, player_army_fn: Callable,
		prepare_for_battle_fn: Callable,
		capture_town_fn: Callable,
		player_heroes_fn: Callable = Callable()) -> void:
	_root = root
	_map = map
	_astar = astar
	_fog = fog
	_world = world
	_player_hero_fn = player_hero_fn
	_player_army_fn = player_army_fn
	_prepare_for_battle_fn = prepare_for_battle_fn
	_capture_town_fn = capture_town_fn
	_player_heroes_fn = player_heroes_fn
	roster.setup(root, map, fog, player_hero_fn, player_heroes_fn)
	castle_turn.setup(map, world, roster, _turn_economy, capture_town_fn, Callable(self, "_refresh_boats"))
	arrival.setup(root, map, astar, world, roster, castle_turn, prepare_for_battle_fn, _turn_economy)

func spawn_ai_hero() -> void:
	roster.spawn_ai_hero()

## One AI day, as heroes.exe 0x693d4 orders it: the economy snapshot, the
## buy (AIBuyer), then each hero picks targets and marches until movement or
## targets run out. The hero with the most movement points left goes next (0x69cde).
## Always terminates (safety cap + monotone move spend).
## Returns true if a battle is launching (scene switch pending).
func run_turn(ai: PlayerState) -> bool:
	var turn_t0 := Time.get_ticks_usec()
	var original_active := ai.active_hero
	shown_to_human = false
	if Game.state != null:
		AIBuyer.expire_naval_request(ai, Game.state.day)
		_turn_economy[ai.side] = AIBuyer.economy(ai,
				AIBuyer.income_of(ai, _map.objects if _map != null else [], Game.state.day), Game.state.day)
	var buy_t0 := Time.get_ticks_usec()
	castle_turn.buy(ai)
	var buy_usec := Time.get_ticks_usec() - buy_t0
	var heroes_run := 0
	while true:
		var best_index := -1
		var best_mp := 0
		var nodes: Array = roster.heroes_for_side(ai.side)
		for i in ai.heroes.size():
			var model: HeroModel = ai.heroes[i]
			var node: Hero = nodes[i] if i < nodes.size() else null
			var mp: int = node.move_points if is_instance_valid(node) else model.move_points
			if mp > best_mp:
				best_mp = mp
				best_index = i
		if best_index < 0 or best_mp < 4:
			break
		ai.active_hero = best_index
		var prev_mp := best_mp
		var picked: HeroModel = ai.heroes[best_index]
		heroes_run += 1
		if await _run_active_hero(ai):
			ai_turn_completed.emit({
				"side": ai.side,
				"day": Game.state.day if Game.state != null else 1,
				"duration_usec": Time.get_ticks_usec() - turn_t0,
				"buy_usec": buy_usec,
				"heroes_run": heroes_run,
				"battle_pending": true,
			})
			return true
		# A hero that died in its run is gone from the roster; the index now
		# names its teammate, which keeps its day.
		if best_index >= ai.heroes.size() or ai.heroes[best_index] != picked:
			continue
		nodes = roster.heroes_for_side(ai.side)
		var node: Hero = nodes[best_index] if best_index < nodes.size() else null
		var current_mp: int = node.move_points if is_instance_valid(node) else picked.move_points
		if current_mp >= prev_mp:
			if is_instance_valid(node):
				node.move_points = 0
			picked.move_points = 0
	ai.active_hero = clampi(original_active, 0, max(0, ai.heroes.size() - 1))
	var is_battle: bool = Game.pending_ai_battle or Game.pending_town_battle_side >= 0
	ai_turn_completed.emit({
		"side": ai.side,
		"day": Game.state.day if Game.state != null else 1,
		"duration_usec": Time.get_ticks_usec() - turn_t0,
		"buy_usec": buy_usec,
		"heroes_run": heroes_run,
		"battle_pending": is_battle,
	})
	return is_battle

## Lets the screen redraw when the AI has run past one frame's budget.
## Headless runs never yield, so tests keep their synchronous order.
func _yield_if_over_budget() -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	if Engine.get_process_frames() != _budget_frame:
		_budget_frame = Engine.get_process_frames()
		_budget_start_usec = Time.get_ticks_usec()
		return
	if Time.get_ticks_usec() - _budget_start_usec < FRAME_BUDGET_USEC:
		return
	await get_tree().process_frame

func _buy(ai: PlayerState) -> void:
	castle_turn.buy(ai)

func _home_town(ai: PlayerState) -> TownModel:
	return castle_turn.home_town(ai)

func _run_active_hero(ai: PlayerState) -> bool:
	var hero_t0 := Time.get_ticks_usec()
	var hero := hero_for_side(ai.side)
	if hero == null or ai.active() == null:
		return Game.pending_ai_battle or Game.pending_town_battle_side >= 0
	var hero_name: String = ai.active().hero_name
	# heroes.exe 0x6b38a: a hero walks a few steps (more at sea), then plans
	# again; it remembers where it planned this turn, and planning again on
	# one of those tiles (a town's gate aside) ends its day.
	var steps := AIPlanner.step_count(ai, ai.active())
	var planned_at: Array[Vector2i] = []
	var revisit_limit := int(AIPlanner.rules().get("revisit_limit", 30))
	var grab := {}
	var safety := 12
	var factors := {}
	var hero_iterations := 0
	while safety > 0:
		safety -= 1
		hero_iterations += 1
		var iter_t0 := Time.get_ticks_usec()
		var iter_from_tile := hero.tile
		var plan_usec := 0
		var route_usec := 0
		var steps_taken := 0
		await _yield_if_over_budget()
		var ctx := {
			"player_hero_tile": (_player_hero_fn.call() as Hero).tile if _player_hero_fn.is_valid() and Game.player_hero != null else Vector2i(-1, -1),
			"player_strength": ArmyStrength.of(_player_army_fn.call()) if _player_army_fn.is_valid() else 0.0,
			"own_town_tile": _town_entrance(ai.side),
			"game_state": Game.state,
			"hostile_heroes": _hostile_hero_targets(ai),
			"hostile_towns": _hostile_town_targets(ai),
			"home_town": _home_town(ai),
			"economy": _turn_economy.get(ai.side, {}),
			"move_left": hero.move_points,
			"max_move": hero.max_move_points,
			"roll": func(lo: int, hi: int) -> int: return Game.rng.randi_range(lo, hi) if Game.rng != null else randi_range(lo, hi),
		}
		if factors.is_empty():
			factors = AIPlanner.turn_factors(ai, _map, _astar, ctx)
		ctx.merge(factors)
		# Teammates block scoring as well as movement, so two of this side's
		# heroes never pick (and end up sharing) one tile, such as the gate.
		var teammates_solid: Array[Vector2i] = []
		for other: Hero in heroes_for_side(ai.side):
			if other != hero and is_instance_valid(other) \
					and _astar != null and not _astar.is_point_solid(other.tile):
				_astar.set_point_solid(other.tile, true)
				teammates_solid.append(other.tile)
		# A neighbour worth taking now goes first (GOODADJ), as found before
		# the last step or here before the first.
		# heroes.exe 0x6a619: a hero with his whole day ahead of him on the
		# tile his player believes holds the Ultimate Artifact digs there.
		if hero.move_points >= hero.max_move_points and hero.tile == ai.dig_tile \
				and ai.dig_confidence > int((AIPlanner.rules().get("dig", {}) as Dictionary).get("above", 15)):
			for tile: Vector2i in teammates_solid:
				if _astar != null:
					_astar.set_point_solid(tile, false)
			await _ai_resolve_arrival(ai, {"tile": hero.tile, "kind": "dig_ultimate", "object": null})
			hero.move_points = 0
			_emit_iteration(ai.side, hero_name, hero_iterations, iter_t0, 0, 0, {"tile": hero.tile, "kind": "dig_ultimate"}, 0, iter_from_tile, [hero.tile], [hero.tile])
			_emit_hero_turn(ai.side, hero_name, hero_t0, hero_iterations, 0)
			return Game.pending_ai_battle or Game.pending_town_battle_side >= 0
		# GOODADJ runs at sea as well (0x6b71d has no sea check).
		var plan_t0 := Time.get_ticks_usec()
		var grab_plan: AIPlanner.Plan = null
		var target := grab
		grab = {}
		if target.is_empty():
			grab_plan = AIPlanner.make(ai, _map, _astar, ctx)
			target = AIPlanner.adjacent_grab(grab_plan, hero.tile)
		if target.is_empty():
			if planned_at.has(hero.tile) and (_map == null or _map.own_town_gate_at(hero.tile, ai.side) == null):
				for tile: Vector2i in teammates_solid:
					if _astar != null:
						_astar.set_point_solid(tile, false)
				hero.move_points = 0
				if ai.active() != null:
					ai.active().move_points = 0
				plan_usec = Time.get_ticks_usec() - plan_t0
				_emit_iteration(ai.side, hero_name, hero_iterations, iter_t0, plan_usec, 0, {}, 0, iter_from_tile)
				_emit_hero_turn(ai.side, hero_name, hero_t0, hero_iterations, 0)
				return Game.pending_ai_battle or Game.pending_town_battle_side >= 0
			if planned_at.size() < revisit_limit:
				planned_at.append(hero.tile)
			target = AIController.pick_target(ai, _map, _astar, hero.tile, ctx, grab_plan)
		plan_usec = Time.get_ticks_usec() - plan_t0
		for tile: Vector2i in teammates_solid:
			if _astar != null:
				_astar.set_point_solid(tile, false)
		if bool(target.get("naval_buy", false)):
			# 0x6b26f: the naval fallback ends with a buy, so a request it
			# just made can be met at once.
			_buy(ai)
		if target.is_empty():
			hero.move_points = 0
			if ai.active() != null:
				ai.active().move_points = 0
			_emit_iteration(ai.side, hero_name, hero_iterations, iter_t0, plan_usec, 0, {}, 0, iter_from_tile)
			_emit_hero_turn(ai.side, hero_name, hero_t0, hero_iterations, 0)
			return Game.pending_ai_battle or Game.pending_town_battle_side >= 0
		if hero.tile == target.tile:
			var stop: bool = await _ai_resolve_arrival(ai, target)
			if ai.active() != null:
				AIPlanner.forget_near(factors, ai.active().planned_dest)
			_emit_iteration(ai.side, hero_name, hero_iterations, iter_t0, plan_usec, 0, target, 0, iter_from_tile, [hero.tile], [hero.tile])
			# A castle arrival zeroes movement (0x6b266), so the day is over.
			if stop or hero.move_points < 4:
				_emit_hero_turn(ai.side, hero_name, hero_t0, hero_iterations, hero.move_points)
				return Game.pending_ai_battle or Game.pending_town_battle_side >= 0
			continue
		await _yield_if_over_budget()
		var temporarily_solid: Array[Vector2i] = []
		var occupied_hero_tiles: Array[Vector2i] = []
		for other: Hero in all_map_heroes():
			if other != hero and is_instance_valid(other) and other.tile != Vector2i(-1, -1):
				if not occupied_hero_tiles.has(other.tile):
					occupied_hero_tiles.append(other.tile)
		if Game.state != null:
			for p: PlayerState in Game.state.players:
				if not p.alive:
					continue
				for hm: HeroModel in p.heroes:
					if hm.tile != Vector2i(-1, -1) and hm.tile != hero.tile:
						if not occupied_hero_tiles.has(hm.tile):
							occupied_hero_tiles.append(hm.tile)
		var route_t0 := Time.get_ticks_usec()
		var path: Array = []
		if target.has("path") and not (target.path as Array).is_empty():
			var pre_path: Array = target.path
			var valid := true
			for step in pre_path:
				if step is Vector2i:
					path.append(step)
				elif step is Dictionary:
					path.append(step.tile)
				else:
					valid = false
					break
			if valid and path.size() >= 2 and path[0] == hero.tile and path[-1] == target.tile:
				for idx in range(1, path.size() - 1):
					if occupied_hero_tiles.has(path[idx]):
						valid = false
						break
			else:
				valid = false
			if not valid:
				path.clear()
		if path.is_empty():
			for tile: Vector2i in occupied_hero_tiles:
				if tile != target.tile and _astar != null and not _astar.is_point_solid(tile):
					_astar.set_point_solid(tile, true)
					temporarily_solid.append(tile)
			var plan := NavalPlanner.find(_astar, _map, Game.state, hero.tile,
					target.tile, hero.travel_mode, hero.carried_boat_id,
					hero.hero_class)
			for step: Dictionary in plan:
				path.append(step.tile)
			for tile: Vector2i in temporarily_solid:
				if _astar != null:
					_astar.set_point_solid(tile, false)
		route_usec = Time.get_ticks_usec() - route_t0
		if path.size() < 2:
			hero.move_points = 0
			if ai.active() != null:
				ai.active().move_points = 0
			_emit_iteration(ai.side, hero_name, hero_iterations, iter_t0, plan_usec, route_usec, target, 0, iter_from_tile, path, [])
			_emit_hero_turn(ai.side, hero_name, hero_t0, hero_iterations, 0)
			return Game.pending_ai_battle or Game.pending_town_battle_side >= 0
		var jump_from := hero.tile
		if hero.travel_mode == &"land" and _ai_dimension_door(ai, hero, path):
			# 0xa5200 shows the jump when the human sees the tile the hero leaves.
			shown_to_human = shows_step(_fog, jump_from, jump_from)
			var fade := hero.view_dissolve() if shown_to_human else null
			if fade != null:
				await fade.finished
			_emit_iteration(ai.side, hero_name, hero_iterations, iter_t0, plan_usec, route_usec, target, 1, iter_from_tile, path, [hero.tile])
			continue
		var prefix: Array = [path[0]]
		var spent := 0
		var remaining := hero.move_points
		var transition_kind := TravelRules.MOVE
		for i in range(1, path.size()):
			if prefix.size() > steps:
				break
			if i > 1 and path[i - 1] != target.tile:
				if grab_plan == null:
					grab_plan = AIPlanner.make(ai, _map, _astar, ctx)
				grab = AIPlanner.adjacent_grab(grab_plan, path[i - 1])
				if not grab.is_empty():
					break
			var kind := TravelRules.step_kind(_map, _astar, Game.state,
					hero.travel_mode, path[i - 1], path[i])
			if not TravelRules.is_walk(kind):
				if remaining <= 0:
					break
				prefix.append(path[i])
				transition_kind = kind
				break
			var raw_cost := Hero.step_cost(path[i - 1], path[i], _map,
					hero.travel_mode == &"sea", hero.hero_class)
			var straight_cost := Hero.step_cost(path[i - 1],
					path[i - 1] + Vector2i.RIGHT, _map,
					hero.travel_mode == &"sea", hero.hero_class)
			if not Pathfinder.can_take_today(raw_cost, straight_cost, remaining):
				break
			var charged_cost := Pathfinder.current_day_step_cost(
					raw_cost, straight_cost, remaining)
			spent += charged_cost
			remaining -= charged_cost
			prefix.append(path[i])
		# Ground pickups use the same engage-style collection as the player: pay
		# for the final step, but halt on the adjacent tile and face the object
		# while resolving it. Previously only artifacts did this; resource piles
		# (and the other pickup-handler objects) were collected after overlap.
		# Defending heroes (player or rival AI) also halt on the adjacent tile
		# and engage from there instead of stepping onto the defender's tile.
		# A guarded hostile town is attacked from the tile before its gate too, and the
		# hero stays there after taking it, as a human hero does.
		var is_hero_target := String(target.get("kind", "")) in ["player_hero", "enemy_hero"]
		var is_town_target := String(target.get("kind", "")) in ["player_town", "enemy_town"]
		var target_town_obj: TownObject = target.get("object") as TownObject
		if is_town_target and target_town_obj == null and _map != null:
			var t_tile: Vector2i = target.get("tile", Vector2i(-1, -1))
			if t_tile != Vector2i(-1, -1):
				var obj: MapObject = _map.object_at_action(t_tile)
				if obj is TownObject:
					target_town_obj = obj as TownObject
				else:
					target_town_obj = _map.town_at(t_tile)
		var is_guarded_town := is_town_target and target_town_obj != null \
				and target_town_obj.is_guarded_against(ai.side, _map, Game.state)
		var stop_before_target := false
		var target_object := target.get("object") as MapObject
		if ((target_object != null and (target_object.is_walk_on_pickup() or target_object is NeutralStack)) \
				or is_hero_target or is_guarded_town) \
				and prefix[-1] == target.tile \
				and transition_kind == TravelRules.MOVE:
			stop_before_target = true
			prefix.remove_at(prefix.size() - 1)
		# A hero halts on the shore beside a boat and boards from there.
		var board_tile := Vector2i(-1, -1)
		if transition_kind == TravelRules.BOARD:
			board_tile = prefix.pop_back()
		# A hero halts on the water beside the shore and disembarks from there.
		var disembark_tile := Vector2i(-1, -1)
		if transition_kind == TravelRules.DISEMBARK:
			disembark_tile = prefix.pop_back()
		if prefix.size() < 2 and not stop_before_target \
				and board_tile == Vector2i(-1, -1) \
				and disembark_tile == Vector2i(-1, -1):
			_emit_iteration(ai.side, hero_name, hero_iterations, iter_t0, plan_usec, route_usec, target, 0, iter_from_tile, path, prefix)
			_emit_hero_turn(ai.side, hero_name, hero_t0, hero_iterations, hero.move_points)
			return Game.pending_ai_battle or Game.pending_town_battle_side >= 0   # out of movement
		steps_taken = maxi(0, prefix.size() - 1)
		hero.move_points = maxi(0, hero.move_points - spent)
		if prefix.size() >= 2:
			shown_to_human = shows_step(_fog, hero.tile, prefix[-1])
		elif board_tile != Vector2i(-1, -1):
			shown_to_human = shows_step(_fog, hero.tile, board_tile)
		elif disembark_tile != Vector2i(-1, -1):
			shown_to_human = shows_step(_fog, hero.tile, disembark_tile)
		if prefix.size() >= 2 and shown_to_human:
			hero.move_along(prefix)
			await hero.arrived
		elif prefix.size() >= 2:
			# invisible in fog or view_enemy_movement is off: teleport (spec: unexplored segments apply instantly)
			hero.tile = prefix[-1]
			hero.position = Vector2(hero.tile.x * _map.tile_size, hero.tile.y * _map.tile_size)
		elif stop_before_target:
			hero.face_towards(target.tile)
		if transition_kind == TravelRules.BOARD:
			var boat := Game.state.boat_at(board_tile)
			if boat != null:
				Game.state.take_boat(boat.id)
				var fade := hero.board(board_tile, boat.id, boat.direction)
				hero.move_points = 0
				if fade != null and shown_to_human:
					await fade.finished
				_refresh_boats()
		elif transition_kind == TravelRules.DISEMBARK:
			var water_tile := hero.tile
			Game.state.place_boat(hero.carried_boat_id, water_tile,
					ai.side, Hero.landing_facing(water_tile, disembark_tile))
			_refresh_boats()
			var fade := hero.disembark(disembark_tile)
			hero.move_points = 0
			if fade != null and shown_to_human:
				await fade.finished
		if stop_before_target:
			hero.face_towards(target.tile)
		if ai.active() != null:
			ai.active().tile = hero.tile
			ai.active().move_points = hero.move_points
			ai.active().travel_mode = hero.travel_mode
			ai.active().carried_boat_id = hero.carried_boat_id
			ai.active().facing = hero.get_direction()
		# A guard on the way attacks as soon as the hero steps next to it.
		var zone_guard: NeutralStack = _astar.protecting_stack_at(hero.tile) \
				if _astar != null and not stop_before_target else null
		var met_guard := String(target.get("kind", "")) == "guard" and zone_guard == target_object
		# A stack guarding the cell the hero stopped on attacks before the hero
		# visits what it came for (a mine entrance beside a monster), unless a
		# town or armed object comes first, as for a human hero (adventure_map.gd).
		if zone_guard != null and not met_guard and not is_town_target \
				and not (target_object != null and target_object.is_armed()):
			target = {"tile": zone_guard.action_tile, "kind": "guard", "object": zone_guard}
			met_guard = true
		if stop_before_target or met_guard or hero.tile == target.tile:
			var is_object_visit := target.get("object") is MapObject \
					or String(target.get("kind", "")) in ["resource", "mine", "dragon_city", "player_town", "enemy_town", "obelisk", "dig_ultimate"]
			if is_object_visit:
				var penalty := Hero.ai_visit_cost_penalty(ai.ai_level)
				if penalty > 0:
					hero.move_points = maxi(0, hero.move_points - penalty)
					if ai.active() != null:
						ai.active().move_points = hero.move_points
			var stop: bool = await _ai_resolve_arrival(ai, target)
			if ai.active() != null:
				AIPlanner.forget_near(factors, ai.active().planned_dest)
			_emit_iteration(ai.side, hero_name, hero_iterations, iter_t0, plan_usec, route_usec, target, steps_taken, iter_from_tile, path, prefix)
			if stop:
				_emit_hero_turn(ai.side, hero_name, hero_t0, hero_iterations, hero.move_points)
				return Game.pending_ai_battle or Game.pending_town_battle_side >= 0
		else:
			_emit_iteration(ai.side, hero_name, hero_iterations, iter_t0, plan_usec, route_usec, target, steps_taken, iter_from_tile, path, prefix)
		if hero_for_side(ai.side) == null or hero.move_points < 4:
			if hero != null:
				hero.move_points = 0
				if ai.active() != null:
					ai.active().move_points = 0
			_emit_hero_turn(ai.side, hero_name, hero_t0, hero_iterations, 0)
			return Game.pending_ai_battle or Game.pending_town_battle_side >= 0
	if hero != null:
		hero.move_points = 0
		if ai.active() != null:
			ai.active().move_points = 0
	_emit_hero_turn(ai.side, hero_name, hero_t0, hero_iterations, 0)
	return Game.pending_ai_battle or Game.pending_town_battle_side >= 0

func _emit_iteration(ai_side: int, hero_name: String, iteration_idx: int,
		iter_t0: int, plan_usec: int, route_usec: int, target: Dictionary,
		steps_taken: int, from_tile: Vector2i = Vector2i(-1, -1),
		planned_path: Array = [], walked_path: Array = []) -> void:
	var total_usec := Time.get_ticks_usec() - iter_t0
	planning_iteration_completed.emit({
		"day": Game.state.day if Game.state != null else 1,
		"side": ai_side,
		"hero_name": hero_name,
		"iteration": iteration_idx,
		"duration_usec": total_usec,
		"plan_usec": plan_usec,
		"route_usec": route_usec,
		"target_kind": String(target.get("kind", "")),
		"target_tile": target.get("tile", Vector2i(-1, -1)),
		"from_tile": from_tile,
		"planned_path": planned_path,
		"walked_path": walked_path,
		"steps_taken": steps_taken,
	})

func _emit_hero_turn(ai_side: int, hero_name: String, hero_t0: int,
		iterations: int, remaining_mp: int) -> void:
	hero_turn_completed.emit({
		"side": ai_side,
		"hero_name": hero_name,
		"duration_usec": Time.get_ticks_usec() - hero_t0,
		"iterations": iterations,
		"remaining_mp": remaining_mp,
	})

func _refresh_boats() -> void:
	if _world != null:
		_world.refresh_boats()

static func shows_step(fog: FogLayer, from: Vector2i, to: Vector2i) -> bool:
	if not Game.view_enemy_movement or Game.game_mode == &"network":
		return false
	return fog == null or fog.is_explored(from) or fog.is_explored(to)

func handle_ai_hero_death(ai: PlayerState, shown: bool = true) -> void:
	roster.handle_ai_hero_death(ai, shown)

func remove_all_heroes_for_side(side: int) -> void:
	roster.remove_all_heroes_for_side(side)

func hero_for_side(side: int) -> Hero:
	return roster.hero_for_side(side)

func heroes_for_side(side: int) -> Array:
	return roster.heroes_for_side(side)

func all_heroes() -> Array[Hero]:
	return roster.all_heroes()

func all_map_heroes() -> Array[Hero]:
	return roster.all_map_heroes()

func side_at(tile: Vector2i) -> int:
	return roster.side_at(tile)

func hero_node_at(tile: Vector2i) -> Hero:
	return roster.hero_node_at(tile)

func persist_heroes() -> void:
	roster.persist_heroes()

func hero_model_at(tile: Vector2i) -> HeroModel:
	return roster.hero_model_at(tile)

func first_ai() -> PlayerState:
	return roster.first_ai()

func _town_entrance(side: int) -> Vector2i:
	return castle_turn.town_entrance(side)

func _hostile_hero_targets(ai: PlayerState) -> Array:
	return roster.hostile_hero_targets(ai)

func _hostile_town_targets(ai: PlayerState) -> Array:
	return castle_turn.hostile_town_targets(ai)

## heroes.exe runs the kingdom status check (0xd2830) after fights and
## captures, and its vanquished box is modal: the computer turn waits for OKAY.
func _ai_resolve_arrival(ai: PlayerState, target: Dictionary) -> bool:
	var stop: bool = await arrival.resolve_arrival(ai, target)
	if Game.pending_ai_battle or Game.pending_town_battle_side >= 0:
		return stop
	if status_check_fn.is_valid():
		status_check_fn.call()
	await _await_modal()
	return stop

## Headless runs have nobody to press OKAY.
func _await_modal() -> void:
	if not modal_fn.is_valid() or DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	while modal_fn.call():
		await get_tree().process_frame

func _ai_dimension_door(ai: PlayerState, hero: Hero, path: Array) -> bool:
	var model := ai.active()
	var r: Dictionary = AIPlanner.rules().get("dimension_door", {})
	if model == null or not model.has_spellbook or model.spellbook == null \
			or model.spellbook.charges("dimension_door") <= 0 \
			or hero.move_points < int(r.get("min_points", 4)):
		return false
	var reach := int(r.get("reach", 7))
	var landing := Vector2i(-1, -1)
	var steps := 0
	for k in range(1, path.size() - 1):
		var t: Vector2i = path[k]
		if absi(t.x - hero.tile.x) > reach or absi(t.y - hero.tile.y) > reach:
			continue
		if _map.is_water(t):
			continue
		if _astar != null and _astar.action_object_at(t) != null:
			continue
		var has_hero := false
		for h: Hero in all_map_heroes():
			if h.tile == t:
				has_hero = true
				break
		if has_hero:
			continue
		landing = t
		steps = k
	if landing == Vector2i(-1, -1) or steps <= int(r.get("min_steps", 4)):
		return false
	model.spellbook.cast("dimension_door")
	hero.tile = landing
	hero.position = Vector2(landing.x * _map.tile_size, landing.y * _map.tile_size)
	hero.move_points = maxi(0, hero.move_points - int(r.get("cost", 12)))
	model.tile = landing
	model.move_points = hero.move_points
	return true

