class_name PassabilityGrid
extends RefCounted

## Per-tile entry-direction masks.
## Bit d set on tile T = T may be entered from its neighbor in direction d
## (Direction enum). Built once at map load; footprints never change at
## runtime, and consumption is read live via terminal_at().

var map: MapData
var masks: PackedInt32Array = PackedInt32Array()
var terrain_costs: PackedByteArray = PackedByteArray()

var _action_objects: Dictionary = {}   # Vector2i interaction tile -> MapObject
var _neutral_stacks: Array[NeutralStack] = [] # live-read guards; consumed state may change
var _dynamic_solid: Dictionary = {}    # Vector2i -> true (occupied hero tiles)
var _source_masked: Dictionary = {}    # Vector2i -> true (mask also controls exits)
## Oasis cells on a native map: the route searches refuse a step in from above.
var no_entry_from_above: Dictionary = {}

var _cached_guard_zones: Dictionary = {}
var _cached_stack_armed: Array[bool] = []
var _cached_native_consumed: Array[bool] = []
var _native_zone_objects: Array[MapObject] = []
var _cached_native_zones: bool = false
var _guard_zones_dirty: bool = true
var _guard_revision: int = 0

func _init(p_map: MapData) -> void:
	map = p_map
	rebuild()

func rebuild() -> void:
	var cat := ObjectCatalog.shared()
	_action_objects.clear()
	_neutral_stacks.clear()
	_source_masked.clear()
	_dynamic_solid.clear()
	no_entry_from_above.clear()
	invalidate_guard_zones()
	for o: MapObject in map.objects:
		for action: Vector2i in o.interaction_tiles():
			_action_objects[action] = o
			if map.native_zones and o.type == "oasis":
				no_entry_from_above[action] = true
		if o is NeutralStack:
			_neutral_stacks.append(o as NeutralStack)
	masks.resize(map.width * map.height)
	terrain_costs.resize(map.width * map.height)
	# Pass 1: terrain/footprint blocks, then per-object entry masks. An action
	# tile inside its own footprint (e.g. the town gate) is OVERRIDDEN back to
	# enterable — it is a path terminal, same rule the old solid/clear dance kept.
	for y in map.height:
		for x in map.width:
			var flat := y * map.width + x
			masks[flat] = Direction.MASK_ALL if map.is_passable(x, y) else 0
			var t := map.terrain_at(Vector2i(x, y))
			match t:
				"snow", "swamp":
					terrain_costs[flat] = 6
				"desert":
					terrain_costs[flat] = 8
				_:
					terrain_costs[flat] = 4
	for tile: Vector2i in map.passability_masks:
		if is_in_boundsv(tile):
			masks[tile.y * map.width + tile.x] = int(map.passability_masks[tile])
			_source_masked[tile] = true
	for o: MapObject in map.objects:
		var m := Direction.MASK_ALL
		var entry := o.entry_rule if o.entry_rule != "" else cat.entry(o.type)
		match entry:
			"building": m = Direction.MASK_BUILDING
			"horizontal": m = Direction.MASK_HORIZONTAL
		for off: Vector2i in cat.entry_tiles(o.type):
			var tile := o.tile + off
			if is_in_boundsv(tile):
				var flat := tile.y * map.width + tile.x
				masks[flat] &= m
				_source_masked[tile] = true
		# The entrance leaves the way it is entered: a hero on a sawmill's
		# door steps off to the sides or below, never up through the building.
		for action: Vector2i in o.interaction_tiles():
			if is_in_boundsv(action):
				masks[action.y * map.width + action.x] = m
				if m != Direction.MASK_ALL:
					_source_masked[action] = true
	# Pass 2: tall rule — a tall sprite on (x,y) kills
	# the diagonal entries that would cut over its top corners.
	for collision: Dictionary in map.collision:
		if not bool(collision.get("tall", false)):
			continue
		var ta: Array = collision.get("tile", [])
		if ta.size() != 2:
			continue
		_kill_tall_corners(Vector2i(int(ta[0]), int(ta[1])))
	# Directly-constructed unit-test maps have no serialized v3 collision list.
	# Production maps never take this path because the loader requires collision.
	if map.collision.is_empty():
		for o: MapObject in map.objects:
			if not cat.tall(o.type):
				continue
			for off: Vector2i in cat.footprint(o.type):
				_kill_tall_corners(o.tile + off)

