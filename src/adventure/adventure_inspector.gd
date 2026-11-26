# src/adventure/adventure_inspector.gd
class_name AdventureInspector
extends RefCounted

## Helper for authentic right-click inspection on the adventure map and HUD.

## Long quantity words, heroes.exe's table at data 0x2118c (index 1), used
## for neutral stacks as "%s %s" (data 0x1fd0).
static func quantity_phrase(count: int) -> String:
	if count <= 4:
		return "A few"
	elif count <= 9:
		return "Several"
	elif count <= 19:
		return "A pack of"
	elif count <= 49:
		return "Lots of"
	elif count <= 99:
		return "A Horde of"
	else:
		return "Zounds..."

## Short quantity words, the same table at index 0, used by the hero and
## town quick info.
static func short_quantity(count: int) -> String:
	if count <= 4:
		return "Few"
	elif count <= 9:
		return "Several"
	elif count <= 19:
		return "Pack"
	elif count <= 49:
		return "Lots"
	elif count <= 99:
		return "Horde"
	else:
		return "Zounds!"

## Inspects a map tile, taking into account Fog of War, objects, decor, and terrain.
static func inspect_tile(map: MapData, fog: FogLayer, tile: Vector2i) -> Dictionary:
	if map == null:
		return {"title": "", "body": ""}

	if fog != null and not fog.is_explored(tile):
		return {"title": "Uncharted territory", "body": ""}

	# 1. Check for interactive objects on or associated with this tile
	var obj: MapObject = map.active_object_at_action(tile)
	if obj == null:
		for candidate: MapObject in map.objects:
			if candidate.consumed:
				continue
			if candidate.tile == tile or candidate.action_tile == tile or tile in candidate.interaction_tiles():
				obj = candidate
				break
			# Footprint check for multi-tile objects (Windmill: 2x2, Town/Castle: 4x3)
			if candidate.type == "windmill":
				if tile.x >= candidate.tile.x and tile.x <= candidate.tile.x + 1 \
						and tile.y >= candidate.tile.y - 1 and tile.y <= candidate.tile.y:
					obj = candidate
					break
			elif candidate is TownObject:
				if tile.x >= candidate.tile.x - 2 and tile.x <= candidate.tile.x + 1 \
						and tile.y >= candidate.tile.y - 2 and tile.y <= candidate.tile.y:
					obj = candidate
					break

	if obj != null:
		return inspect_object(obj)

	# 2. Check for static decor in render_parts (Trees, Mountains)
	for raw_part: Variant in map.render_parts:
		if not (raw_part is Dictionary):
			continue
		var part: Dictionary = raw_part
		var t_arr: Array = part.get("tile", [])
		if t_arr.size() >= 2 and int(t_arr[0]) == tile.x and int(t_arr[1]) == tile.y:
			var art := String(part.get("art", ""))
			if art == "" and part.has("frames") and not (part["frames"] as Array).is_empty():
				art = String(part["frames"][0])
			if art.begins_with("tree32/") or art.contains("tree"):
				return {"title": "Trees", "body": ""}
			elif art.begins_with("mtn32/") or art.contains("mtn") or art.contains("mount"):
				return {"title": "Mountains", "body": ""}

	# 3. Check terrain character
	var ch := ""
	if not map.terrain_chars.is_empty() and tile.y >= 0 and tile.y < map.terrain_chars.size():
		var row: String = String(map.terrain_chars[tile.y])
		if tile.x >= 0 and tile.x < row.length():
			ch = row[tile.x]

	match ch:
		"W":
			return {"title": "Ocean", "body": ""}
		"G":
			return {"title": "Grass", "body": ""}
		"S":
			return {"title": "Snow", "body": ""}
		"T":
			return {"title": "Swamp", "body": ""}
		"L":
			return {"title": "Lava", "body": ""}
		"D":
			return {"title": "Desert", "body": ""}
		"I":
			return {"title": "Dirt", "body": ""}

	# 4. Fall back to terrain table or "Nothing here" if unpassable
	if ch != "":
		var table := TerrainTable.load_table()
		if table != null and table.has_char(ch):
			if not table.is_passable(ch):
				return {"title": "Nothing here", "body": ""}
			return {"title": table.terrain_name(ch).capitalize(), "body": ""}

	return {"title": "Nothing here", "body": ""}

