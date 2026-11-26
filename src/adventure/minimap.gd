# src/adventure/minimap.gd
class_name Minimap
extends Control

## Live radar: terrain blocks + catalog-driven landmark and hero markers +
## camera-view rectangle.
## Click/drag pans the camera. Static helpers below are pure and unit-tested.

## Camera-view rectangle: dashed salmon matching radar/0001.png and the DOS UI.
const VIEW_RECT_COLOR := Color8(236, 98, 119)
const LOGO := UiKit.ART + "herologo/0000.png"

static func tile_block(rect_size: Vector2, map_tiles: Vector2i) -> Vector2:
	return Vector2(rect_size.x / float(map_tiles.x), rect_size.y / float(map_tiles.y))

static func world_to_minimap(world: Vector2, rect: Rect2, map_px: Vector2) -> Vector2:
	var frac := Vector2(world.x / map_px.x, world.y / map_px.y)
	return rect.position + Vector2(frac.x * rect.size.x, frac.y * rect.size.y)

static func minimap_to_world(mm: Vector2, rect: Rect2, map_px: Vector2) -> Vector2:
	var frac := Vector2((mm.x - rect.position.x) / rect.size.x, (mm.y - rect.position.y) / rect.size.y)
	return Vector2(frac.x * map_px.x, frac.y * map_px.y)

var show_logo: bool = false
var _map: MapData
var _hero: Hero
var _cam: MapCamera
var _rect: Rect2                     # minimap pixel rect on screen
var _cam_view: Vector2 = Vector2.ZERO # clamp view size used to draw the view rectangle
var _enemy_markers: Array[Dictionary] = []
var _fog: FogLayer = null
var _terrain_texture: Texture2D = null
var _logo_texture: Texture2D = null
var _last_cam_pos: Vector2 = Vector2(-999999, -999999)
var _last_cam_view: Vector2 = Vector2.ZERO
var _landmark_objects: Array[MapObject] = []
var _landmark_markers: Array[Dictionary] = []

signal pan_requested(world_pos: Vector2)

static func cell_color(map: MapData, fog: FogLayer, x: int, y: int) -> Color:
	if map == null:
		return Color.BLACK
	if fog != null and not fog.is_explored(Vector2i(x, y)):
		return Color.BLACK
	return MinimapColors.radar_color(tile_index_at(map, x, y))

## The scenario's own ground tile index for a cell. The grid only holds the
## terrain class, so shores and variants live in the overrides.
static func tile_index_at(map: MapData, x: int, y: int) -> int:
	var override: Dictionary = map.tile_overrides.get(Vector2i(x, y), {})
	return int(override.get("tile", map.get_tile(x, y)))

## Tiles whose base layer holds a mountain or tree; the radar draws them in the
## shaded colour.
static func shaded_tiles(map: MapData) -> Dictionary:
	var shaded := {}
	for raw_part: Variant in map.render_parts:
		if not (raw_part is Dictionary) or String(raw_part.get("phase", "")) != "base":
			continue
		var art := String(raw_part.get("art", ""))
		if art == "" and raw_part.has("frames") and not (raw_part["frames"] as Array).is_empty():
			art = String(raw_part["frames"][0])
		if not (art.begins_with("mtn32/") or art.begins_with("tree32/")):
			continue
		var t: Array = raw_part.get("tile", [])
		if t.size() >= 2:
			shaded[Vector2i(int(t[0]), int(t[1]))] = true
	return shaded

## ground32 stores four transform variants for each native 6px radar tile.
## Integer division recovers the exact GROUND6 frame used by the original.
static func native_ground_frame(tile_index: int) -> int:
	return tile_index / 4 if tile_index >= 0 else -1

func setup(map: MapData, hero: Hero, cam: MapCamera, rect: Rect2, cam_view: Vector2, enemy_tile: Vector2i, fog: FogLayer = null) -> void:
	if _fog != null and is_instance_valid(_fog) and _fog.fog_changed.is_connected(_on_fog_changed):
		_fog.fog_changed.disconnect(_on_fog_changed)
	_map = map
	_hero = hero
	_cam = cam
	_rect = rect
	_cam_view = cam_view
	_last_cam_pos = _cam.global_position if _cam != null else Vector2(-999999, -999999)
	_last_cam_view = cam_view
	_enemy_markers.clear()
	if enemy_tile != Vector2i(-1, -1):
		_enemy_markers.append({"tile": enemy_tile, "color": Color8(208, 0, 0)})
	_fog = fog
	if _fog != null:
		_fog.fog_changed.connect(_on_fog_changed)
	position = rect.position
	size = rect.size
	# Hover motion must reach the input controller so the map cursor reverts to the arrow.
	mouse_filter = Control.MOUSE_FILTER_PASS
	_terrain_texture = _build_terrain_texture()
	_logo_texture = UiKit.load_texture(LOGO)
	_index_landmark_objects()
	_update_landmark_markers()
	queue_redraw()

