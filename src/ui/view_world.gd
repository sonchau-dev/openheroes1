class_name ViewWorld
extends CanvasLayer

## Native 640x480 "View World" viewer and "View X" map-spell overlay.
## Displays the explored world map using HOMM1's purpose-built 6px mini graphics
## (ground6, tree6, mtn6, town6, flag6) centered inside the 448x448 viewport,
## with the authentic viewwrld.png panel and EXIT button in the top-right corner.

const ART := UiKit.ART
const GROUND6 := ART + "ground6/%04d.png"
const MTN6 := ART + "mtn6/%04d.png"
const TREE6 := ART + "tree6/%04d.png"
const TOWN6 := ART + "town6/%04d.png"
const FLAG6 := ART + "flag6/%04d.png"

const MAP_RECT := Rect2(16, 16, 448, 448)
const PANEL_RECT := Rect2(480, 16, 144, 144)
const EXIT_POS := Vector2(513, 130)
const NATIVE_MINI_TILE := 6
const HERO_PULSE_PERIOD := 0.75
const ARTIFACT_PULSE_PERIOD := 0.65
const PULSE_MIN_ALPHA := 0.35
const PULSE_MAX_ALPHA := 1.0

# Native town6 block indices: 4x3 sprites per block (12 sprites each)
# Knight: town=0, castle=1
# Barbarian: town=4, castle=5
# Sorceress: town=2, castle=3
# Warlock: town=6, castle=7
const TOWN_BLOCK := {0: 1, 1: 5, 2: 3, 3: 7}
const TOWN_FLAG_DX: Array[int] = [-9, 3]
const TOWN_BLOCK_UNWALLED := {0: 0, 1: 4, 2: 2, 3: 6}

# The original ships one panel per View spell (view-00..05.bin); resources and
# mines share the legend that explains the lettered badges.
const PANEL_ART := {
	"resources": "legend.png",
	"mines": "legend.png",
	"artifacts": "viewrtfx.png",
	"towns": "viewtwns.png",
	"heroes": "viewhros.png",
}
const DEFAULT_PANEL := "viewwrld.png"

# Lettered badge: the gray sphere (spheres/0004) under a letter from letters/.
# Both sprites carry their own anchor offsets; the resource badge sits half a
# tile left of the mine badge (measured against DOS captures).
const BADGE_SPHERE := 4
const BADGE_LETTER := {"wood": 0, "mercury": 1, "ore": 2, "sulfur": 3,
		"crystal": 4, "gems": 5, "gold": 6}
const RESOURCE_BADGE_SHIFT := Vector2(-3, 0)
const MINE_BADGE_SHIFT := Vector2.ZERO
const MARK_BADGE := 0
const MARK_FLAG := 1

signal closed

var _map: MapData
var _objects: Array = []
var _players: Array = []
var _category: String = "world"
var _fog: FogLayer = null
var _active_hero: Variant = null
var _hero_tile: Vector2i = Vector2i(-1, -1)

var _input_blocker: Control
var _map_clip: Control
var _canvas: Control
var _pulse_canvas: Control
var _panel: TextureRect
var _exit_btn: TextureButton

var static_redraw_count: int = 0
var pulse_redraw_count: int = 0
var static_redraw_queued: int = 0
var pulse_redraw_queued: int = 0

var _ground_cache: Dictionary = {}
var _tree_cache: Dictionary = {}
var _tree_offsets: Dictionary = {}
var _mtn_cache: Dictionary = {}
var _mtn_offsets: Dictionary = {}
var _town_cache: Dictionary = {}
var _town_offsets: Dictionary = {}
var _flag_cache: Dictionary = {}
var _badge_cache: Dictionary = {}

var _elapsed := 0.0

static func _get_game() -> Node:
	var ml := Engine.get_main_loop() as SceneTree
	if ml != null and ml.root != null:
		return ml.root.get_node_or_null("Game")
	return null

