class_name PuzzleMap
extends CanvasLayer

## Native 640x480 puzzle-map viewer. The 448x448 adventure-map opening is
## opened around the buried Ultimate Artifact and shows terrain and scenery
## (trees, mountains) but no map objects, as in the DOS original. The 48
## extracted PUZZLE.ICN wooden fragments cover undiscovered portions; visiting
## obelisks removes them in the original's index-walk order.

const ART := UiKit.ART
const PUZZLE_DIR := ART + "puzzle/"
const ROUTE_DIR := ART + "route/"
const MAP_RECT := Rect2(16, 16, 448, 448)
const PANEL_RECT := Rect2(480, 16, 144, 144)
const EXIT_POS := Vector2(512, 123)
const PIECE_COUNT := 48
const REVEAL_DURATION := 3.0
const DISSOLVE_SHADER := preload("res://src/ui/puzzle_piece_dissolve.gdshader")

signal closed

var _map: MapData
var _player: PlayerState
var _total_obelisks := 0
var _cross := Vector2i(-1, -1)
var _map_origin_px := Vector2.ZERO
var _input_blocker: Control
var _reveal_order: Array[int] = []

## Buried Ultimate Artifact tile iff the player has solved this map's puzzle.
static func cross_tile(map: MapData, player: PlayerState, total_obelisks: int) -> Vector2i:
	if map == null or player == null or not player.puzzle_solved(total_obelisks):
		return Vector2i(-1, -1)
	var ua: Dictionary = map.ultimate_artifact
	if ua.is_empty():
		return Vector2i(-1, -1)
	var tile_v: Variant = ua.get("tile", null)
	if tile_v is Vector2i:
		return tile_v
	if tile_v is Array and (tile_v as Array).size() == 2:
		return Vector2i(int(tile_v[0]), int(tile_v[1]))
	return Vector2i(-1, -1)

## Fixed HOMM1-TE behavior: every visit reveals its proportional share and the
## last visit always reaches all 48 pieces (the DOS integer-division remainder
## bug could leave pieces covered after every obelisk had been found).
static func revealed_piece_count(visited_obelisks: int, total_obelisks: int) -> int:
	if total_obelisks <= 0:
		return 0
	return clampi((clampi(visited_obelisks, 0, total_obelisks) * PIECE_COUNT) / total_obelisks, 0, PIECE_COUNT)

## heroes.exe 0x76fd0 reveals one piece at a time by PUZZLE.ICN index, not
## by distance: start at piece 0 and hop 1-5 pieces forward while the piece
## under the hop is already uncovered; past piece 47, take a random covered
## piece. The ICN numbers its outer pieces low and the middle ones high, so
## the reveal looks scattered while the buried tile stays covered longest.
## The original also gave up after 100 random tries; we keep drawing so the
## last obelisk always clears the board (same fix as the remainder bug).
static func reveal_order(seed_value: int) -> Array[int]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var shown := {}
	var out: Array[int] = []
	while out.size() < PIECE_COUNT:
		var k := 0
		while k < PIECE_COUNT and shown.has(k):
			k += rng.randi_range(1, 5)
		while k >= PIECE_COUNT or shown.has(k):
			k = rng.randi_range(0, PIECE_COUNT - 1)
		shown[k] = true
		out.append(k)
	return out

static func covered_piece_indices(order: Array[int], visited_obelisks: int,
		total_obelisks: int) -> Array[int]:
	return order.slice(revealed_piece_count(visited_obelisks, total_obelisks))

static func newly_revealed_piece_indices(order: Array[int], previous_visited: int,
		current_visited: int, total_obelisks: int) -> Array[int]:
	var first := revealed_piece_count(previous_visited, total_obelisks)
	var last := revealed_piece_count(current_visited, total_obelisks)
	return order.slice(first, last)

## Top-left world pixel of the native-size 448px crop. heroes.exe 0x9fa91
## starts 7 tiles up-left of the buried tile and nudges that by a
## position-derived -1..1 tiles across and -2..2 down, so the X is never in
## the exact middle. Clamp like the adventure camera so a hand-authored map's
## treasure near an edge does not expose empty space.
static func map_origin_px(map: MapData, focus_tile: Vector2i) -> Vector2:
	if map == null:
		return Vector2.ZERO
	var tile_size := maxi(map.tile_size, 1)
	var x := focus_tile.x
	var y := focus_tile.y
	var dx := (x + y) % 3 - 1
	var dy := (2 * x + 5 * y) % 3 - 1
	if (x + y) % 3 != 1 and (x + y) % 2 == 1:
		dy += signi(dy)
	var wanted := Vector2(x - 7 + dx, y - 7 + dy) * tile_size
	var maximum := (map.pixel_size() - MAP_RECT.size).max(Vector2.ZERO)
	return Vector2(clampf(wanted.x, 0.0, maximum.x), clampf(wanted.y, 0.0, maximum.y))

