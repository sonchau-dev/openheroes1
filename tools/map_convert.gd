extends SceneTree

## Turns HOMM1's binary scenarios into the JSON this game loads.
##
##   godot --headless --path . --script tools/map_convert.gd
##   godot --headless --path . --script tools/map_convert.gd -- --map=assets/maps/CLAW.MAP
##
## Flags:
##   --map=PATH     convert one scenario instead of all of them
##   --in=DIR       where the .map and .cmp files are, default assets/maps
##   --out=DIR      where the JSON goes, default data/maps
##   --index-only   only regenerate index.json without converting scenarios
##   --quiet        only print the totals
##
## 21 .map single scenarios and 9 .cmp campaign maps. A .cmp is the same blob
## without the scenario header, so its name, description and objectives come
## from CampaignCatalog rather than from the file.
##
## The four hand-authored scenarios in data/maps are not produced here and this
## never touches them.
##
## Format authority: data/knowledge_base/homm1-native-data.md 4.2 to 4.3.2.

const Convert := preload("res://tools/mapconv/convert.gd")
const Transform := preload("res://tools/mapconv/transform.gd")
const SchemaV3 := preload("res://tools/mapconv/schema_v3.gd")
const NativePassability := preload("res://tools/mapconv/native_passability.gd")

const DEFAULT_IN := "res://assets/maps"
const DEFAULT_OUT := "res://data/maps"


func _initialize() -> void:
	var in_dir := DEFAULT_IN
	var out_dir := DEFAULT_OUT
	var one := ""
	var quiet := false
	var index_only := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			one = arg.trim_prefix("--map=")
		elif arg.begins_with("--in="):
			in_dir = arg.trim_prefix("--in=")
		elif arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg == "--quiet":
			quiet = true
		elif arg == "--index-only":
			index_only = true
		else:
			push_error("unknown argument: %s" % arg)
			quit(2)
			return

	if index_only:
		if ScenarioCatalog.write_index(out_dir):
			if not quiet:
				print("scenario index written -> %s/%s" % [out_dir, ScenarioCatalog.INDEX_FILE])
			quit(0)
		else:
			push_error("failed to write scenario index to %s" % out_dir)
			quit(1)
		return

	var sources := [one] if one != "" else _scenarios(in_dir)
	if sources.is_empty():
		push_error("no .map or .cmp files under %s" % in_dir)
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var converter := Convert.new()
	var catalog: Dictionary = SchemaV3.load_catalog()
	var objects := 0
	var skipped := 0
	var failed := 0

	for path: String in sources:
		var result := convert_file(path, converter, catalog)
		if not result["ok"]:
			push_error("%s: %s" % [path, result["error"]])
			failed += 1
			continue
		var stem := path.get_file().get_basename().to_lower()
		var dst := "%s/%s.json" % [out_dir, stem]
		if not _write(dst, result["map"]):
			failed += 1
			continue
		var count: int = (result["map"]["objects"] as Array).size()
		objects += count
		var missed := 0
		for label in (result["skipped"] as Dictionary):
			missed += int(result["skipped"][label])
		skipped += missed
		if not quiet:
			print("%-16s -> %s  name='%s' objs=%d players=%d skipped=%d" % [
				path.get_file(), dst, result["map"]["name"], count,
				(result["map"]["players"] as Array).size(), missed])
		for label in (result["skipped"] as Dictionary):
			print("    unrecognised %s x%d" % [label, result["skipped"][label]])

	var done := sources.size() - failed
	print("\nconverted %d %s: %d objects placed, %d skipped%s" % [
		done, "map" if done == 1 else "maps", objects, skipped,
		", %d failed" % failed if failed > 0 else ""])
	if failed == 0:
		if ScenarioCatalog.write_index(out_dir):
			if not quiet:
				print("scenario index written -> %s/%s" % [out_dir, ScenarioCatalog.INDEX_FILE])
		else:
			push_error("failed to write scenario index to %s" % out_dir)
	quit(1 if failed > 0 or skipped > 0 else 0)


## Returns {ok, error, map, skipped}. `map` is the finished v3 dictionary.
static func convert_file(path: String, converter: Convert,
		catalog: Dictionary) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "cannot read it", "map": {}, "skipped": {}}
	var data := f.get_buffer(f.get_length())
	f.close()
	return convert_data(data, path.get_file().get_basename(), converter, catalog)


