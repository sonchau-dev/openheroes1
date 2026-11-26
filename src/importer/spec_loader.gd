class_name SpecLoader
extends RefCounted

## Reads a sprite directory's spec.json into plain data.
##
## The extractor writes one per directory next to the PNGs. It carries what the
## archive's frame headers said, which the pixels cannot: where each frame sits
## against the shared anchor, how big it is, and what the frame is for.
##
## load_spec returns a Dictionary:
##   count       : int                  frames the source file declared
##   sprites     : Array[Dictionary]    one per frame, ordered by id
##   composites  : Array[String]        filenames of the baked composites
##   by_id       : Dictionary           id (int) -> sprite Dictionary
##   by_file     : Dictionary           filename (String) -> sprite Dictionary
##
## Each sprite Dictionary:
##   id     : int
##   file   : String                    PNG filename, relative to the spec dir
##   offset : Vector2i                  (offsetX, offsetY) against the anchor
##   size   : Vector2i                  (width, height)
##   role   : String                    "", "shadow_body", "shadow_gnd",
##                                      "base", "overlay" or "projectile"
##
## Some entries name a file that was never written: the one-pixel filler slots
## in the creature files are declared and skipped. Check the file exists before
## loading it.
##
## A few directories carry no spec at all (clof32, ground32, herologo, ston).
## Every caller indexes those by number, so there is nothing to look up.

const SPEC_FILE := "spec.json"

static var _built_specs: Dictionary = {}


static func load_spec(spec_path: String) -> Dictionary:
	var path := _spec_path(spec_path)
	if _built_specs.has(path):
		return _built_specs[path]

	var result := {
		"count": 0,
		"sprites": [] as Array[Dictionary],
		"composites": [] as Array[String],
		"by_id": {},
		"by_file": {},
	}
	var raw := JsonFile.read_dict(path)
	if raw.is_empty():
		return result

	result.count = int(raw.get("count", 0))
	result.composites.assign(raw.get("composites", []))

	var sprites: Dictionary = raw.get("sprites", {})
	var ids: Array[int] = []
	for key in sprites:
		ids.append(int(key))
	ids.sort()
	for id in ids:
		var sprite_data: Dictionary = sprites[str(id)]
		var entry := _entry(id, sprite_data)
		result.sprites.append(entry)
		result.by_id[id] = entry
		if entry.file != "":
			result.by_file[entry.file] = entry

	var raw_by_file: Dictionary = raw.get("by_file", {})
	for fname: String in raw_by_file:
		var target_id := int(raw_by_file[fname])
		if result.by_id.has(target_id):
			result.by_file[fname] = result.by_id[target_id]

	_built_specs[path] = result
	return result


## One sprite by its frame id, straight off the index instead of scanning the
## array. Returns {} when the directory or the id is unknown.
static func sprite(dir: String, id: int) -> Dictionary:
	var spec := load_spec(_spec_path(dir))
	return (spec.by_id as Dictionary).get(id, {})


## One sprite by its filename. The extractor names most frames after their
## number, but the creature shadows carry descriptive names, and the maps
## imported from the original scenarios reference art by filename.
static func sprite_by_file(dir: String, file: String) -> Dictionary:
	var spec := load_spec(_spec_path(dir))
	return (spec.by_file as Dictionary).get(file, {})


## Drops the accessor cache. Only the asset tooling needs this, when it reads a
## tree it has just rewritten.
static func clear_cache() -> void:
	_built_specs.clear()
	JsonFile.clear_cache()


static func _spec_path(dir_or_path: String) -> String:
	var clean := dir_or_path.trim_suffix("/")
	if clean.ends_with(SPEC_FILE):
		return clean
	return "%s/%s" % [clean, SPEC_FILE]


static func _entry(id: int, sprite_data: Dictionary) -> Dictionary:
	if sprite_data.is_empty():
		return {}
	return {
		"id": id,
		"file": String(sprite_data.get("file", "")),
		"offset": Vector2i(int(sprite_data.get("ox", 0)), int(sprite_data.get("oy", 0))),
		"size": Vector2i(int(sprite_data.get("w", 0)), int(sprite_data.get("h", 0))),
		"role": String(sprite_data.get("role", "")),
	}
