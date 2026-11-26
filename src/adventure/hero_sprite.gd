class_name HeroSprite
extends Node2D

## Renders a hero's directional walk frames from kngt32 via hero_anim_table.json.

const ART := UiKit.ART
const TABLE := "res://data/heroes/hero_anim_table.json"
const _DIR_NAMES := ["S", "SE", "E", "NE", "N", "NW", "W", "SW"]

var _sprite: Sprite2D
var _flag_sprite: Sprite2D
var _facings: Dictionary = {}   # dir(int) -> { frames: Array[{tex, off}], mirror: bool }
## Built facings shared by every sprite of one class and flag colour (read-only
## once built). Holding them keeps the walk frames loaded across scene changes,
## so returning to the map does not read every hero's PNGs from disk again.
static var _facings_cache: Dictionary = {}
var _fps: float = 8.0
var _dir: int = Direction.S
var _frame: int = 0
var _elapsed: float = 0.0
var _walking: bool = false

var _tile_size: int = 32
## Where heroes.exe hangs a frame on its cell (0x9ac13): a hero at cell y + 31,
## a boat (or a hero sailing one) 10 px higher. The frame's own offsets add to
## that. A mirrored frame (blit 0xe3066) runs leftward from cell x + 32 - ox,
## one pixel right of a plain flip about x + 32, so mirrored frames flip about
## x + 33. Measured on DOSBox captures of Claw, 2026-10-15.
const HERO_ANCHOR_Y := 31
const BOAT_ANCHOR_Y := 21
const MIRROR_AXIS_X := 33
var _anchor_y: int = HERO_ANCHOR_Y
var _hero_class: String = "knight"
var _crest_idx: int = 0
## False for a boat nobody is sailing: the flag shows only who is aboard.
var show_flag: bool = true

func _init() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = false
	add_child(_sprite)
	
	_flag_sprite = Sprite2D.new()
	_flag_sprite.centered = false
	add_child(_flag_sprite)

func setup(hero_class: String, tile_size: int = 32, crest_idx: int = 0) -> void:
	_hero_class = hero_class
	_crest_idx = crest_idx
	_tile_size = tile_size
	_load_hero(hero_class, crest_idx)
	# Heroes spawn facing east, as in the original game.
	set_direction(Direction.E)

func _load_hero(hero_class: String, crest_idx: int) -> void:
	_anchor_y = HERO_ANCHOR_Y
	var key := "hero:%s:%d" % [hero_class, crest_idx / 4]
	if _facings_cache.has(key):
		_facings = _facings_cache[key]
		_fps = float(_facings_cache[key + ":fps"])
		return
	_facings = {}
	var table := JsonFile.read_dict(TABLE)
	if not table.has(hero_class):
		push_error("HeroSprite: unknown class %s" % hero_class)
		return
	var cfg: Dictionary = table[hero_class]
	var dir_name: String = cfg.get("dir", "")
	_fps = float(cfg.get("fps", 8.0))
	var spec := SpecLoader.load_spec(ART + dir_name + "/spec.json")
	
	var color_idx := crest_idx / 4
	var prefixes := ["b", "g", "r", "y"]
	var color_prefix: String = prefixes[color_idx] if color_idx >= 0 and color_idx < prefixes.size() else "b"
	var flag_dir_name := color_prefix + "-flag32"
	var flag_spec := SpecLoader.load_spec(ART + flag_dir_name + "/spec.json")
	
	var facings: Dictionary = cfg.get("facings", {})
	for i in _DIR_NAMES.size():
		var fn: String = _DIR_NAMES[i]
		if not facings.has(fn):
			continue
		var entry: Dictionary = facings[fn]
		var frames: Array = []
		for idx_v in entry.get("frames", []):
			var idx := int(idx_v)
			var rel_hero := "%s/%04d.png" % [dir_name, idx]
			var tex: Texture2D = MapArtResolver.get_atlas_texture(rel_hero)
			if tex == null:
				tex = UiKit.load_texture(ART + dir_name + "/%04d.png" % idx)
			var rel_flag := "%s/%04d.png" % [flag_dir_name, idx]
			var flag_tex: Texture2D = MapArtResolver.get_atlas_texture(rel_flag)
			if flag_tex == null:
				flag_tex = UiKit.load_texture(ART + flag_dir_name + "/%04d.png" % idx)
			frames.append({
				"tex": tex,
				"off": _offset_by_id(spec, idx),
				"flag_tex": flag_tex,
				"flag_off": _offset_by_id(flag_spec, idx)
			})
		_facings[i] = {"frames": frames, "mirror": bool(entry.get("mirror", false))}
	_facings_cache[key] = _facings
	_facings_cache[key + ":fps"] = _fps

func set_travel_mode(mode: StringName, crest_idx: int = -1) -> void:
	if crest_idx >= 0:
		_crest_idx = crest_idx
	var keep_dir := _dir
	if mode == &"sea":
		_load_boat(_crest_idx)
	else:
		_load_hero(_hero_class, _crest_idx)
	set_direction(keep_dir)

