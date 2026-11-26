class_name MapLoaderJson
extends RefCounted

static var _json_cache: Dictionary = {}

## Art paths found in the asset tree; a scenario names the same few hundred
## frames thousands of times. Misses are not kept, so art extracted later counts.
static var _art_exists: Dictionary = {}

## Parses a v3 char-grid JSON map into MapData. Returns null on malformed input.
## Terrain alphabet + passability come from data/terrain/terrain.json (TerrainTable).
## force_human_side >= 0 overrides the human seat: the player whose `side` matches
## becomes human, all others AI (dev `-- --side=N` override). Ignored if no player
## has that side.
static func load_map(path: String, force_human_side: int = -1) -> MapData:
	if not FileAccess.file_exists(path):
		push_error("MapLoaderJson: cannot open %s" % path)
		return null
	var data: Variant = _read_json(path)
	if not (data is Dictionary):
		push_error("MapLoaderJson: %s is not a JSON object" % path)
		return null
	if int(data.get("version", 1)) != 3:
		push_error("MapLoaderJson: %s: unsupported map version %s (expected 3)" % [path, str(data.get("version", 1))])
		return null

	var table := TerrainTable.load_table()
	if table == null:
		return null

	var terrain_v: Variant = data.get("terrain", [])
	if not (terrain_v is Array):
		push_error("MapLoaderJson: %s: terrain must be an array of row strings" % path)
		return null
	var terrain: Array = terrain_v
	if terrain.is_empty():
		push_error("MapLoaderJson: %s has no terrain rows" % path)
		return null
	var h := terrain.size()
	var w := String(terrain[0]).length()

	var grid: Array = []
	var passable: Array = []
	var chars: Array = []
	for y in h:
		var line := String(terrain[y])
		if line.length() != w:
			push_error("MapLoaderJson: row %d length %d, expected %d" % [y, line.length(), w])
			return null
		chars.append(line)
		var row: Array = []
		var prow: Array = []
		for x in w:
			var ch := line[x]
			if not table.has_char(ch):
				push_error("MapLoaderJson: unknown terrain char '%s' at (%d,%d)" % [ch, x, y])
				return null
			row.append(table.base_tile(ch))
			prow.append(table.is_passable(ch))
		grid.append(row)
		passable.append(prow)

	var md := MapData.new()
	md.setup(String(data.get("name", "")), w, h, int(data.get("tile_size", 32)), grid, passable)
	md.version = 3
	md.seed = int(data.get("seed", 1337))
	md.terrain_chars = chars
	md.description = String(data.get("description", ""))
	md.map_difficulty = clampi(int(data.get("map_difficulty", 0)), 0, 3)
	md.size = clampi(int(data.get("size", 0)), 0, 2)
	for count in data.get("supported_human_counts", []):
		var n := int(count)
		if n >= 1 and n <= 4 and not md.supported_human_counts.has(n):
			md.supported_human_counts.append(n)

	# tile_overrides: {"x,y": {"tile": int, "flipH": bool, "flipV": bool}}
	var ov_v: Variant = data.get("tile_overrides", {})
	if not (ov_v is Dictionary):
		push_error("MapLoaderJson: %s: tile_overrides must be an object" % path)
		return null
	var ov: Dictionary = ov_v
	for key: String in ov.keys():
		var parts := key.split(",")
		if parts.size() != 2:
			push_error("MapLoaderJson: bad tile_overrides key '%s' (want \"x,y\")" % key)
			return null
		if not (parts[0].is_valid_int() and parts[1].is_valid_int()):
			push_error("MapLoaderJson: bad tile_overrides key '%s' (want \"x,y\" ints)" % key)
			return null
		if not (ov[key] is Dictionary):
			push_error("MapLoaderJson: tile_overrides['%s'] must be an object" % key)
			return null
		md.tile_overrides[Vector2i(int(parts[0]), int(parts[1]))] = ov[key]

	var parts_v: Variant = data.get("render_parts", null)
	if not (parts_v is Array):
		push_error("MapLoaderJson: %s: render_parts must be an array" % path)
		return null
	var order_keys: Dictionary = {}
	for i in (parts_v as Array).size():
		var raw: Variant = (parts_v as Array)[i]
		if not (raw is Dictionary):
			push_error("MapLoaderJson: render_parts[%d] must be an object" % i)
			return null
		var part: Dictionary = raw as Dictionary
		var tile := _tile(part, "tile")
		if tile.x < 0 or tile.y < 0 or tile.x >= w or tile.y >= h:
			push_error("MapLoaderJson: render_parts[%d] tile out of bounds" % i)
			return null
		part["tile"] = [tile.x, tile.y]
		var phase := String(part.get("phase", ""))
		if phase != "ground" and phase != "base" and phase != "top":
			push_error("MapLoaderJson: render_parts[%d] phase must be ground, base or top" % i)
			return null
		var has_art := part.has("art") and String(part.get("art", "")) != ""
		var has_frames := part.get("frames", []) is Array and not (part.get("frames", []) as Array).is_empty()
		if has_art == has_frames:
			push_error("MapLoaderJson: render_parts[%d] needs exactly one of art or frames" % i)
			return null
		if has_art:
			var art := String(part.get("art", ""))
			if not _valid_art(art):
				push_error("MapLoaderJson: render_parts[%d] references invalid art '%s'" % [i, art])
				return null
		else:
			var frames: Array = part.get("frames", [])
			for frame: Variant in frames:
				if not _valid_art(String(frame)):
					push_error("MapLoaderJson: render_parts[%d] references invalid frame '%s'" % [i, String(frame)])
					return null
			var has_clock := part.has("clock")
			var has_fps := part.has("fps")
			if has_clock == has_fps or (has_clock and String(part.get("clock", "")) != "native") \
					or (has_fps and float(part.get("fps", 0.0)) <= 0.0):
				push_error("MapLoaderJson: render_parts[%d] animation needs native clock or positive fps" % i)
				return null
		var order := int(part.get("order", -1))
		var order_key := "%d,%d:%s:%d" % [tile.x, tile.y, phase, order]
		if order < 0 or order_keys.has(order_key):
			push_error("MapLoaderJson: render_parts[%d] has invalid/duplicate order" % i)
			return null
		order_keys[order_key] = true
		part["order"] = order
		part["stable_id"] = int(part.get("stable_id", i))
		md.render_parts.append(part)

	var collision_v: Variant = data.get("collision", null)
	if not (collision_v is Array):
		push_error("MapLoaderJson: %s: collision must be an array" % path)
		return null
	var collision_tiles: Dictionary = {}
	for i in (collision_v as Array).size():
		var raw: Variant = (collision_v as Array)[i]
		if not (raw is Dictionary):
			push_error("MapLoaderJson: collision[%d] must be an object" % i)
			return null
		var tile := _tile(raw as Dictionary, "tile")
		if tile.x < 0 or tile.y < 0 or tile.x >= w or tile.y >= h or collision_tiles.has(tile):
			push_error("MapLoaderJson: collision[%d] has invalid/duplicate tile" % i)
			return null
		collision_tiles[tile] = true
		md.collision.append({"tile": [tile.x, tile.y], "tall": bool((raw as Dictionary).get("tall", false))})
		md.block(tile.x, tile.y)

	# Optional directional passability for native obstacle-edge cells. Unlike a
	# collision, a nonzero mask keeps the tile usable through only its open sides.
	var masks_v: Variant = data.get("passability_masks", {})
	if not (masks_v is Dictionary):
		push_error("MapLoaderJson: %s: passability_masks must be an object" % path)
		return null
	for key: String in (masks_v as Dictionary).keys():
		var parts := key.split(",")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			push_error("MapLoaderJson: bad passability_masks key '%s'" % key)
			return null
		var tile := Vector2i(int(parts[0]), int(parts[1]))
		var mask := int((masks_v as Dictionary)[key])
		if (tile.x < 0 or tile.y < 0 or tile.x >= w or tile.y >= h
				or collision_tiles.has(tile) or mask <= 0 or mask > Direction.MASK_ALL):
			push_error("MapLoaderJson: passability_masks['%s'] has invalid tile/mask" % key)
			return null
		md.passability_masks[tile] = mask

	# Optional native monster zones: the cells with a layer-1 sprite.
	var sprites_v: Variant = data.get("zone_sprites", null)
	if sprites_v != null:
		if not (sprites_v is Array):
			push_error("MapLoaderJson: %s: zone_sprites must be an array" % path)
			return null
		md.native_zones = true
		for raw: Variant in sprites_v:
			if not (raw is Array) or (raw as Array).size() != 2:
				push_error("MapLoaderJson: bad zone_sprites entry %s" % [raw])
				return null
			var tile := Vector2i(int(raw[0]), int(raw[1]))
			if tile.x < 0 or tile.y < 0 or tile.x >= w or tile.y >= h:
				push_error("MapLoaderJson: zone_sprites tile %s out of bounds" % [tile])
				return null
			md.zone_sprites[tile] = true

	# Optional native object cells (B8 != 0, scenery included): the creature-month
	# spawn skips them (heroes.exe 0x8026b).
	var cells_v: Variant = data.get("object_cells", null)
	if cells_v != null:
		if not (cells_v is Array):
			push_error("MapLoaderJson: %s: object_cells must be an array" % path)
			return null
		for raw: Variant in cells_v:
			if not (raw is Array) or (raw as Array).size() != 2:
				push_error("MapLoaderJson: bad object_cells entry %s" % [raw])
				return null
			var tile := Vector2i(int(raw[0]), int(raw[1]))
			if tile.x < 0 or tile.y < 0 or tile.x >= w or tile.y >= h:
				push_error("MapLoaderJson: object_cells tile %s out of bounds" % [tile])
				return null
			md.object_cells[tile] = true

	# Optional native cells an object leaves blocked (1) or one-way (0) when it
	# is taken (heroes.exe 0xb46d8).
	var left_v: Variant = data.get("after_removal", [])
	if not (left_v is Array):
		push_error("MapLoaderJson: %s: after_removal must be an array" % path)
		return null
	for raw: Variant in left_v:
		if not (raw is Array) or (raw as Array).size() != 3:
			push_error("MapLoaderJson: bad after_removal entry %s" % [raw])
			return null
		var tile := Vector2i(int(raw[0]), int(raw[1]))
		if tile.x < 0 or tile.y < 0 or tile.x >= w or tile.y >= h:
			push_error("MapLoaderJson: after_removal tile %s out of bounds" % [tile])
			return null
		md.after_removal[tile] = int(raw[2]) != 0

	# ultimate_artifact: {"tile": [x,y], "artifact": "<id>"} — optional buried metadata.
	# Absent/malformed -> stays {} (MapData default).
	var ua_v: Variant = data.get("ultimate_artifact", {})
	if ua_v is Dictionary and not (ua_v as Dictionary).is_empty():
		var ua: Dictionary = (ua_v as Dictionary).duplicate()
		var tile_v: Variant = ua.get("tile", null)
		if tile_v is Array and (tile_v as Array).size() == 2:
			ua["tile"] = [int(tile_v[0]), int(tile_v[1])]
		md.ultimate_artifact = ua

	# ambient_sounds: {"x,y": loop_id, ...} — authored ambient loop grid
	var amb_v: Variant = data.get("ambient_sounds", null)
	if amb_v is Dictionary:
		for k: String in (amb_v as Dictionary):
			var parts := k.split(",")
			if parts.size() == 2:
				var ax := int(parts[0])
				var ay := int(parts[1])
				if ax >= 0 and ay >= 0 and ax < w and ay < h:
					md.ambient_sounds[Vector2i(ax, ay)] = int((amb_v as Dictionary)[k])

	var pl: Variant = data.get("players", null)
	if pl is Array:
		for pspec in pl:
			if not (pspec is Dictionary):
				continue
			var heroes: Array = []
			# One entry per hero: [x, y], or {"tile": [x, y], "preset": {...}}
			# where the preset uses the keys of a saved hero (HeroModel.to_dict)
			# and replaces what a new game would roll for that hero.
			var presets: Array = []
			for hentry in pspec.get("heroes", []):
				var hpos: Variant = hentry
				var preset: Dictionary = {}
				if hentry is Dictionary:
					hpos = (hentry as Dictionary).get("tile", null)
					var raw_preset: Variant = (hentry as Dictionary).get("preset", {})
					if raw_preset is Dictionary:
						preset = (raw_preset as Dictionary).duplicate(true)
				if hpos is Array and (hpos as Array).size() == 2:
					heroes.append(Vector2i(int(hpos[0]), int(hpos[1])))
					presets.append(preset)
			var start: Vector2i = heroes[0] if not heroes.is_empty() else Vector2i.ZERO
			md.players.append({
				"side": int(pspec.get("side", md.players.size())),
				"authored_side": int(pspec.get("side", md.players.size())),
				"human": bool(pspec.get("human", md.players.is_empty())),
				"heroes": heroes,
				"hero_presets": presets,
				"hero_start": start,   # legacy key; game.gd reads it
				"color": int(pspec.get("color", 0)),
				"team": int(pspec.get("team", pspec.get("side", md.players.size()))),
			})
		# Dev override: reseat the human player onto force_human_side (if present).
		if force_human_side >= 0:
			var found := false
			for p: Dictionary in md.players:
				if int(p.side) == force_human_side:
					found = true
					break
			if found:
				for p: Dictionary in md.players:
					p.human = int(p.side) == force_human_side
			else:
				push_warning("MapLoaderJson: %s has no player with side %d — keeping default human" % [path, force_human_side])
		for p: Dictionary in md.players:
			if bool(p.human):
				md.hero_start = p.hero_start
				break

	if md.players.is_empty():
		push_error("MapLoaderJson: %s has no players" % path)
		return null
	var has_human := false
	for p: Dictionary in md.players:
		if bool(p.human):
			has_human = true
			break
	if not has_human:
		push_error("MapLoaderJson: %s has no human player" % path)
		return null

	# Optional free boats present at the beginning of a new game. Boat IDs remain
	# runtime state; maps author only location, ownership, and initial facing.
	var boats_v: Variant = data.get("boats", [])
	if not (boats_v is Array):
		push_error("MapLoaderJson: %s: boats must be an array" % path)
		return null
	var occupied_boat_tiles: Dictionary = {}
	for i in (boats_v as Array).size():
		var boat_v: Variant = (boats_v as Array)[i]
		if not (boat_v is Dictionary):
			push_error("MapLoaderJson: boats[%d] must be an object" % i)
			return null
		var boat_spec := boat_v as Dictionary
		var boat_tile := _tile(boat_spec, "tile")
		if not md.is_water(boat_tile):
			push_error("MapLoaderJson: boats[%d] must be placed on water" % i)
			return null
		if occupied_boat_tiles.has(boat_tile):
			push_error("MapLoaderJson: duplicate boat at %s" % boat_tile)
			return null
		occupied_boat_tiles[boat_tile] = true
		md.starting_boats.append({
			"tile": boat_tile,
			"owner": int(boat_spec.get("owner", -1)),
			"direction": int(boat_spec.get("direction", Direction.E)),
		})

	# Deterministic RNG so random pickup amounts are stable across loads (tests).
	var rng := RandomNumberGenerator.new()
	rng.seed = md.seed

	var cat := ObjectCatalog.shared()
	if cat == null:
		push_error("MapLoaderJson: object catalog unavailable — cannot load %s" % path)
		return null

	var obj_list: Array = data.get("objects", [])
	for i in obj_list.size():
		if not (obj_list[i] is Dictionary):
			push_error("MapLoaderJson: objects[%d] must be an object" % i)
			return null
		var spec: Dictionary = obj_list[i]
		if _tile(spec, "tile") == Vector2i(-1, -1):
			push_error("MapLoaderJson: objects[%d] (%s) has a missing or malformed tile; skipped" % [i, spec.get("type", "")])
			continue
		var obj := _build_object(spec, rng)
		if obj == null:
			push_warning("MapLoaderJson: objects[%d] has unknown type %s; skipped" % [i, spec.get("type", "")])
			continue
		obj.id = md.objects.size()
		var interaction_v: Variant = spec.get("interaction_tiles", null)
		if not (interaction_v is Array) or (interaction_v as Array).is_empty():
			push_error("MapLoaderJson: objects[%d] needs interaction_tiles in v3" % i)
			return null
		for action_v: Variant in interaction_v as Array:
			if not (action_v is Array) or (action_v as Array).size() != 2:
				push_error("MapLoaderJson: objects[%d] has malformed interaction tile" % i)
				return null
			var action := Vector2i(int(action_v[0]), int(action_v[1]))
			if action.x < 0 or action.y < 0 or action.x >= w or action.y >= h:
				push_error("MapLoaderJson: objects[%d] interaction tile out of bounds" % i)
				return null
			if not obj.authored_interaction_tiles.has(action):
				obj.authored_interaction_tiles.append(action)
		obj.action_tile = obj.authored_interaction_tiles[0]
		obj.entry_rule = String(spec.get("entry", "all"))
		if obj.entry_rule not in ["all", "building", "horizontal"]:
			push_error("MapLoaderJson: objects[%d] has invalid entry '%s'" % [i, obj.entry_rule])
			return null
		if obj is DragonCity:
			for existing: MapObject in md.objects:
				if existing is DragonCity:
					push_warning("MapLoaderJson: %s has more than one dragon_city — only one is supported per the note" % path)
					break
		md.objects.append(obj)

	for part: Dictionary in md.render_parts:
		var object_id := int(part.get("object_id", -1))
		if object_id < -1 or object_id >= md.objects.size():
			push_error("MapLoaderJson: render part references invalid object_id %d" % object_id)
			return null
		if object_id >= 0:
			(md.objects[object_id] as MapObject).map_art = true

	md.rebuild_indexes()
	return md

