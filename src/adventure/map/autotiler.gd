class_name Autotiler
extends RefCounted

## Spec Section 3: per-cell terrain tile choice. Plain variants by position
## hash; boundaries via 8-neighbor bitmask -> shape -> transitions.json entry.
## Bit order: N=1, NE=2, E=4, SE=8, S=16, SW=32, W=64, NW=128.

var _table: TerrainTable
var _shapes: Dictionary = {}

static func create() -> Autotiler:
	var table := TerrainTable.load_table()
	if table == null:
		push_error("Autotiler: failed to load TerrainTable")
		return null
	
	var data := JsonFile.read_dict("res://data/terrain/transitions.json")
	if data.is_empty():
		push_error("Autotiler: transitions.json is missing or not a JSON object")
		return null
	
	var at := Autotiler.new()
	at._table = table
	for key: String in data.keys():
		if key.begins_with("_"):
			continue
		at._shapes[key] = data[key]
	return at

func resolve(map: MapData, x: int, y: int) -> Dictionary:
	if map == null:
		return {"tile": -1, "flip_h": false, "flip_v": false}
	
	if map.terrain_chars.is_empty():
		return {"tile": map.get_tile(x, y), "flip_h": false, "flip_v": false}
	
	if y < 0 or y >= map.height or x < 0 or x >= map.width:
		return {"tile": -1, "flip_h": false, "flip_v": false}

	var center_char: String = map.terrain_chars[y][x]
	var base_tile := _table.base_tile(center_char)
	if base_tile == -1:
		return {"tile": -1, "flip_h": false, "flip_v": false}

	# 1. Dirt is always plain
	if center_char == "I":
		var variant := _hash_pick(x, y, 4)
		return {"tile": base_tile + variant, "flip_h": false, "flip_v": false}

	# 2. Compute 8-neighbor differs-mask
	var mask := 0
	var deltas = [
		Vector2i(0, -1),   # N (1)
		Vector2i(1, -1),   # NE (2)
		Vector2i(1, 0),    # E (4)
		Vector2i(1, 1),    # SE (8)
		Vector2i(0, 1),    # S (16)
		Vector2i(-1, 1),   # SW (32)
		Vector2i(-1, 0),   # W (64)
		Vector2i(-1, -1),  # NW (128)
	]
	for i in 8:
		var nx = x + deltas[i].x
		var ny = y + deltas[i].y
		if nx >= 0 and nx < map.width and ny >= 0 and ny < map.height:
			var neighbor_char: String = map.terrain_chars[ny][nx]
			if neighbor_char != center_char:
				mask |= (1 << i)

	if mask == 0:
		var variant := _hash_pick(x, y, 4)
		return {"tile": base_tile + variant, "flip_h": false, "flip_v": false}

	# 3. Resolve mask to shape
	var shape := shape_for_mask(mask)
	if shape == "" or not _shapes.has(shape):
		var variant := _hash_pick(x, y, 4)
		return {"tile": base_tile + variant, "flip_h": false, "flip_v": false}

	# 4. Get shape details from transitions JSON
	var shape_dict: Dictionary = _shapes[shape]
	var offset: int = shape_dict.get("offset", 4)
	var variants: Array = shape_dict.get("variants", [])
	if not variants.is_empty():
		var var_idx := _hash_pick(x, y, variants.size())
		offset = int(variants[var_idx])

	return {
		"tile": base_tile + offset,
		"flip_h": bool(shape_dict.get("flip_h", false)),
		"flip_v": bool(shape_dict.get("flip_v", false))
	}

func _hash_pick(x: int, y: int, n: int) -> int:
	return posmod((x * 73856093) ^ (y * 19349663), n)

