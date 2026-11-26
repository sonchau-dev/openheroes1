class_name AIHeroRoster
extends RefCounted

## Manages the active AI hero nodes on the adventure map, hero lookup by tile
## or side, spawning, node removal, and persistence to HeroModel.

signal hero_defeated(hero: Hero)

var ai_heroes: Dictionary = {} # runtime side -> Array[Hero], index-aligned with PlayerState.heroes

var _root: Node2D
var _map: MapData
var _fog: FogLayer
var _player_hero_fn: Callable
var _player_heroes_fn: Callable

func setup(root: Node2D, map: MapData, fog: FogLayer,
		player_hero_fn: Callable = Callable(),
		player_heroes_fn: Callable = Callable()) -> void:
	_root = root
	_map = map
	_fog = fog
	_player_hero_fn = player_hero_fn
	_player_heroes_fn = player_heroes_fn

func spawn_ai_hero() -> void:
	if Game.state == null:
		return
	var active_side := Game.state.active_player_side
	for ai: PlayerState in Game.state.players:
		if ai.side == active_side or not ai.alive:
			continue
		var nodes: Array[Hero] = []
		for model: HeroModel in ai.heroes:
			if model.tile == Vector2i(-1, -1):
				continue
			nodes.append(make_hero_node(ai, model))
		ai_heroes[ai.side] = nodes

func make_hero_node(ai: PlayerState, model: HeroModel) -> Hero:
	var node := Hero.new()
	node.z_index = 0
	if _root != null:
		_root.add_child(node)
	node.setup(model.hero_class, model.tile, _map.tile_size if _map != null else 32, _map, model.crest_idx)
	node.set_travel_mode(model.travel_mode, model.carried_boat_id)
	node.max_move_points = Hero.calculate_model_max_move(model, _map.objects if _map != null else [], ai.side, ai.ai_level)
	node.move_points = model.move_points if model.move_points >= 0 else node.max_move_points
	node.visible = _fog.is_explored(node.tile) if _fog != null else true
	return node

func drop_hero_node(node: Hero, shown: bool) -> void:
	if not is_instance_valid(node):
		return
	if shown:
		hero_defeated.emit(node)
		node.disappear()
	else:
		node.disappear(0.0)

func handle_ai_hero_death(ai: PlayerState, shown: bool = true) -> void:
	var dead_index := ai.active_hero
	var dead_model := ai.active()
	var nodes: Array = ai_heroes.get(ai.side, [])
	var node: Hero = nodes[dead_index] as Hero if dead_index >= 0 and dead_index < nodes.size() else null
	if dead_model != null:
		ai.defeat_hero(dead_model, Game.rng, Game.state.hero_pool if Game.state != null else null)
	drop_hero_node(node, shown)
	if dead_index >= 0 and dead_index < nodes.size():
		nodes.remove_at(dead_index)
	if nodes.is_empty():
		ai_heroes.erase(ai.side)
	else:
		ai_heroes[ai.side] = nodes

func remove_all_heroes_for_side(side: int) -> void:
	var nodes: Array = ai_heroes.get(side, [])
	for node: Hero in nodes:
		drop_hero_node(node, false)
	ai_heroes.erase(side)

func hero_for_side(side: int) -> Hero:
	var nodes: Array = ai_heroes.get(side, [])
	var player := Game.state.player_of(side) if Game.state != null else null
	var index := clampi(player.active_hero, 0, nodes.size() - 1) if player != null and not nodes.is_empty() else 0
	return nodes[index] as Hero if not nodes.is_empty() else null

func heroes_for_side(side: int) -> Array:
	return ai_heroes.get(side, [])

func all_heroes() -> Array[Hero]:
	var out: Array[Hero] = []
	var sides := ai_heroes.keys()
	sides.sort()
	for side in sides:
		for node: Hero in ai_heroes[side]:
			if is_instance_valid(node):
				out.append(node)
	return out

func all_map_heroes() -> Array[Hero]:
	var out: Array[Hero] = []
	for h: Hero in all_heroes():
		if is_instance_valid(h) and not out.has(h):
			out.append(h)
	if _player_heroes_fn.is_valid():
		var ph_list = _player_heroes_fn.call()
		if ph_list is Array:
			for node: Hero in ph_list:
				if is_instance_valid(node) and not out.has(node):
					out.append(node)
	if _player_hero_fn.is_valid():
		var ph: Hero = _player_hero_fn.call()
		if is_instance_valid(ph) and not out.has(ph):
			out.append(ph)
	return out

