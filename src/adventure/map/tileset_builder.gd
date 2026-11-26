class_name TileSetBuilder
extends RefCounted

## Builds a Godot TileSet from the extracted ground32 terrain tiles.
## Single-source texture atlas layout (TERRAIN_SOURCE_ID == 0).
## 20 water animated tiles (5-frame strips) + 104 static tiles in a unified 512x640 atlas.
## Eliminates per-tile texture switching, enabling the entire terrain layer
## to render in a single GPU draw call.

const GROUND := UiKit.ART + "ground32/"
## Baked by tools/extract/bake.gd from the ground32 tiles, in the layout
## tile_to_atlas_coords() gives.
const ATLAS := UiKit.ART + "ground32_atlas.png"
const TILE := 32

const TERRAIN_SOURCE_ID := 0
const WATER_TILE_COUNT := 20
const WATER_ANIM_FRAMES := 5
const WATER_ANIM_FPS := 5.83

const ATLAS_WIDTH := 512
const ATLAS_HEIGHT := 640
const STATIC_COLS := 11

static var _cached_tileset: TileSet = null

static func tile_to_atlas_coords(tile_id: int) -> Vector2i:
	if tile_id < WATER_TILE_COUNT:
		return Vector2i(0, tile_id)
	var static_idx := tile_id - WATER_TILE_COUNT
	return Vector2i(5 + (static_idx % STATIC_COLS), static_idx / STATIC_COLS)

static func atlas_coords_to_tile(coords: Vector2i) -> int:
	if coords.x < 0 or coords.y < 0:
		return -1
	if coords.x < 5:
		return coords.y
	return WATER_TILE_COUNT + coords.y * STATIC_COLS + (coords.x - 5)

static func alt_id(flip_h: bool, flip_v: bool) -> int:
	var id := 0
	if flip_h:
		id |= TileSetAtlasSource.TRANSFORM_FLIP_H
	if flip_v:
		id |= TileSetAtlasSource.TRANSFORM_FLIP_V
	return id

static func clear_cache() -> void:
	_cached_tileset = null

static func build() -> TileSet:
	if _cached_tileset != null:
		return _cached_tileset

	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)

	var atlas_tex := UiKit.load_texture(ATLAS)
	if atlas_tex == null:
		push_error("TileSetBuilder: %s is missing; rerun tools/extract.gd" % ATLAS)
	var static_count := 0
	while ResourceLoader.exists(GROUND + "%04d.png" % (WATER_TILE_COUNT + static_count)):
		static_count += 1

	var src := TileSetAtlasSource.new()
	src.texture = atlas_tex
	src.texture_region_size = Vector2i(TILE, TILE)

	# Register water tiles with animation
	for w in WATER_TILE_COUNT:
		var coords := tile_to_atlas_coords(w)
		src.create_tile(coords)
		src.set_tile_animation_columns(coords, WATER_ANIM_FRAMES)
		src.set_tile_animation_frames_count(coords, WATER_ANIM_FRAMES)
		src.set_tile_animation_speed(coords, WATER_ANIM_FPS)

	# Register static tiles
	for s in static_count:
		var tile_id := WATER_TILE_COUNT + s
		var coords := tile_to_atlas_coords(tile_id)
		src.create_tile(coords)

	ts.add_source(src, TERRAIN_SOURCE_ID)
	_cached_tileset = ts
	return ts

