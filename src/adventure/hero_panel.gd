class_name HeroPanel
extends Control

## Native 144x72 adventure-map status window: hero crest/name plus army stacks.
## The five army cells reflow into two rows: at most two beside the crest and
## at most three along the bottom.

const STONE := UiKit.ART + "stonback/0000.png"
const CREST := UiKit.ART + "smcrest/%04d.png"   # small crest (25x25): id = color*4 + class
const MONS32 := UiKit.ART + "mons32/%04d.png"
const RESSMALL := UiKit.ART + "ressmall/0000.png"
const SUNMOON := UiKit.ART + "sunmoon/%04d.png"
const INFO_WIDTH := 64.0
const CREST_POS := Vector2(16, 4)
## The original draws the hero's SHORT name in `smalfont` with the pen at
## (486, 427) in screen coordinates, which is (6, 35) inside the panel at
## (480, 392). The name is left-aligned there, not centred (KB
## file-formats-assets.md 11.7, confirmed on a DOS capture).
const NAME_X := 6.0
const NAME_BASELINE := 35.0
const TOP_ROW_BOTTOM := 35.0
const BOTTOM_ROW_BOTTOM := 70.0
const STACK_STRIDE := 50.0
const BOTTOM_ROW_CENTER := 68.0
const TOP_ROW_CENTER := 94.0
const TOP_ROW_STRIDE := 42.0
const COUNT_OFFSET_X := 14.0
const AUTO_REVERT_DELAY := 5.0

var _rect: Rect2
var _hero_name: String = ""
var _font: Font
var _small_font: Font
var _stone: Texture2D
var _crest: Texture2D
var _ressmall: Texture2D
var _army: ArmyData = null
var _crest_idx: int = 0
var _stacks: Array = []   # [{count:int, tex:Texture2D}]
var show_details: bool = true
var _player: PlayerState = null
var _view_mode: int = 0   # 0: army, 1: kingdom resources, 2: date
var _revert_timer: float = 0.0

static var _mons32_cache: Dictionary = {}
static var _crest_cache: Dictionary = {}
static var _sunmoon_cache: Texture2D = null

static func get_mons32_texture(native_id: int) -> Texture2D:
	var key := maxi(0, native_id)
	if not _mons32_cache.has(key):
		var rel := "mons32/%04d.png" % key
		var tex: Texture2D = MapArtResolver.get_atlas_texture(rel)
		if tex == null:
			tex = UiKit.load_texture(MONS32 % key)
		_mons32_cache[key] = tex
	return _mons32_cache[key]

static func get_crest_texture(idx: int) -> Texture2D:
	if not _crest_cache.has(idx):
		_crest_cache[idx] = UiKit.load_texture(CREST % idx)
	return _crest_cache[idx]

static func get_sunmoon_texture() -> Texture2D:
	if _sunmoon_cache == null:
		_sunmoon_cache = UiKit.load_texture(SUNMOON % 0)
	return _sunmoon_cache

var _last_hero_name: String = ""
var _last_crest_idx: int = -1
var _last_army_sig: Array = []
var _last_view_mode: int = -1
var _last_show_details: bool = true
var _last_res_sig: Array = []
var _last_day: int = -1

func _get_army_signature() -> Array:
	if _army == null:
		return []
	var sig := []
	for slot: Dictionary in _army.slots.slice(0, 5):
		sig.append(slot.get("unit", ""))
		sig.append(int(slot.get("count", 0)))
	return sig

func _get_res_signature() -> Array:
	if _player == null:
		return []
	var sig := [_player.towns.size(), _player.gold()]
	var res_order := ["wood", "mercury", "ore", "sulfur", "crystal", "gems"]
	for r in res_order:
		sig.append(int(_player.resources.get(r, 0)))
	return sig

func _get_current_day() -> int:
	var loop := Engine.get_main_loop() as SceneTree
	if loop != null and loop.root != null:
		var game: Node = loop.root.get_node_or_null("Game")
		if game != null:
			var state_value: Variant = game.get("state")
			if state_value != null:
				return int(state_value.day)
	return 1

func setup(rect: Rect2, _hero: Hero, army: ArmyData, hero_name: String,
		crest_idx: int = 0, player: PlayerState = null) -> void:
	_rect = rect
	if player != null:
		_player = player
	_hero_name = hero_name
	_army = army
	_crest_idx = crest_idx
	_font = UiKit.font_normal()
	_small_font = UiKit.font_small()
	_stone = UiKit.load_texture(STONE)
	_crest = get_crest_texture(crest_idx)
	_ressmall = UiKit.load_texture(RESSMALL)
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_process(false)
	refresh(true)