func _kill_tall_corners(t: Vector2i) -> void:
	_clear_bit(Vector2i(t.x + 1, t.y), Direction.NW)   # no SE-diagonal over our top-right
	_clear_bit(Vector2i(t.x - 1, t.y), Direction.NE)   # no SW-diagonal over our top-left

func _clear_bit(t: Vector2i, d: int) -> void:
	if is_in_boundsv(t):
		masks[t.y * map.width + t.x] &= ~Direction.bit(d)

func is_in_boundsv(t: Vector2i) -> bool:
	return t.x >= 0 and t.x < map.width and t.y >= 0 and t.y < map.height

func entry_mask(t: Vector2i) -> int:
	if not is_in_boundsv(t):
		return 0
	var left := _left_mask(t)
	return left if left >= 0 else masks[t.y * map.width + t.x]

## heroes.exe 0xb46d8: an object taken off a cell that has a second class
## leaves it blocked (0) or, its layer-2 sprite dropped to layer 1, entered
## and left from the sides and below. -1 while the object stands, and for
## every other cell.
func _left_mask(t: Vector2i) -> int:
	if map.after_removal.is_empty() or not map.after_removal.has(t):
		return -1
	var gone: MapObject = _action_objects.get(t)
	if gone == null or not gone.consumed:
		return -1
	return 0 if map.after_removal[t] else Direction.MASK_BUILDING

## Dynamic runtime blocks (tiles occupied by other heroes). Terrain/footprint
## solidity lives in the masks; this only layers temporary overrides on top.
func set_point_solid(t: Vector2i, solid: bool = true) -> void:
	if solid:
		if not _dynamic_solid.has(t):
			_dynamic_solid[t] = true
			invalidate_guard_zones()
	else:
		if _dynamic_solid.has(t):
			_dynamic_solid.erase(t)
			invalidate_guard_zones()

func has_dynamic_solids() -> bool:
	return not _dynamic_solid.is_empty()

func guard_revision() -> int:
	return _guard_revision

func invalidate_guard_zones() -> void:
	_guard_zones_dirty = true
	_guard_revision += 1

func is_point_solid(t: Vector2i) -> bool:
	return _dynamic_solid.has(t) or entry_mask(t) == 0

