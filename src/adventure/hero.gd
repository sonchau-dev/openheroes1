class_name Hero
extends Node2D

## A hero that walks a tile path, updating facing per segment.

signal arrived()
signal entered_tile(tile: Vector2i)

## Fallback when no Game node is around to hold the speed setting. Matches
## Canter, which is Game's default. See step_time_for_speed.
const BASE_STEP_TIME := 0.20
const MAX_MOVE := 60    # maximum possible movement points on land (Fastest slowest unit)
const DEFAULT_DISAPPEAR_TIME := 1.0
## How long the map is held after a hero turns to face the hero it engages,
## before the battle screen takes over. Turning is a single frame of sprite
## swap and the scene change lands on the very next frame, so without this
## beat the player never sees the two heroes square off: the last thing on
## screen is the walk, with the hero facing the direction it came from.
const ENGAGE_FACE_DELAY := 0.35
## heroes.exe sets each step clip's volume to 0x40 (0x92740) against the 127 of
## a one-shot effect, then scales it by the Effects setting.
const STEP_SOUND_GAIN := 64.0 / 127.0
const CreatureCatalogScript := preload("res://src/battle/creature_catalog.gd")
const DISSOLVE_SHADER := preload("res://src/town/building_reveal.gdshader")

static func get_unit_speed(unit_name: String) -> String:
	return String(CreatureCatalogScript.stats(unit_name).get("speed_name", "Slow"))

static func calculate_max_move(army: ArmyData) -> int:
	if army == null or army.slots.is_empty():
		return 60
	var slowest := "Fast"
	for slot: Dictionary in army.slots:
		if slot.count <= 0:
			continue
		var speed := get_unit_speed(slot.unit)
		if speed == "Slow":
			slowest = "Slow"
			break
		elif speed == "Medium":
			slowest = "Medium"
	
	match slowest:
		"Slow": return 40
		"Medium": return 50
		"Fast": return 60
		_: return 40

const AI_MOVEMENT_PATH := "res://data/terrain/ai_movement.json"
static var _ai_movement_cache: Dictionary = {}

static func _get_ai_movement_data() -> Dictionary:
	if _ai_movement_cache.is_empty():
		_ai_movement_cache = JsonFile.read_dict(AI_MOVEMENT_PATH)
	return _ai_movement_cache

static func ai_movement_bonus(ai_level: int) -> int:
	var bonuses: Dictionary = _get_ai_movement_data().get("mp_bonus", {})
	return int(bonuses.get(str(ai_level), 0))

static func ai_visit_cost_penalty(ai_level: int) -> int:
	var penalties: Dictionary = _get_ai_movement_data().get("visit_cost_penalty", {})
	return int(penalties.get(str(ai_level), 0))

static func calculate_model_max_move(model: HeroModel, objects: Array = [],
		side: int = 0, ai_level: int = 0) -> int:
	if model == null:
		return 60
	var amount := calculate_max_move(model.army)
	if model.travel_mode == &"sea":
		var sorceress := model.hero_class == "sorceress"
		amount = 120 if sorceress else 60
		amount += model.sea_movement_bonus()
		for object: MapObject in objects:
			if object.type == "lighthouse" and object.owner == side:
				amount += 40 if sorceress else 20
	else:
		amount += model.land_movement_bonus()
	amount += ai_movement_bonus(ai_level)
	return amount

## Movement-point cost to step between two adjacent tiles.
static func step_cost(a: Vector2i, b: Vector2i, map: MapData = null,
		force_water: bool = false, hero_class: String = "") -> int:
	if map == null:
		var d := b - a
		return 6 if (d.x != 0 and d.y != 0) else 4
		
	if force_water or map.is_water(a):
		var water_delta := b - a
		return 6 if water_delta.x != 0 and water_delta.y != 0 else 4
	
	var cost_straight := 4
	var cost_diagonal := 6
	
	# Barbarians ignore the snow, swamp, and desert movement penalties. The
	# diagonal multiplier still applies, so their native-terrain costs are the
	# same 4/6 MP as grass, dirt, and lava.
	if hero_class == "barbarian":
		pass
	else:
		var terrain := map.terrain_at(a)
		if terrain == "snow" or terrain == "swamp":
			cost_straight = 6
			cost_diagonal = 9
		elif terrain == "desert":
			cost_straight = 8
			cost_diagonal = 12
		
	var d := b - a
	var is_diag := (d.x != 0 and d.y != 0)
	return cost_diagonal if is_diag else cost_straight

