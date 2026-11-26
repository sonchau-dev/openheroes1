class_name ObjectCatalog
extends RefCounted

## data/objects/catalog.json: per object type — handler id, action-tile offset,
## blocking footprint, default params, minimap class. Adding a map-object type =
## a catalog entry + (if new behavior) one handler script. (Spec Section 5.)

const DEFAULT_PATH := "res://data/objects/catalog.json"

static var _shared: ObjectCatalog = null

var defs: Dictionary = {}       # type -> entry dict
var _handlers: Dictionary = {}  # handler id -> instance

static func shared() -> ObjectCatalog:
	if _shared == null:
		_shared = load_catalog()
	return _shared

static func load_catalog(path: String = DEFAULT_PATH) -> ObjectCatalog:
	var data := JsonFile.read_dict(path)
	if data.is_empty():
		push_error("ObjectCatalog: cannot open or parse %s" % path)
		return null
	var c := ObjectCatalog.new()
	for key: String in data.keys():
		if key.begins_with("_"):
			continue
		c.defs[key] = data[key]
	return c

func has_type(t: String) -> bool:
	return defs.has(t)

func handler_id(t: String) -> String:
	return String(defs.get(t, {}).get("handler", ""))

func action_offset(t: String) -> Vector2i:
	var a: Variant = defs.get(t, {}).get("action_offset", null)
	if a is Array and (a as Array).size() == 2:
		return Vector2i(int(a[0]), int(a[1]))
	return Vector2i.ZERO

## Every tile offset that can trigger the object. Most objects expose only
## action_offset; wide objects may expose multiple equivalent interaction
## cells (the Faerie Ring's left and right openings, for example).
func action_offsets(t: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for e: Variant in defs.get(t, {}).get("action_offsets", []):
		if e is Array and (e as Array).size() == 2:
			var off := Vector2i(int(e[0]), int(e[1]))
			if not out.has(off):
				out.append(off)
	if out.is_empty():
		out.append(action_offset(t))
	return out

func footprint(t: String) -> Array:
	var out: Array = []
	for e in defs.get(t, {}).get("footprint", []):
		if e is Array and (e as Array).size() == 2:
			out.append(Vector2i(int(e[0]), int(e[1])))
	return out

## Additional walkable art tiles that share the object's directional entry
## mask. A castle's lower wall can be crossed horizontally, but its closed top
## edge prevents a diagonal cut through either keep corner.
func entry_tiles(t: String) -> Array:
	var out: Array = []
	for e in defs.get(t, {}).get("entry_tiles", []):
		if e is Array and (e as Array).size() == 2:
			out.append(Vector2i(int(e[0]), int(e[1])))
	return out

## Entry-direction class (spec 2026-07-19): "building" = enterable from the
## sides/below only (Direction.MASK_BUILDING); "horizontal" = the two left/right
## openings of a Faerie Ring; "all" = any of the 8 neighbors.
func entry(t: String) -> String:
	var e := String(defs.get(t, {}).get("entry", "all"))
	if e != "all" and e != "building" and e != "horizontal":
		push_warning("ObjectCatalog: unknown entry '%s' for type '%s' — treating as 'all'" % [e, t])
		return "all"
	return e

## Tall sprite flag: kills diagonal top-entry into left/right neighbors
## (tall-object rule).
func tall(t: String) -> bool:
	return bool(defs.get(t, {}).get("tall", false))

## Force stop-before (halt one tile short, never occupy the action tile) for
## types whose handler isn't pickup/weekly_pickup — e.g. statue, whose art was
## shifted a tile south of its logical position so the head/sword clear the
## tile above, leaving no room for the hero to stand without overlapping it.
func stop_before(t: String) -> bool:
	return bool(defs.get(t, {}).get("stop_before", false))

func default_params(t: String) -> Dictionary:
	return (defs.get(t, {}).get("params", {}) as Dictionary).duplicate(true)

## Visual class used by the live radar. Keeping this catalog-driven means new
## adventure objects can opt into the minimap without adding type checks there.
func minimap_class(t: String) -> String:
	return String(defs.get(t, {}).get("minimap", ""))

## Catalog-driven render art: {} when the type has none
## (still supplied by DynamicObjectProvider). {"dir": "obj32-01", "sprite": 10} for a
## single static sprite (offsets resolved from that dir's spec.json at render
## time); optional {"anim": {"frames": [ids], "fps": N}} layers a looping
## frame-swap sprite above the static body (DynamicObjectProvider._spawn_catalog_animation,
## e.g. windmill sails).
func art(t: String) -> Dictionary:
	var a: Variant = defs.get(t, {}).get("art", null)
	if a is Dictionary:
		return (a as Dictionary).duplicate(true)
	return {}

func handler(t: String) -> RefCounted:
	var hid := handler_id(t)
	if hid == "":
		return null
	if not _handlers.has(hid):
		var script: Variant = load("res://src/adventure/objects/handlers/%s.gd" % hid)
		if script == null:
			push_error("ObjectCatalog: missing handler script '%s'" % hid)
			return null
		_handlers[hid] = (script as GDScript).new()
	return _handlers[hid]
