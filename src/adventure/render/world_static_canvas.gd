class_name WorldStaticCanvas
extends Node2D

## Every native-art render part of a map, painted at the depth heroes.exe gives
## it (AdventureDepth). The ground decals share this node's own canvas item;
## layer 1 gets one canvas item per row and layer 2 one per cell, created on the
## rendering server rather than as nodes, so a large retail map stays a single
## node. Animated delta frames share one clock and redraw only their own item.

var _map: MapData
var _resolver: MapArtResolver
var _elapsed := 0.0
var _reverse := false

## Parts per phase, in paint order.
var _parts: Dictionary = {}          # phase -> Array[Dictionary]
var _ground: Array[Dictionary] = []
## Canvas items: key -> {rid, z_cell, phase, parts, drawn_parts}.
var _items: Dictionary = {}
var _anim_items: Dictionary = {}
var _animated: Array[String] = []
var _object_items: Dictionary = {}   # object id -> Array[String] of item keys
var _ground_objects: Dictionary = {} # object ids with a ground part

var static_redraw_count := 0
var anim_redraw_count := 0

## The rate the original advances every adventure-map animation.
##
## Measured off four DOSBox recordings of three different objects, all of which
## loop their six frames in 0.770 s: the lighthouse lamp on Badlands and on
## Squirrel Lake, the windmill sails on Claw, and the watermill wheel on
## Shangri-La. That is 0.1283 s per frame, or nine VGA refreshes at 70 Hz, so
## the engine is almost certainly ticking these on the retrace.
##
## The watermill is the clean one: all six of its wheel frames are distinct, so
## 0.770 s is what it measures directly. The windmill appears to run twice that
## fast until you notice its sails are three images stored twice, 92 to 94
## repeated as 95 to 97, which is what a four-blade sail looks like half a turn
## on. The lighthouse lamp has five distinct frames of six.
##
## The 4.0 that stood here before was an unexplained default and ran everything
## at about half speed.
const NATIVE_FPS := 7.8

## heroes.exe 0x98950 marks a dug cell with layer-1 group 7 frame 1, a hole.
const HOLE_ART := "obj32-07/0001.png"

## Tiles dug this run, shared with GameState.dug_tiles so a dig shows up at once.
var holes: Array[Vector2i] = []
var holes_drawn := 0

## The puzzle map draws only what heroes.exe 0x9fbcc does: lava, mountain and
## forest sprites (cell groups 4, 8, 9), never a flat layer-1 decal, unanimated.
const PUZZLE_DIRS := ["obj32-04", "mtn32", "tree32"]
var scenery_only := false