func _exit_tree() -> void:
	if _fog != null and is_instance_valid(_fog) and _fog.fog_changed.is_connected(_on_fog_changed):
		_fog.fog_changed.disconnect(_on_fog_changed)

func _on_fog_changed() -> void:
	if _update_landmark_markers():
		pass
	queue_redraw()

func _index_landmark_objects() -> void:
	_landmark_objects.clear()
	if _map == null:
		return
	var catalog := ObjectCatalog.shared()
	for obj: MapObject in _map.objects:
		if obj == null:
			continue
		var kind := catalog.minimap_class(obj.type)
		if kind == "town" or kind == "mine":
			_landmark_objects.append(obj)

func _update_landmark_markers() -> bool:
	var new_markers: Array[Dictionary] = []
	for obj: MapObject in _landmark_objects:
		var marker := landmark_marker(_map, _fog, obj)
		if not marker.is_empty():
			new_markers.append(marker)
	if _landmark_markers_equal(_landmark_markers, new_markers):
		return false
	_landmark_markers = new_markers
	return true

static func _landmark_markers_equal(a: Array[Dictionary], b: Array[Dictionary]) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		var ma: Dictionary = a[i]
		var mb: Dictionary = b[i]
		if ma.get("tile", Vector2i(-1, -1)) != mb.get("tile", Vector2i(-1, -1)):
			return false
		if ma.get("size", Vector2i.ZERO) != mb.get("size", Vector2i.ZERO):
			return false
		if ma.get("color", Color.BLACK) != mb.get("color", Color.BLACK):
			return false
	return true

func refresh() -> bool:
	var redraw_needed := _update_landmark_markers()
	if refresh_camera():
		redraw_needed = true
	elif redraw_needed:
		queue_redraw()
	return redraw_needed

## Per-frame path: only the camera box can change between events. Landmarks
## follow fog_changed and the HUD refresh after an ownership change.
func refresh_camera() -> bool:
	if _cam == null:
		return false
	var cam_pos := _cam.global_position
	if cam_pos == _last_cam_pos and _cam_view == _last_cam_view:
		return false
	_last_cam_pos = cam_pos
	_last_cam_view = _cam_view
	queue_redraw()
	return true

func set_show_logo(enabled: bool) -> bool:
	if show_logo == enabled:
		return false
	show_logo = enabled
	queue_redraw()
	return true

## Side-aware form used by AdventureMap. Each entry is {tile: Vector2i,
## owner: runtime side}; the map's player-color assignment determines its hue.
func set_enemy_markers(markers: Array[Dictionary]) -> bool:
	if _markers_equal(_enemy_markers, markers):
		return false
	_enemy_markers = markers.duplicate(true)
	queue_redraw()
	return true

static func _markers_equal(a: Array[Dictionary], b: Array[Dictionary]) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		var ma: Dictionary = a[i]
		var mb: Dictionary = b[i]
		if ma.get("tile", Vector2i(-1, -1)) != mb.get("tile", Vector2i(-1, -1)):
			return false
		if ma.get("owner", -1) != mb.get("owner", -1):
			return false
		if ma.get("color", Color.BLACK) != mb.get("color", Color.BLACK):
			return false
	return true

static func owner_color(map: MapData, owner: int) -> Color:
	if map == null or owner < 0:
		return MinimapColors.NEUTRAL_OBJECT
	for player: Dictionary in map.players:
		if int(player.get("side", -1)) == owner:
			return MinimapColors.player_color(int(player.get("color", owner)))
	return MinimapColors.player_color(owner)

## Draw data for the landmarks the original radar shows: a town or castle is a
## 4x2 tile block (columns gate-2..gate+1, rows gate-1..gate) in its owner's
## colour, a mine a 2x1 block at its tile. Everything else stays off the radar,
## as in the DOS captures of Claw and Badlands.
static func landmark_marker(map: MapData, fog: FogLayer, obj: MapObject) -> Dictionary:
	if obj == null or obj.consumed:
		return {}
	var kind := ObjectCatalog.shared().minimap_class(obj.type)
	if kind != "town" and kind != "mine":
		return {}
	var tile := obj.action_tile
	if fog != null and not fog.is_explored(tile):
		return {}
	var top_left := tile + Vector2i(-2, -1) if kind == "town" else tile
	return {
		"tile": top_left,
		"size": Vector2i(4, 2) if kind == "town" else Vector2i(2, 1),
		"color": owner_color(map, obj.owner),
	}

static var _terrain_cache_key := ""
static var _terrain_cache: Texture2D = null

