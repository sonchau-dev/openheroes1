class_name HeroSelection
extends RefCounted

## Manages player hero spawning, active hero selection, hero/town cycling,
## hero and town queries, movement persistence, and teleportation.

const REVEAL_RADIUS := 4

var hero: Hero = null
var heroes: Array = []   # Live Hero nodes, index-aligned with Game.state.human().heroes

func spawn_player_heroes(map_data: MapData, world: AdventureWorldRenderer,
		fog: FogLayer, current_army_fn: Callable, on_entered_fn: Callable,
		on_arrived_fn: Callable, root_node: Node2D = null) -> Hero:
	# Clean up any existing player heroes
	for n in heroes:
		if is_instance_valid(n):
			n.queue_free()
	heroes.clear()

	if Game.state == null or Game.state.players.is_empty():
		var h_model := Game.ensure_player_hero(current_army_fn.call())
		var start_tile: Vector2i = Game.hero_tile if Game.hero_tile != Vector2i(-1, -1) else map_data.hero_start
		var n := Hero.new()
		_add_actor(world, root_node, n)
		n.setup(h_model.hero_class, start_tile, map_data.tile_size, map_data, h_model.crest_idx)
		n.set_travel_mode(h_model.travel_mode, h_model.carried_boat_id)
		n.max_move_points = Hero.calculate_model_max_move(h_model, map_data.objects, 0)
		n.planned_dest = h_model.planned_dest
		if Game.hero_move_points >= 0:
			n.move_points = Game.hero_move_points
		else:
			n.move_points = n.max_move_points
		n.entered_tile.connect(on_entered_fn.bind(n))
		n.arrived.connect(on_arrived_fn)
		heroes.append(n)
		hero = n
		if fog != null:
			fog.reveal(start_tile, REVEAL_RADIUS + h_model.sight_bonus)
		return hero

	var human := Game.state.human()
	if human.heroes.is_empty():
		# Critical 4: only a genuinely FRESH game auto-creates the starting
		# hero (no persisted tile AND no heroes). A player whose last hero
		# died but who still holds a town must re-hire at the tavern —
		# ensure_player_hero here would be a free respawn bypassing the 2500g.
		if Game.hero_tile == Vector2i(-1, -1):
			Game.ensure_player_hero(current_army_fn.call())
		else:
			hero = null
			Game.player_hero = null
			return null

	for idx in human.heroes.size():
		var model: HeroModel = human.heroes[idx]
		var tile: Vector2i = model.tile
		if tile == Vector2i(-1, -1):
			if idx == 0:
				tile = Game.hero_tile if Game.hero_tile != Vector2i(-1, -1) else map_data.hero_start
			else:
				tile = Game.town_tile if Game.town_tile != Vector2i(-1, -1) else map_data.hero_start

		# Nudge placement if tile is occupied by another player hero. A tile off
		# the map (a model from another scenario) starts from the nearest edge.
		tile = tile.clamp(Vector2i.ZERO, Vector2i(map_data.width - 1, map_data.height - 1))
		var visited := {tile: true}
		var queue := [tile]
		var nudge_tile := tile

		while not queue.is_empty():
			var curr: Vector2i = queue.pop_front()
			var is_occ := false
			for other_node in heroes:
				if other_node.tile == curr:
					is_occ = true
					break
			# A hero may stand on an object's action tile (e.g. the castle gate he
			# starts on) — same rule Pathfinder.find applies when leaving one.
			var is_pass := (map_data.is_water(curr) if model.travel_mode == &"sea" \
					else map_data.is_passable(curr.x, curr.y)) or curr == Game.town_tile \
					or (curr == tile and map_data.object_at_action(curr) != null)
			if not is_occ and is_pass:
				nudge_tile = curr
				break
			for offset in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var neighbor: Vector2i = curr + offset
				if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= map_data.width \
						or neighbor.y >= map_data.height:
					continue
				if not visited.has(neighbor):
					visited[neighbor] = true
					queue.push_back(neighbor)

		model.tile = nudge_tile

		var n := Hero.new()
		_add_actor(world, root_node, n)
		n.setup(model.hero_class, model.tile, map_data.tile_size, map_data, model.crest_idx)
		n.set_travel_mode(model.travel_mode, model.carried_boat_id)
		n.face_towards(model.tile + Direction.DELTAS.get(model.facing, Vector2i.RIGHT))
		n.max_move_points = Hero.calculate_model_max_move(model, map_data.objects, human.side)
		n.planned_dest = model.planned_dest
		if model.move_points >= 0:
			n.move_points = model.move_points
		else:
			n.move_points = n.max_move_points

		n.entered_tile.connect(on_entered_fn.bind(n))
		n.arrived.connect(on_arrived_fn)

		heroes.append(n)
		if fog != null:
			fog.reveal(model.tile, REVEAL_RADIUS + model.sight_bonus)

	var active_idx := human.active_hero
	if active_idx >= heroes.size():
		active_idx = 0
		human.active_hero = 0
	hero = heroes[active_idx]
	Game.player_hero = human.active()
	return hero