func _update_stacks() -> void:
	_stacks.clear()
	if _army != null:
		for slot: Dictionary in _army.slots.slice(0, 5):
			var unit: String = slot.unit
			var native_id := CreatureCatalog.native_id(unit)
			var tex := get_mons32_texture(native_id)
			_stacks.append({"count": int(slot.count), "tex": tex})

## Re-point the banner at a newly-activated hero (Stage-5 switching): same
## data as setup() but keeps the band rect already configured.
func set_hero(hero: Hero, army: ArmyData, hero_name: String, crest_idx: int = 0) -> void:
	setup(_rect, hero, army, hero_name, crest_idx, _player)

func cycle_view() -> void:
	_view_mode = (_view_mode + 1) % 3
	if _view_mode != 0:
		_revert_timer = AUTO_REVERT_DELAY
		set_process(true)
	else:
		_revert_timer = 0.0
		set_process(false)
	queue_redraw()

func reset_view() -> void:
	_view_mode = 0
	_revert_timer = 0.0
	set_process(false)
	queue_redraw()

func _process(delta: float) -> void:
	if _view_mode != 0:
		_revert_timer -= delta
		if _revert_timer <= 0.0:
			_view_mode = 0
			_revert_timer = 0.0
			set_process(false)
			queue_redraw()

func _has_point(point: Vector2) -> bool:
	return _rect.has_point(point)

func _gui_input(event: InputEvent) -> void:
	if not show_details:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _rect.has_point(event.position):
			cycle_view()
			accept_event()

func refresh(force: bool = false) -> bool:
	if _player != null:
		var active_model := _player.active()
		if active_model != null:
			_hero_name = active_model.hero_name
			if active_model.army != null:
				_army = active_model.army
			if active_model.crest_idx != _crest_idx:
				_crest_idx = active_model.crest_idx
				_crest = get_crest_texture(_crest_idx)

	var current_army_sig := _get_army_signature()
	var current_res_sig := _get_res_signature() if _view_mode == 1 else []
	var current_day := _get_current_day() if _view_mode == 2 else -1

	if not force and _hero_name == _last_hero_name and _crest_idx == _last_crest_idx \
			and current_army_sig == _last_army_sig and _view_mode == _last_view_mode \
			and show_details == _last_show_details and current_res_sig == _last_res_sig \
			and current_day == _last_day:
		return false

	_last_hero_name = _hero_name
	_last_crest_idx = _crest_idx
	_last_army_sig = current_army_sig
	_last_view_mode = _view_mode
	_last_show_details = show_details
	_last_res_sig = current_res_sig
	_last_day = current_day

	_update_stacks()
	queue_redraw()
	return true

func _draw() -> void:
	var base := _rect.position
	var w := _rect.size.x
	# stonback is the original status-window background at its native 144x72.
	if _stone != null:
		draw_texture(_stone, base)
	
	if not show_details:
		return
	if _view_mode == 1:
		_draw_resources(base, w)
		return
	if _view_mode == 2:
		_draw_date(base, w)
		return

	# View 0: Army stacks
	# The crest is native 25x25 at (16,4). The name is the hero's short name,
	# drawn in the information cell beneath the crest at the original's pen.
	if _crest != null:
		draw_texture(_crest, base + CREST_POS)
	if _small_font != null:
		var name_text := fit_name(display_name(_hero_name), INFO_WIDTH - NAME_X, _small_font)
		draw_string(_small_font, base + Vector2(NAME_X, NAME_BASELINE), name_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font.fixed_size, Color.WHITE)

	# Native mons32 icons stay at 1:1. Three stacks fit on the bottom row; a
	# fourth/fifth stack uses the space to the right of the crest.
	var n := _stacks.size()
	if n == 0:
		return
	var top_count := maxi(0, n - 3)
	var bottom_count := n - top_count
	for i in n:
		var st: Dictionary = _stacks[i]
		var in_top := i < top_count
		var row_index := i if in_top else i - top_count
		var row_count := top_count if in_top else bottom_count
		var center_x := stack_center_x(row_index, row_count, in_top)
		var row_bottom := TOP_ROW_BOTTOM if in_top else BOTTOM_ROW_BOTTOM
		var tex: Texture2D = st.tex
		if tex != null:
			var tw := float(tex.get_width())
			var th := float(tex.get_height())
			draw_texture(tex, base + Vector2(round(center_x - tw * 0.5), row_bottom - th))
		var count_text := str(st.count)
		if _small_font != null:
			var count_width := _small_font.get_string_size(count_text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font.fixed_size).x
			var count_x := minf(center_x + COUNT_OFFSET_X, w - count_width - 2.0)
			draw_string(_small_font, base + Vector2(round(count_x), row_bottom), count_text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, _small_font.fixed_size, Color.WHITE)

