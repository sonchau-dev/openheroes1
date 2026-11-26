class_name MapData
extends RefCounted

## Source-agnostic adventure-map model. Every map loader produces one of these.

var name: String = ""
var description: String = ""
var map_difficulty: int = 0
var size: int = 0
var supported_human_counts: Array[int] = []
var width: int = 0
var height: int = 0
var tile_size: int = 32
var grid: Array = []          # Array[Array[int]] indexed [y][x], ground32 tile indices
var passable: Array = []      # Array[Array[bool]] indexed [y][x]
var hero_start: Vector2i = Vector2i.ZERO
var objects: Array = []:
	set(val):
		objects = val
		_indexes_dirty = true

var _action_index: Dictionary = {}    # Vector2i -> MapObject (first-inserted wins)
var _objects_by_id: Dictionary = {}   # int -> MapObject (first-inserted wins)
var _towns_by_tile: Dictionary = {}   # Vector2i -> TownObject (first-inserted wins)
var _towns: Array[TownObject] = []    # live list of all TownObjects in objects
var _indexes_dirty: bool = true
var _indexed_size: int = -1
var _indexed_first: Variant = null
var _indexed_last: Variant = null
var players: Array = []       # Array[Dictionary]: {side, human, hero_start: Vector2i, color}
## Authored free boats placed when a new run begins. Each entry is
## {tile: Vector2i, owner: authored/runtime side, direction: Direction value}.
var starting_boats: Array[Dictionary] = []

# --- v3 schema: paint, collision, and interaction semantics are independent. ---
var version: int = 3
var seed: int = 1337
var terrain_chars: Array = []      # Array[String]; authored terrain rows (saver source)
var tile_overrides: Dictionary = {}  # Vector2i -> {"tile": int, "flipH": bool, "flipV": bool}
var render_parts: Array = []       # {tile, phase, order, art|frames, object_id?}
var _parts_by_tile: Dictionary = {}  # Vector2i -> Array of render_parts on that cell
var _parts_indexed_size := -1
var collision: Array = []          # {tile:[x,y], tall:bool}; visual phase is unrelated
## Authored non-binary tile passability. Values use Direction bits and describe
## the sides through which a tile may be entered or exited.
var passability_masks: Dictionary = {}  # Vector2i -> int (1..Direction.MASK_ALL)
## Native maps: the original's monster zone (heroes.exe 0x84138) covers a
## stack's eight neighbours except a cell below it listed here, one with a
## layer-1 sprite. False for hand-authored maps, which keep the two-way rule.
var native_zones := false
var zone_sprites: Dictionary = {}  # Vector2i -> true
var object_cells: Dictionary = {}  # Vector2i -> true; native cells whose B8 is not 0 at map start
## Native object cells with a second class (cell B7): what taking the object
## leaves of the cell (heroes.exe 0xb46d8). true = blocked, false = entered and
## left from the sides and below.
var after_removal: Dictionary = {}  # Vector2i -> bool
## Authored ambient sound loop grid (loop_idx 0..21). Keyed by Vector2i tile.
var ambient_sounds: Dictionary = {}  # Vector2i -> int

func get_ambient_sound(tile: Vector2i) -> int:
	return ambient_sounds.get(tile, -1)

func clear_ambient_sound(tile: Vector2i) -> void:
	ambient_sounds.erase(tile)

## Buried Ultimate Artifact: {"tile": [x,y], "artifact":
## "<id>"} when authored, {} when absent. Not an object — never placed/rendered on
## the live map; only PuzzleMap.cross_tile() (once the puzzle is solved) and the
## dig action read it.
var ultimate_artifact: Dictionary = {}

func setup(p_name: String, p_w: int, p_h: int, p_ts: int, p_grid: Array, p_passable := [], p_hero_start := Vector2i.ZERO) -> void:
	name = p_name
	width = p_w
	height = p_h
	tile_size = p_ts
	grid = p_grid
	passable = p_passable
	hero_start = p_hero_start