## Formats inspection info for a specific MapObject.
static func inspect_object(obj: MapObject) -> Dictionary:
	if obj == null or obj.consumed:
		return {"title": "", "body": ""}

	if obj is NeutralStack:
		var stack := obj as NeutralStack
		var count: int = stack.army.total() if stack.army != null else 1
		var unit_name: String = "creatures"
		if stack.army != null and not stack.army.slots.is_empty():
			unit_name = String(stack.army.slots[0].unit)
		var phrase: String = quantity_phrase(count)
		var title: String = "%s %s" % [phrase, CreatureCatalog.plural(unit_name)]
		return {"title": title, "body": ""}

	if obj is Mine:
		var mine := obj as Mine
		match mine.res:
			"wood": return {"title": "Sawmill", "body": ""}
			"mercury": return {"title": "Alchemist Lab", "body": ""}
			"ore": return {"title": "Ore Mine", "body": ""}
			"gold": return {"title": "Gold Mine", "body": ""}
			"sulfur": return {"title": "Sulfur Mine", "body": ""}
			"crystal": return {"title": "Crystal Mine", "body": ""}
			"gems": return {"title": "Gems Mine", "body": ""}
			_: return {"title": "%s Mine" % mine.res.capitalize(), "body": ""}

	if obj is TownObject:
		var town := obj as TownObject
		var name_str: String = String(town.params.get("name", ""))
		var kind_str: String = "Castle" if bool(town.params.get("has_castle", false)) else "Town"
		var title_str: String = name_str if name_str != "" else kind_str
		return {"title": title_str, "body": ""}

	if obj is ResourcePile:
		var res := obj as ResourcePile
		return {"title": res.res.capitalize(), "body": ""}

	match obj.type:
		"treasure_chest", "chest":
			return {"title": "Treasure Chest", "body": ""}
		"artifact":
			return {"title": "Artifact", "body": ""}
		"obelisk":
			return {"title": "Obelisk", "body": ""}
		"windmill":
			return {"title": "Windmill", "body": ""}
		"watermill":
			return {"title": "Watermill", "body": ""}
		"faerie_ring":
			return {"title": "Faerie Ring", "body": ""}
		"fountain":
			return {"title": "Fountain", "body": ""}
		"statue":
			return {"title": "Statue", "body": ""}
		"gazebo":
			return {"title": "Gazebo", "body": ""}
		"shrine_first", "shrine_second", "shrine_third", "shrine":
			return {"title": "Shrine of Magic", "body": ""}
		"tree_of_knowledge":
			return {"title": "Tree of Knowledge", "body": ""}
		"dwelling":
			var d := obj as Dwelling
			var title := d.title if d != null and d.title != "" else ""
			var unit_name := d.unit if d != null else String(obj.params.get("unit", obj.params.get("unit_type", "")))
			if title == "":
				# heroes.exe's object name table. Thatched Hut, Cottage and
				# Archery Range in that table are town buildings, not the map
				# dwellings they were being used for.
				match unit_name:
					"peasant": title = "House"
					"goblin": title = "Straw Hut"
					"archer": title = "Cabin"
					"dwarf": title = "Log Cabin"
					"nomad": title = "Desert Tent"
					"rogue": title = "Wagon Camp"
					"genie": title = "Ancient Lamp"
					_: title = "Dwelling"
			var body := ""
			if unit_name != "":
				body = "Recruits %s" % CreatureCatalog.plural(unit_name).capitalize()
			return {"title": title, "body": body}
		"thatched_hut":
			return {"title": "Thatched Hut", "body": "Recruits Peasants"}
		"cottage":
			return {"title": "Cottage", "body": "Recruits Dwarves"}
		"archery_range":
			return {"title": "Archery Range", "body": "Recruits Archers"}
		"blacksmith":
			return {"title": "Blacksmith", "body": ""}
		"campfire":
			return {"title": "Campfire", "body": ""}
		"daemon_cave", "demon_cave":
			return {"title": "Demon Cave", "body": ""}
		"rogue_camp", "wagon_camp":
			return {"title": "Wagon Camp", "body": "Recruits Rogues"}
		"nomad_tent", "desert_tent":
			return {"title": "Desert Tent", "body": "Recruits Nomads"}
		"genie_lamp", "ancient_lamp", "lamp":
			return {"title": "Ancient Lamp", "body": "Recruits Genies"}
		"graveyard":
			return {"title": "Graveyard", "body": ""}
		"shipwreck":
			return {"title": "Shipwreck", "body": ""}
		_:
			var display_name: String = obj.type.replace("_", " ").capitalize()
			return {"title": display_name, "body": ""}

## Formats inspection info for HUD action buttons (0..5).
static func button_hint(button_idx: int) -> Dictionary:
	match button_idx:
		0:
			return {"title": "Next Hero (H)", "body": "Select next available hero"}
		1:
			return {"title": "Move Hero (M)", "body": "Walk along the planned route"}
		2:
			return {"title": "Town / Kingdom (T / K)", "body": "View town or kingdom overview"}
		3:
			return {"title": "End Turn (E)", "body": "Pass turn to other players"}
		4:
			return {"title": "Adventure Options / Cast Spell (C)", "body": "View puzzle, world map, cast spells, dig"}
		5:
			return {"title": "System Options (O)", "body": "Game settings, save, load, quit"}
		_:
			return {"title": "", "body": ""}
