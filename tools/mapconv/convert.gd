extends RefCounted

## One .map or .cmp into one v2 map dictionary.
##
## The shape of the job, in order:
##
##   1. terrain characters and per-tile overrides, straight off B0 and B6
##   2. interactive objects, found by flood-filling equal B8 values over 128
##   3. players, from the trailer's castle table
##   4. scenery, from every sprite on a cell no object claimed
##
## Everything here works in the binary's own cell coordinates. The axes are
## swapped relative to the screen, and transform.gd puts that right afterwards,
## because doing it at the end means only positions move and every sprite id,
## flip flag and offset stays as the file wrote it.

const Tables := preload("res://tools/mapconv/tables.gd")
const HMap := preload("res://tools/mapconv/hmap.gd")
const NativePassability := preload("res://tools/mapconv/native_passability.gd")

const CATALOG_PATH := "res://data/objects/catalog.json"

var sprite_types := {}


func _init() -> void:
	sprite_types = _catalog_sprite_types()
	for key in Tables.EXTRA_SPRITE_TYPE:
		sprite_types[key] = Tables.EXTRA_SPRITE_TYPE[key]


## Returns {ok, error, map, skipped}. `map` is a v2 dictionary in cell
## coordinates; `skipped` counts the interactive cells no rule could type.
func run(data: PackedByteArray) -> Dictionary:
	var m := HMap.new(data)
	if not m.ok:
		return {"ok": false, "error": m.error, "map": {}, "skipped": {}}
	# Paint each sprite on the layer the game holds it on once the map has
	# started, not the one the file stores it on.
	NativePassability.apply_start(m)

	var built := _terrain(m)
	var found := _objects(m)
	var players := _players(found["towns"])
	var decor := _decor(m, found["consumed"])
	var ambient := _ambient_sounds(m)

	var map_dict: Dictionary = {
		"version": 2,
		"name": m.name,
		"description": m.description,
		"map_difficulty": m.difficulty,
		"size": m.size,
		"supported_human_counts": [],
		"tile_size": 32,
		"seed": 1337,
		"terrain": built["terrain"],
		"tile_overrides": built["overrides"],
		"players": players,
		"objects": found["objects"],
		"decor": decor,
	}
	if not ambient.is_empty():
		map_dict["ambient_sounds"] = ambient

	return {"ok": true, "error": "", "skipped": found["skipped"], "hmap": m, "map": map_dict}


static func _ambient_sounds(m: HMap) -> Dictionary:
	var grid := m.ambient_sound_grid()
	if grid.is_empty():
		return {}
	var sounds := {}
	for by in Tables.H:
		for bx in Tables.W:
			var val := grid[by * Tables.W + bx]
			if val != 0xFF:
				sounds["%d,%d" % [bx, by]] = val
	return sounds


## Seats come from the filename. Retail names encode them in positions 4 to 7,
## so hnm11234 seats one through four. A map written by our own tools can be
## called anything, and one that seats nobody fails new-game validation, so fall
## back to one seat per authored player.
static func supported_humans(stem: String, player_count: int) -> Array:
	var out: Array = []
	for n in range(1, 5):
		if stem.length() >= 4 + n and stem[3 + n] == str(n):
			out.append(n)
	if out.is_empty():
		for n in range(1, maxi(1, mini(4, player_count)) + 1):
			out.append(n)
	return out


func _terrain(m: HMap) -> Dictionary:
	var rows: Array = []
	var overrides := {}
	for y in Tables.H:
		var row := ""
		for x in Tables.W:
			var cell := m.cell(x, y)
			var ground: int = cell[0]
			var band: int = ground / 20
			row += String(Tables.TERRAIN_BAND.get(band, "I" if ground >= 20 else "W"))
			var override := {"tile": ground}
			if cell[6] & 0x02:
				override["flipH"] = true
			if cell[6] & 0x01:
				override["flipV"] = true
			overrides["%d,%d" % [x, y]] = override
		rows.append(row)
	return {"terrain": rows, "overrides": overrides}