func open(map: MapData, player: PlayerState, total_obelisks: int,
		previous_visited_obelisks: int = -1) -> void:
	_map = map
	_player = player
	_total_obelisks = total_obelisks
	_cross = cross_tile(map, player, total_obelisks)
	layer = 200

	# Full-screen modal input shield. The live adventure HUD stays visible in the
	# right column, matching the native viewer, but receives no clicks.
	_input_blocker = Control.new()
	_input_blocker.name = "ModalInputShield"
	_input_blocker.position = Vector2.ZERO
	_input_blocker.size = Vector2(640, 480)
	_input_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_input_blocker)

	if _map == null:
		return

	var focus := _authored_artifact_tile(_map)
	if focus == Vector2i(-1, -1):
		focus = Vector2i(_map.width / 2, _map.height / 2)
	_map_origin_px = map_origin_px(_map, focus)
	# shortcut: the original rolls the hops live per game; a seed fixed per
	# side and buried tile keeps the picture stable across save/load.
	_reveal_order = reveal_order(hash([focus, _player.side if _player != null else 0]))

	var map_clip := Control.new()
	map_clip.name = "PuzzleTerrainClip"
	map_clip.position = MAP_RECT.position
	map_clip.size = MAP_RECT.size
	map_clip.clip_contents = true
	map_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(map_clip)

	var empty_ground := ColorRect.new()
	empty_ground.color = Color8(38, 25, 14)
	empty_ground.size = MAP_RECT.size
	empty_ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	empty_ground.z_index = AdventureDepth.Z_TERRAIN - 1
	map_clip.add_child(empty_ground)

	var terrain := MapRenderer.new()
	terrain.name = "PuzzleTerrain"
	terrain.position = -_map_origin_px
	terrain.z_index = AdventureDepth.Z_TERRAIN
	map_clip.add_child(terrain)
	terrain.render(_map)

	var scenery := WorldStaticCanvas.new()
	scenery.name = "PuzzleScenery"
	scenery.scenery_only = true
	scenery.position = -_map_origin_px
	map_clip.add_child(scenery)
	scenery.setup(_map, MapArtResolver.new())

	if _cross != Vector2i(-1, -1):
		_add_cross()

	_add_cover_pieces(previous_visited_obelisks)
	_add_control_panel()

func _authored_artifact_tile(map: MapData) -> Vector2i:
	if map == null or map.ultimate_artifact.is_empty():
		return Vector2i(-1, -1)
	var raw: Variant = map.ultimate_artifact.get("tile", null)
	if raw is Vector2i:
		return raw
	if raw is Array and (raw as Array).size() == 2:
		return Vector2i(int(raw[0]), int(raw[1]))
	return Vector2i(-1, -1)

func _add_cover_pieces(previous_visited_obelisks: int) -> void:
	var spec := SpecLoader.load_spec(PUZZLE_DIR + "spec.json")
	var sprites: Array = spec.get("sprites", [])
	var current_visited := _player.puzzle_pieces.size() if _player != null else 0
	var initial_visited := current_visited if previous_visited_obelisks < 0 \
			else clampi(previous_visited_obelisks, 0, current_visited)
	var covered := covered_piece_indices(_reveal_order, initial_visited, _total_obelisks)
	var newly_revealed := newly_revealed_piece_indices(
			_reveal_order, initial_visited, current_visited, _total_obelisks)
	var newly_revealed_set: Dictionary = {}
	for piece_id: int in newly_revealed:
		newly_revealed_set[piece_id] = true

	var dissolve_material := ShaderMaterial.new()
	dissolve_material.shader = DISSOLVE_SHADER
	dissolve_material.set_shader_parameter("progress", 0.0)
	var dissolving_pieces: Array[Sprite2D] = []
	for piece_id: int in covered:
		if piece_id < 0 or piece_id >= sprites.size():
			continue
		var sprite_spec: Dictionary = sprites[piece_id]
		var piece := Sprite2D.new()
		piece.name = "CoverPiece%02d" % piece_id
		piece.centered = false
		piece.z_index = AdventureDepth.Z_FOG  # above every scenery row
		piece.texture = load(PUZZLE_DIR + String(sprite_spec.get("file", "%04d.png" % piece_id))) as Texture2D
		piece.position = Vector2(sprite_spec.get("offset", Vector2.ZERO))
		if newly_revealed_set.has(piece_id):
			piece.material = dissolve_material
			dissolving_pieces.append(piece)
		add_child(piece)
	if not dissolving_pieces.is_empty():
		_start_reveal_animation(dissolve_material, dissolving_pieces)

func _start_reveal_animation(material: ShaderMaterial, pieces: Array[Sprite2D]) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(material, "shader_parameter/progress", 1.0, REVEAL_DURATION)
	tween.finished.connect(func():
		for piece: Sprite2D in pieces:
			if is_instance_valid(piece):
				piece.queue_free()
	)

func _add_control_panel() -> void:
	var panel := TextureRect.new()
	panel.name = "ViewPuzzlePanel"
	panel.texture = load(ART + "viewpuzl.png") as Texture2D
	panel.position = PANEL_RECT.position
	panel.size = PANEL_RECT.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var exit := TextureButton.new()
	exit.name = "Exit"
	exit.texture_normal = load(ART + "swapbtn/0000.png") as Texture2D
	exit.texture_pressed = load(ART + "swapbtn/0001.png") as Texture2D
	exit.position = EXIT_POS
	exit.size = (exit.texture_normal as Texture2D).get_size()
	exit.focus_mode = Control.FOCUS_NONE
	exit.pressed.connect(_close)
	add_child(exit)

func _add_cross() -> void:
	# The original draws its own red-and-white route X (route/0013, the
	# unreachable-destination marker) on the buried tile, centered like the
	# adventure map's route arrows.
	var tile_size := maxi(_map.tile_size, 1)
	var mark := Sprite2D.new()
	mark.name = "TreasureMark"
	var cross_tex: Texture2D = MapArtResolver.get_atlas_texture("route/%04d.png" % RouteArrows.DEST_RED)
	mark.texture = cross_tex if cross_tex != null else (load(ROUTE_DIR + "%04d.png" % RouteArrows.DEST_RED) as Texture2D)
	mark.centered = true
	mark.z_index = AdventureDepth.Z_ROUTE
	mark.position = MAP_RECT.position + Vector2(_cross) * tile_size \
			+ Vector2.ONE * (tile_size * 0.5) - _map_origin_px
	add_child(mark)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		_close()

func _close() -> void:
	closed.emit()
	queue_free()
