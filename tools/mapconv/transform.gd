extends RefCounted

## Four passes over a converted map, after the cells are read and before the
## v3 upgrade: put the axes the right way round, replace the windmill's native
## tiles with the catalog composite, open the lowest cells of solid plates to
## the sides and below, and apply the corrections that are not derivable from
## cell data.

const SchemaV3 := preload("res://tools/mapconv/schema_v3.gd")
const Tables := preload("res://tools/mapconv/tables.gd")


## The cell stream's axes are swapped relative to the screen: source (x, y) is
## displayed at (y, x).
##
## An earlier 90-degree rotation added a horizontal mirror that nothing needed.
## Claw made the error unambiguous, because every landmark around the starting
## castle sat on the opposite side from the DOS original.
##
## Tile ids and the B6 flip flags already describe the sprite as it appears on
## screen, so only positions move. flipH and flipV are left alone.
static func transpose(out: Dictionary) -> Dictionary:
	var old: Array = out["terrain"]
	var n := old.size()
	for row: String in old:
		assert(row.length() == n, "a HOMM1 map must be square")

	var rows: Array = []
	for x in n:
		var row := ""
		for y in n:
			row += (old[y] as String)[x]
		rows.append(row)
	out["terrain"] = rows

	var overrides := {}
	for key: String in (out.get("tile_overrides", {}) as Dictionary):
		var parts := key.split(",")
		overrides["%s,%s" % [parts[1], parts[0]]] = out["tile_overrides"][key]
	out["tile_overrides"] = overrides

	if out.has("ambient_sounds"):
		var ambient := {}
		for key: String in (out.get("ambient_sounds", {}) as Dictionary):
			var parts := key.split(",")
			ambient["%s,%s" % [parts[1], parts[0]]] = int(out["ambient_sounds"][key])
		out["ambient_sounds"] = ambient

	for obj: Dictionary in out.get("objects", []):
		obj["tile"] = _swap(obj["tile"])
		if obj.has("art"):
			var art: Array = []
			for entry: Array in obj["art"]:
				art.append([entry[1], entry[0], entry[2]])
			obj["art"] = art
		for anim: Dictionary in obj.get("_animations", []):
			anim["offset"] = _swap(anim["offset"])
		if obj.has("blocks"):
			obj["blocks"] = (obj["blocks"] as Array).map(_swap)
		if obj.has("_obstacles"):
			obj["_obstacles"] = (obj["_obstacles"] as Array).map(_swap)
	for player: Dictionary in out.get("players", []):
		player["heroes"] = (player.get("heroes", []) as Array).map(_swap)
	for decor: Dictionary in out.get("decor", []):
		decor["tile"] = _swap(decor["tile"])
		if decor.has("blocks"):
			decor["blocks"] = (decor["blocks"] as Array).map(_swap)

	# Emission followed the cell scan, which is screen columns once the axes
	# are swapped. The renderer paints in list order, so re-sort into screen
	# rows and a sprite in a lower row correctly overlaps the one above it.
	# The sort has to be stable: two entries on one tile are its layer 1 and
	# layer 2 plates, and swapping them puts the overlay underneath.
	out["decor"] = _stable_sort_by_row(out.get("decor", []))
	return out