## Interactive cells are B8 over 128, and neighbouring cells sharing a B8 make
## one cluster. Only the handful of types in MULTI_TILE_TYPES keep the cluster;
## everything else splits back into one object per cell, because the flood fill
## will otherwise weld nineteen adjacent resource piles into a single object.
func _objects(m: HMap) -> Dictionary:
	var seen := {}
	var objects: Array = []
	var towns: Array = []
	var consumed := {}
	var skipped := {}

	for y in Tables.H:
		for x in Tables.W:
			var key := y * Tables.W + x
			var value: int = m.cell(x, y)[8]
			if value < 128 or seen.has(key):
				continue
			var cluster := _flood(m, x, y, value, seen)
			var base := _base_tile(cluster)
			var sprite := _cluster_sprite(m, cluster, base)

			var type := ""
			if (value == 168 or value == 192 or value == 193) \
					and not sprite.is_empty() and String(sprite[0]) == "town32":
				type = "town"
			elif Tables.B8_TYPE.has(value):
				type = String(Tables.B8_TYPE[value])
			elif not sprite.is_empty():
				type = String(sprite_types.get("%s/%d" % [sprite[0], sprite[1]], ""))
			if type == "":
				if Tables.B8_DECOR_ONLY.has(value):
					continue
				var label := "B8=%d %s" % [value,
					("%s:%d" % [sprite[0], sprite[1]]) if not sprite.is_empty() else "?"]
				skipped[label] = int(skipped.get(label, 0)) + 1
				continue

			if Tables.BODY_ABOVE_TYPES.has(type):
				_take_body_above(m, cluster, value)
			for tile: Vector2i in cluster:
				consumed[tile] = true
			var parts: Array = [cluster] if Tables.MULTI_TILE_TYPES.has(type) \
				else cluster.map(func(t: Vector2i) -> Array: return [t])
			for part: Array in parts:
				_emit(m, objects, towns, type, value, part, sprite)

	return {"objects": objects, "towns": towns, "consumed": consumed, "skipped": skipped}


## A skeleton is two stacked cells: the flagged class (132) holds the lower
## half and the same class without the 0x80 flag (4) holds the bones above it.
## The unflagged cell is below the object threshold, so without this it stays
## decor and survives the visit that removes the lower half.
func _take_body_above(m: HMap, cluster: Array, value: int) -> void:
	for tile: Vector2i in cluster.duplicate():
		var above := Vector2i(tile.x, tile.y - 1)
		if above.y < 0 or cluster.has(above):
			continue
		var cell := m.cell(above.x, above.y)
		if cell[8] == value - 128 and not HMap.sprite(cell, 1).is_empty():
			cluster.append(above)


func _flood(m: HMap, x: int, y: int, value: int, seen: Dictionary) -> Array:
	var cluster: Array = []
	var stack: Array = [Vector2i(x, y)]
	while not stack.is_empty():
		var at: Vector2i = stack.pop_back()
		if at.x < 0 or at.x >= Tables.W or at.y < 0 or at.y >= Tables.H:
			continue
		var key := at.y * Tables.W + at.x
		if seen.has(key) or m.cell(at.x, at.y)[8] != value:
			continue
		seen[key] = true
		cluster.append(at)
		stack.append(Vector2i(at.x + 1, at.y))
		stack.append(Vector2i(at.x - 1, at.y))
		stack.append(Vector2i(at.x, at.y + 1))
		stack.append(Vector2i(at.x, at.y - 1))
	return cluster


## The base tile is the cluster's lowest row, leftmost column: where a HOMM1
## object's action cell and anchor sit.
static func _base_tile(cluster: Array) -> Vector2i:
	var best: Vector2i = cluster[0]
	for tile: Vector2i in cluster:
		if tile.y > best.y or (tile.y == best.y and tile.x < best.x):
			best = tile
	return best


func _cluster_sprite(m: HMap, cluster: Array, base: Vector2i) -> Array:
	var at_base := HMap.sprite(m.cell(base.x, base.y), 1)
	if not at_base.is_empty():
		return at_base
	for tile: Vector2i in cluster:
		var sprite := HMap.sprite(m.cell(tile.x, tile.y), 1)
		if not sprite.is_empty():
			return sprite
	return []