func get_tile(x: int, y: int) -> int:
	if y < 0 or y >= height or x < 0 or x >= width:
		return -1
	if grid.is_empty() or y >= grid.size() or x >= grid[y].size():
		return -1
	return grid[y][x]

func is_passable(x: int, y: int) -> bool:
	if y < 0 or y >= height or x < 0 or x >= width:
		return false
	if passable.is_empty():
		return true
	return passable[y][x]

func is_water(tile: Vector2i) -> bool:
	if tile.x < 0 or tile.y < 0 or tile.x >= width or tile.y >= height:
		return false
	if tile.y < terrain_chars.size():
		var row: String = terrain_chars[tile.y]
		if tile.x < row.length():
			return row[tile.x] == "W"
	var idx := get_tile(tile.x, tile.y)
	return idx >= 0 and idx <= 19

func is_land(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < width and tile.y < height \
			and not is_water(tile)

func terrain_at(tile: Vector2i) -> String:
	if tile.x < 0 or tile.y < 0 or tile.x >= width or tile.y >= height:
		return "grass"
	if tile.y < terrain_chars.size():
		var row: String = terrain_chars[tile.y]
		if tile.x < row.length():
			match row[tile.x]:
				"W": return "water"
				"G": return "grass"
				"S": return "snow"
				"T": return "swamp"
				"L": return "lava"
				"D": return "desert"
				"I": return "dirt"
	var idx := get_tile(tile.x, tile.y)
	if idx >= 0 and idx <= 19: return "water"
	if idx >= 20 and idx <= 39: return "grass"
	if idx >= 40 and idx <= 59: return "snow"
	if idx >= 60 and idx <= 79: return "swamp"
	if idx >= 80 and idx <= 99: return "lava"
	if idx >= 100 and idx <= 119: return "desert"
	if idx >= 120 and idx <= 139: return "dirt"
	return "grass"

## The render parts stored on a cell: its layer-1 and layer-2 sprites.
func parts_at(tile: Vector2i) -> Array:
	if _parts_indexed_size != render_parts.size():
		_parts_by_tile.clear()
		for part: Variant in render_parts:
			var t: Array = (part as Dictionary).get("tile", [])
			if t.size() == 2:
				var key := Vector2i(int(t[0]), int(t[1]))
				if not _parts_by_tile.has(key):
					_parts_by_tile[key] = []
				(_parts_by_tile[key] as Array).append(part)
		_parts_indexed_size = render_parts.size()
	return _parts_by_tile.get(tile, [])

func pixel_size() -> Vector2:
	return Vector2(width * tile_size, height * tile_size)

func rebuild_indexes() -> void:
	_rebuild_indexes()

func _ensure_indexes() -> void:
	if not _indexes_dirty and _indexed_size == objects.size():
		var first: Variant = objects[0] if not objects.is_empty() else null
		var last: Variant = objects[-1] if not objects.is_empty() else null
		if _indexed_first == first and _indexed_last == last:
			return
	_rebuild_indexes()

func _rebuild_indexes() -> void:
	_action_index.clear()
	_objects_by_id.clear()
	_towns_by_tile.clear()
	_towns.clear()
	for o: MapObject in objects:
		if o == null:
			continue
		if not _objects_by_id.has(o.id):
			_objects_by_id[o.id] = o
		for t: Vector2i in o.interaction_tiles():
			if not _action_index.has(t):
				_action_index[t] = o
		if o is TownObject:
			var town := o as TownObject
			_towns.append(town)
			for t: Vector2i in _town_covered_tiles(town):
				if not _towns_by_tile.has(t):
					_towns_by_tile[t] = town
	_indexed_size = objects.size()
	_indexed_first = objects[0] if not objects.is_empty() else null
	_indexed_last = objects[-1] if not objects.is_empty() else null
	_indexes_dirty = false

func _index_single_object(obj: MapObject) -> void:
	if obj == null:
		return
	if not _objects_by_id.has(obj.id):
		_objects_by_id[obj.id] = obj
	for t: Vector2i in obj.interaction_tiles():
		if not _action_index.has(t):
			_action_index[t] = obj
	if obj is TownObject:
		var town := obj as TownObject
		_towns.append(town)
		for t: Vector2i in _town_covered_tiles(town):
			if not _towns_by_tile.has(t):
				_towns_by_tile[t] = town

func _town_covered_tiles(town: TownObject) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	tiles.append(town.tile)
	if not tiles.has(town.action_tile):
		tiles.append(town.action_tile)
	for t: Vector2i in town.interaction_tiles():
		if not tiles.has(t):
			tiles.append(t)
	for dy in range(-2, 1):
		for dx in range(-2, 2):
			var t1 := Vector2i(town.tile.x + dx, town.tile.y + dy)
			if not tiles.has(t1):
				tiles.append(t1)
			var t2 := Vector2i(town.action_tile.x + dx, town.action_tile.y + dy)
			if not tiles.has(t2):
				tiles.append(t2)
	return tiles

func _is_town_covering_tile(candidate: TownObject, tile: Vector2i) -> bool:
	if candidate.tile == tile or candidate.action_tile == tile or tile in candidate.interaction_tiles():
		return true
	if tile.x >= candidate.tile.x - 2 and tile.x <= candidate.tile.x + 1 \
			and tile.y >= candidate.tile.y - 2 and tile.y <= candidate.tile.y:
		return true
	if tile.x >= candidate.action_tile.x - 2 and tile.x <= candidate.action_tile.x + 1 \
			and tile.y >= candidate.action_tile.y - 2 and tile.y <= candidate.action_tile.y:
		return true
	return false

func add_object(obj: MapObject) -> void:
	if obj == null:
		return
	objects.append(obj)
	if not _indexes_dirty and _indexed_size == objects.size() - 1:
		_index_single_object(obj)
		_indexed_size = objects.size()
		if objects.size() == 1:
			_indexed_first = obj
		_indexed_last = obj
	else:
		_indexes_dirty = true

func remove_object(obj: MapObject) -> void:
	if obj == null:
		return
	objects.erase(obj)
	_indexes_dirty = true

## The object whose canonical or aliased interaction tile is `t`, or null.
func object_at_action(t: Vector2i) -> MapObject:
	_ensure_indexes()
	return _action_index.get(t, null)

func block(x: int, y: int) -> void:
	if y < 0 or y >= height or x < 0 or x >= width or passable.is_empty():
		return
	passable[y][x] = false

## The map's town owned by `side`, or null. (Moved from adventure_map.gd)
func town_of_side(side: int) -> TownObject:
	_ensure_indexes()
	for t: TownObject in _towns:
		if t.owner == side:
			return t
	return null

## Returns the TownObject covering `tile` (including gate, interaction tiles,
## or the 4x3 castle footprint), or null if no town covers this tile.
func town_at(tile: Vector2i) -> TownObject:
	_ensure_indexes()
	var candidate: TownObject = _towns_by_tile.get(tile, null)
	if candidate != null:
		if not candidate.consumed:
			return candidate
		for town: TownObject in _towns:
			if not town.consumed and _is_town_covering_tile(town, tile):
				return town
	return null

func object_by_id(oid: int) -> MapObject:
	_ensure_indexes()
	return _objects_by_id.get(oid, null)

## Returns the TownObject with matching id, or null if not found or not a TownObject.
func town_by_id(oid: int) -> TownObject:
	return object_by_id(oid) as TownObject

## The gate of `side`'s own town standing on `t`, or null. A hero parked on
## that cell defends the town, so attacking him besieges the castle rather than
## meeting him in the open field.
func own_town_gate_at(t: Vector2i, side: int) -> TownObject:
	if side < 0:
		return null
	var town := active_object_at_action(t) as TownObject
	return town if town != null and town.owner == side else null

## object_at_action, but consumed objects (piles/stacks) don't count.
func active_object_at_action(t: Vector2i) -> MapObject:
	var obj := object_at_action(t)
	if obj != null and "consumed" in obj and obj.consumed:
		return null
	return obj