var _cached_movement_tile: Vector2i = Vector2i(-1, -1)
var _cached_movement_mp: int = -1
var _cached_movement_mode: StringName = &""
var _cached_can_move: bool = false

## Returns true if the hero has enough movement points to make at least one step
## to an adjacent passable tile on the map. If map is null, returns true if move_points >= 4.
func has_enough_movement_to_move() -> bool:
	if move_points < 4:
		return false
	if map == null:
		return true
	if tile == _cached_movement_tile and move_points == _cached_movement_mp and travel_mode == _cached_movement_mode:
		return _cached_can_move

	# Water is impassable in the land grid, so a sailing hero would read as
	# stuck in open sea without this.
	var at_sea := travel_mode == &"sea"
	var can_move := false

	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var target_tile := tile + Vector2i(dx, dy)
			if target_tile.x >= 0 and target_tile.x < map.width and target_tile.y >= 0 and target_tile.y < map.height:
				if map.is_passable(target_tile.x, target_tile.y) \
						or (at_sea and map.is_water(target_tile)):
					var cost := step_cost(tile, target_tile, map, at_sea, hero_class)
					var straight_cost := step_cost(tile,
							tile + Vector2i.RIGHT, map, at_sea, hero_class)
					if move_points >= mini(cost, straight_cost):
						can_move = true
						break
		if can_move:
			break
	_cached_movement_tile = tile
	_cached_movement_mp = move_points
	_cached_movement_mode = travel_mode
	_cached_can_move = can_move
	return _cached_can_move


var tile: Vector2i = Vector2i.ZERO
var planned_dest: Vector2i = Vector2i(-1, -1)
var move_points: int = MAX_MOVE
var max_move_points: int = MAX_MOVE
var map: MapData = null
var hero_class: String = "knight"
var travel_mode: StringName = &"land"
var carried_boat_id: int = -1
var crest_idx: int = 0

var _sprite: HeroSprite
var _tile_size: int = 32
var _path: Array = []          # remaining destination tiles (Vector2i)
var _seg_from: Vector2i
var _seg_to: Vector2i
var _seg_t: float = 0.0
var _moving: bool = false
var _current_step_time: float = BASE_STEP_TIME
var _audio_voices: Array[AudioStreamPlayer] = []
var _next_audio_voice := 0
var _pending_step_sound := ""
var _disappearing := false
var _disappear_duration := 0.0
## True while the hero dissolves on the shore after boarding.
var _fading := false

func setup(hero_class: String, start_tile: Vector2i, tile_size: int, p_map: MapData = null, crest_idx: int = 0) -> void:
	self.hero_class = hero_class
	map = p_map
	_tile_size = tile_size
	tile = start_tile
	self.crest_idx = crest_idx
	_sprite = HeroSprite.new()
	add_child(_sprite)
	# The original starts one asynchronous footstep clip per tile. Two voices
	# let adjacent steps overlap instead of cutting the previous hoofbeat off.
	for _i in 2:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_audio_voices.append(voice)
	_sprite.setup(hero_class, _tile_size, crest_idx)
	position = _world_of(tile)

## Place the hero on a tile outright, skipping the walk. Used by the probe
## runner to seat a run on the same tile the DOS reference started from.
func teleport(t: Vector2i) -> void:
	_path.clear()
	_moving = false
	tile = t
	position = _world_of(t)