func set_active_hero(idx: int, hud: AdventureHud, input: AdventureInputController,
		cam: MapCamera, persist_fn: Callable, update_ui_fn: Callable) -> Hero:
	# Important 5: never switch away from a walking hero — the mover's step
	# costs/persistence are tracked per node but input/UI assume a settled hero.
	if hero != null and is_instance_valid(hero) and hero.is_moving():
		return hero
	if Game.state != null and not Game.state.players.is_empty():
		var human := Game.state.human()
		if idx >= 0 and idx < human.heroes.size():
			human.active_hero = idx
			if hud != null and hud.roster_panel != null:
				hud.roster_panel.set_selected_kind(1)
			if idx < heroes.size():
				hero = heroes[idx]
				Game.player_hero = human.active()
				if input != null:
					input.update_hero(hero)
				if hud != null:
					hud.set_active_hero(hero, human.active())
				if cam != null:
					cam.center_on(hero.center())
				persist_fn.call()
				update_ui_fn.call()
	return hero

func cycle_next_hero(cam: MapCamera, hud: AdventureHud, input: AdventureInputController,
		persist_fn: Callable, update_ui_fn: Callable) -> bool:
	if Game.state == null or Game.state.players.is_empty():
		return false
	var human := Game.state.human()
	if human.heroes.size() <= 1:
		if hero != null and cam != null:
			cam.center_on(hero.center())
			return true
		return false

	var curr_idx := human.active_hero
	var next_idx := -1
	for i in range(1, human.heroes.size()):
		var idx := (curr_idx + i) % human.heroes.size()
		if idx < heroes.size():
			var h_node: Hero = heroes[idx]
			if h_node.move_points > 0:
				next_idx = idx
				break

	if next_idx != -1:
		set_active_hero(next_idx, hud, input, cam, persist_fn, update_ui_fn)
		return true
	else:
		if hero != null and cam != null:
			cam.center_on(hero.center())
			return true
	return false

func heroes_may_still_move() -> bool:
	for hero_node in heroes:
		if is_instance_valid(hero_node) and hero_node.has_enough_movement_to_move():
			return true
	return false

func cycle_next_town(map_data: MapData, hud: AdventureHud, cam: MapCamera) -> bool:
	if Game.state == null or Game.state.players.is_empty() or map_data == null:
		return false
	var human := Game.state.human()
	if human.towns.is_empty():
		return false
	var curr_idx := human.active_town
	var next_idx := (curr_idx + 1) % human.towns.size()
	human.active_town = next_idx
	if "prefer_active_town" in Game:
		Game.prefer_active_town = true
	if hud != null and hud.roster_panel != null:
		hud.roster_panel.set_selected_kind(2)
		hud.roster_panel.refresh()
	var town_model: TownModel = human.towns[next_idx]
	if town_model == null:
		return false
	var town_obj := map_data.town_by_id(town_model.object_id)
	if town_obj == null and human.side >= 0:
		town_obj = map_data.town_of_side(human.side)
	if town_obj != null:
		Game.town_tile = town_obj.action_tile
		if cam != null:
			cam.center_on(Vector2(town_obj.tile * map_data.tile_size) + Vector2.ONE * (map_data.tile_size * 0.5))
		return true
	return false

