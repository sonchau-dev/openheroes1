class_name FogLayer
extends TileMapLayer

## Per-player fog of war with the original engine's semantics: interior fog
## cells paint solid clof32 TIL tiles;
## BOUNDARY fog cells drop the solid tile and draw a partial clop32 sprite on
## themselves, leaving a reveal fringe of terrain visible under the purple
## curve. Explored cells carry no fog art at all.
##
## Bitset in PlayerState is the source of truth; cell state is for rendering.

## Interior fill: the 4 clof32 TIL variants — the original's dedicated
## solid-fog tiles (plain opaque black starfield, no accents). clop32 is the
## *boundary* ICN set only: every clop32 tile bakes a purple corner accent
## with a transparent notch, so tiling any of them across deep fog paints
## visible crescent lines (screenshot-verified against the DOS original,
## whose interior fog is accent-free starfield). So the split is CLOF32 for
## full fog, CLOP32 for edges.
const SOLID_SOURCE_ID := 0
const SOLID_TILE_COUNT := 4
const SOLID_TILE_IDS: Array[int] = [0, 1, 2, 3]
## The clof32 tiles side by side, baked by tools/extract/bake.gd.
const ATLAS := "res://assets/art/clof32_atlas.png"

signal fog_revealed(revealed_cells: Array[Vector2i])
signal fog_changed

static var _cached_tileset: TileSet = null

static func clear_cache() -> void:
	_cached_tileset = null

static func build_tileset(tile_size: int) -> TileSet:
	if _cached_tileset != null:
		return _cached_tileset

	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_size, tile_size)

	var atlas_tex := UiKit.load_texture(ATLAS)
	if atlas_tex == null:
		push_error("FogLayer: %s is missing; rerun tools/extract.gd" % ATLAS)

	var src := TileSetAtlasSource.new()
	src.texture = atlas_tex
	src.texture_region_size = Vector2i(tile_size, tile_size)
	for id in SOLID_TILE_IDS:
		src.create_tile(Vector2i(id, 0))

	ts.add_source(src, SOLID_SOURCE_ID)
	_cached_tileset = ts
	return ts

var _map: MapData
var _player: PlayerState
var _edges: Node2D
var _shape_data: Dictionary = {}
var _spec_offsets: Dictionary = {} # id (int) -> Vector2
var _edge_sprites: Dictionary = {} # Vector2i -> Array[Sprite2D]
var _edge_pool: Array[Sprite2D] = []
var _mask_image: Image = null
var _mask_texture: ImageTexture = null
# Read-only fog data and edge textures, kept across map scene reloads.
static var _shared_shape_data: Dictionary = {}
static var _shared_spec_offsets: Dictionary = {}
static var _edge_textures: Dictionary = {}

func get_mask_texture() -> Texture2D:
	return _mask_texture

func get_mask_image() -> Image:
	return _mask_image

func setup(map: MapData, player: PlayerState) -> void:
	clear()
	_map = map
	_player = player

	# Manage _edges Node2D child
	if _edges == null:
		_edges = Node2D.new()
		_edges.name = "Edges"
		add_child(_edges)
	else:
		for child in _edges.get_children():
			child.free()
	_edge_sprites.clear()
	_edge_pool.clear()

	if player == null:
		push_warning("FogLayer: setup called with null player state; fog disabled.")
		_mask_image = null
		_mask_texture = null
		return

	player.explored_init(map.width, map.height)
	_load_shape_data()
	_load_spec_offsets()

	_mask_image = Image.create(map.width, map.height, false, Image.FORMAT_RGBA8)
	for y in map.height:
		for x in map.width:
			if player.is_explored_at(x, y):
				_mask_image.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				_mask_image.set_pixel(x, y, Color(0, 0, 0, 1))
	_mask_texture = ImageTexture.create_from_image(_mask_image)

	tile_set = build_tileset(map.tile_size)

	# Draw solid fog on unexplored cells; _refresh_all_edges then swaps
	# boundary fog cells to partial sprites.
	for y in map.height:
		for x in map.width:
			if not player.is_explored_at(x, y):
				_set_solid(Vector2i(x, y))

	# Build all edges
	_refresh_all_edges()

## The player's explored cells, row-major, 1 = explored; empty without a player.
func explored_cells() -> PackedByteArray:
	return _player.explored if _player != null else PackedByteArray()

func is_explored(t: Vector2i) -> bool:
	if _player == null:
		return true
	return _player.is_explored_at(t.x, t.y)