func open(map: MapData, objects: Array = [], players: Array = [],
		category: String = "world", fog: FogLayer = null,
		active_hero: Variant = null) -> void:
	var game := _get_game()
	_map = map
	_objects = objects if not objects.is_empty() else (map.objects if map != null else [])
	_players = players if not players.is_empty() else (game.state.players if game != null and game.state != null else [])
	_category = category
	# View All shows every tile; the spell never reveals the real map.
	_fog = null if category == "all" else fog
	if active_hero is Hero or active_hero is HeroModel:
		_active_hero = active_hero
		_hero_tile = active_hero.tile
	elif active_hero is Vector2i:
		_hero_tile = active_hero
	elif game != null and "hero_tile" in game and game.hero_tile != Vector2i(-1, -1):
		_hero_tile = game.hero_tile

	layer = 200

	_load_specs()

	# Full-screen modal shield
	_input_blocker = Control.new()
	_input_blocker.name = "ModalInputShield"
	_input_blocker.position = Vector2.ZERO
	_input_blocker.size = Vector2(640, 480)
	_input_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_input_blocker)

	# 448x448 viewport clip
	_map_clip = Control.new()
	_map_clip.name = "WorldMapClip"
	_map_clip.position = MAP_RECT.position
	_map_clip.size = MAP_RECT.size
	_map_clip.clip_contents = true
	_map_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_map_clip)

	var empty_bg := ColorRect.new()
	empty_bg.name = "EmptyBackground"
	empty_bg.color = Color.BLACK
	empty_bg.position = Vector2.ZERO
	empty_bg.size = MAP_RECT.size
	empty_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_clip.add_child(empty_bg)

	if _map != null and _map.width > 0 and _map.height > 0:
		var map_px_size := Vector2(_map.width * NATIVE_MINI_TILE, _map.height * NATIVE_MINI_TILE)
		var origin := ((MAP_RECT.size - map_px_size) * 0.5).round()

		_canvas = Control.new()
		_canvas.name = "WorldCanvas"
		_canvas.position = origin
		_canvas.size = map_px_size
		_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_canvas.draw.connect(_draw_world)
		_map_clip.add_child(_canvas)

		_pulse_canvas = Control.new()
		_pulse_canvas.name = "PulseCanvas"
		_pulse_canvas.position = Vector2.ZERO
		_pulse_canvas.size = map_px_size
		_pulse_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pulse_canvas.draw.connect(_draw_pulse)
		_canvas.add_child(_pulse_canvas)

		static_redraw_queued += 1
		pulse_redraw_queued += 1

	_connect_fog()

	# Top-right View World panel
	_panel = TextureRect.new()
	_panel.name = "ViewWorldPanel"
	_panel.texture = load(ART + String(PANEL_ART.get(_category, DEFAULT_PANEL))) as Texture2D
	_panel.position = PANEL_RECT.position
	_panel.size = PANEL_RECT.size
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	# Exit button
	_exit_btn = TextureButton.new()
	_exit_btn.name = "Exit"
	_exit_btn.texture_normal = load(ART + "legend/0000.png") as Texture2D
	_exit_btn.texture_pressed = load(ART + "legend/0001.png") as Texture2D
	_exit_btn.position = EXIT_POS
	_exit_btn.size = (_exit_btn.texture_normal as Texture2D).get_size()
	_exit_btn.focus_mode = Control.FOCUS_NONE
	_exit_btn.pressed.connect(_close)
	add_child(_exit_btn)

	set_process(_has_pulse())

func refresh() -> void:
	static_redraw_queued += 1
	pulse_redraw_queued += 1
	if is_instance_valid(_canvas):
		_canvas.queue_redraw()
	if is_instance_valid(_pulse_canvas):
		_pulse_canvas.queue_redraw()

func _has_pulse() -> bool:
	if _hero_tile != Vector2i(-1, -1) and (_fog == null or _fog.is_explored(_hero_tile)):
		return true
	for o: MapObject in _objects:
		if o is ArtifactPickup and not o.consumed and _shows_layer("artifacts"):
			if _visible(o.tile, "artifacts"):
				return true
	return false

func _connect_fog() -> void:
	if _fog != null and is_instance_valid(_fog):
		if _fog.has_signal("fog_revealed") and not _fog.fog_revealed.is_connected(_on_fog_revealed):
			_fog.fog_revealed.connect(_on_fog_revealed)
		if _fog.has_signal("fog_changed") and not _fog.fog_changed.is_connected(_on_fog_changed):
			_fog.fog_changed.connect(_on_fog_changed)

func _disconnect_fog() -> void:
	if _fog != null and is_instance_valid(_fog):
		if _fog.has_signal("fog_revealed") and _fog.fog_revealed.is_connected(_on_fog_revealed):
			_fog.fog_revealed.disconnect(_on_fog_revealed)
		if _fog.has_signal("fog_changed") and _fog.fog_changed.is_connected(_on_fog_changed):
			_fog.fog_changed.disconnect(_on_fog_changed)

func _on_fog_revealed(_cells: Array = []) -> void:
	refresh()