func on_town_selected(town: TownObject, hud: AdventureHud,
		on_double_click_fn: Callable) -> void:
	if town == null or Game.state == null:
		return
	var human := Game.state.human()
	if human == null or town.owner != human.side:
		return
	var was_selected := false
	if hud != null and hud.roster_panel != null:
		was_selected = (hud.roster_panel.get_selected_kind() == 2 \
				and human.town != null and human.town.object_id == town.id)
	else:
		was_selected = (Game.town_tile == town.action_tile \
				and human.town != null and human.town.object_id == town.id)
	if was_selected:
		on_double_click_fn.call(town)
		return
	human.select_town(town.id)
	Game.town_tile = town.action_tile
	if "prefer_active_town" in Game:
		Game.prefer_active_town = true
	if hud != null and hud.roster_panel != null:
		hud.roster_panel.set_selected_kind(2)
		hud.roster_panel.refresh()

func on_town_double_clicked(town: TownObject, hud: AdventureHud,
		input: AdventureInputController, get_hero_at_fn: Callable,
		current_army_fn: Callable, persist_fn: Callable) -> void:
	if town == null or Game.state == null:
		return
	var human := Game.state.human()
	if human == null or town.owner != human.side:
		return
	human.select_town(town.id)
	Game.town_tile = town.action_tile
	if "prefer_active_town" in Game:
		Game.prefer_active_town = true
	if hud != null and hud.roster_panel != null:
		hud.roster_panel.set_selected_kind(2)
		hud.roster_panel.refresh()
	if input != null:
		input.cancel_route()
		input.clear_path()
	var visitor: HeroModel = null
	if hero != null and hero.tile == town.action_tile:
		persist_fn.call()
		visitor = Game.ensure_player_hero(current_army_fn.call())
	else:
		var hero_info: Dictionary = get_hero_at_fn.call(town.action_tile)
		if not hero_info.is_empty() and bool(hero_info.get("is_own", false)):
			visitor = hero_info.get("model") as HeroModel
	Game.to_town(visitor)

func on_hero_double_clicked(current_army_fn: Callable) -> void:
	if hero != null:
		Game.to_hero(Game.ensure_player_hero(current_army_fn.call()))

func on_hero_selected(hud: AdventureHud) -> void:
	if hud != null and hud.roster_panel != null:
		hud.roster_panel.set_selected_kind(1)
		hud.roster_panel.refresh()

func on_roster_town_selected(map_data: MapData, hud: AdventureHud, cam: MapCamera) -> bool:
	if Game.state == null or Game.state.players.is_empty() or map_data == null:
		return false
	if hud != null and hud.turn_transition_panel != null \
			and hud.turn_transition_panel.mode == TurnTransitionPanel.Mode.NEW_DAY:
		hud.hide_turn_transition()
	var human := Game.state.human()
	if human.towns.is_empty() or human.town == null:
		return false
	if "prefer_active_town" in Game:
		Game.prefer_active_town = true
	var t: TownObject = map_data.town_by_id(human.town.object_id)
	if t == null and human.side >= 0:
		t = map_data.town_of_side(human.side)
	if t != null:
		Game.town_tile = t.action_tile
		if cam != null:
			var town_world_pos = Vector2(t.action_tile.x * map_data.tile_size + 16, t.action_tile.y * map_data.tile_size + 16)
			cam.center_on(town_world_pos)
		return true
	return false

func on_open_selected(hud: AdventureHud, current_army_fn: Callable) -> void:
	if hud != null and hud.roster_panel != null and hud.roster_panel.get_selected_kind() == 2:
		if "prefer_active_town" in Game:
			Game.prefer_active_town = true
		Game.to_town()
		return
	if hero != null:
		Game.to_hero(Game.ensure_player_hero(current_army_fn.call()))