## Random pickup ranges (data/knowledge_base/objects.md).
const _RES_RANGE := {
	"gold": [500, 1000], "wood": [8, 16], "ore": [8, 16],
	"gems": [3, 7], "crystal": [3, 7], "sulfur": [3, 7], "mercury": [3, 7],
}

static func _tile(spec: Dictionary, key: String) -> Vector2i:
	var a: Variant = spec.get(key, null)
	if a is Array and (a as Array).size() == 2:
		return Vector2i(int(a[0]), int(a[1]))
	return Vector2i(-1, -1)

static func _valid_art(art: String) -> bool:
	if _art_exists.has(art):
		return true
	var ok := art.split("/").size() == 2 and not art.contains("..") \
			and (ResourceLoader.exists("res://assets/art/" + art) or FileAccess.file_exists("res://assets/art/" + art))
	if ok:
		_art_exists[art] = true
	return ok

## The parsed JSON of the last res:// map, so the scene reload after every
## town, battle or hero screen skips the read and parse. Scenario JSON is
## read-only during map loading and gameplay, so the parsed dictionary is safely
## shared with subsequent loads without duplicating. Only one map is kept.
static func _read_json(path: String) -> Variant:
	var cacheable := path.begins_with("res://")
	var mtime := FileAccess.get_modified_time(path) if cacheable else 0
	if cacheable and _json_cache.get("path", "") == path and int(_json_cache.get("mtime", -1)) == mtime:
		return _json_cache.get("data")
	var data: Variant = JsonFile.read_json(path, false)
	if cacheable and data is Dictionary:
		_json_cache = {"path": path, "mtime": mtime, "data": data}
	return data