func setup(map: MapData, resolver: MapArtResolver) -> void:
	_map = map
	_resolver = resolver
	_free_items()
	z_as_relative = false
	z_index = AdventureDepth.Z_GROUND
	# Paint order: row, then column, then authored order, then stable id. Sorting
	# key arrays lets Array.sort compare natively, ten times faster than a
	# GDScript comparator on a large map.
	var all: Array[Dictionary] = []
	var keyed: Array = []
	for raw: Variant in map.render_parts:
		if not (raw is Dictionary):
			continue
		var part := raw as Dictionary
		if scenery_only and (String(part.get("phase", "")) == AdventureDepth.GROUND
				or not _art_at_time(part).get_slice("/", 0) in PUZZLE_DIRS):
			continue
		var tile: Array = part.get("tile", [0, 0])
		keyed.append([int(tile[1]), int(tile[0]), int(part.get("order", 0)),
				int(part.get("stable_id", 0)), all.size()])
		all.append(part)
	keyed.sort()
	_parts = {AdventureDepth.GROUND: [], AdventureDepth.LAYER_1: [], AdventureDepth.LAYER_2: []}
	for entry: Array in keyed:
		var part: Dictionary = all[int(entry[4])]
		var phase := String(part.get("phase", AdventureDepth.LAYER_1))
		if not _parts.has(phase):
			phase = AdventureDepth.LAYER_1
		(_parts[phase] as Array).append(part)
		var tile := _tile_of(part)
		var object_id := int(part.get("object_id", -1))
		if phase == AdventureDepth.GROUND:
			_ground.append(part)
			if object_id >= 0:
				_ground_objects[object_id] = true
			continue
		if part.has("frames"):
			var anim_key := "anim:%s:%d,%d" % [phase, tile.x, tile.y]
			if not _anim_items.has(anim_key):
				_anim_items[anim_key] = {
					"phase": phase,
					"cell": tile,
					"parts": [],
					"frames": -1,
					"z_index": AdventureDepth.phase_z(phase, tile, _reverse),
					"drawn_parts": [],
					"frame_history": [],
					"rid": _create_item(phase, tile)
				}
			(_anim_items[anim_key]["parts"] as Array).append(part)
			if not _animated.has(anim_key):
				_animated.append(anim_key)
			if object_id >= 0:
				if not _object_items.has(object_id):
					_object_items[object_id] = []
				if not (_object_items[object_id] as Array).has(anim_key):
					(_object_items[object_id] as Array).append(anim_key)
		else:
			var key := "%s:%d" % [phase, tile.y] if phase == AdventureDepth.LAYER_1 \
					else "%s:%d,%d" % [phase, tile.x, tile.y]
			if not _items.has(key):
				_items[key] = {
					"phase": phase,
					"cell": tile,
					"parts": [],
					"z_index": AdventureDepth.phase_z(phase, tile, _reverse),
					"drawn_parts": [],
					"rid": _create_item(phase, tile)
				}
			(_items[key]["parts"] as Array).append(part)
			if object_id >= 0:
				if not _object_items.has(object_id):
					_object_items[object_id] = []
				if not (_object_items[object_id] as Array).has(key):
					(_object_items[object_id] as Array).append(key)
	for key: String in _items:
		_redraw_item(key)
	for key: String in _anim_items:
		_redraw_anim_item(key)
	queue_redraw()
	set_process(not _animated.is_empty() and not scenery_only)

## Flip the order the cells of a row are painted in (AdventureDepth.reverse_for).
func set_reverse(reverse: bool) -> void:
	if reverse == _reverse:
		return
	_reverse = reverse
	for key: String in _items:
		var item: Dictionary = _items[key]
		if String(item["phase"]) == AdventureDepth.LAYER_2:
			var z := AdventureDepth.layer2_z(item["cell"], _reverse)
			item["z_index"] = z
			RenderingServer.canvas_item_set_z_index(item["rid"], z)
	for key: String in _anim_items:
		var item: Dictionary = _anim_items[key]
		if String(item["phase"]) == AdventureDepth.LAYER_2:
			var z := AdventureDepth.layer2_z(item["cell"], _reverse)
			item["z_index"] = z
			RenderingServer.canvas_item_set_z_index(item["rid"], z)