## Board the boat on the neighbouring `boat_tile`. heroes.exe never walks the
## hero onto it: the step routine (0xa7eab) hides the hero where it stands and
## dissolves the 3x3 tiles around it with the pickup fade (0xdd388, same block
## size and rate), then the boat visit (0xb2770) shows the hero in the boat.
## Neither plays a sound. Returns the fade, or null when nothing is drawn.
func board(boat_tile: Vector2i, boat_id: int, boat_heading: int) -> Tween:
	face_towards(boat_tile)
	var fade := _dissolve_in_place()
	teleport(boat_tile)
	set_travel_mode(&"sea", boat_id, boat_heading)
	if fade != null:
		_sprite.visible = false
		_fading = true
		fade.tween_callback(func() -> void:
			_sprite.visible = true
			_fading = false)
	return fade

## Leave a copy of the hero's current frame here and dissolve it.
func _dissolve_in_place() -> Tween:
	if not is_inside_tree() or not is_visible_in_tree() or get_parent() == null:
		return null
	var ghost := Node2D.new()
	ghost.position = position + _sprite.position
	ghost.z_index = z_index
	ghost.z_as_relative = z_as_relative
	var materials: Array[ShaderMaterial] = []
	for c: Node in _sprite.get_children():
		if not (c is Sprite2D) or not (c as Sprite2D).visible:
			continue
		var copy := (c as Sprite2D).duplicate() as Sprite2D
		var mat := ShaderMaterial.new()
		mat.shader = DISSOLVE_SHADER
		mat.set_shader_parameter("pattern_offset", copy.position)
		mat.set_shader_parameter("reveal_progress", 1.0)
		mat.set_shader_parameter("block_size", 1.0)
		mat.set_shader_parameter("noise_steps", DynamicObjectProvider.PICKUP_DISSOLVE_STEPS)
		copy.material = mat
		materials.append(mat)
		ghost.add_child(copy)
	get_parent().add_child(ghost)
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void:
		for mat in materials:
			mat.set_shader_parameter("reveal_progress", v)
	, 1.0, 0.0, DynamicObjectProvider.PICKUP_DISSOLVE_DURATION)
	tween.tween_callback(ghost.queue_free)
	return tween

## Disembark onto the neighbouring `shore_tile`. heroes.exe never moves the
## boat onto land: the boat stays on the water tile, while the hero appears
## ashore with the pickup dissolve. Returns the fade, or null when nothing is drawn.
func disembark(shore_tile: Vector2i) -> Tween:
	face_towards(shore_tile)
	teleport(shore_tile)
	set_travel_mode(&"land")
	move_points = 0
	var g := _get_game()
	var sfx_on: bool = bool(g.sfx_enabled) if (g != null and "sfx_enabled" in g) else true
	if sfx_on and is_visible_in_tree():
		_play_step_sound("res://assets/art/KILLFADE.wav")
	var fade := _fade_in()
	return fade

## Reveal the hero's current frame here with the native dissolve.
func _fade_in() -> Tween:
	if not is_inside_tree() or not is_visible_in_tree() or get_parent() == null:
		return null
	var ghost := Node2D.new()
	ghost.position = position + _sprite.position
	ghost.z_index = z_index
	ghost.z_as_relative = z_as_relative
	var materials: Array[ShaderMaterial] = []
	for c: Node in _sprite.get_children():
		if not (c is Sprite2D) or not (c as Sprite2D).visible:
			continue
		var copy := (c as Sprite2D).duplicate() as Sprite2D
		var mat := ShaderMaterial.new()
		mat.shader = DISSOLVE_SHADER
		mat.set_shader_parameter("pattern_offset", copy.position)
		mat.set_shader_parameter("reveal_progress", 0.0)
		mat.set_shader_parameter("block_size", 1.0)
		mat.set_shader_parameter("noise_steps", DynamicObjectProvider.PICKUP_DISSOLVE_STEPS)
		copy.material = mat
		materials.append(mat)
		ghost.add_child(copy)
	if materials.is_empty():
		ghost.queue_free()
		return null
	get_parent().add_child(ghost)
	_sprite.visible = false
	_fading = true
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void:
		for mat in materials:
			mat.set_shader_parameter("reveal_progress", v)
	, 0.0, 1.0, DynamicObjectProvider.PICKUP_DISSOLVE_DURATION)
	tween.tween_callback(func() -> void:
		_sprite.visible = true
		_fading = false
		ghost.queue_free())
	return tween