## One object from the cells it occupies, carrying the sprites the .map itself
## puts on them. Layer 1 paints first and layer 2 is the visual overlay for the
## same cell.
func _emit(m: HMap, objects: Array, towns: Array, type: String, value: int,
		cluster: Array, cluster_sprite: Array) -> void:
	var base := _base_tile(cluster)
	var sprite := _cluster_sprite(m, cluster, base)
	if sprite.is_empty():
		sprite = cluster_sprite

	var obj := {"type": type, "tile": [base.x, base.y]}

	var art: Array = []
	var phases: Array = []
	var classes: Array = []
	var animations: Array = []
	var ordered := cluster.duplicate()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x or (a.x == b.x and a.y < b.y))
	for tile: Vector2i in ordered:
		var cell := m.cell(tile.x, tile.y)
		var dx := tile.x - base.x
		var dy := tile.y - base.y
		for layer in [1, 2]:
			var s := HMap.sprite(cell, layer)
			if s.is_empty() or String(s[0]) == "flag32" \
					or Tables.is_placeholder(String(s[0]), int(s[1])):
				continue
			# B6 bit 0x80 paints layer 1 flat with the ground (see _decor).
			var ground: bool = layer == 1 and (cell[6] & 0x80) != 0
			art.append([dx, dy, "%s/%04d.png" % [s[0], s[1]]])
			phases.append("ground" if ground else ("base" if layer == 1 else "top"))
			classes.append(int(cell[8]))
			var anim_bit := 0x04 if layer == 1 else 0x08
			if cell[6] & anim_bit and not ground:
				var frames: Array = []
				for i in range(1, 7):
					frames.append("%s/%04d.png" % [s[0], int(s[1]) + i])
				animations.append({"offset": [dx, dy],
					"phase": "base" if layer == 1 else "top",
					"frames": frames, "clock": "native"})
		if cell[6] & 0x10:
			art.append([dx, dy, "rsrc32/%04d.png" % cell[5]])
			phases.append("base")
			classes.append(int(cell[8]))

	# Stacks and artifacts are rolled at run time, from a random class or a
	# random frame, and drawn from that roll rather than from the cell sprite.
	if type == "stack" or type == "artifact":
		art = []
		phases = []
		classes = []
		animations = []
	if not art.is_empty():
		obj["art"] = art
		obj["_art_phases"] = phases
		obj["_art_classes"] = classes
	if not animations.is_empty():
		obj["_animations"] = animations

	if type == "windmill" and value == 173:
		# The interactive marker sits on the right-hand tower tile while our
		# catalog composite anchors at the left-hand hut tile.
		obj["tile"] = [base.x, base.y - 1]
		_strip_art(obj)

	_apply_params(m, obj, towns, type, value, base, sprite)
	objects.append(obj)


func _apply_params(m: HMap, obj: Dictionary, towns: Array, type: String,
		value: int, base: Vector2i, sprite: Array) -> void:
	match type:
		"town":
			# Trailer coordinates are already in screen orientation while cell
			# coordinates are still transposed, hence (y, x) here.
			var trailer := m.trailer_value_at(base.y, base.x, 0, 36)
			var trailer_type := Tables.town_type_from_trailer(trailer & 0x7F) if trailer >= 0 else -1
			var resolved := trailer_type if trailer_type >= 0 and trailer_type < 5 \
				else Tables.town_type_from_sprite(sprite)
			# Keep the native random sentinel; Game resolves it once per run.
			obj["town_type"] = resolved if resolved >= 0 else 4
			obj["owner"] = -1
			var has_castle := bool(trailer & 0x80) if trailer >= 0 else value != 192
			obj["params"] = {"name": "", "has_castle": has_castle}
			obj["native_start"] = bool(trailer & 0x80) if trailer >= 0 else false
			# object_layer.gd composites a castle from the resolved faction's
			# town32 block, because the map stores only eight of its twelve
			# tiles and a random castle stores the purple placeholder plates.
			_strip_art(obj)
			towns.append(obj)
		"resource":
			if value == 190:
				obj["res"] = "random"
			elif not sprite.is_empty() and String(sprite[0]) == "rsrc32":
				obj["res"] = String(Tables.RESOURCE_PILE.get(int(sprite[1]), "gold"))
		"mine":
			if value == 129:
				obj["res"] = "mercury"
			elif value == 160:
				obj["res"] = "wood"
			else:
				var kind := m.trailer_value_at(base.y, base.x, 38, 180,
					Tables.MINE_RESOURCE.keys())
				obj["res"] = String(Tables.MINE_RESOURCE.get(kind, "ore"))
		"dwelling":
			var unit := String(Tables.DWELLING_UNIT.get(value, "peasant"))
			obj["unit"] = unit
			var stats: Dictionary = Tables.DWELLING_STATS.get(unit, {})
			for stat in stats:
				obj[stat] = stats[stat]
			if Tables.DWELLING_TITLE.has(value):
				obj["title"] = String(Tables.DWELLING_TITLE[value])
			obj["available"] = maxi(m.cell(base.x, base.y)[9],
				int(stats.get("initial_min", 1)))
		"dragon_city":
			obj["owner"] = -1
			obj["guard"] = [["dragon", 1], ["dragon", 1], ["dragon", 1],
				["dragon", 1], ["dragon", 1]]
		"stack":
			if sprite.is_empty() or String(sprite[0]) != "mons32":
				return
			if Tables.RANDOM_STACK_IDS.has(value):
				obj["random_stack_id"] = value
				return
			var creature := String(Tables.MONS32_CREATURE.get(int(sprite[1]), ""))
			var count: int = m.cell(base.x, base.y)[9]
			if creature != "" and count <= 0:
				# B9 = 0 leaves the count to the game: it rolls one from the
				# creature's wandering range and a joinable flag at start, like
				# a random class. The DOS campaign autosave of camp1 holds
				# 50-71 peasants and 20-29 archers where the file has 0.
				obj["unit"] = creature
				return
			obj["army"] = [[creature, count]] if creature != "" and count > 0 else []
		"artifact":
			if sprite.is_empty() or String(sprite[0]) != "art32":
				return
			if Tables.NATIVE_ARTIFACTS.has(int(sprite[1])):
				obj["artifact_id"] = String(Tables.NATIVE_ARTIFACTS[int(sprite[1])])