static func shape_for_mask(mask: int) -> String:
	var n := bool(mask & 1)
	var ne := bool(mask & 2)
	var e := bool(mask & 4)
	var se := bool(mask & 8)
	var s := bool(mask & 16)
	var sw := bool(mask & 32)
	var w := bool(mask & 64)
	var nw := bool(mask & 128)

	var cardinals_count = int(n) + int(e) + int(s) + int(w)
	
	# 1. Adjacent cardinal pairs first -> outer corners
	if cardinals_count == 2:
		if n and e:
			return "corner_tr"
		if n and w:
			return "corner_tl"
		if s and e:
			return "corner_br"
		if s and w:
			return "corner_bl"
	
	# 2. Single cardinal -> matching edge (diagonals ignored)
	if cardinals_count == 1:
		if n:
			return "edge_top"
		if s:
			return "edge_bottom"
		if w:
			return "edge_left"
		if e:
			return "edge_right"

	# 3. No cardinals, exactly one diagonal -> inner corners
	if cardinals_count == 0:
		var diagonals_count = int(ne) + int(se) + int(sw) + int(nw)
		if diagonals_count == 1:
			if ne:
				return "inner_tr"
			if se:
				return "inner_br"
			if sw:
				return "inner_bl"
			if nw:
				return "inner_tl"

	# 4. Fallback (opposite edges, 3+ cardinals, multiple diagonals, etc.)
	# Prefer any matching edge (N > S > W > E), else plain
	if n:
		return "edge_top"
	if s:
		return "edge_bottom"
	if w:
		return "edge_left"
	if e:
		return "edge_right"

	return ""

## Fog-boundary resolver. Same mask convention as `shape_for_mask` (bit j is
## set when the neighbour at direction (j+4)%8 is explored), but with the full
## clop32 vocabulary. The 12-name resolver above is for terrain transitions;
## applying it to fog is lossy whenever the explored area pinches the fog:
## opposite cardinals, three cardinals, isolated cells and multi-diagonal
## reveals all hit its single-edge fallback, which paints a half-tile block
## instead of the band/tongue/notch art that exists for them. Masks only
## reach here for unexplored cells, so every non-empty result must exist in
## `data/terrain/fog_shapes.json`.
static func fog_shape_for_mask(mask: int) -> String:
	var n := bool(mask & 1)
	var ne := bool(mask & 2)
	var e := bool(mask & 4)
	var se := bool(mask & 8)
	var s := bool(mask & 16)
	var sw := bool(mask & 32)
	var w := bool(mask & 64)
	var nw := bool(mask & 128)
	var cardinals_count := int(n) + int(e) + int(s) + int(w)

	if mask == 0:
		return "" # deep fog: caller paints the solid clof32 tile

	# One explored cardinal: the edge art covers the fog half of the cell and
	# already leaves the diagonal fringes clear.
	if cardinals_count == 1:
		if n:
			return "edge_top"
		if s:
			return "edge_bottom"
		if w:
			return "edge_left"
		return "edge_right"

	if cardinals_count == 2:
		if n and e:
			return "corner_tr"
		if n and w:
			return "corner_tl"
		if s and e:
			return "corner_br"
		if s and w:
			return "corner_bl"
		# Opposite explored cardinals: the fog is a band between two fronts.
		# `n and s` means N and S are explored -> fog reaches E and W.
		if n and s:
			return "band_h"
		return "band_v" # E and W explored -> fog reaches N and S

	# Three explored cardinals: the fog enters from one side and must end
	# inside the cell, so the narrow "tongue" art is the right silhouette.
	# The missing explored cardinal sits opposite the fog side.
	if cardinals_count == 3:
		if not n:
			return "tongue_bottom"
		if not s:
			return "tongue_top"
		if not w:
			return "tongue_right"
		return "tongue_left"

	# All four cardinals explored: a one-cell fog pocket with no fog
	# neighbour to connect to. Sprite 10 is the only centered blob in the set.
	if cardinals_count == 4:
		return "island"

	# No explored cardinals: diagonal-only reveals. One diagonal reuses the
	# existing inner-corner entries (notch tiles 15/22 + flips).
	var diagonals_count := int(ne) + int(se) + int(sw) + int(nw)
	if diagonals_count == 1:
		if ne:
			return "inner_tr"
		if se:
			return "inner_br"
		if sw:
			return "inner_bl"
		return "inner_tl"

	# Multiple clear diagonals: a full fog tile whose transparent corner
	# notches sit on the explored corners. A set diagonal bit at direction j
	# is explored at (j+4)%8, so the notch lands opposite the mask bit.
	var tl := se
	var tr := sw
	var bl := ne
	var br := nw
	var key := "notch"
	if tl:
		key += "_tl"
	if tr:
		key += "_tr"
	if bl:
		key += "_bl"
	if br:
		key += "_br"
	return key