## Stable cache key for the temporary hero-occupancy overrides used while
## building a route field. Callers set the same blockers around each query;
## sorting prevents Dictionary iteration order from invalidating that cache.
func dynamic_solid_signature() -> String:
	var tiles: Array = _dynamic_solid.keys()
	tiles.sort_custom(func(a: Vector2i, b: Vector2i):
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	var parts: PackedStringArray = []
	for tile: Vector2i in tiles:
		parts.append("%d,%d" % [tile.x, tile.y])
	return ";".join(parts)

## One adjacent step from -> to. Existing terrain/object masks encode destination
## entry restrictions. Explicit native passability overrides additionally encode
## the source tile's open exit sides; checking that side prevents paths from
## cutting out through an obstacle's closed top edge (Claw's tree corridor).
## When `check_source` is false, only destination entry is checked, matching
## heroes.exe 0xa89f2 (used by 0x6b71d GOODADJ).
## `onto_hero` asks whether the step would be legal were `to` free: a route
## may end on a hero's cell, by the same entry rules as any other cell.
func can_enter(from: Vector2i, to: Vector2i, check_source: bool = true, onto_hero := false) -> bool:
	if not is_in_boundsv(from) or not is_in_boundsv(to):
		return false
	if _dynamic_solid.has(to) and not onto_hero:
		return false
	var d := to - from
	if maxi(absi(d.x), absi(d.y)) != 1 or d == Vector2i.ZERO:
		return false
	var move_dir := Direction.from_delta(d.x, d.y)
	var entry_dir := Direction.reflect(move_dir)
	if check_source and (_source_masked.has(from) or _left_mask(from) > 0) \
			and entry_mask(from) & Direction.bit(move_dir) == 0:
		return false
	# heroes.exe 0x87a98: no step leaves a cell holding a standing sprite to
	# the N, NE or NW, walk-on objects included, until a pickup takes it.
	if check_source and d.y < 0 and map.native_zones and map.zone_sprites.has(from):
		var gone: MapObject = _action_objects.get(from)
		if not (gone != null and gone.consumed):
			return false
	return entry_mask(to) & Direction.bit(entry_dir) != 0

## The live object whose interaction tile is t. Consumed objects disappear from
## pathing immediately (read live; no rebuild/unblock call is required).
func action_object_at(t: Vector2i) -> MapObject:
	var o: MapObject = _action_objects.get(t)
	if o != null and o.consumed:
		return null
	return o

## Whether a stack on `from` guards its neighbour `t`. Native maps follow
## heroes.exe 0x84138: every neighbour on the stack's land or water, except
## a cell below it holding a layer-1 sprite. A pickup taken, or a stack
## beaten, takes its sprite with it. Elsewhere a wall or one-way boundary
## blocks the reach: protection needs a step across the edge both ways.
func _guards(from: Vector2i, t: Vector2i) -> bool:
	if map.native_zones:
		var gone: MapObject = _action_objects.get(t)
		if t.y > from.y and map.zone_sprites.has(t) \
				and (not (gone != null and gone.consumed) or _left_mask(t) > 0):
			return false
		return map.is_water(t) == map.is_water(from)
	return can_enter(t, from) and can_enter(from, t)

func _is_guard_cache_valid() -> bool:
	if _guard_zones_dirty:
		return false
	if _cached_stack_armed.size() != _neutral_stacks.size():
		return false
	if _cached_native_zones != (map != null and map.native_zones):
		return false
	for i in _neutral_stacks.size():
		if _neutral_stacks[i].is_armed() != _cached_stack_armed[i]:
			return false
	for i in _native_zone_objects.size():
		if _native_zone_objects[i].consumed != _cached_native_consumed[i]:
			return false
	return true

func _rebuild_guard_zones() -> void:
	_cached_guard_zones.clear()
	_cached_stack_armed.clear()
	_cached_native_consumed.clear()
	_native_zone_objects.clear()
	_cached_native_zones = map != null and map.native_zones

	for stack: NeutralStack in _neutral_stacks:
		var armed := stack.is_armed()
		_cached_stack_armed.append(armed)
		if not armed:
			continue
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var t := stack.action_tile + Vector2i(dx, dy)
				if (dx == 0 and dy == 0) or _cached_guard_zones.has(t) or not is_in_boundsv(t):
					continue
				if _guards(stack.action_tile, t):
					_cached_guard_zones[t] = stack

	if map.native_zones:
		for stack: NeutralStack in _neutral_stacks:
			if not stack.is_armed():
				continue
			for dy in range(1, 2):
				for dx in range(-1, 2):
					var t := stack.action_tile + Vector2i(dx, dy)
					if map.zone_sprites.has(t):
						var obj: MapObject = _action_objects.get(t)
						if obj != null and not _native_zone_objects.has(obj):
							_native_zone_objects.append(obj)
							_cached_native_consumed.append(obj.consumed)

	_guard_zones_dirty = false

## Every cell an armed stack guards, cell -> stack, cached and invalidated
## when stacks or hero solid overrides change.
func guard_zones() -> Dictionary:
	if not _is_guard_cache_valid():
		_rebuild_guard_zones()
	return _cached_guard_zones

## An armed wandering stack controls every reachable neighboring tile. Entering
## one of those eight cells makes the stack attack, so the cell may END a route
## but must never be used as a corridor. Exact stack tiles are excluded here;
## action_object_at() owns those.
func protecting_stack_at(t: Vector2i) -> NeutralStack:
	if not is_in_boundsv(t):
		return null
	return guard_zones().get(t)

## A path may END on an action or monster-controlled tile, never pass through
## it. This is the HOMM1 neutral-monster control-zone rule. A town's gate is
## no exception: entering a town, own or not, is always the route's goal.
func terminal_at(t: Vector2i) -> MapObject:
	var o := action_object_at(t)
	return o if o != null else protecting_stack_at(t)

## terminal_at() with the guard zones precomputed by guard_zones().
func terminal_in(t: Vector2i, zones: Dictionary) -> MapObject:
	var o := action_object_at(t)
	return o if o != null else zones.get(t)