## The trailer's castle array says who owns which castle. Player i in trailer
## order owns castle i, and the first is the human. A town the array does not
## name stays neutral.
static func _players(towns: Array) -> Array:
	var players: Array = []
	for town: Dictionary in towns:
		var native_start := bool(town.get("native_start", false))
		town.erase("native_start")
		if not native_start:
			continue
		var side := players.size()
		var tile: Array = town["tile"]
		town["owner"] = side
		players.append({"side": side, "human": side == 0,
			"heroes": [[int(tile[0]), int(tile[1])]], "color": side})
	if players.is_empty():
		players = [{"side": 0, "human": true, "heroes": [[36, 36]], "color": 0}]
	return players


## Scenery: every layer-1 and layer-2 sprite on a cell no object claimed.
##
## HOMM1 draws map objects per tile with no anchor compositing, so one entry per
## cell sprite reproduces the original picture. Layer 2 never blocks but is the
## visual overlay, so layer 1 has to be painted first. Verified in the DOS
## original: Claw's layer-2 sawmill and alchemist-lab plates occlude the layer-1
## trees they share a cell with, and Claw's hero walks onto (42,47), whose only
## sprite is a sawmill layer-2 plate.
##
## A layer-1 sprite on a cell with B6 bit 0x80 (the class-50 decals: flowers,
## dunes, cracks, small hills) is phase "ground": heroes.exe paints it with the
## ground tile and never animates it (cell routine 0x9a398, pass 1).
func _decor(m: HMap, consumed: Dictionary) -> Array:
	var decor: Array = []
	for y in Tables.H:
		for x in Tables.W:
			if consumed.has(Vector2i(x, y)):
				continue
			var cell := m.cell(x, y)
			for layer in [1, 2]:
				var s := HMap.sprite(cell, layer)
				if s.is_empty() or not Tables.DECOR_DIRS.has(String(s[0])):
					continue
				if Tables.is_placeholder(String(s[0]), int(s[1])):
					continue
				var ground: bool = layer == 1 and (cell[6] & 0x80) != 0
				var entry := {"art": "%s/%04d.png" % [s[0], s[1]], "tile": [x, y],
					"_phase": "ground" if ground else ("base" if layer == 1 else "top")}
				var anim_bit := 0x04 if layer == 1 else 0x08
				if cell[6] & anim_bit and not ground:
					var frames: Array = []
					for i in range(1, 7):
						frames.append("%s/%04d.png" % [s[0], int(s[1]) + i])
					entry["_frames"] = frames
					entry["_clock"] = "native"
				if layer == 1:
					entry["_class"] = int(cell[8])
				decor.append(entry)
			# B5 is a resource-cart overlay painted after the layer-1 underlay.
			if cell[6] & 0x10:
				decor.append({"art": "rsrc32/%04d.png" % cell[5], "tile": [x, y],
					"_phase": "base"})
	return decor


static func _strip_art(obj: Dictionary) -> void:
	obj.erase("art")
	obj.erase("_art_phases")
	obj.erase("_art_classes")
	obj.erase("_animations")


## data/objects/catalog.json nests {dir, sprite} art entries at varying depths.
## The type is whichever key the walk was under when it found one.
func _catalog_sprite_types() -> Dictionary:
	var out := {}
	_walk_catalog(_read_json(CATALOG_PATH), "", out)
	return out


static func _walk_catalog(node: Variant, type: String, out: Dictionary) -> void:
	if node is Dictionary:
		var dict: Dictionary = node
		if dict.has("dir") and dict.has("sprite"):
			out["%s/%d" % [dict["dir"], int(dict["sprite"])]] = type
		for key in dict:
			_walk_catalog(dict[key], String(key) if type == "" else type, out)
	elif node is Array:
		for item: Variant in (node as Array):
			_walk_catalog(item, type, out)


static func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("cannot read %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}