func _load_boat(crest_idx: int) -> void:
	_anchor_y = BOAT_ANCHOR_Y
	var key := "boat:%d" % (crest_idx / 4)
	if _facings_cache.has(key):
		_facings = _facings_cache[key]
		return
	_facings = {}
	var boat_spec := SpecLoader.load_spec(ART + "boat32/spec.json")
	var prefixes := ["b", "g", "r", "y"]
	var color_idx := crest_idx / 4
	var prefix: String = prefixes[color_idx] if color_idx >= 0 and color_idx < prefixes.size() else "b"
	var flag_dir := "%s-bflg32" % prefix
	var flag_spec := SpecLoader.load_spec(ART + flag_dir + "/spec.json")
	var starts := {
		Direction.N: [0, false], Direction.NE: [9, false],
		Direction.E: [18, false], Direction.SE: [27, false],
		Direction.S: [36, false], Direction.SW: [27, true],
		Direction.W: [18, true], Direction.NW: [9, true],
	}
	for dir: int in starts:
		var cfg: Array = starts[dir]
		var frames: Array = []
		for idx in range(int(cfg[0]), int(cfg[0]) + 9):
			var rel_boat := "boat32/%04d.png" % idx
			var tex: Texture2D = MapArtResolver.get_atlas_texture(rel_boat)
			if tex == null:
				tex = UiKit.load_texture(ART + "boat32/%04d.png" % idx)
			var rel_flag := "%s/%04d.png" % [flag_dir, idx]
			var flag_tex: Texture2D = MapArtResolver.get_atlas_texture(rel_flag)
			if flag_tex == null:
				flag_tex = UiKit.load_texture(ART + flag_dir + "/%04d.png" % idx)
			frames.append({
				"tex": tex,
				"off": _offset_by_id(boat_spec, idx),
				"flag_tex": flag_tex,
				"flag_off": _offset_by_id(flag_spec, idx),
			})
		_facings[dir] = {"frames": frames, "mirror": bool(cfg[1])}
	_facings_cache[key] = _facings

func set_direction(dir: int) -> void:
	if not _facings.has(dir):
		return
	_dir = dir
	_frame = 0
	var mirror: bool = _facings[dir].mirror
	scale.x = -1.0 if mirror else 1.0
	position.x = float(MIRROR_AXIS_X) if mirror else 0.0
	_apply()

func play_walk() -> void:
	_walking = true

## Lock the walk cycle to tile-crossing progress t in [0,1) — the original
## plays exactly one 9-frame cycle per tile, restarting on each tile edge.
func set_walk_progress(t: float) -> void:
	if not _facings.has(_dir):
		return
	var frames: Array = _facings[_dir].frames
	if frames.size() <= 1:
		return
	var f := clampi(int(t * frames.size()), 0, frames.size() - 1)
	if f != _frame:
		_frame = f
		_apply()

func walk_frame() -> int:
	return _frame

func stop() -> void:
	_walking = false
	_frame = 0
	_apply()

func advance(dt: float) -> void:
	if not _walking or not _facings.has(_dir):
		return
	var frames: Array = _facings[_dir].frames
	if frames.size() <= 1:
		return
	_elapsed += dt
	var step := 1.0 / _fps
	while _elapsed >= step:
		_elapsed -= step
		_frame = (_frame + 1) % frames.size()
		_apply()

func frame_index() -> int:
	return _frame

func frame_texture() -> Texture2D:
	return _sprite.texture

## True when a world-space pointer is over the visible hero/boat artwork.
## Adventure entities are taller and wider than their logical 32px tile, so
## tile-only pointer picking misses much of a ship's hull.
func hit_test_world(world_position: Vector2) -> bool:
	for visual: Sprite2D in [_sprite, _flag_sprite]:
		if not visual.visible or visual.texture == null:
			continue
		var local_point := visual.to_local(world_position)
		if visual.get_rect().has_point(local_point) and visual.is_pixel_opaque(local_point):
			return true
	return false

func get_direction() -> int:
	return _dir

func _apply() -> void:
	if not _facings.has(_dir):
		return
	var frames: Array = _facings[_dir].frames
	if frames.is_empty():
		return
	var f: Dictionary = frames[_frame]
	_sprite.texture = f.tex
	_sprite.position = Vector2(f.off.x, f.off.y + _anchor_y)
	
	if _flag_sprite != null:
		if show_flag and f.has("flag_tex") and f.flag_tex != null:
			_flag_sprite.texture = f.flag_tex
			_flag_sprite.position = Vector2(f.flag_off.x, f.flag_off.y + _anchor_y)
			_flag_sprite.visible = true
		else:
			_flag_sprite.visible = false

func _offset_by_id(spec: Dictionary, id: int) -> Vector2i:
	if spec.has("by_id") and (spec.by_id as Dictionary).has(id):
		return (spec.by_id as Dictionary)[id].offset
	var fname := "%04d.png" % id
	if spec.has("by_file") and (spec.by_file as Dictionary).has(fname):
		return (spec.by_file as Dictionary)[fname].offset
	for sp in spec.get("sprites", []):
		if sp.id == id or sp.file == fname:
			return sp.offset
	return Vector2i.ZERO
