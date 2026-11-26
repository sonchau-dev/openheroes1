class_name AdventureSpells

## Map-spell resolver (KB spells.md 5.2). Pure decision logic — the adventure
## map applies results (teleport, overlay, dialogs) and spends the charge on
## anything except {"kind": "fail"}.

static func resolve(spell_id: String, ctx: Dictionary) -> Dictionary:
	var spell := SpellData.get_spell(spell_id)
	match String(spell.get("kind", "")):
		"view":
			return {"kind": "view", "category": spell_id.trim_prefix("view_")}
		"travel":
			return _travel(spell_id, ctx)
		"info":
			return _identify(ctx)
		"summon":
			return _summon_boat(ctx)
	return {"kind": "fail", "text": "Cannot cast that here."}

static func _summon_boat(ctx: Dictionary) -> Dictionary:
	var hero: HeroModel = ctx.get("hero") as HeroModel
	if hero != null and hero.travel_mode == &"sea":
		return {"kind": "fail", "text": "Summon Boat failed!!!"}
	var state: GameState = ctx.get("state") as GameState
	var map: MapData = ctx.get("map") as MapData
	if state == null or map == null:
		return {"kind": "fail", "text": "Summon Boat failed!!!"}
	var here: Vector2i = ctx.get("hero_tile", Vector2i(-1, -1))
	var owner := int(ctx.get("side", 0))
	var candidates: Array = []
	for boat: BoatState in state.boats:
		if boat.owner != owner:
			continue
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var dest := here + Vector2i(dx, dy)
				if not map.is_water(dest) or state.boat_at(dest) != null:
					continue
				candidates.append({
					"boat_id": boat.id,
					"dest": dest,
					"distance": boat.tile.distance_squared_to(dest),
				})
	if candidates.is_empty():
		return {"kind": "fail", "text": "Summon Boat failed!!!"}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.distance) != int(b.distance):
			return int(a.distance) < int(b.distance)
		if int(a.boat_id) != int(b.boat_id):
			return int(a.boat_id) < int(b.boat_id)
		var ad: Vector2i = a.dest
		var bd: Vector2i = b.dest
		return ad.y < bd.y or (ad.y == bd.y and ad.x < bd.x))
	return {"kind": "summon_boat", "boat_id": int(candidates[0].boat_id),
		"dest": candidates[0].dest}

static func _travel(spell_id: String, ctx: Dictionary) -> Dictionary:
	if spell_id in ["dimension_door", "town_portal"]:
		if ctx.has("target_tile"):
			var dest: Vector2i = ctx.target_tile
			if not is_valid_dimension_door_dest(dest, ctx):
				return {"kind": "fail", "text": "Dimension Door failed!!!"}
			return {"kind": "teleport", "dest": dest}
		if spell_id == "dimension_door" or not ctx.has("friendly_towns") or ctx.get("friendly_towns", []).is_empty():
			return {"kind": "target_dimdoor"}

	# town_gate / legacy town_portal:
	var hero = ctx.get("hero")
	var is_sailing := false
	if hero != null:
		if "travel_mode" in hero and hero.travel_mode == &"sea":
			is_sailing = true
		elif "in_boat" in hero and hero.in_boat:
			is_sailing = true
	if is_sailing:
		return {"kind": "fail", "text": "No available town.  Town Gate Failed!!!"}

	var here: Vector2i = ctx.get("hero_tile", Vector2i.ZERO)
	var owned_towns: Array = []
	if ctx.has("owned_towns"):
		owned_towns = ctx.get("owned_towns", []).duplicate()
	elif ctx.has("friendly_towns"):
		owned_towns = ctx.get("friendly_towns", []).duplicate()
	elif ctx.has("objects"):
		var side: int = int(ctx.get("side", 0))
		for o in ctx.get("objects", []):
			if o is TownObject and o.owner == side:
				owned_towns.append((o as TownObject).action_tile)

	# Exclude the town gate tile the hero is already standing on
	owned_towns.erase(here)

	if owned_towns.is_empty():
		return {"kind": "fail", "text": "No available town.  Town Gate Failed!!!" if spell_id == "town_gate" else "You have no available town."}

	if spell_id == "town_gate":
		var sorted_towns := owned_towns.duplicate()
		sorted_towns.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da: int = absi(a.x - here.x) + absi(a.y - here.y)
			var db: int = absi(b.x - here.x) + absi(b.y - here.y)
			return da < db)
		var nearest: Vector2i = sorted_towns[0]
		var occupied: Array = ctx.get("occupied_tiles", [])
		if nearest in occupied:
			return {"kind": "fail", "text": "Nearest town occupied.  Town Gate Failed!!!"}
		return {"kind": "teleport", "dest": nearest}

	if owned_towns.size() == 1:
		return {"kind": "teleport", "dest": owned_towns[0]}
	return {"kind": "pick_town", "towns": owned_towns}

