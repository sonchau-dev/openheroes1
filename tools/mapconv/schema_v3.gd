extends RefCounted

## Upgrade an authored map from schema v2 to v3.
##
## v3 materializes paint order, collision, interaction cells and entry rules, so
## loading a scenario never re-derives its geometry from the object catalog. A
## catalog edit then changes new maps rather than silently moving the walls in
## saved ones.
##
## Both the converter and the hand-authored maps go through this.

const CATALOG_PATH := "res://data/objects/catalog.json"


## Returns a v3 copy. A map already at v3 is returned unchanged; anything other
## than v2 is an error, because there is no v1 left to upgrade from.
static func upgrade(data: Dictionary, catalog: Dictionary = {}) -> Dictionary:
	var version := int(data.get("version", 1))
	if version == 3:
		return data
	assert(version == 2, "only map schema v2 can be upgraded, got v%d" % version)
	var cat := catalog if not catalog.is_empty() else load_catalog()

	var out: Dictionary = data.duplicate(true)
	var parts: Array = []
	var collision := {}
	var order := {}

	for decor: Dictionary in out.get("decor", []):
		var tile := _xy(decor.get("tile"))
		var phase := String(decor.get("_phase", "base"))
		var art := String(decor.get("art", ""))
		if art != "":
			parts.append(_part(order, parts.size(), tile, phase, art, [], "", 0.0, -1))
		var frames: Array = decor.get("_frames", [])
		if not frames.is_empty():
			parts.append(_part(order, parts.size(), tile, phase, "", frames,
				String(decor.get("_clock", "native")), float(decor.get("_fps", 0.0)), -1))
		for block: Variant in decor.get("blocks", []):
			var at := _xy(block)
			_collide(collision, tile + at, bool(decor.get("tall", false)))
	out.erase("decor")

	var objects: Array = out.get("objects", [])
	for object_id in objects.size():
		var obj: Dictionary = objects[object_id]
		var definition: Dictionary = cat.get(String(obj.get("type", "")), {})
		var tile := _xy(obj.get("tile"))
		var art_entries: Array = obj.get("art", [])
		var art_classes: Array = obj.get("_art_classes", [])
		var phases: Array = obj.get("_art_phases", [])
		var animations: Array = obj.get("_animations", [])
		var native_blocks: Array = obj.get("blocks", [])
		var had_native_art := not art_entries.is_empty()
		obj.erase("art")
		obj.erase("_art_phases")
		obj.erase("_art_classes")
		obj.erase("_animations")
		obj.erase("blocks")
		obj.erase("_obstacles")

		for index in art_entries.size():
			var entry: Variant = art_entries[index]
			if not (entry is Array) or (entry as Array).size() != 3:
				continue
			var offset := Vector2i(int(entry[0]), int(entry[1]))
			parts.append(_part(order, parts.size(), tile + offset,
				String(phases[index]) if index < phases.size() else "base",
				String(entry[2]), [], "", 0.0, object_id))
		for anim: Dictionary in animations:
			parts.append(_part(order, parts.size(), tile + _xy(anim.get("offset")),
				String(anim.get("phase", "base")), "", anim.get("frames", []),
				String(anim.get("clock", "")), float(anim.get("fps", 0.0)), object_id))

		var action := tile
		if had_native_art:
			# A native footprint overrides the catalog's, because the .map knows
			# where this object's own tiles are and the catalog only knows the
			# shape of a typical one.
			action = native_action(String(obj.get("type", "")), tile)
			for block: Variant in native_blocks:
				_collide(collision, tile + _xy(block), bool(definition.get("tall", false)))
		else:
			action = tile + _xy(definition.get("action_offset"))
			for block: Variant in definition.get("footprint", []):
				_collide(collision, tile + _xy(block), bool(definition.get("tall", false)))

		var canonical := _xy(definition.get("action_offset"))
		var offsets: Array = definition.get("action_offsets", [[canonical.x, canonical.y]])
		var interactions: Array = []
		if String(obj.get("type", "")) == "whirlpool" and had_native_art:
			# Every 0x80 cell of the whirlpool's three-cell cluster is an
			# entrance. heroes.exe 0xb5ed5 reads the destination cell's class,
			# and the teleport's destination scan (0xb670c) compares each cell's
			# raw B8 with 0x80|class, so all three are both sources and
			# destinations. The decorative row below uses B8 = 0x2c without the
			# 0x80 bit and stays out of the cluster.
			interactions = _whirlpool_entrances(tile, action, art_entries, art_classes)
		else:
			for off: Variant in offsets:
				var at := _xy(off)
				interactions.append([action.x + at.x - canonical.x,
					action.y + at.y - canonical.y])
		obj["interaction_tiles"] = interactions
		obj["entry"] = entry_rule(obj, cat)

	out["version"] = 3
	out["render_parts"] = parts
	out["collision"] = _collision_rows(collision)
	return out