## HOMM1 stores a windmill as four ordinary obj32-07 tiles, two of which are
## only animation underlays: 105 is transparent and 112 is the hub joint, and
## the DOS renderer supplies the rotating quadrants separately. Left in decor
## they produce a sail-less mill and lose the weekly-pickup interaction.
static func promote_composites(out: Dictionary) -> Dictionary:
	var parts := {
		Vector2i(0, -1): "obj32-07/0105.png",
		Vector2i(1, -1): "obj32-07/0112.png",
		Vector2i(0, 0): "obj32-07/0091.png",
		Vector2i(1, 0): "obj32-07/0098.png",
	}
	var decor: Array = out.get("decor", [])
	var index := {}
	for i in decor.size():
		var tile: Array = (decor[i] as Dictionary).get("tile", [])
		if tile.size() != 2:
			continue
		var key := "%s|%d,%d" % [(decor[i] as Dictionary).get("art", ""),
			int(tile[0]), int(tile[1])]
		if not index.has(key):
			index[key] = []
		(index[key] as Array).append(i)

	var consumed := {}
	var promoted: Array = []
	var anchors := {}
	for obj: Dictionary in out.get("objects", []):
		var tile: Array = obj.get("tile", [])
		if String(obj.get("type", "")) == "windmill" and tile.size() == 2:
			anchors[Vector2i(int(tile[0]), int(tile[1]))] = true
	# B8=173 marks the tower tile itself, so the other three body tiles survive
	# as decor and double-draw under the catalog composite. Take the whole
	# native footprint around those anchors out.
	for anchor: Vector2i in anchors:
		for offset: Vector2i in parts:
			for i: int in _lookup(index, parts[offset], anchor + offset):
				consumed[i] = true

	for i in decor.size():
		var entry: Dictionary = decor[i]
		if consumed.has(i) or String(entry.get("art", "")) != parts[Vector2i(0, 0)]:
			continue
		var tile: Array = entry.get("tile", [])
		if tile.size() != 2:
			continue
		var base := Vector2i(int(tile[0]), int(tile[1]))
		if anchors.has(base):
			continue
		var matched: Array = []
		var complete := true
		for offset: Vector2i in parts:
			var found := -1
			for candidate: int in _lookup(index, parts[offset], base + offset):
				if not consumed.has(candidate) and not matched.has(candidate):
					found = candidate
					break
			if found < 0:
				complete = false
				break
			matched.append(found)
		if not complete:
			continue
		for j: int in matched:
			consumed[j] = true
		promoted.append({"type": "windmill", "tile": [base.x, base.y]})

	if promoted.is_empty() and consumed.is_empty():
		return out
	var kept: Array = []
	for i in decor.size():
		if not consumed.has(i):
			kept.append(decor[i])
	out["decor"] = kept
	if not out.has("objects"):
		out["objects"] = []
	(out["objects"] as Array).append_array(promoted)
	return out


static func _xy(value: Variant) -> Vector2i:
	if value is Array and (value as Array).size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i.ZERO


## Corrections that the cell data cannot express.
##
## Note what is deliberately absent: which castle the human wakes up in is not
## the trailer's first entry, and on a map whose starting castles are all marked
## random faction the original picks one per game. Three launches of Dragon Pass
## seated Blue at the east, west and south castle in turn, so pinning a seat
## there would be a fiction.
static func apply_fixups(out: Dictionary, stem: String) -> Dictionary:
	if stem == "camp3":
		# The Eye of Goros is campaign-only executable metadata, not a visible
		# map object. Keeping the buried objective in the JSON is what stops
		# campaign play depending on the CMP and EXE files at run time. The tile
		# is rolled per game (UltimatePlacement); a fixed one sat in a forest.
		out["ultimate_artifact"] = {"artifact": "book_of_omniscience"}
	if stem != "aes31000":
		return out

	# Claw's four authored seats are all playable, but Blue starts at the
	# southern castle rather than the trailer's first, north-west one.
	var south := [37, 51]
	var northern := [[24, 26], [37, 26], [50, 26]]
	var players: Array = [{"side": 0, "human": true, "heroes": [south.duplicate()],
		"color": 0}]
	for i in northern.size():
		players.append({"side": i + 1, "human": false,
			"heroes": [(northern[i] as Array).duplicate()], "color": i + 1})
	out["players"] = players

	for obj: Dictionary in out.get("objects", []):
		if String(obj.get("type", "")) != "town":
			continue
		var tile: Array = obj.get("tile", [])
		if tile == south:
			obj["owner"] = 0
		elif northern.has(tile):
			obj["owner"] = northern.find(tile) + 1
	return out


static func _swap(pair: Variant) -> Array:
	var values: Array = pair
	return [values[1], values[0]]


static func _lookup(index: Dictionary, art: String, tile: Vector2i) -> Array:
	return index.get("%s|%d,%d" % [art, tile.x, tile.y], [])


## Godot's sort_custom is not stable, so the original position is the last
## tiebreak. Without it, two plates on one tile can swap.
static func _stable_sort_by_row(entries: Array) -> Array:
	var ordered: Array = []
	for i in entries.size():
		ordered.append([entries[i], i])
	ordered.sort_custom(func(a: Array, b: Array) -> bool:
		var at: Array = (a[0] as Dictionary)["tile"]
		var bt: Array = (b[0] as Dictionary)["tile"]
		if int(at[1]) != int(bt[1]):
			return int(at[1]) < int(bt[1])
		if int(at[0]) != int(bt[0]):
			return int(at[0]) < int(bt[0])
		return int(a[1]) < int(b[1]))
	var out: Array = []
	for pair: Array in ordered:
		out.append(pair[0])
	return out
