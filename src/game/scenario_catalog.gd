class_name ScenarioCatalog
extends RefCounted

const MAP_DIR := "res://data/maps"
const INDEX_FILE := "index.json"
const INDEX_VERSION := 1
const SKIRMISH := "skirmish01.json"
const PROJECT_SCENARIOS := [SKIRMISH, "naval_test.json", "artifact_test.json",
	"siege_test.json", "arena_ai_test.json", "arena_spells_test.json",
	"arena_ghost_procs_test.json", "arena_blind_duration_test.json",
	"arena_strike_duration_test.json",
	"arena_area_spells_test.json"]

## map_dir -> {mtime: int, data: Dictionary, standard_infos: Array[ScenarioInfo], by_path_infos: Dictionary}
static var _index_cache: Dictionary = {}

## map_dir -> {key: String, list: Array[ScenarioInfo]}: the last fallback listing and the file names/mtimes.
static var _listing_cache: Dictionary = {}

static func clear_cache() -> void:
	_index_cache.clear()
	_listing_cache.clear()

## Builds a scenario index dictionary from all scenario JSON files in map_dir.
static func build_index(map_dir: String = MAP_DIR) -> Dictionary:
	var dir := DirAccess.open(map_dir)
	if dir == null:
		return {}

	# 1. Identify standard candidates (21 native + project scenarios)
	var native_files: Array[String] = []
	var all_json_files: Array[String] = []
	for file in dir.get_files():
		if not file.ends_with(".json") or file == INDEX_FILE:
			continue
		all_json_files.append(file)
		if PROJECT_SCENARIOS.has(file):
			continue
		var stem := file.get_basename()
		if stem.length() == 8 and stem[0] >= "a" and stem[0] <= "u":
			native_files.append(file)
	native_files.sort_custom(func(a: String, b: String) -> bool: return a[0] < b[0])

	var standard_files: Array[String] = []
	standard_files.append_array(native_files)
	for project_scenario: String in PROJECT_SCENARIOS:
		if dir.file_exists(project_scenario):
			standard_files.append(project_scenario)

	# 2. Parse headers of all .json scenarios in map_dir
	var file_mtimes: Dictionary = {}
	var by_path: Dictionary = {}
	var infos_by_file: Dictionary = {}

	for file in all_json_files:
		var path := map_dir.path_join(file)
		file_mtimes[file] = FileAccess.get_modified_time(path)
		var d := JsonFile.read_dict(path, false)
		if d.is_empty() or (int(d.get("version", 0)) != 3 and not d.has("name")):
			continue
		var order := standard_files.find(file)
		var info := ScenarioInfo.from_header(path, d, order)
		if info.is_valid():
			var info_dict := info.to_dict()
			infos_by_file[file] = info_dict
			by_path[path] = info_dict
			by_path[file] = info_dict
			if path.begins_with("res://"):
				by_path[path.trim_prefix("res://")] = info_dict

	# 3. Assemble standard list in order
	var standard_list: Array[Dictionary] = []
	for i in standard_files.size():
		var file := standard_files[i]
		if infos_by_file.has(file):
			var info_dict: Dictionary = (infos_by_file[file] as Dictionary).duplicate(true)
			info_dict["native_order"] = i
			standard_list.append(info_dict)

	return {
		"version": INDEX_VERSION,
		"file_mtimes": file_mtimes,
		"standard": standard_list,
		"by_path": by_path,
	}