func _on_fog_changed() -> void:
	refresh()

func _exit_tree() -> void:
	_disconnect_fog()

func _process(delta: float) -> void:
	_elapsed += delta
	if _active_hero != null and _active_hero.tile != _hero_tile:
		_hero_tile = _active_hero.tile
	pulse_redraw_queued += 1
	if is_instance_valid(_pulse_canvas):
		_pulse_canvas.queue_redraw()

func _get_hero_pulse_color() -> Color:
	var pulse := 0.5 + 0.5 * sin(_elapsed * (TAU / HERO_PULSE_PERIOD))
	var a := lerpf(PULSE_MIN_ALPHA, PULSE_MAX_ALPHA, pulse)
	return Color(1.0, 1.0, 1.0, a)

func _get_artifact_pulse_color(tile: Vector2i = Vector2i.ZERO) -> Color:
	var phase_offset := (tile.x * 1.3 + tile.y * 2.7) if tile != Vector2i.ZERO else 1.5
	var pulse := 0.5 + 0.5 * sin(_elapsed * (TAU / ARTIFACT_PULSE_PERIOD) + phase_offset)
	var a := lerpf(PULSE_MIN_ALPHA, PULSE_MAX_ALPHA, pulse)
	return Color(1.0, 1.0, 1.0, a)

func _load_specs() -> void:
	var tree_spec := SpecLoader.load_spec(ART + "tree6/spec.json")
	for s: Dictionary in tree_spec.get("sprites", []):
		_tree_offsets[int(s.get("id", 0))] = Vector2(s.get("offset", Vector2.ZERO))

	var mtn_spec := SpecLoader.load_spec(ART + "mtn6/spec.json")
	for s: Dictionary in mtn_spec.get("sprites", []):
		_mtn_offsets[int(s.get("id", 0))] = Vector2(s.get("offset", Vector2.ZERO))

	var town_spec := SpecLoader.load_spec(ART + "town6/spec.json")
	for s: Dictionary in town_spec.get("sprites", []):
		_town_offsets[int(s.get("id", 0))] = Vector2(s.get("offset", Vector2.ZERO))

func _get_ground_texture(frame_id: int, flip_h: bool, flip_v: bool) -> Texture2D:
	var key := (frame_id << 2) | (1 if flip_h else 0) | (2 if flip_v else 0)
	if _ground_cache.has(key):
		return _ground_cache[key]
	var path := GROUND6 % frame_id
	# ResourceLoader, not FileAccess: an exported build packs only the imported
	# copy of each PNG, so FileAccess finds nothing and the map draws black.
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	if flip_h or flip_v:
		var img := tex.get_image()
		if img != null:
			if flip_h:
				img.flip_x()
			if flip_v:
				img.flip_y()
			tex = ImageTexture.create_from_image(img)
	_ground_cache[key] = tex
	return tex

func _get_tree_texture(idx: int) -> Texture2D:
	if _tree_cache.has(idx):
		return _tree_cache[idx]
	var path := TREE6 % idx
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	_tree_cache[idx] = tex
	return tex

func _get_mtn_texture(idx: int) -> Texture2D:
	if _mtn_cache.has(idx):
		return _mtn_cache[idx]
	var path := MTN6 % idx
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	_mtn_cache[idx] = tex
	return tex

func _get_town_texture(idx: int) -> Texture2D:
	if _town_cache.has(idx):
		return _town_cache[idx]
	var path := TOWN6 % idx
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	_town_cache[idx] = tex
	return tex

func _get_flag_texture(idx: int) -> Texture2D:
	if _flag_cache.has(idx):
		return _flag_cache[idx]
	var path := FLAG6 % idx
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	_flag_cache[idx] = tex
	return tex

## ground6 frame for one tile. The override carries the scenario's own ground
## tile (shores included); the grid only knows the terrain class.
func ground_frame_at(x: int, y: int) -> int:
	var override: Dictionary = _map.tile_overrides.get(Vector2i(x, y), {})
	return Minimap.native_ground_frame(int(override.get("tile", _map.get_tile(x, y))))