## A relocation (heroes.exe 0xa5200, e.g. Dimension Door) pauses 6 ticks with the
## view already on the landing, then redraws the 448x448 map view at (16,16) with
## the 0xdd388 dissolve in 2 px blocks. That fade waits one tick per 255 blocks
## for a computer hero, two for a human's: 64 or 128 ticks here against the
## pickup fade's 16, so 4x or 8x its measured duration.
const VIEW_DISSOLVE_RECT := Rect2i(16, 16, 448, 448)
const VIEW_DISSOLVE_TICK := DynamicObjectProvider.PICKUP_DISSOLVE_DURATION / 16.0
const VIEW_DISSOLVE_PAUSE := 6 * VIEW_DISSOLVE_TICK
const VIEW_DISSOLVE_TICKS_AI := 64
const VIEW_DISSOLVE_TICKS_HUMAN := 128

## Dissolve the last drawn map view into the next one. Call it right after
## moving the hero: the view follows a hero that is fading. Null when nothing is drawn.
func view_dissolve(ticks: int = VIEW_DISSOLVE_TICKS_AI) -> Tween:
	if not is_inside_tree() or DisplayServer.get_name() == "headless":
		return null
	var img := get_viewport().get_texture().get_image()
	if img == null or not Rect2i(Vector2i.ZERO, img.get_size()).encloses(VIEW_DISSOLVE_RECT):
		return null
	var mat := ShaderMaterial.new()
	mat.shader = DISSOLVE_SHADER
	mat.set_shader_parameter("reveal_progress", 1.0)
	mat.set_shader_parameter("block_size", 2.0)
	mat.set_shader_parameter("noise_steps", 32.0)
	var shot := TextureRect.new()
	shot.texture = ImageTexture.create_from_image(img.get_region(VIEW_DISSOLVE_RECT))
	shot.position = Vector2(VIEW_DISSOLVE_RECT.position)
	shot.material = mat
	var layer := CanvasLayer.new()
	layer.layer = 50
	layer.add_child(shot)
	get_tree().root.add_child(layer)
	_fading = true
	var tween := create_tween()
	tween.tween_interval(VIEW_DISSOLVE_PAUSE)
	tween.tween_method(func(v: float) -> void:
		mat.set_shader_parameter("reveal_progress", v)
	, 1.0, 0.0, ticks * VIEW_DISSOLVE_TICK)
	tween.tween_callback(func() -> void:
		_fading = false
		layer.queue_free())
	return tween

## `boat_heading` is the facing a boarded boat already had; without it the
## sprite keeps the facing of the step that brought the hero here.
func set_travel_mode(mode: StringName, boat_id: int = -1, boat_heading: int = -1) -> void:
	travel_mode = &"sea" if mode == &"sea" else &"land"
	carried_boat_id = boat_id if travel_mode == &"sea" else -1
	if _sprite != null:
		_sprite.set_travel_mode(travel_mode, crest_idx)
		if travel_mode == &"sea" and boat_heading >= 0:
			_sprite.set_direction(boat_heading)
			_sprite.stop()

func face_towards(target_tile: Vector2i) -> void:
	var d := target_tile - tile
	if d != Vector2i.ZERO:
		_sprite.set_direction(Direction.from_delta(d.x, d.y))
		# face_towards is used for stationary interactions/spawn restoration.
		# Always settle onto the direction row's standing frame so an engage
		# cannot leave the horse frozen in a stride pose.
		_sprite.stop()

func get_direction() -> int:
	return _sprite.get_direction() if _sprite != null else Direction.S

## A landed boat is moored facing the hero's step ashore: heroes.exe 0xa7bd2
## turns the hero to the step (0xa7873 sets +0x164) and copies that to the
## boat record's facing byte (0xa7df9).
static func landing_facing(water_tile: Vector2i, shore_tile: Vector2i) -> int:
	var d := shore_tile - water_tile
	return Direction.from_delta(d.x, d.y)

func move_along(path: Array) -> void:
	if path.size() < 2:
		return
	_path = path.slice(1)   # drop current tile
	_moving = true
	_start_next_segment()

