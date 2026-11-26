class_name TurnTransitionPanel
extends Control

## Bottom-right end-turn display from the original adventure screen. During an
## AI turn the hero banner becomes the player's large color crest beside the
## animated hourglass. At dawn it becomes the sunrise/calendar card.

const STONE := UiKit.ART + "stonback/0000.png"
const CREST := UiKit.ART + "brcrest/%04d.png"
const HOURGLASS_DIR := UiKit.ART + "hourglas/"
const SUNMOON := UiKit.ART + "sunmoon/%04d.png"
const HOURGLASS_FPS := 8.0
const HOURGLASS_LAST_FRAME := 10
const HOURGLASS_CELL_X := 66
## The sand sprites are drawn 2 px lower than their ICN offsets.
##
## hourglas.icn puts every frame on one shared origin, and its sand deltas
## carry offsets 2 px above the glass they belong to. Measured on the
## extracted art: the base frame's glass cavity runs from row 8 (top bulb
## ceiling) to row 42 (bottom bulb floor), with the neck at rows 24..26.
## The sand art is authored against exactly that cavity, so at the raw
## offsets it does not fit:
##
##   frame 1  (full top bulb)   rows 6..23  -> 2 rows spill over the wooden
##                                        cap's bottom lip
##   frame 10 (full bottom bulb) rows 23..40 -> the pile stops 2 rows above
##                                        the glass floor
##
## Dropping the art 2 px puts every opaque sand pixel of all ten state frames
## inside the cavity, makes frame 1 exactly the 18-row top bulb and frame 10
## exactly the 18-row bottom bulb, and lets the top bulb's sand plug the
## neck. tests/test_hourglass_sand_alignment.gd holds that measurement.
## The DOS recording agrees: matched against the computer turns at 4:32-4:44
## of the campaign 1 video, every sand frame fits best 2 px down.
const SAND_DY := 2
## The DOS calendar card text is centred about 3 px left of the panel centre.
const CALENDAR_TEXT_DX := -3

signal transition_hidden

enum Mode { NONE, AI_TURN, NEW_DAY }

var mode := Mode.NONE
var color_index: int = 0
var shown_day: int = 1
var hourglass_frame: int = 1
var hold: bool = false

const NEW_DAY_DISPLAY_SECONDS := 4.0

var _rect: Rect2
var _elapsed: float = 0.0
var _display_timer: float = 0.0
var _stone: Texture2D
var _crest: Texture2D
var _hourglass_base: Texture2D
var _sand_specs: Array = []
var _sand_textures: Array[Texture2D] = []
var _sunmoon: Texture2D
var _font: Font
var _small_font: Font

func setup(rect: Rect2) -> void:
	_rect = rect
	_stone = UiKit.load_texture(STONE)
	_hourglass_base = UiKit.load_texture(HOURGLASS_DIR + "0000.png")
	_sunmoon = UiKit.load_texture(SUNMOON % 0)
	_font = UiKit.font_normal()
	_small_font = UiKit.font_small()

	# Frames 1..10 are complete sand states. The later sprites in hourglas.icn
	# are particle deltas, not part of the turn-progress sequence seen here.
	var spec := SpecLoader.load_spec(HOURGLASS_DIR + "spec.json")
	_sand_specs.clear()
	_sand_textures.clear()
	for frame_id in range(1, HOURGLASS_LAST_FRAME + 1):
		var frame_spec: Dictionary = spec.sprites[frame_id]
		_sand_specs.append(frame_spec)
		_sand_textures.append(UiKit.load_texture(HOURGLASS_DIR + String(frame_spec.file)))

	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)

static func content_origin(rect: Rect2) -> Vector2:
	# hourglas frame 0 is the native 117x51 two-cell base. Center it without
	# scaling inside the native 144x72 hero band.
	return rect.position + Vector2(
			round((rect.size.x - 117.0) * 0.5),
			round((rect.size.y - 51.0) * 0.5))

## Where a sand delta from hourglas.icn lands inside the 51x51 hourglass cell.
## The cell starts 66 px into frame 0 (the crest cell and its divider come
## first) and the sand sits SAND_DY lower than its ICN offset.
static func sand_origin(spec_offset: Vector2) -> Vector2:
	return Vector2(HOURGLASS_CELL_X, SAND_DY) + spec_offset

static func calendar_parts(day: int) -> Vector3i:
	var safe_day := maxi(1, day)
	var month := ((safe_day - 1) / 28) + 1
	var week := (((safe_day - 1) / 7) % 4) + 1
	var day_of_week := ((safe_day - 1) % 7) + 1
	return Vector3i(month, week, day_of_week)