## Compose the radar once as one flat colour per tile, then scale it to the HUD
## opening with nearest-neighbour sampling. Fog and live markers
## stay dynamic layers in _draw().
func _build_terrain_texture() -> Texture2D:
	if _map == null or _map.width <= 0 or _map.height <= 0:
		return null
	# Terrain never changes during a run, and the map scene (with this minimap)
	# is rebuilt after every town, battle or hero screen.
	var key := "%d:%d:%s" % [_map.terrain_chars.hash(), _map.tile_overrides.hash(), str(_rect.size)]
	if _terrain_cache_key == key and _terrain_cache != null:
		return _terrain_cache
	_terrain_cache_key = key
	_terrain_cache = _compose_terrain_texture()
	return _terrain_cache

func _compose_terrain_texture() -> Texture2D:
	var image := Image.create(_map.width, _map.height, false, Image.FORMAT_RGBA8)
	var shaded := shaded_tiles(_map)
	for y in _map.height:
		for x in _map.width:
			image.set_pixel(x, y, MinimapColors.radar_color(
					tile_index_at(_map, x, y), shaded.has(Vector2i(x, y))))
	var target := Vector2i(maxi(1, roundi(_rect.size.x)), maxi(1, roundi(_rect.size.y)))
	image.resize(target.x, target.y, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(image)

## Re-point the radar at a newly-activated hero node (Stage-5 switching).
func set_hero(node: Hero) -> bool:
	if _hero == node:
		return false
	_hero = node
	queue_redraw()
	return true

func _draw() -> void:
	if show_logo:
		if _logo_texture != null:
			draw_texture(_logo_texture, Vector2.ZERO)
		return
	if _map == null:
		return
	var map_px := _map.pixel_size()
	var blk := tile_block(_rect.size, Vector2i(_map.width, _map.height))
	# Static native radar terrain (local coords: this Control is positioned at
	# _rect.position), with the live exploration mask painted over it.
	if _terrain_texture != null:
		draw_texture(_terrain_texture, Vector2.ZERO)
	else:
		for y in _map.height:
			for x in _map.width:
				draw_rect(Rect2(Vector2(x, y) * blk, blk.ceil()),
						MinimapColors.radar_color(tile_index_at(_map, x, y)), true)
	# The native radar reveals exactly the terrain the current player has
	# explored. Unexplored tiles come from a 1 px/tile mask texture updated
	# when fog is revealed.
	if _fog != null:
		var mask := _fog.get_mask_texture()
		if mask != null:
			draw_texture_rect(mask, Rect2(Vector2.ZERO, _rect.size), false)
		else:
			for y in _map.height:
				for x in _map.width:
					if not _fog.is_explored(Vector2i(x, y)):
						draw_rect(Rect2(Vector2(x, y) * blk, blk.ceil()), Color.BLACK, true)
	# Towns and mines, including neutral ones.
	if _landmark_markers.is_empty() and _landmark_objects.is_empty() and not _map.objects.is_empty():
		_index_landmark_objects()
		_update_landmark_markers()
	for marker: Dictionary in _landmark_markers:
		draw_rect(Rect2(Vector2(Vector2i(marker.tile)) * blk,
				Vector2(Vector2i(marker.size)) * blk), marker.color, true)
	# Heroes of other kingdoms are one gray tile. The original radar does not
	# mark the player's own hero; the camera rectangle shows where it is.
	for marker: Dictionary in _enemy_markers:
		var enemy_tile := Vector2i(marker.get("tile", Vector2i(-1, -1)))
		if enemy_tile == Vector2i(-1, -1) \
				or (_fog != null and not _fog.is_explored(enemy_tile)):
			continue
		draw_rect(Rect2(Vector2(enemy_tile) * blk, blk), MinimapColors.OTHER_HERO, true)
	# camera-view rectangle (dashed salmon outline) in local coords
	if _cam != null and _cam_view != Vector2.ZERO:
		var top_left := _cam.global_position - _cam_view * 0.5
		var lo := Vector2(top_left.x / map_px.x, top_left.y / map_px.y) * _rect.size
		var sz := Vector2(_cam_view.x / map_px.x, _cam_view.y / map_px.y) * _rect.size
		_draw_dashed_rect(Rect2(lo, sz), VIEW_RECT_COLOR)

func _draw_dashed_rect(r: Rect2, col: Color) -> void:
	var tr := r.position + Vector2(r.size.x, 0)
	var bl := r.position + Vector2(0, r.size.y)
	var br := r.position + r.size
	draw_dashed_line(r.position, tr, col, 1.0, 2.0)
	draw_dashed_line(bl, br, col, 1.0, 2.0)
	draw_dashed_line(r.position, bl, col, 1.0, 2.0)
	draw_dashed_line(tr, br, col, 1.0, 2.0)

func _gui_input(event: InputEvent) -> void:
	if show_logo:
		return
	var pressed_drag: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	var moving: bool = event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if pressed_drag or moving:
		var screen: Vector2 = _rect.position + event.position  # _gui_input position is local to the Control
		pan_requested.emit(minimap_to_world(screen, _rect, _map.pixel_size()))
		accept_event()