## Halt hero movement after completing the current tile segment.
## Clears any queued steps remaining in this walk run (heroes.exe 0x93059 / 0xa711a).
func stop_movement() -> void:
	if not _moving:
		return
	_path.clear()

func is_moving() -> bool:
	return _moving or _fading

## The cell the hero is painted on (AdventureDepth): for horizontal movement on
## the same row, the hero belongs to the cell left so layer-2 scenery (castle
## roofs, mountain tops) cleanly occludes the horse without legs popping out;
## for vertical/diagonal steps, it belongs to the cell left until half the step,
## then to the entered cell.
func paint_tile() -> Vector2i:
	if _moving and _seg_from.y == _seg_to.y:
		return _seg_from
	return _seg_to if _moving and _seg_t >= 0.5 else tile

## Remove a defeated adventure-map hero with the native fade-out visual. The
## caller owns sound playback so every removal can share AdventureAudio's
## one-shot lifetime handling and use the cue's exact duration.
func disappear(duration: float = DEFAULT_DISAPPEAR_TIME) -> void:
	if _disappearing:
		return
	_disappearing = true
	_disappear_duration = duration
	_moving = false
	_path.clear()
	set_process(false)
	if _sprite != null:
		_sprite.stop()
	if not is_inside_tree() or duration <= 0.0:
		queue_free()
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.tween_property(self, "modulate:a", 0.0, duration)
	tween.finished.connect(queue_free)

func center() -> Vector2:
	return position + Vector2(_tile_size, _tile_size) * 0.5

static func _get_game() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop != null and loop.root != null and loop.root.has_node("Game"):
		return loop.root.get_node("Game")
	return null

## Seconds a hero spends crossing one tile, per System Menu speed setting.
##
## Measured off five DOSBox recordings, one per setting, by tracking how far
## the map scrolled and how fast the plotted path's arrows were consumed:
##
##   Walk    1.33 s   map scroll over 4.6 s, 116 smooth steps, the cleanest read
##   Trot    0.46 s   scroll says 0.47, arrow cadence says 0.44
##   Canter  0.20 s   arrow cadence only, no cross-check
##   Gallop  0.167 s  arrow cadence only, no cross-check
##   Jump    0.112 s  arrow cadence, regular to within 0.02 s
##
## Jump is not instant. It was 0.0 here, which made a ten-tile move finish in
## one frame; the original still spends about an eighth of a second a tile.
## Walk was more than twice too fast.
##
## Expressed as pixels of the 32-wide tile per VGA frame at 70 Hz these come to
## 0.34, 0.99, 2.29, 2.74 and 4.08, so the original is very likely moving a
## hero 1/3, 1, 2, 3 and 4 pixels a frame. That model reproduces walk, trot and
## jump, the three solid measurements, to within 3%, and it predicts 0.229 for
## canter and 0.152 for gallop against the 0.20 and 0.167 measured here. Those
## two are the weakest readings and the ones to re-measure.
static func step_time_for_speed(speed: int) -> float:
	match speed:
		0: return 1.33  # WALK
		1: return 0.46  # TROT
		2: return 0.20  # CANTER
		3: return 0.167 # GALLOP
		4: return 0.112 # JUMP
		_: return 0.20

static func current_step_time() -> float:
	var g := _get_game()
	if g != null and "movement_speed" in g:
		return step_time_for_speed(int(g.movement_speed))
	return BASE_STEP_TIME

func advance(dt: float) -> void:
	if not _moving:
		return

	if _current_step_time <= 0.0:
		while _moving:
			tile = _seg_to
			position = _world_of(tile)
			emit_signal("entered_tile", tile)
			if _path.is_empty():
				_moving = false
				_sprite.stop()
				emit_signal("arrived")
				break
			_start_next_segment()
		return

	var remaining_dt := dt
	while remaining_dt > 0.0 and _moving:
		var step_left_time := (1.0 - _seg_t) * _current_step_time
		if remaining_dt >= step_left_time:
			remaining_dt -= step_left_time
			tile = _seg_to
			position = _world_of(tile)
			_play_pending_step_sound(true)
			emit_signal("entered_tile", tile)
			if _path.is_empty():
				_moving = false
				_sprite.stop()
				emit_signal("arrived")
				break
			_start_next_segment()
		else:
			_seg_t += remaining_dt / _current_step_time
			remaining_dt = 0.0
			position = _world_of(_seg_from).lerp(_world_of(_seg_to), _seg_t)
			# Walk cycle is locked to tile progress (one 9-frame cycle per
			# tile, like the original) — not to a wall-clock fps timer.
			_sprite.set_walk_progress(_seg_t)
			_play_pending_step_sound()