func reveal(center: Vector2i, radius: int) -> void:
	if _player == null or _map == null:
		return

	# Near-circular reveal matching the original: cell is in scouting range
	# when dx^2 + dy^2 < limit, with limit tuned per radius to reproduce the
	# original's flat-edged octagon.
	var limit: int = _reveal_limit(radius)
	var any_revealed := false
	var revealed_cells: Array[Vector2i] = []
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			if x >= 0 and x < _map.width and y >= 0 and y < _map.height:
				var dx: int = absi(x - center.x)
				var dy: int = absi(y - center.y)
				if dx * dx + dy * dy < limit:
					if not _player.is_explored_at(x, y):
						any_revealed = true
						revealed_cells.append(Vector2i(x, y))
						if _mask_image != null:
							_mask_image.set_pixel(x, y, Color(0, 0, 0, 0))
					_player.explore(x, y)
					erase_cell(Vector2i(x, y))

	if any_revealed:
		if _mask_texture != null and _mask_image != null:
			_mask_texture.update(_mask_image)
		fog_revealed.emit(revealed_cells)
		fog_changed.emit()

	var rect := Rect2i(center.x - radius, center.y - radius, radius * 2 + 1, radius * 2 + 1)
	_refresh_edges(rect)

## Squared-distance cutoff per radius, tuned to the original game's reveal
## shapes (small radii cut slightly tighter than a true circle; 7 and 8 are
## hardcoded in the original).
static func _reveal_limit(radius: int) -> int:
	if radius < 6:
		return (radius + 1) * (radius + 1) - radius
	if radius == 7:
		return 66
	if radius == 8:
		return 90
	return (radius + 1) * (radius + 1)

func explore_everything() -> void:
	if _player != null:
		_player.explore_all()
	clear()
	for cell in _edge_sprites:
		for spr in _edge_sprites[cell]:
			if spr != null and is_instance_valid(spr):
				spr.visible = false
				_edge_pool.append(spr)
	_edge_sprites.clear()
	if _mask_image != null:
		_mask_image.fill(Color(0, 0, 0, 0))
		if _mask_texture != null:
			_mask_texture.update(_mask_image)
	fog_changed.emit()

## Bookkeeping-based count (not `_edges.get_child_count()`): edge sprites are
## torn down with `queue_free()`, which defers actual node removal to the next
## idle frame. Headless script runs (and rapid reveal->reveal->reveal calls
## within one frame) never reach that idle frame, so the scene-tree child
## count would over-count stale, already-logically-removed sprites. `_edge_sprites`
## is cleared synchronously in the same call that queues the free, so it's the
## authoritative source of "how many edge sprites exist right now".
func edge_sprite_count() -> int:
	var count := 0
	for cell in _edge_sprites:
		count += _edge_sprites[cell].size()
	return count

## Test/debug accessor: the live edge Sprite2D nodes drawn on `cell` (empty if none).
func edge_sprites_at(cell: Vector2i) -> Array:
	return _edge_sprites.get(cell, [])

func _load_shape_data() -> void:
	if _shared_shape_data.is_empty():
		_shared_shape_data = JsonFile.read_dict("res://data/terrain/fog_shapes.json")
	_shape_data = _shared_shape_data

func _load_spec_offsets() -> void:
	if _shared_spec_offsets.is_empty():
		var spec_path := "res://assets/art/clop32/spec.json"
		if FileAccess.file_exists(spec_path):
			var spec := SpecLoader.load_spec(spec_path)
			for spr in spec.get("sprites", []):
				var spr_id: int = spr.get("id", -1)
				if spr_id != -1:
					_shared_spec_offsets[spr_id] = Vector2(spr.get("offset", Vector2i.ZERO))
	_spec_offsets = _shared_spec_offsets

func _refresh_all_edges() -> void:
	for cell in _edge_sprites:
		for spr in _edge_sprites[cell]:
			if spr != null and is_instance_valid(spr):
				spr.visible = false
				_edge_pool.append(spr)
	_edge_sprites.clear()
	
	if _map == null:
		return

	for y in _map.height:
		for x in _map.width:
			_refresh_cell_edges(Vector2i(x, y))

func _refresh_edges(rect: Rect2i) -> void:
	if _map == null:
		return
	var dirty_rect := rect.grow(1)
	var x_min: int = int(max(0, dirty_rect.position.x))
	var y_min: int = int(max(0, dirty_rect.position.y))
	var x_max: int = int(min(_map.width - 1, dirty_rect.end.x))
	var y_max: int = int(min(_map.height - 1, dirty_rect.end.y))
	
	for y in range(y_min, y_max + 1):
		for x in range(x_min, x_max + 1):
			_refresh_cell_edges(Vector2i(x, y))

func _set_solid(cell: Vector2i) -> void:
	var idx := posmod((cell.x * 73856093) ^ (cell.y * 19349663), SOLID_TILE_IDS.size())
	set_cell(cell, SOLID_SOURCE_ID, Vector2i(idx, 0))