## Where a converted object with its own cell art is entered. The converter
## anchors a multi-cell cluster on the right-hand cell of its lowest row (the
## cell stream is transposed), which is not always the entrance: the Wagon
## Camp is entered at its centre and the Oasis at its left-hand interactive
## cell. The Oasis was walked in the DOS original on 2026-09-23: stepping onto
## that left-hand cell, from above or from below, opens it.
static func native_action(type: String, tile: Vector2i) -> Vector2i:
	if type == "wagon_camp" or type == "oasis":
		return tile + Vector2i(-1, 0)
	return tile


## The whirlpool's entrance cells: every native art cell whose B8 carries the
## 0x80 entrance flag. The canonical action stays first (save data and the AI
## use it), the rest follow right-to-left.
static func _whirlpool_entrances(tile: Vector2i, action: Vector2i,
		art_entries: Array, art_classes: Array) -> Array:
	var seen := {action: true}
	var extra: Array[Vector2i] = []
	for index in art_entries.size():
		if index >= art_classes.size() or (int(art_classes[index]) & 0x80) == 0:
			continue
		var entry: Variant = art_entries[index]
		if not (entry is Array) or (entry as Array).size() != 3:
			continue
		var at := tile + Vector2i(int(entry[0]), int(entry[1]))
		if seen.has(at):
			continue
		seen[at] = true
		extra.append(at)
	extra.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y > b.y or (a.y == b.y and a.x > b.x))
	var out: Array = [[action.x, action.y]]
	for at: Vector2i in extra:
		out.append([at.x, at.y])
	return out


## How an object's entrance may be entered. A native Ancient Lamp converts as a
## genie dwelling, but the DOS original lets a hero step onto it from above,
## which no other dwelling allows, so it takes the lamp's own catalog rule.
static func entry_rule(obj: Dictionary, catalog: Dictionary) -> String:
	var type := String(obj.get("type", ""))
	if type == "dwelling" and String(obj.get("unit", "")) == "genie":
		type = "ancient_lamp"
	return String((catalog.get(type, {}) as Dictionary).get("entry", "all"))


static func load_catalog() -> Dictionary:
	var f := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if f == null:
		push_error("cannot read %s" % CATALOG_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


## One render part. `order` counts how many parts already share this tile and
## phase, which is what keeps two plates on one cell in the order they were
## emitted once the renderer sorts them.
static func _part(order: Dictionary, stable_id: int, tile: Vector2i, phase: String,
		art: String, frames: Array, clock: String, fps: float,
		object_id: int) -> Dictionary:
	var key := "%s|%d,%d" % [phase, tile.x, tile.y]
	var at := int(order.get(key, 0))
	order[key] = at + 1
	var part := {"tile": [tile.x, tile.y], "phase": phase, "order": at,
		"stable_id": stable_id}
	if art != "":
		part["art"] = art
	else:
		part["frames"] = frames.duplicate()
		if clock != "":
			part["clock"] = clock
		else:
			part["fps"] = fps if fps > 0.0 else 4.0
	if object_id >= 0:
		part["object_id"] = object_id
	return part


static func _collide(collision: Dictionary, tile: Vector2i, tall: bool) -> void:
	collision[tile] = bool(collision.get(tile, false)) or tall


static func _collision_rows(collision: Dictionary) -> Array:
	var tiles: Array = collision.keys()
	tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	var rows: Array = []
	for tile: Vector2i in tiles:
		rows.append({"tile": [tile.x, tile.y], "tall": bool(collision[tile])})
	return rows


static func _xy(value: Variant, fallback := Vector2i.ZERO) -> Vector2i:
	if value is Array and (value as Array).size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	return fallback