## Every part, or the parts of one phase, in paint order.
func manifest(phase := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: String in [AdventureDepth.GROUND, AdventureDepth.LAYER_1, AdventureDepth.LAYER_2]:
		if phase == "" or phase == p:
			out.append_array(_parts.get(p, []))
	return out

func visible_manifest(phase := "") -> Array[Dictionary]:
	return manifest(phase).filter(func(part: Dictionary) -> bool: return _shows(part))

## z the part with this phase on `tile` is painted at.
func part_z(phase: String, tile: Vector2i) -> int:
	return AdventureDepth.phase_z(phase, tile, _reverse)

func refresh_object(object_id: int) -> void:
	if _ground_objects.has(object_id):
		queue_redraw()
	for key: String in _object_items.get(object_id, []):
		if _items.has(key):
			_redraw_item(key)
		elif _anim_items.has(key):
			_redraw_anim_item(key)

func _process(delta: float) -> void:
	_elapsed += delta
	for key: String in _animated:
		var item: Dictionary = _anim_items[key]
		var frame := _frame_signature(item["parts"])
		if frame != int(item["frames"]):
			_redraw_anim_item(key)

func _draw() -> void:
	if _map == null or _resolver == null:
		return
	for part: Dictionary in _ground:
		if _shows(part):
			_paint(get_canvas_item(), part)
	for tile: Vector2i in holes:
		_paint(get_canvas_item(), {"tile": [tile.x, tile.y], "art": HOLE_ART})
	holes_drawn = holes.size()

## Repaint the ground when a hole was dug or the dug list was reset.
func sync_holes() -> void:
	if holes.size() != holes_drawn:
		queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_free_items()

func _create_item(phase: String, cell: Vector2i) -> RID:
	var rid := RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(rid, get_canvas_item())
	RenderingServer.canvas_item_set_z_as_relative_to_parent(rid, false)
	RenderingServer.canvas_item_set_z_index(rid, AdventureDepth.phase_z(phase, cell, _reverse))
	return rid

func _redraw_item(key: String) -> void:
	static_redraw_count += 1
	var item: Dictionary = _items[key]
	var rid: RID = item["rid"]
	RenderingServer.canvas_item_clear(rid)
	var drawn: Array[Dictionary] = []
	for part: Dictionary in item["parts"]:
		if _shows(part):
			_paint(rid, part)
			drawn.append(part)
	item["drawn_parts"] = drawn

func _redraw_anim_item(key: String) -> void:
	anim_redraw_count += 1
	var item: Dictionary = _anim_items[key]
	var rid: RID = item["rid"]
	RenderingServer.canvas_item_clear(rid)
	var drawn: Array[Dictionary] = []
	for part: Dictionary in item["parts"]:
		if _shows(part):
			_paint(rid, part)
			drawn.append(part)
	item["drawn_parts"] = drawn
	var sig := _frame_signature(item["parts"])
	item["frames"] = sig
	if not item.has("frame_history"):
		item["frame_history"] = []
	(item["frame_history"] as Array).append(sig)

func _paint(rid: RID, part: Dictionary) -> void:
	var art := _art_at_time(part)
	if art == "":
		return
	var tex := _resolver.texture(art)
	if tex == null:
		return
	tex.draw(rid, Vector2(_tile_of(part) * _map.tile_size) + _resolver.offset(art))

func _shows(part: Dictionary) -> bool:
	var object_id := int(part.get("object_id", -1))
	if object_id < 0:
		return true
	var owner := _map.object_by_id(object_id)
	return owner != null and not owner.consumed

func _frame_signature(parts: Array) -> int:
	var sig := 0
	for part: Dictionary in parts:
		if part.has("frames"):
			sig = sig * 31 + _frame_index(part)
	return sig

func _frame_index(part: Dictionary) -> int:
	var frames: Array = part.get("frames", [])
	if frames.is_empty():
		return 0
	var fps := NATIVE_FPS if String(part.get("clock", "native")) == "native" \
			else float(part.get("fps", NATIVE_FPS))
	return int(_elapsed * fps) % frames.size()

func _art_at_time(part: Dictionary) -> String:
	if part.has("art"):
		return String(part.get("art", ""))
	var frames: Array = part.get("frames", [])
	if frames.is_empty():
		return ""
	return String(frames[_frame_index(part)])

func _free_items() -> void:
	for key: String in _items:
		RenderingServer.free_rid(_items[key]["rid"])
	_items.clear()
	for key: String in _anim_items:
		RenderingServer.free_rid(_anim_items[key]["rid"])
	_anim_items.clear()
	_animated.clear()
	_object_items.clear()
	_ground_objects.clear()
	_ground.clear()
	_elapsed = 0.0
	static_redraw_count = 0
	anim_redraw_count = 0

static func _tile_of(part: Dictionary) -> Vector2i:
	var tile: Array = part.get("tile", [0, 0])
	return Vector2i(int(tile[0]), int(tile[1]))