func _draw_world() -> void:
	if _map == null:
		return
	static_redraw_count += 1

	# 1. Ground terrain
	for y in _map.height:
		for x in _map.width:
			var tile_pos := Vector2i(x, y)
			if _fog != null and not _fog.is_explored(tile_pos):
				continue
			var override: Dictionary = _map.tile_overrides.get(tile_pos, {})
			var frame_id := ground_frame_at(x, y)
			if frame_id < 0:
				continue
			var flip_h := bool(override.get("flipH", false))
			var flip_v := bool(override.get("flipV", false))
			var tex := _get_ground_texture(frame_id, flip_h, flip_v)
			if tex != null:
				_canvas.draw_texture(tex, Vector2(x * NATIVE_MINI_TILE, y * NATIVE_MINI_TILE))

	# 2. Static decor (Mountains and Trees from render_parts)
	for raw_part: Variant in _map.render_parts:
		if not (raw_part is Dictionary):
			continue
		var part: Dictionary = raw_part
		var tile_arr: Array = part.get("tile", [])
		if tile_arr.size() < 2:
			continue
		var tile_pos := Vector2i(int(tile_arr[0]), int(tile_arr[1]))
		if _fog != null and not _fog.is_explored(tile_pos):
			continue

		var art := String(part.get("art", ""))
		if art == "" and part.has("frames") and not (part["frames"] as Array).is_empty():
			art = String(part["frames"][0])

		if art.begins_with("tree32/"):
			var idx := int(art.trim_prefix("tree32/").trim_suffix(".png"))
			var tex := _get_tree_texture(idx)
			if tex != null:
				var offset: Vector2 = _tree_offsets.get(idx, Vector2.ZERO)
				_canvas.draw_texture(tex, Vector2(tile_pos * NATIVE_MINI_TILE) + offset)
		elif art.begins_with("mtn32/"):
			var idx := int(art.trim_prefix("mtn32/").trim_suffix(".png"))
			var tex := _get_mtn_texture(idx)
			if tex != null:
				var offset: Vector2 = _mtn_offsets.get(idx, Vector2.ZERO)
				_canvas.draw_texture(tex, Vector2(tile_pos * NATIVE_MINI_TILE) + offset)

	# 3. Towns / Castles (town6)
	for o: MapObject in _objects:
		if o is TownObject and _shows_layer("towns"):
			var t := o as TownObject
			var gate := t.action_tile
			if not _visible(gate, "towns"):
				continue
			var has_castle := bool(t.params.get("has_castle", true))
			var faction := t.town_type
			if faction < 0 or faction >= 4:
				faction = 0
			var block_table := TOWN_BLOCK if has_castle else TOWN_BLOCK_UNWALLED
			var block: int = int(block_table.get(faction, block_table[0]))
			var base_idx := block * 12

			for r in 3:
				for c in 4:
					var sid := base_idx + r * 4 + c
					var tex := _get_town_texture(sid)
					if tex != null:
						var offset: Vector2 = _town_offsets.get(sid, Vector2.ZERO)
						var pos := Vector2((gate.x - 2 + c) * NATIVE_MINI_TILE,
								(gate.y - 2 + r) * NATIVE_MINI_TILE) + offset
						_canvas.draw_texture(tex, pos)

			# Owner flags on both towers (pixel-measured against DOS captures)
			if t.owner >= 0:
				var flag_tex := _get_flag_texture(_owner_color_index(t.owner))
				if flag_tex != null:
					for dx: int in TOWN_FLAG_DX:
						_canvas.draw_texture(flag_tex, Vector2(
								gate.x * NATIVE_MINI_TILE + dx,
								gate.y * NATIVE_MINI_TILE - 6))

	# 4. Other heroes' flags and the lettered badges, in marker order.
	for m: Array in markers():
		if m[1] == MARK_FLAG:
			var flag_tex := _get_flag_texture(m[2])
			if flag_tex != null:
				_canvas.draw_texture(flag_tex, Vector2(m[0].x * NATIVE_MINI_TILE,
						m[0].y * NATIVE_MINI_TILE - 6))
		else:
			_draw_badge(m[2], m[3])

## Other heroes' flags ([tile, MARK_FLAG, colour]) and lettered badges ([tile,
## MARK_BADGE, object, shift]) in the original's draw order (heroes.exe
## 0xa0d4f): columns left to right, each column bottom to top, and on one cell
## the mine badge before the hero flag, so a hero on a mine stays visible.
## View Resources badges piles; View Mines and View All badge mines (the DOS
## View All draws no resource badges).
func markers() -> Array:
	var out: Array = []
	var badge_class: Variant = ResourcePile if _category == "resources" \
			else Mine if _category == "mines" or _category == "all" else null
	if badge_class != null:
		var shift := RESOURCE_BADGE_SHIFT if _category == "resources" else MINE_BADGE_SHIFT
		for o in _objects:
			if is_instance_of(o, badge_class) and not (o as MapObject).consumed:
				out.append([(o as MapObject).tile, MARK_BADGE, o, shift])
	for p in _players if _shows_layer("heroes") else []:
		var flag_col := (_owner_color_index(int(p.side)) if "side" in p else 0) % 5
		for htile: Vector2i in hero_tiles(p):
			if htile != _hero_tile and _visible(htile, "heroes"):
				out.append([htile, MARK_FLAG, flag_col])
	out.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0].x != b[0].x:
			return a[0].x < b[0].x
		if a[0].y != b[0].y:
			return a[0].y > b[0].y
		return a[1] < b[1])
	return out