static func _army(rows: Array) -> ArmyData:
	var ad := ArmyData.new()
	for u: Array in rows:
		ad.add(String(u[0]), int(u[1]), false)
	return ad

## Build a single MapObject from its JSON spec. action_tile and footprint are
## derived afterward by the caller (load_map's load loop) from the object catalog.
static func _build_object(spec: Dictionary, rng: RandomNumberGenerator) -> MapObject:
	var t := _tile(spec, "tile")
	var kind := String(spec.get("type", ""))
	match kind:
		"artifact":
			var artifact := ArtifactPickup.new()
			artifact.type = kind; artifact.tile = t
			artifact.params = _merged_params(kind, spec)
			var authored_id := String(spec.get("artifact_id",
					spec.get("artifact", artifact.params.get("artifact", ""))))
			var authored_mode := String(spec.get("encounter_mode",
					artifact.params.get("encounter_mode", "")))
			artifact.authored_artifact = authored_id != ""
			artifact.authored_mode = authored_mode != ""
			artifact.artifact_id = ArtifactCatalog.shared().normalize(authored_id) if authored_id != "" else ""
			artifact.encounter_mode = authored_mode
			artifact.resolved = authored_id != "" and authored_mode != ""
			return artifact
		"resource":
			var p := ResourcePile.new()
			p.type = kind; p.tile = t
			p.res = String(spec.get("res", "gold"))
			if p.res == "random":
				var native_resources := ["wood", "mercury", "ore", "sulfur", "crystal", "gems", "gold"]
				p.res = native_resources[rng.randi_range(0, native_resources.size() - 1)]
			p.amount_authored = spec.has("amount")
			if spec.has("amount"):
				p.amount = int(spec["amount"])
			elif p.res == "gold":
				p.amount = rng.randi_range(5, 10) * 100   # 500–1000 in steps of 100
			else:
				var rg: Array = _RES_RANGE.get(p.res, [1, 1])
				p.amount = rng.randi_range(int(rg[0]), int(rg[1]))
			p.params = _merged_params(kind, spec)
			return p
		"mine":
			var m := Mine.new()
			m.type = kind; m.tile = t
			m.res = String(spec.get("res", "ore"))
			m.params = _merged_params(kind, spec)
			# Native scenarios name only the resource; the yield follows from it.
			m.daily = int(spec.get("daily", (m.params.get("yield", {}) as Dictionary).get(m.res, 0)))
			if spec.has("guard"):
				m.guard = _army(spec["guard"])
			return m
		"dragon_city":
			# Mine-shaped (capture -> daily yield), NOT
			# routed through the generic guarded_pickup match below — see
			# src/adventure/objects/dragon_city.gd header for why.
			# KB objects.md §7.2: guarded by 5 dragons (one dragon per stack).
			var dc := DragonCity.new()
			dc.type = kind; dc.tile = t
			dc.owner = int(spec.get("owner", -1))
			if spec.has("guard"):
				dc.guard = _army(spec["guard"])
			else:
				dc.guard = _army([["dragon", 1], ["dragon", 1], ["dragon", 1], ["dragon", 1], ["dragon", 1]])
			dc.params = _merged_params(kind, spec)
			return dc
		"dwelling", "wagon_camp", "desert_tent", "nomad_tent", "ancient_lamp", "genie_lamp":
			var d := Dwelling.new()
			d.type = kind; d.tile = t
			d.params = _merged_params(kind, spec)
			d.unit = String(spec.get("unit", d.params.get("unit", "peasant")))
			d.weekly = int(spec.get("weekly", d.params.get("weekly", 0)))
			d.weekly_min = int(spec.get("weekly_min", d.params.get("weekly_min", 0)))
			d.weekly_max = int(spec.get("weekly_max", d.params.get("weekly_max", 0)))
			d.cost = int(spec.get("cost", d.params.get("cost", 0)))
			var raw_cr: Variant = spec.get("cost_resources", d.params.get("cost_resources", {}))
			d.cost_resources = {}
			if raw_cr is Dictionary:
				for rk: String in (raw_cr as Dictionary):
					d.cost_resources[rk] = int((raw_cr as Dictionary)[rk])
			d.disappears_when_empty = bool(spec.get("disappears_when_empty", d.params.get("disappears_when_empty", false)))
			d.title = String(spec.get("title", d.params.get("title", "")))
			d.offer_text = String(spec.get("offer_text", d.params.get("offer_text", "")))
			d.empty_text = String(spec.get("empty_text", d.params.get("empty_text", "")))
			# Native scenario dwellings keyed by unit defaults if cost is unspecified
			if d.unit == "nomad" and d.cost == 0:
				d.cost = 200
				if d.weekly_min == 0: d.weekly_min = 1
				if d.weekly_max == 0: d.weekly_max = 3
				if d.title == "": d.title = "Tents"
			elif d.unit == "genie" and d.cost == 0 and d.cost_resources.is_empty():
				d.cost = 650
				d.cost_resources = {"gold": 650, "gems": 1}
				d.weekly = 0
				d.disappears_when_empty = true
				if d.title == "": d.title = "Genie Lamp"
			elif d.unit == "rogue" and d.cost == 0:
				d.cost = 50
				if d.weekly_min == 0: d.weekly_min = 3
				if d.weekly_max == 0: d.weekly_max = 6
				if d.title == "": d.title = "Wagon"
			elif d.unit == "peasant":
				if d.title == "": d.title = "Thatched Hut"
				if d.weekly_min == 0 and d.weekly_max == 0 and not spec.has("weekly"):
					d.weekly_min = 5; d.weekly_max = 10
			elif d.unit == "archer":
				if d.title == "": d.title = "Cottage"
				if d.weekly_min == 0 and d.weekly_max == 0 and not spec.has("weekly"):
					d.weekly_min = 1; d.weekly_max = 4
			elif d.unit == "goblin":
				if d.title == "": d.title = "Hut"
				if d.weekly_min == 0 and d.weekly_max == 0 and not spec.has("weekly"):
					d.weekly_min = 3; d.weekly_max = 6
			elif d.unit == "dwarf":
				if d.title == "": d.title = "Cottage"
				if d.weekly_min == 0 and d.weekly_max == 0 and not spec.has("weekly"):
					d.weekly_min = 1; d.weekly_max = 3

			if spec.has("available"):
				d.available = int(spec.available)
			else:
				var def_min := 0
				var def_max := 0
				match d.unit:
					"nomad": def_min = 10; def_max = 20
					"genie": def_min = 2; def_max = 5
					"rogue": def_min = 30; def_max = 50
					"peasant": def_min = 20; def_max = 50
					"archer": def_min = 1; def_max = 4
					"goblin": def_min = 10; def_max = 30
					"dwarf": def_min = 1; def_max = 3
					_: def_min = d.weekly; def_max = d.weekly
				var initial_min := int(d.params.get("initial_min", def_min))
				var initial_max := int(d.params.get("initial_max", def_max if def_max > 0 else initial_min))
				d.available = rng.randi_range(mini(initial_min, initial_max), maxi(initial_min, initial_max))
			return d
		"stack":
			var s := NeutralStack.new()
			s.type = kind; s.tile = t
			s.army = _army(spec.get("army", []))
			s.random_stack_id = int(spec.get("random_stack_id", -1))
			s.random_unit = String(spec.get("unit", ""))
			s.joinable = bool(spec.get("joinable", false))
			s.fought_before = bool(spec.get("fought_before", false))
			s.authored_fixed = bool(spec.get("authored_fixed", s.random_stack_id < 0 and s.random_unit == ""
					and s.army != null and not s.army.is_empty()))
			s.params = _merged_params(kind, spec)
			return s
		"shrine":
			# Spell is NOT rolled here: this loader also runs under deterministic
			# per-map seeding (amounts above), while the shrine's spell should use
			# the game's live RNG. adventure_map.gd's _spawn_objects() rolls it
			# (via Game.rng) the first time the object is spawned, then persists it.
			var sh := Shrine.new()
			sh.type = kind; sh.tile = t
			sh.params = _merged_params(kind, spec)
			return sh
		"town":
			var tw := TownObject.new()
			tw.type = kind; tw.tile = t
			tw.town_type = int(spec.get("town_type", 0))
			tw.owner = int(spec.get("owner", -1))
			tw.authored_owner = tw.owner
			tw.params = _merged_params(kind, spec)
			if spec.has("army") and spec["army"] is Array:
				tw.garrison = _army(spec["army"])
			elif tw.params.has("army") and tw.params["army"] is Array:
				tw.garrison = _army(tw.params["army"])
			# A neutral town's garrison is generated when the map starts, not
			# here: it is 4 stacks of level 1-4 creatures of that town's own
			# faction (KB calendar-economy.md §6.1), and a "random" town
			# (town_type 4, trailer faction 4) only learns its faction when
			# the run resolves it. RunSetup._roll_neutral_garrisons() does the
			# roll once the faction is known.
			if tw.garrison != null:
				tw.params["army"] = tw.garrison
			return tw
		"lighthouse":
			var light := Lighthouse.new()
			light.type = kind; light.tile = t
			light.owner = int(spec.get("owner", -1))
			light.params = _merged_params(kind, spec)
			return light
	# Any catalog type routed to the guarded_pickup handler (graveyard,
	# demon_cave, plus the bare `guarded_pickup` seam type) becomes a
	# GuardedPickup. dragon_city is Mine-shaped
	# instead and has its own match arm above. Its outcome table lives
	# in params.outcomes (catalog default merged under authored spec) — kept
	# generic so new guarded sites need only a catalog entry, no loader change.
	var cat := ObjectCatalog.shared()
	if cat != null and cat.has_type(kind) and cat.handler_id(kind) == "guarded_pickup":
		var gp := GuardedPickup.new()
		gp.type = kind; gp.tile = t
		gp.params = _merged_params(kind, spec)
		var oc: Variant = gp.params.get("outcomes", [])
		gp.outcomes = oc if oc is Array else []
		return gp
	# Any catalog type routed to the weekly_pickup
	# handler (windmill/watermill) becomes a WeeklyPickup. last_collected_week
	# is runtime state (Game.record_object_state), never authored on the map
	# spec, so nothing to parse here beyond the merged params -- same shape as
	# the guarded_pickup arm just above.
	if cat != null and cat.has_type(kind) and cat.handler_id(kind) == "weekly_pickup":
		var wp := WeeklyPickup.new()
		wp.type = kind; wp.tile = t
		wp.params = _merged_params(kind, spec)
		return wp
	# Generic catalog-driven object: no dedicated class needed.
	if cat != null and cat.has_type(kind):
		var g := MapObject.new()
		g.type = kind; g.tile = t
		g.params = _merged_params(kind, spec)
		return g
	return null

## Catalog default_params merged under authored spec params, normalized (JSON
## floats -> ints for whole values). Shared by every typed arm above and the
## generic branch so authored params (e.g. a town's `name`) survive load —
## previously only the generic branch did this and typed arms silently
## dropped authored params.
static func _merged_params(kind: String, spec: Dictionary) -> Dictionary:
	var cat := ObjectCatalog.shared()
	var params: Dictionary = cat.default_params(kind) if cat != null else {}
	var sp: Variant = spec.get("params", {})
	if sp is Dictionary:
		params.merge(sp as Dictionary, true)
	return _normalize_params(params)

## JSON numbers parse as floats; whole-valued floats in authored params are ints.
## Covers scalars and nested Dictionaries only — Arrays are NOT walked, so tier
## tables (e.g. chest/campfire "tiers") stay float-valued inside params; readers
## int-cast on use (see pickup.gd).
static func _normalize_params(p: Dictionary) -> Dictionary:
	var out := {}
	for k in p.keys():
		var v: Variant = p[k]
		if v is float and v == floorf(v):
			out[k] = int(v)
		elif v is Dictionary:
			out[k] = _normalize_params(v)
		else:
			out[k] = v
	return out