## SUNMOON frame 0 is the day 2-7 sunrise. Frames 1-4 are the successive
## week-start moon phases, selected on Day 1 of each week.
static func calendar_art_frame(day: int) -> int:
	var parts := calendar_parts(day)
	return parts.y if parts.z == 1 else 0

static func calendar_month_week_text(day: int) -> String:
	var parts := calendar_parts(day)
	# The DOS card has two spaces between the fields (100 px wide in smalfont,
	# measured on a DOSBox capture). Bitmap-font whitespace is visible, so do
	# not use alignment padding here.
	return "Month: %d  Week: %d" % [parts.x, parts.y]

static func frame_at(elapsed: float) -> int:
	return clampi(1 + int(maxf(0.0, elapsed) * HOURGLASS_FPS),
			1, HOURGLASS_LAST_FRAME)

func show_ai_turn(player_color: int) -> void:
	mode = Mode.AI_TURN
	color_index = clampi(player_color, 0, 4)
	_crest = UiKit.load_texture(CREST % color_index)
	_elapsed = 0.0
	hourglass_frame = 1
	visible = true
	set_process(true)
	queue_redraw()

func show_new_day(day: int, p_hold: bool = false) -> void:
	mode = Mode.NEW_DAY
	hold = p_hold
	shown_day = maxi(1, day)
	_sunmoon = UiKit.load_texture(SUNMOON % calendar_art_frame(shown_day))
	_display_timer = NEW_DAY_DISPLAY_SECONDS
	visible = true
	set_process(true)
	queue_redraw()

func hide_transition() -> void:
	mode = Mode.NONE
	hold = false
	visible = false
	set_process(false)
	transition_hidden.emit()

func _has_point(point: Vector2) -> bool:
	return visible and _rect.has_point(point)

func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed:
		if _rect.has_point(event.position):
			if event.button_index == MOUSE_BUTTON_LEFT:
				if mode == Mode.NEW_DAY and not hold:
					hide_transition()
					accept_event()
				elif mode == Mode.AI_TURN or hold:
					accept_event()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				accept_event()

func _process(delta: float) -> void:
	if mode == Mode.AI_TURN:
		_elapsed += delta
		var next_frame := frame_at(_elapsed)
		if next_frame != hourglass_frame:
			hourglass_frame = next_frame
			queue_redraw()
	elif mode == Mode.NEW_DAY:
		if not hold:
			_display_timer -= delta
			if _display_timer <= 0.0:
				hide_transition()

func _draw() -> void:
	if mode == Mode.NONE:
		return
	var base := _rect.position
	if _stone != null:
		draw_texture(_stone, base)

	if mode == Mode.AI_TURN:
		_draw_ai_turn()
	else:
		_draw_new_day(base)

func _draw_ai_turn() -> void:
	var origin := content_origin(_rect)
	if _hourglass_base != null:
		draw_texture(_hourglass_base, origin)
	# brcrest is 50x47; the hourglas base reserves the native 50x51 black
	# cell for it, leaving a two-pixel top/bottom inset.
	if _crest != null:
		draw_texture(_crest, origin + Vector2(0, 2))
	var index := hourglass_frame - 1
	if index >= 0 and index < _sand_specs.size() and index < _sand_textures.size():
		var frame_spec: Dictionary = _sand_specs[index]
		var sand: Texture2D = _sand_textures[index]
		if sand != null:
			# Delta offsets are local to the 51x51 hourglass cell. Frame 0 also
			# contains the 50x51 crest cell and a 16px divider before it, and
			# the sand sits 2 px lower than its ICN offset (SAND_DY).
			draw_texture(sand, origin + sand_origin(frame_spec.offset))

func _draw_new_day(base: Vector2) -> void:
	if _sunmoon != null:
		draw_texture(_sunmoon, base)
	if _font == null or _small_font == null:
		return
	var date := calendar_parts(shown_day)
	var font_size: int = _font.fixed_size
	var small_font_size: int = _small_font.fixed_size
	draw_string(_small_font, base + Vector2(CALENDAR_TEXT_DX, 36),
			calendar_month_week_text(shown_day),
			HORIZONTAL_ALIGNMENT_CENTER, _rect.size.x, small_font_size, Color.WHITE)
	draw_string(_font, base + Vector2(CALENDAR_TEXT_DX - 1, 55), "Day: %d" % date.z,
			HORIZONTAL_ALIGNMENT_CENTER, _rect.size.x, font_size, Color.WHITE)