## heroes.exe 0xa770a starts the step clip when the walk frame counter reaches
## 3, not when the tile move begins.
const STEP_SOUND_FRAME := 3

func _play_pending_step_sound(force := false) -> void:
	if _pending_step_sound == "" or (not force and _sprite.walk_frame() < STEP_SOUND_FRAME):
		return
	var path := _pending_step_sound
	_pending_step_sound = ""
	_play_step_sound(path)

func _start_next_segment() -> void:
	_seg_from = tile
	_seg_to = _path.pop_front() as Vector2i
	_seg_t = 0.0
	var d := _seg_to - _seg_from
	_sprite.set_direction(Direction.from_delta(d.x, d.y))
	_sprite.play_walk()
	_sprite.set_walk_progress(0.0)
	var g := _get_game()
	var mv_speed: int = int(g.movement_speed) if (g != null and "movement_speed" in g) else 2
	var sfx_on: bool = bool(g.sfx_enabled) if (g != null and "sfx_enabled" in g) else true
	# heroes.exe 0x926eb / 0x92de2 load wsnd0x for Walk and wsnd2x for every
	# other speed; the wsnd1x tier is never picked.
	var speed_tier := 0 if mv_speed == 0 else 2
	# A hero stepping on a tile the human has not explored is hidden and silent
	# (the computer march in the original teleports there unseen).
	_pending_step_sound = ""
	if map != null and mv_speed != 4 and sfx_on and is_visible_in_tree():
		_pending_step_sound = walk_sound_path(map, _seg_to, speed_tier)
		if map.is_water(_seg_from) != map.is_water(_seg_to):
			_pending_step_sound = "res://assets/art/KILLFADE.wav"
	# Every step takes the same wall-clock time regardless of terrain or
	# diagonal direction (as in the original) — cost only drains move points.
	_current_step_time = current_step_time()

## HOMM1's wsnd bank is 3 speed tiers x 7 terrain classes. A 0.25-second tile
## transit is the fast tier (wsnd20..26); the destination ground selects the
## final digit. Snow shares desert, matching the native table.
static func walk_sound_path(p_map: MapData, destination: Vector2i, speed_tier: int = 2) -> String:
	if p_map == null:
		return ""
	var terrain_digit := 1 # grass / safe fallback
	if p_map.is_water(destination):
		terrain_digit = 0
	else:
		match p_map.terrain_at(destination):
			"snow": terrain_digit = 5
			"swamp": terrain_digit = 3
			"lava": terrain_digit = 4
			"desert": terrain_digit = 5
			"dirt": terrain_digit = 6
			_: terrain_digit = 1
	return "res://assets/art/wsnd%d%d.wav" % [clampi(speed_tier, 0, 2), terrain_digit]

func _play_step_sound(path: String) -> void:
	if not is_inside_tree() or path == "" or _audio_voices.is_empty():
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	var voice := _audio_voices[_next_audio_voice]
	_next_audio_voice = (_next_audio_voice + 1) % _audio_voices.size()
	voice.stream = stream
	var g := _get_game()
	var vol: float = float(g.get_sfx_volume()) if (g != null and g.has_method("get_sfx_volume")) else 1.0
	voice.volume_db = linear_to_db(maxf(vol * STEP_SOUND_GAIN, 0.001))
	voice.play()

func _world_of(t: Vector2i) -> Vector2:
	return Vector2(t.x * _tile_size, t.y * _tile_size)

func _process(delta: float) -> void:
	advance(delta)