func get_solid_variant(cell: Vector2i) -> int:
	if get_cell_source_id(cell) != SOLID_SOURCE_ID:
		return -1
	return get_cell_atlas_coords(cell).x

func _recycle_edge_sprites(cell: Vector2i) -> void:
	if _edge_sprites.has(cell):
		for spr in _edge_sprites[cell]:
			if spr != null and is_instance_valid(spr):
				spr.visible = false
				_edge_pool.append(spr)
		_edge_sprites.erase(cell)

func _refresh_cell_edges(cell: Vector2i) -> void:
	if is_explored(cell):
		_recycle_edge_sprites(cell)
		return # Explored cells carry no fog art; reveal() erases their tile.

	# Mask of EXPLORED neighbors, mirrored through the cell center (bit i ->
	# bit (i+4)%8): shape_for_mask names shapes by where the *other* terrain
	# sits, and the fog art must attach to the side opposite the reveal
	# (clear to the south -> art hangs from the north edge = edge_top).
	var mask := 0
	var deltas = [
		Vector2i(0, -1),   # N
		Vector2i(1, -1),   # NE
		Vector2i(1, 0),    # E
		Vector2i(1, 1),    # SE
		Vector2i(0, 1),    # S
		Vector2i(-1, 1),   # SW
		Vector2i(-1, 0),   # W
		Vector2i(-1, -1),  # NW
	]
	for i in 8:
		var ncell = cell + deltas[i]
		if is_explored(ncell):
			mask |= (1 << ((i + 4) % 8))

	if mask == 0:
		_set_solid(cell) # interior fog: no explored neighbor anywhere
		_recycle_edge_sprites(cell)
		return

	var shape := Autotiler.fog_shape_for_mask(mask)
	if shape == "" or not _shape_data.has(shape):
		_set_solid(cell) # no art for this configuration; stay fully fogged
		_recycle_edge_sprites(cell)
		return

	erase_cell(cell) # partial sprite replaces the solid tile on this cell

	var shape_dict: Dictionary = _shape_data[shape]
	var sprite_id: int = shape_dict["sprite"]
	var variants: Array = shape_dict.get("variants", [])
	if not variants.is_empty():
		var idx: int = posmod((cell.x * 73856093) ^ (cell.y * 19349663), variants.size())
		sprite_id = int(variants[idx])
		
	var flip_h: bool = bool(shape_dict.get("flip_h", false))
	var flip_v: bool = bool(shape_dict.get("flip_v", false))
	
	var tex: Texture2D = _edge_textures.get(sprite_id)
	if tex == null:
		var rel := "clop32/%04d.png" % sprite_id
		tex = MapArtResolver.get_atlas_texture(rel)
		if tex == null:
			tex = load("res://assets/art/clop32/%04d.png" % sprite_id) as Texture2D
		if tex != null:
			_edge_textures[sprite_id] = tex
	if tex == null:
		_recycle_edge_sprites(cell)
		return

	var offset: Vector2 = _spec_offsets.get(sprite_id, Vector2.ZERO)
	if shape_dict.has("offset_override"):
		var ov: Array = shape_dict["offset_override"]
		offset = Vector2(ov[0], ov[1])

	var final_x: int = cell.x * _map.tile_size
	if flip_h:
		final_x += _map.tile_size - int(offset.x) - tex.get_width()
	else:
		final_x += int(offset.x)

	var final_y: int = cell.y * _map.tile_size
	if flip_v:
		final_y += _map.tile_size - int(offset.y) - tex.get_height()
	else:
		final_y += int(offset.y)
	var target_pos := Vector2(final_x, final_y)

	var existing: Array = _edge_sprites.get(cell, [])
	if not existing.is_empty():
		var spr: Sprite2D = existing[0]
		if spr != null and is_instance_valid(spr):
			if spr.texture == tex and spr.flip_h == flip_h and spr.flip_v == flip_v and spr.position == target_pos and spr.visible:
				return
			spr.texture = tex
			spr.flip_h = flip_h
			spr.flip_v = flip_v
			spr.position = target_pos
			spr.visible = true
			return

	var spr: Sprite2D
	while not _edge_pool.is_empty():
		var candidate: Sprite2D = _edge_pool.pop_back()
		if candidate != null and is_instance_valid(candidate) and not candidate.is_queued_for_deletion():
			spr = candidate
			break
	if spr == null:
		spr = Sprite2D.new()
		spr.centered = false
		spr.z_index = 1
		_edges.add_child(spr)
	spr.texture = tex
	spr.centered = false
	spr.flip_h = flip_h
	spr.flip_v = flip_v
	spr.position = target_pos
	spr.z_index = 1
	spr.visible = true
	_edge_sprites[cell] = [spr]
