class_name UltimatePlacement
extends RefCounted

## The Ultimate Artifact a new game buries when the scenario names none, by
## the original's rule (data/artifacts/ultimate_placement.json). Returns
## {"tile": [x, y], "artifact": id}, or {} when the map has no free cell.

const RULES_PATH := "res://data/artifacts/ultimate_placement.json"
const MAX_TRIES := 20000

static func roll(map: MapData, rng: RandomNumberGenerator, human_start: Vector2i,
		single_human: bool) -> Dictionary:
	var r: Dictionary = JsonFile.read_dict(RULES_PATH)
	var lo := int(r.get("min", 9))
	var hi_x := mini(int(r.get("max", 62)), map.width - 1)
	var hi_y := mini(int(r.get("max", 62)), map.height - 1)
	if hi_x < lo or hi_y < lo:
		lo = 0
	var dice: Array = r.get("distance_dice", [])
	var artifacts: Array = r.get("artifacts", [])
	var painted := {}
	for part: Dictionary in map.render_parts:
		var t: Array = part.get("tile", [])
		if t.size() == 2:
			painted[Vector2i(int(t[0]), int(t[1]))] = true
	var town_footprints := town_footprint_tiles(map)
	var accessible := accessible_tiles(map, human_start)
	var fallback := Vector2i(-1, -1)
	for _i in MAX_TRIES:
		var tile := Vector2i(rng.randi_range(lo, hi_x), rng.randi_range(lo, hi_y))
		if not accessible.is_empty() and not accessible.has(tile):
			continue
		if not free_cell(map, tile, painted, town_footprints):
			continue
		if fallback.x < 0:
			fallback = tile
		if single_human and human_start.x >= 0:
			var reach := 0
			for die: Variant in dice:
				reach += rng.randi_range(1, int(die))
			var d := human_start - tile
			if reach >= absi(d.x) + absi(d.y):
				continue
		return _result(tile, rng, artifacts)
	return {} if fallback.x < 0 else _result(fallback, rng, artifacts)

## Multi-tile footprints and perimeter for all towns/castles.
## Castles occupy 4 tiles wide, 3 tall: [t.x-2..t.x+1, t.y-2..t.y].
## A perimeter buffer ensures the artifact is never buried directly against
## castle walls or the entrance.
static func town_footprint_tiles(map: MapData, buffer: int = 1) -> Dictionary:
	var footprints := {}
	if map == null:
		return footprints
	for o: MapObject in map.objects:
		if o.type == "town" or o is TownObject:
			for cx in range(o.tile.x - 2 - buffer, o.tile.x + 2 + buffer):
				for cy in range(o.tile.y - 2 - buffer, o.tile.y + 1 + buffer):
					footprints[Vector2i(cx, cy)] = true
	return footprints

## Reachable land tiles from player starting positions or towns.
static func accessible_tiles(map: MapData, human_start: Vector2i) -> Dictionary:
	var accessible := {}
	if map == null:
		return accessible
	var seeds: Array[Vector2i] = []
	if human_start.x >= 0 and human_start.y >= 0 and map.is_land(human_start):
		seeds.append(human_start)
	for p: Dictionary in map.players:
		var h_start: Vector2i = p.get("hero_start", Vector2i(-1, -1))
		if h_start.x >= 0 and h_start.y >= 0 and map.is_land(h_start):
			seeds.append(h_start)
	for o: MapObject in map.objects:
		if o.type == "town" or o is TownObject:
			for step: Vector2i in [Vector2i(0, 1), Vector2i(-1, 1), Vector2i(1, 1), Vector2i.ZERO]:
				var t := o.tile + step
				if map.is_land(t) and (map.passable.is_empty() or map.is_passable(t.x, t.y)):
					seeds.append(t)
					break
	var queue: Array[Vector2i] = []
	for s: Vector2i in seeds:
		if not accessible.has(s):
			accessible[s] = true
			queue.append(s)
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nxt := cur + Vector2i(dx, dy)
				if nxt.x < 0 or nxt.y < 0 or nxt.x >= map.width or nxt.y >= map.height:
					continue
				if accessible.has(nxt):
					continue
				if not map.is_land(nxt):
					continue
				if not map.passable.is_empty() and not map.is_passable(nxt.x, nxt.y):
					continue
				accessible[nxt] = true
				queue.append(nxt)
	return accessible

## Land with nothing painted on it and no object standing there.
static func free_cell(map: MapData, tile: Vector2i, painted: Dictionary, town_footprints: Dictionary = {}) -> bool:
	if tile.x < 0 or tile.y < 0 or tile.x >= map.width or tile.y >= map.height:
		return false
	if map.is_water(tile) or painted.has(tile) or town_footprints.has(tile):
		return false
	if not map.passable.is_empty() and not map.is_passable(tile.x, tile.y):
		return false
	for o: MapObject in map.objects:
		if (o.type == "town" or o is TownObject) and tile.x >= o.tile.x - 2 and tile.x <= o.tile.x + 1 \
				and tile.y >= o.tile.y - 2 and tile.y <= o.tile.y:
			return false
		if o.tile == tile or o.action_tile == tile or o.interaction_tiles().has(tile):
			return false
	return true

static func _result(tile: Vector2i, rng: RandomNumberGenerator, artifacts: Array) -> Dictionary:
	var id := String(artifacts[rng.randi_range(0, artifacts.size() - 1)]) if not artifacts.is_empty() else "sword_of_power"
	return {"tile": [tile.x, tile.y], "artifact": id}