## The cast (heroes.exe 0x969a3): a clickable cell whose land/water matches the hero.
static func is_valid_dimension_door_dest(dest: Vector2i, ctx: Dictionary) -> bool:
	if not is_dimension_door_click_target(dest, ctx):
		return false
	var map: MapData = ctx.get("map") as MapData
	if map != null:
		var hero = ctx.get("hero")
		var is_sailing := bool(hero.in_boat) if hero != null and "in_boat" in hero else false
		var on_water := map.is_water(dest)
		if is_sailing and not on_water:
			return false
		if not is_sailing and on_water:
			return false
	return true

## The target click handler (heroes.exe 0xa39cc): it ignores a click on a blocked
## cell or one whose B8 has bit 0x80 (an interactive object or hero). No fog test:
## neither it nor the cast reads the explored bits.
static func is_dimension_door_click_target(dest: Vector2i, ctx: Dictionary) -> bool:
	var map: MapData = ctx.get("map") as MapData
	if map != null:
		if dest.x < 0 or dest.x >= map.width or dest.y < 0 or dest.y >= map.height:
			return false
		if not map.is_passable(dest.x, dest.y):
			return false
		if map.active_object_at_action(dest) != null:
			return false
	var occupied: Array = ctx.get("occupied_tiles", [])
	return not dest in occupied

static func _identify(ctx: Dictionary) -> Dictionary:
	var state: GameState = ctx.get("state") as GameState
	var side: int = int(ctx.get("side", 0))
	var player: PlayerState = ctx.get("player") as PlayerState
	if player == null and state != null:
		player = state.player_of(side)
	if player != null and player.identify_hero_active:
		return {"kind": "fail", "text": "This spell is already in effect."}

	var raw_players = ctx.get("players", state.players if state != null else [])
	var players: Array = raw_players if raw_players is Array else []
	var lines: Array = []
	var has_enemy_heroes := false
	for p in players:
		if p is PlayerState:
			if player != null and p == player:
				continue
			if player == null and p.side == side and not p.is_ai:
				continue
		var heroes: Array = []
		if p is PlayerState:
			if not p.heroes.is_empty():
				heroes = p.heroes
			elif p.hero_model != null:
				heroes = [p.hero_model]
		for h in heroes:
			if h is HeroModel:
				has_enemy_heroes = true
				var army_desc := ""
				if h.army != null and not h.army.slots.is_empty():
					var parts: Array[String] = []
					for s: Dictionary in h.army.slots:
						if int(s.get("count", 0)) > 0:
							parts.append("%d %s" % [int(s.get("count", 0)), String(s.get("unit", "")).capitalize()])
					if not parts.is_empty():
						army_desc = "  [" + ", ".join(parts) + "]"
				lines.append("%s  A:%d D:%d P:%d K:%d%s" %
					[h.hero_name, h.effective_attack(), h.effective_defense(),
					h.effective_spell_power(), h.effective_knowledge(), army_desc])

	if not has_enemy_heroes and ctx.has("players"):
		return {"kind": "fail", "text": "No enemy heroes to identify."}

	return {
		"kind": "identify_hero",
		"text": "Enemy Heroes are now fully identifiable.",
		"lines": lines,
	}
