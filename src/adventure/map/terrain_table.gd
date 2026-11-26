class_name TerrainTable
extends RefCounted

## The v2 terrain alphabet (data/terrain/terrain.json): char -> name/base tile/
## passability/move cost. Loader + (later) autotiler read terrain through this.

var defs: Dictionary = {}   # "G" -> {name, base, passable, move_cost}

static func load_table(path: String = "res://data/terrain/terrain.json") -> TerrainTable:
	var data := JsonFile.read_dict(path)
	if data.is_empty():
		push_error("TerrainTable: cannot open or parse %s" % path)
		return null
	var t := TerrainTable.new()
	for key: String in data.keys():
		if key.begins_with("_"):
			continue   # comment keys
		t.defs[key] = data[key]
	return t

func has_char(ch: String) -> bool:
	return defs.has(ch)

func base_tile(ch: String) -> int:
	return int(defs.get(ch, {}).get("base", -1))

func is_passable(ch: String) -> bool:
	return bool(defs.get(ch, {}).get("passable", false))

func move_cost(ch: String) -> int:
	return int(defs.get(ch, {}).get("move_cost", 4))

func terrain_name(ch: String) -> String:
	return String(defs.get(ch, {}).get("name", ""))