func side_at(tile: Vector2i) -> int:
	for side in ai_heroes:
		for node: Hero in ai_heroes[side]:
			if is_instance_valid(node) and node.tile == tile:
				return int(side)
	return -1

func hero_node_at(tile: Vector2i) -> Hero:
	for side in ai_heroes:
		for node: Hero in ai_heroes[side]:
			if is_instance_valid(node) and node.tile == tile:
				return node
	return null

func persist_heroes() -> void:
	for side in ai_heroes:
		var player := Game.state.player_of(int(side)) if Game.state != null else null
		if player == null:
			continue
		var nodes: Array = ai_heroes[side]
		for i in mini(nodes.size(), player.heroes.size()):
			var node := nodes[i] as Hero
			var model: HeroModel = player.heroes[i]
			if is_instance_valid(node) and model != null:
				model.tile = node.tile
				model.move_points = node.move_points
				model.travel_mode = node.travel_mode
				model.carried_boat_id = node.carried_boat_id
				model.facing = node.get_direction()

func hero_model_at(tile: Vector2i) -> HeroModel:
	for side in ai_heroes:
		var nodes: Array = ai_heroes[side]
		var player := Game.state.player_of(int(side)) if Game.state != null else null
		if player == null:
			continue
		for i in mini(nodes.size(), player.heroes.size()):
			var node := nodes[i] as Hero
			if is_instance_valid(node) and node.tile == tile:
				return player.heroes[i]
		for h: HeroModel in player.heroes:
			if h.tile == tile:
				return h
	if Game.state != null:
		for p: PlayerState in Game.state.players:
			if p.is_ai and p.alive:
				for h: HeroModel in p.heroes:
					if h.tile == tile:
						return h
	return null

func first_ai() -> PlayerState:
	if Game.state == null:
		return null
	for p: PlayerState in Game.state.players:
		if p.is_ai and p.alive:
			return p
	return null

func hero_stands_at(tile: Vector2i) -> bool:
	if side_at(tile) >= 0:
		return true
	if Game.state != null:
		for player: PlayerState in Game.state.players:
			for model: HeroModel in player.heroes:
				if model.tile == tile:
					return true
	return false

func stop_hero(ai: PlayerState, model: HeroModel) -> void:
	model.move_points = 0
	var index := ai.heroes.find(model)
	var nodes: Array = ai_heroes.get(ai.side, [])
	if index >= 0 and index < nodes.size() and is_instance_valid(nodes[index]):
		(nodes[index] as Hero).move_points = 0

func refresh_max_move(ai: PlayerState, model: HeroModel) -> void:
	var index := ai.heroes.find(model)
	var nodes: Array = ai_heroes.get(ai.side, [])
	if index >= 0 and index < nodes.size() and is_instance_valid(nodes[index]):
		(nodes[index] as Hero).max_move_points = Hero.calculate_model_max_move(
				model, _map.objects if _map != null else [], ai.side, ai.ai_level)

func remove_ai_hero_at(player: PlayerState, index: int, shown: bool = false) -> void:
	var nodes: Array = ai_heroes.get(player.side, [])
	if index >= 0 and index < nodes.size():
		drop_hero_node(nodes[index] as Hero, shown)
		nodes.remove_at(index)
	if index >= 0 and index < player.heroes.size():
		player.defeat_hero(player.heroes[index], Game.rng,
				Game.state.hero_pool if Game.state != null else null)
	if nodes.is_empty():
		ai_heroes.erase(player.side)
	else:
		ai_heroes[player.side] = nodes

func hostile_hero_targets(ai: PlayerState) -> Array:
	var out: Array = []
	if Game.state == null:
		return out
	var active_side := Game.state.active_player_side
	for opponent: PlayerState in Game.state.players:
		if opponent.side == ai.side or opponent.side == active_side \
				or not ai.is_hostile_to(opponent):
			continue
		var nodes: Array = heroes_for_side(opponent.side)
		for i in mini(nodes.size(), opponent.heroes.size()):
			var node := nodes[i] as Hero
			if is_instance_valid(node):
				out.append({"tile": node.tile, "strength": ArmyStrength.of(opponent.heroes[i].army),
					"side": opponent.side, "hero_index": i})
	return out
