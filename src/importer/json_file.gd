class_name JsonFile
extends RefCounted

## Cached reader for read-only JSON data files.
## Replaces copy-pasted FileAccess + JSON.parse_string snippets across the codebase.

static var _cache: Dictionary = {}

## Returns the parsed Dictionary from a JSON file, or {} on missing or invalid data.
## cache = false reads without keeping the result: whole scenario files are large,
## and a cache of every one ever read would only grow.
static func read_dict(path: String, cache := true) -> Dictionary:
	var v: Variant = read_json(path, cache)
	if v is Dictionary:
		return v as Dictionary
	return {}

## Returns the parsed Array from a JSON file, or [] on missing or invalid data.
static func read_array(path: String) -> Array:
	var v: Variant = read_json(path)
	if v is Array:
		return v as Array
	return []

## Returns the parsed JSON Variant (Dictionary, Array, etc.), or null on failure.
static func read_json(path: String, cache := true) -> Variant:
	if path.is_empty():
		return null
	if cache and _cache.has(path):
		return _cache[path]
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("JsonFile: cannot open %s" % path)
		return null
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null and not text.strip_edges().is_empty() and text.strip_edges() != "null":
		push_error("JsonFile: failed to parse JSON from %s" % path)
		return null
	if cache and path.begins_with("res://"):
		_cache[path] = parsed
	return parsed

## Removes a specific file from the cache (e.g. after writing to user://).
static func invalidate(path: String) -> void:
	_cache.erase(path)

## Drops the entire JSON cache.
static func clear_cache() -> void:
	_cache.clear()