func persist_hero(active_hero: Hero = null) -> void:
	var target := active_hero if active_hero != null else hero
	if target != null:
		Game.hero_tile = target.tile
		Game.hero_move_points = target.move_points
		if Game.state != null and not Game.state.players.is_empty():
			var active_model := Game.state.human().active()
			if active_model != null:
				active_model.tile = target.tile
				active_model.planned_dest = target.planned_dest
				active_model.move_points = target.move_points
				active_model.travel_mode = target.travel_mode
				active_model.carried_boat_id = target.carried_boat_id
				active_model.facing = target.get_direction()

func persist_mover(node: Hero, active_hero: Hero = null) -> void:
	var primary := active_hero if active_hero != null else hero
	if node == primary:
		persist_hero(primary)
		return
	var idx := heroes.find(node)
	if idx >= 0 and Game.state != null and not Game.state.players.is_empty():
		var human := Game.state.human()
		if idx < human.heroes.size():
			var model: HeroModel = human.heroes[idx]
			model.tile = node.tile
			model.planned_dest = node.planned_dest
			model.move_points = node.move_points
			model.travel_mode = node.travel_mode
			model.carried_boat_id = node.carried_boat_id
			model.facing = node.get_direction()

func get_hero_at(tile: Vector2i, fog: FogLayer, ai: AITurnRunner) -> Dictionary:
	if fog != null and not fog.is_explored(tile):
		return {}
	var active_side := Game.state.active_player_side if Game.state != null else 0
	if Game.state != null:
		var active_player := Game.state.player_of(active_side)
		if active_player != null:
			for h: HeroModel in active_player.heroes:
				if h.tile == tile:
					return {"model": h, "side": active_side, "is_own": true}
	elif hero != null and hero.tile == tile and Game.player_hero != null:
		return {"model": Game.player_hero, "side": active_side, "is_own": true}
	if ai != null:
		var side := ai.side_at(tile)
		if side >= 0:
			var model := ai.hero_model_at(tile)
			if model != null:
				return {"model": model, "side": side, "is_own": (side == active_side)}
	if Game.state != null:
		for player: PlayerState in Game.state.players:
			if player.side != active_side:
				for h: HeroModel in player.heroes:
					if h.tile == tile:
						return {"model": h, "side": player.side, "is_own": false}
	return {}

func get_town_at(tile: Vector2i, map_data: MapData, fog: FogLayer) -> TownObject:
	if map_data == null or (fog != null and not fog.is_explored(tile)):
		return null
	return map_data.town_at(tile)

func occupied_hero_tiles(ai: AITurnRunner) -> Array:
	var out: Array = []
	for h in heroes:
		if is_instance_valid(h):
			out.append(h.tile)
	if ai != null:
		for ai_node: Hero in ai.all_heroes():
			out.append(ai_node.tile)
	return out

func side_for_hero_node(node: Hero, ai: AITurnRunner) -> int:
	var idx := heroes.find(node)
	if idx >= 0:
		return Game.state.human().side
	if ai != null and Game.state != null:
		for p: PlayerState in Game.state.players:
			if p.side == Game.state.active_player_side:
				continue
			if ai.heroes_for_side(p.side).has(node):
				return p.side
	return 0

func teleport_hero(tile: Vector2i, map_data: MapData, fog: FogLayer,
		cam: MapCamera, input: AdventureInputController,
		walk_prev_by_node: Dictionary, update_ui_fn: Callable) -> void:
	if hero == null:
		return
	if input != null:
		input.cancel_route()
	walk_prev_by_node.erase(hero)
	hero.tile = tile
	hero.position = Vector2(tile.x * map_data.tile_size, tile.y * map_data.tile_size)
	if fog != null:
		var model: HeroModel = Game.state.human().active() if Game.state != null else Game.player_hero
		fog.reveal(tile, REVEAL_RADIUS + (model.sight_bonus if model != null else 0))
	if cam != null:
		cam.center_on(hero.center())
	persist_hero(hero)
	update_ui_fn.call()

func _add_actor(world: AdventureWorldRenderer, root_node: Node2D, actor: Node2D) -> void:
	if world != null:
		world.add_actor(actor)
	elif root_node != null:
		root_node.add_child(actor)