## Writes index.json to map_dir (default res://data/maps).
static func write_index(map_dir: String = MAP_DIR) -> bool:
	var index_data := build_index(map_dir)
	if index_data.is_empty():
		return false
	var index_path := map_dir.path_join(INDEX_FILE)
	var f := FileAccess.open(index_path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write scenario index to %s" % index_path)
		return false
	f.store_string(JSON.stringify(index_data, "  ", false) + "\n")
	f.close()
	clear_cache()
	return true

## Checks if the index is stale compared to scenario files on disk in map_dir.
static func is_index_stale(map_dir: String, index_data: Dictionary) -> bool:
	if int(index_data.get("version", 0)) != INDEX_VERSION:
		return true
	var file_mtimes: Dictionary = index_data.get("file_mtimes", {})
	if file_mtimes.is_empty():
		return true

	var dir := DirAccess.open(map_dir)
	if dir == null:
		return false

	var found_scenarios := 0
	for file in dir.get_files():
		if not file.ends_with(".json") or file == INDEX_FILE:
			continue
		found_scenarios += 1
		# A scenario file exists on disk that wasn't indexed: stale!
		if not file_mtimes.has(file):
			return true
		# A scenario file was modified: stale! An exported pack reports every
		# mtime as 0, so there the index is trusted as shipped.
		var path := map_dir.path_join(file)
		var disk_mtime := FileAccess.get_modified_time(path)
		if disk_mtime != 0 and disk_mtime != int(file_mtimes[file]):
			return true

	# If some scenarios exist on disk, but fewer than indexed (one was deleted):
	if found_scenarios > 0 and found_scenarios < file_mtimes.size():
		return true

	return false

## Loads the scenario index from map_dir/index.json if present and fresh.
static func load_index(map_dir: String = MAP_DIR) -> Dictionary:
	var index_path := map_dir.path_join(INDEX_FILE)
	if not FileAccess.file_exists(index_path):
		return {}

	var index_mtime := FileAccess.get_modified_time(index_path)
	var cached: Dictionary = _index_cache.get(map_dir, {})
	if cached.get("mtime", -1) == index_mtime and cached.has("data"):
		return cached.data

	var data := JsonFile.read_dict(index_path, false)
	if data.is_empty():
		return {}

	if is_index_stale(map_dir, data):
		return {}

	var standard_infos: Array[ScenarioInfo] = []
	for d in data.get("standard", []):
		if d is Dictionary:
			var info := ScenarioInfo.from_dict(d)
			if info.is_valid():
				standard_infos.append(info)

	var by_path_infos: Dictionary = {}
	var raw_by_path: Dictionary = data.get("by_path", {})
	for k in raw_by_path:
		var d: Variant = raw_by_path[k]
		if d is Dictionary:
			by_path_infos[k] = ScenarioInfo.from_dict(d)

	_index_cache[map_dir] = {
		"mtime": index_mtime,
		"data": data,
		"standard_infos": standard_infos,
		"by_path_infos": by_path_infos,
	}
	return data

## Native standard scenarios are named a..u. Project test scenarios are
## intentionally appended after those 21 maps in the order above.
static func list_standard(map_dir: String = MAP_DIR) -> Array[ScenarioInfo]:
	var index_data := load_index(map_dir)
	if not index_data.is_empty() and _index_cache.has(map_dir):
		var infos: Array[ScenarioInfo] = _index_cache[map_dir].get("standard_infos", [])
		return infos.duplicate()

	return _fallback_list_standard(map_dir)

static func _fallback_list_standard(map_dir: String) -> Array[ScenarioInfo]:
	var candidates: Array[String] = []
	var dir := DirAccess.open(map_dir)
	if dir == null:
		return []
	for file in dir.get_files():
		if not file.ends_with(".json") or file == INDEX_FILE or PROJECT_SCENARIOS.has(file):
			continue
		var stem := file.get_basename()
		if stem.length() == 8 and stem[0] >= "a" and stem[0] <= "u":
			candidates.append(file)
	candidates.sort_custom(func(a: String, b: String) -> bool: return a[0] < b[0])
	for project_scenario: String in PROJECT_SCENARIOS:
		if dir.file_exists(project_scenario):
			candidates.append(project_scenario)

	# Every header costs a full parse of a scenario up to 1 MB, so reuse the
	# last listing while no file in the directory has changed.
	var signature := PackedStringArray()
	for file in candidates:
		signature.append("%s:%d" % [file, FileAccess.get_modified_time(map_dir.path_join(file))])
	var key := "|".join(signature)
	var cached: Dictionary = _listing_cache.get(map_dir, {})
	if cached.get("key", "") == key:
		return (cached.list as Array[ScenarioInfo]).duplicate()

	var out: Array[ScenarioInfo] = []
	for file in candidates:
		var path := map_dir.path_join(file)
		var parsed := JsonFile.read_dict(path, false)
		if parsed.is_empty() or int(parsed.get("version", 0)) != 3:
			continue
		var info := ScenarioInfo.from_header(path, parsed, out.size())
		if info.is_valid():
			out.append(info)
	_listing_cache[map_dir] = {"key": key, "list": out.duplicate()}
	return out

static func find_by_path(path: String, catalog: Array[ScenarioInfo] = []) -> ScenarioInfo:
	if not catalog.is_empty():
		for info: ScenarioInfo in catalog:
			if info.path == path or info.path.get_file() == path.get_file():
				return info
		return null

	var map_dir := path.get_base_dir() if (path.begins_with("res://") or path.begins_with("/")) and path.get_base_dir() != "" else MAP_DIR
	var index_data := load_index(map_dir)
	if not index_data.is_empty() and _index_cache.has(map_dir):
		var by_path_infos: Dictionary = _index_cache[map_dir].get("by_path_infos", {})
		if by_path_infos.has(path):
			return by_path_infos[path]
		var file := path.get_file()
		if by_path_infos.has(file):
			return by_path_infos[file]

	for info: ScenarioInfo in list_standard(map_dir):
		if info.path == path or info.path.get_file() == path.get_file():
			return info

	var parsed := JsonFile.read_dict(path, false)
	if not parsed.is_empty():
		var info := ScenarioInfo.from_header(path, parsed, -1)
		if info.is_valid():
			return info

	return null