## The whole pipeline on bytes already in memory, so a test can convert a
## scenario it assembled itself. `name` is the file's basename.
static func convert_data(data: PackedByteArray, name: String, converter: Convert,
		catalog: Dictionary) -> Dictionary:
	var result: Dictionary = converter.run(data)
	if not result["ok"]:
		return result

	var stem := name.to_lower()
	var out: Dictionary = result["map"]
	out["supported_human_counts"] = Convert.supported_humans(stem,
		(out["players"] as Array).size())
	if stem.begins_with("camp"):
		var cid := int(stem.substr(4))
		if cid >= 1 and cid <= 9:
			out["name"] = CampaignCatalog.TITLES[cid]
			out["description"] = CampaignCatalog.MAP_DESCRIPTIONS[cid]
	if String(out["name"]) == "":
		out["name"] = _title(name)
	out = Transform.transpose(out)
	out = Transform.promote_composites(out)
	out = Transform.apply_fixups(out, stem)
	result["map"] = _native_passability(SchemaV3.upgrade(out, catalog), result["hmap"])
	return result


## The original's own blocking and directional cells (NativePassability)
## replace whatever the art suggested; its sprite cells say where a monster's
## zone stops (PassabilityGrid.guard_zones); and an object's entrance takes the
## rule of its cell, except where the catalog opens it from every side: DOS
## visits an Oasis from the tile above (probed 2026-09-23 and 2026-10-04; the
## hero stays put), though its cell refuses the step.
static func _native_passability(out: Dictionary, m: RefCounted) -> Dictionary:
	var native := NativePassability.analyse(m)
	var blocked: Dictionary = native["blocked"]
	var directional: Dictionary = native["directional"]
	var tiles: Array = blocked.keys()
	tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var rows: Array = []
	for tile: Vector2i in tiles:
		rows.append({"tile": [tile.x, tile.y], "tall": false})
	out["collision"] = rows
	var masks := {}
	tiles = directional.keys()
	tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for tile: Vector2i in tiles:
		masks["%d,%d" % [tile.x, tile.y]] = Direction.MASK_BUILDING
	out["passability_masks"] = masks
	var sprite_tiles: Array = (native["sprites"] as Dictionary).keys()
	sprite_tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var sprite_rows: Array = []
	for tile: Vector2i in sprite_tiles:
		sprite_rows.append([tile.x, tile.y])
	out["zone_sprites"] = sprite_rows
	var object_tiles: Array = (native["objects"] as Dictionary).keys()
	object_tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var object_rows: Array = []
	for tile: Vector2i in object_tiles:
		object_rows.append([tile.x, tile.y])
	out["object_cells"] = object_rows
	var left: Dictionary = native["after_removal"]
	var left_tiles: Array = left.keys()
	left_tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var left_rows: Array = []
	for tile: Vector2i in left_tiles:
		left_rows.append([tile.x, tile.y, 1 if left[tile] else 0])
	if not left_rows.is_empty():
		out["after_removal"] = left_rows
	for obj: Dictionary in out.get("objects", []):
		var entrances: Array = obj.get("interaction_tiles", [])
		if entrances.is_empty():
			continue
		var at := Vector2i(int(entrances[0][0]), int(entrances[0][1]))
		if String(obj.get("entry", "all")) != "all":
			obj["entry"] = "building" if directional.has(at) else "all"
	return out


## A campaign file carries no name, so it falls back to its filename. Matching
## Python's str.title(): a letter after a non-letter is capitalised, and digits
## are not letters, so camp1 becomes Camp1 rather than Camp 1.
static func _title(text: String) -> String:
	var out := ""
	var after_letter := false
	for i in text.length():
		var ch := text[i]
		var is_letter := (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z")
		out += ch.to_lower() if after_letter else ch.to_upper()
		after_letter = is_letter
	return out


static func _scenarios(dir: String) -> Array:
	var maps: Array = []
	var campaigns: Array = []
	for file in DirAccess.get_files_at(dir):
		var ext := file.get_extension().to_lower()
		if ext == "map":
			maps.append("%s/%s" % [dir, file])
		elif ext == "cmp":
			campaigns.append("%s/%s" % [dir, file])
	maps.sort()
	campaigns.sort()
	maps.append_array(campaigns)
	return maps


static func _write(path: String, value: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % path)
		return false
	# sort_keys off: the dictionaries are built in a deliberate order, header
	# fields first, and sorting them alphabetically makes every diff unreadable.
	f.store_string(JSON.stringify(value, " ", false) + "\n")
	f.close()
	return true