## Every hero tile of one player: a PlayerState's HeroModels, or a map
## dictionary's [x, y] pairs.
static func hero_tiles(p: Variant) -> Array:
	var out: Array = []
	if "heroes" in p and p.heroes is Array:
		for h in p.heroes:
			if h is HeroModel:
				out.append(h.tile)
			elif h is Array and h.size() >= 2:
				out.append(Vector2i(int(h[0]), int(h[1])))
			elif h is Vector2i:
				out.append(h)
	if "hero_model" in p and p.hero_model != null and not out.has(p.hero_model.tile):
		out.append(p.hero_model.tile)
	out.erase(Vector2i(-1, -1))
	return out

func _draw_pulse() -> void:
	if _pulse_canvas == null:
		return
	pulse_redraw_count += 1

	# Active hero: pulsing yellow dot (flag6/0005.png)
	if _hero_tile != Vector2i(-1, -1) and (_fog == null or _fog.is_explored(_hero_tile)):
		var dot_tex := _get_flag_texture(5)
		if dot_tex != null:
			_pulse_canvas.draw_texture(dot_tex, Vector2(_hero_tile * NATIVE_MINI_TILE), _get_hero_pulse_color())

	# Artifacts: pulsing blue dot (flag6/0006.png)
	for o: MapObject in _objects:
		if o is ArtifactPickup and not o.consumed and _shows_layer("artifacts"):
			if _visible(o.tile, "artifacts"):
				var art_dot := _get_flag_texture(6)
				if art_dot != null:
					_pulse_canvas.draw_texture(art_dot, Vector2(o.tile * NATIVE_MINI_TILE),
							_get_artifact_pulse_color(o.tile))

## Terrain, scenery and the active hero's dot show in every view. Towns, other
## heroes and artifact dots show only in the full views and in their own spell
## (the DOS resource, mine and artifact views draw no castle).
func _shows_layer(layer: String) -> bool:
	return _category == "all" or _category == "world" or _category == layer

## A layer shows through fog in its own View spell; otherwise only where the
## player has explored.
func _visible(tile: Vector2i, layer: String) -> bool:
	return _fog == null or _category == layer or _fog.is_explored(tile)

func _owner_color_index(owner: int) -> int:
	if _map != null:
		for player: Dictionary in _map.players:
			if int(player.get("side", -1)) == owner:
				return int(player.get("color", owner)) % 5
	return owner % 5

func _draw_badge(o: MapObject, shift: Vector2) -> void:
	var letter := int(BADGE_LETTER.get(String(o.res), -1))
	var origin := Vector2(o.tile * NATIVE_MINI_TILE) + shift
	_draw_badge_part("spheres", BADGE_SPHERE, _badge_texture("spheres", BADGE_SPHERE), origin)
	if letter >= 0:
		_draw_badge_part("letters", letter, _badge_texture("letters", letter), origin)

func _badge_texture(dir: String, idx: int) -> Texture2D:
	var key := "%s/%d" % [dir, idx]
	if not _badge_cache.has(key):
		var path := ART + "%s/%04d.png" % [dir, idx]
		_badge_cache[key] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _badge_cache[key]

func _draw_badge_part(dir: String, idx: int, tex: Texture2D, origin: Vector2) -> void:
	if tex == null:
		return
	var off := Vector2(SpecLoader.sprite(ART + dir, idx).get("offset", Vector2i.ZERO))
	_canvas.draw_texture(tex, origin + off)

func _input(event: InputEvent) -> void:
	# Mouse clicks close the view only through EXIT. The original's handler
	# (heroes.exe 0x6e804) ends it on a widget click alone, and left and right
	# clicks on the map do nothing in the DOS recording; the modal shield keeps
	# them off the adventure map below.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_close()

func _close() -> void:
	_disconnect_fog()
	closed.emit()
	queue_free()