static func stack_center_x(index: int, count: int, top_row: bool) -> float:
	if top_row:
		return TOP_ROW_CENTER + (float(index) - float(count - 1) * 0.5) * TOP_ROW_STRIDE
	return BOTTOM_ROW_CENTER + (float(index) - float(count - 1) * 0.5) * STACK_STRIDE


## The name the original's status window shows: the hero's short name, not
## the full one (KB heroes.md 4.2; the DOS capture shows "Gallant" for Sir
## Gallant).
static func display_name(full_name: String) -> String:
	return HeroNames.short_for(full_name)


## Cut a name at a character boundary so no glyph is drawn half. The original
## never shortens a name -- its font routine does not clip a glyph
## (heroes.exe 0xe3191), and every hero it knew had a short name that fit --
## so this only matters for names outside the 36-hero pool.
static func fit_name(text: String, max_width: float, font: Font = null) -> String:
	var f := font if font != null else UiKit.font_small()
	if f == null:
		return text
	if f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, f.fixed_size).x <= max_width:
		return text
	var cut := ""
	for i in text.length():
		var candidate := text.substr(0, i + 1)
		if f.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, f.fixed_size).x > max_width:
			break
		cut = candidate
	return cut.strip_edges()

func _draw_resources(base: Vector2, _width: float) -> void:
	if _ressmall != null:
		draw_texture(_ressmall, base + Vector2(4, 3))
	if _player == null or _small_font == null:
		return

	var small_font_size: int = _small_font.fixed_size

	# Top row: Castles, Towns, Gold
	var castles_count := 0
	var towns_count := 0
	if _player != null:
		for t: TownModel in _player.towns:
			if t.has_castle:
				castles_count += 1
			else:
				towns_count += 1
	var gold_count := _player.gold() if _player != null else 0

	# Top row numbers (Castle under x=25, Town under x=80, Gold under x=121)
	var c_str := str(castles_count)
	var t_str := str(towns_count)
	var g_str := str(gold_count)
	var c_x := roundf(25.5 - _small_font.get_string_size(c_str, HORIZONTAL_ALIGNMENT_LEFT, -1, small_font_size).x * 0.5)
	var t_x := roundf(80.0 - _small_font.get_string_size(t_str, HORIZONTAL_ALIGNMENT_LEFT, -1, small_font_size).x * 0.5)
	var g_x := roundf(121.5 - _small_font.get_string_size(g_str, HORIZONTAL_ALIGNMENT_LEFT, -1, small_font_size).x * 0.5)
	draw_string(_small_font, base + Vector2(c_x, 38), c_str, HORIZONTAL_ALIGNMENT_LEFT, -1, small_font_size, Color.WHITE)
	draw_string(_small_font, base + Vector2(t_x, 38), t_str, HORIZONTAL_ALIGNMENT_LEFT, -1, small_font_size, Color.WHITE)
	draw_string(_small_font, base + Vector2(g_x, 38), g_str, HORIZONTAL_ALIGNMENT_LEFT, -1, small_font_size, Color.WHITE)

	# Bottom row (6 resources): Wood (14), Mercury (37), Ore (60), Sulfur (83), Crystal (107), Gems (130)
	var res_order := ["wood", "mercury", "ore", "sulfur", "crystal", "gems"]
	var res_x: Array[float] = [14.0, 37.0, 60.0, 83.0, 107.0, 130.0]
	for i in range(6):
		var r_name: String = res_order[i]
		var amt := int(_player.resources.get(r_name, 0))
		var amt_str := str(amt)
		var text_w: float = _small_font.get_string_size(amt_str, HORIZONTAL_ALIGNMENT_LEFT, -1, small_font_size).x
		var x_pos := roundf(res_x[i] - text_w * 0.5)
		draw_string(_small_font, base + Vector2(x_pos, 67), amt_str, HORIZONTAL_ALIGNMENT_LEFT, -1, small_font_size, Color.WHITE)

func _draw_date(base: Vector2, width: float) -> void:
	var day := _get_current_day()

	var sunmoon_tex := get_sunmoon_texture()
	if sunmoon_tex != null:
		draw_texture(sunmoon_tex, base)

	if _font == null or _small_font == null:
		return

	var date: Vector3i = TurnTransitionPanel.calendar_parts(day)
	var small_font_size: int = _small_font.fixed_size
	var font_size: int = _font.fixed_size

	draw_string(_small_font, base + Vector2(TurnTransitionPanel.CALENDAR_TEXT_DX, 36),
			TurnTransitionPanel.calendar_month_week_text(day),
			HORIZONTAL_ALIGNMENT_CENTER, width, small_font_size, Color.WHITE)
	draw_string(_font, base + Vector2(TurnTransitionPanel.CALENDAR_TEXT_DX - 1, 55), "Day: %d" % date.z,
			HORIZONTAL_ALIGNMENT_CENTER, width, font_size, Color.WHITE)
