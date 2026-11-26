class_name NavalPlanner
extends RefCounted

## Strategic Dijkstra over (tile, travel mode, carried boat). Unlike the human
## click path this may include both boarding and disembarking in one plan; the
## turn runner stops at each transition and resumes on a later day.

const STEP_DELTAS: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 0), Vector2i(1, -1),
	Vector2i(0, -1), Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1),
]

static func find(grid: PassabilityGrid, map: MapData, state: GameState,
		from: Vector2i, to: Vector2i, mode: StringName = &"land",
		carried_boat_id: int = -1, hero_class: String = "") -> Array:
	if not grid.is_in_boundsv(from) or not grid.is_in_boundsv(to):
		return []
	if mode == &"land" and carried_boat_id < 0 and not map.is_water(to) \
			and (state == null or state.boats.is_empty()):
		var land_path := Pathfinder.find(grid, from, to, map, hero_class)
		if land_path.size() >= 2:
			var out: Array = []
			for step_tile in land_path:
				out.append({"tile": step_tile, "mode": &"land", "boat_id": -1, "transitions": 0, "kind": TravelRules.MOVE})
			return out
		return []

	var boats_by_tile: Dictionary = {}
	if state != null and not state.boats.is_empty():
		for b: BoatState in state.boats:
			if not boats_by_tile.has(b.tile):
				boats_by_tile[b.tile] = b

	var start_key := _encode_key(from, mode, carried_boat_id, 0)
	var best: Dictionary = {start_key: 0}
	var parent: Dictionary = {}
	var step_kinds: Dictionary = {}
	var sequence := 0
	var heap := Pathfinder.Heap.new()
	heap.push(0, sequence, start_key)

	while not heap.is_empty():
		heap.pop()
		var cost := heap.pop_cost
		var key := heap.pop_node
		if cost != int(best.get(key, 1 << 30)):
			continue
		var tile := _decode_tile(key)
		var current_mode := _decode_mode(key)
		var current_boat := _decode_boat_id(key)
		var transitions := _decode_transitions(key)
		if tile == to:
			return _reconstruct(parent, step_kinds, key)
		if tile != from and grid.terminal_at(tile) != null:
			continue
		for d: Vector2i in STEP_DELTAS:
			var next: Vector2i = tile + d
			var kind := TravelRules.step_kind(map, grid, state,
					current_mode, tile, next)
			if kind == TravelRules.INVALID:
				continue
			if kind == TravelRules.ENGAGE and next != to:
				continue
			var next_mode := current_mode
			var next_boat := current_boat
			var next_transitions := transitions
			if kind == TravelRules.BOARD:
				if transitions >= 2:
					continue
				var free_boat: BoatState = boats_by_tile.get(next)
				if free_boat == null:
					continue
				next_mode = &"sea"
				next_boat = free_boat.id
				next_transitions += 1
			elif kind == TravelRules.DISEMBARK:
				if transitions >= 2:
					continue
				next_mode = &"land"
				next_boat = -1
				next_transitions += 1
			var next_cost := cost + TravelRules.step_cost(
					kind, tile, next, map, hero_class)
			# Boarding zeroes the movement left (heroes.exe 0xb2770) and landing
			# ends the day too, so a transition costs a whole day. Charging it a
			# single point let board-then-land beat a two-step walk ashore.
			if not TravelRules.is_walk(kind):
				next_cost += Hero.MAX_MOVE
			var next_key := _encode_key(next, next_mode, next_boat, next_transitions)
			if next_cost >= int(best.get(next_key, 1 << 30)):
				continue
			best[next_key] = next_cost
			parent[next_key] = key
			step_kinds[next_key] = kind
			sequence += 1
			heap.push(next_cost, sequence, next_key)
	return []

static func _encode_key(tile: Vector2i, mode: StringName, boat_id: int,
		transitions: int) -> int:
	var mode_bit: int = 1 if mode == &"sea" else 0
	var boat_code: int = (boat_id + 1) if boat_id >= -1 else 0
	return (tile.x & 0xFFF) | ((tile.y & 0xFFF) << 12) | (mode_bit << 24) | ((transitions & 0x7) << 25) | ((boat_code & 0xFFFFFFF) << 28)

static func _decode_tile(key: int) -> Vector2i:
	return Vector2i(key & 0xFFF, (key >> 12) & 0xFFF)

static func _decode_mode(key: int) -> StringName:
	return &"sea" if ((key >> 24) & 1) != 0 else &"land"

static func _decode_transitions(key: int) -> int:
	return (key >> 25) & 0x7

static func _decode_boat_id(key: int) -> int:
	return ((key >> 28) & 0xFFFFFFF) - 1

static func _reconstruct(parent: Dictionary, step_kinds: Dictionary, key: int) -> Array:
	var out: Array = []
	var current := key
	while true:
		out.push_front({
			"tile": _decode_tile(current),
			"mode": _decode_mode(current),
			"boat_id": _decode_boat_id(current),
			"transitions": _decode_transitions(current),
			"kind": step_kinds.get(current, TravelRules.MOVE),
		})
		if not parent.has(current):
			break
		current = int(parent[current])
	return out
