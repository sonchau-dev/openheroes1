extends Control

const ART := UiKit.ART
const FONT := UiKit.FONT
const MINIMON := ART + "minimon/"
const MINIMON_SPEC := MINIMON + "spec.json"
const IDLE_FRAMES_PER_UNIT := 6
const TICKS_PER_FRAME := 3
const TOTAL_CYCLE_TICKS := IDLE_FRAMES_PER_UNIT * TICKS_PER_FRAME # 18

## Text columns and first row, from the bigfont records in hiscore.bin
## (x, width) per column; every row is 16 px tall and 40 px below the last.
## The record's y is 70; a Label draws the glyphs 2 px higher than the original
## does inside that rect, measured against a DOSBox capture.
const TEXT_TOP := 72.0
const ROW_PITCH := 40.0
const COL_X: Array[float] = [85.0, 255.0, 405.0, 445.0]
const COL_W: Array[float] = [160.0, 140.0, 50.0, 92.0]

## The counter ticks at 7.8 Hz and a pose lasts 3 ticks, so 0.385 s a pose and
## 2.31 s a loop. Measured off a DOSBox recording of the original (2026-10-11):
## pose period 0.3858 s on every row, and the rows sit on three phases 0.128 s
## (one tick) apart, which is the per-row counter offset.
const TICK_S := 1.0 / 7.8
const MINIMON_FRAME_S := TICK_S * float(TICKS_PER_FRAME)

var _campaign := true
var _rows: Array[Node] = []
var _toggle: IcnButton
var _counters: Array[int] = []
var _unit_nodes: Array[TextureRect] = []
var _unit_frames: Array[Array] = []
var _anim_timer: float = 0.0
var _minimon_spec: Dictionary = {}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_campaign = Game.high_scores_mode != &"standard"
	var shots = DevFlags.tool("res://src/tools/shots/menu_shots.gd")
	if shots != null:
		shots.high_scores_prepare(self)

	_minimon_spec = SpecLoader.load_spec(MINIMON_SPEC)
	if _counters.is_empty():
		for i in range(10):
			_counters.append(randi_range(0, TOTAL_CYCLE_TICKS - 1))

	var bg := UiKit.texture_rect(ART + "hiscore.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_toggle = IcnButton.new()
	_toggle.name = "Toggle"
	_toggle.position = Vector2(8, 314)
	_toggle.pressed.connect(func(_action):
		_campaign = not _campaign
		_rebuild())
	add_child(_toggle)

	var exit := IcnButton.new()
	exit.name = "Exit"
	exit.setup(ART + "hiscore/", 4, "exit")
	exit.position = Vector2(604, 314)
	exit.pressed.connect(func(_action): Game.to_menu())
	add_child(exit)

	_rebuild()

	if shots != null:
		await shots.capture(self)

func _process(delta: float) -> void:
	advance_animation(delta)

func advance_animation(delta: float) -> void:
	if _unit_nodes.is_empty():
		return
	_anim_timer += delta
	var ticks := int(_anim_timer / TICK_S)
	if ticks == 0:
		return
	_anim_timer -= float(ticks) * TICK_S
	for i in range(_unit_nodes.size()):
		_counters[i] = (_counters[i] + ticks) % TOTAL_CYCLE_TICKS
		_apply_unit_frame(i)

func _rebuild() -> void:
	for node in _rows:
		node.queue_free()
	_rows.clear()
	_unit_nodes.clear()
	_unit_frames.clear()

	_toggle.setup(ART + "hiscore/", 0 if _campaign else 2,
			"show_standard" if _campaign else "show_campaign")
	var scores := HighScoreStore.load_scores()
	var entries: Array = scores.campaign if _campaign else scores.standard
	var font := UiKit.font_normal()

	# Headers positioned per authentic hiscore.bin
	_add_header(6, Vector2(99, 31))
	_add_header(12 if _campaign else 7, Vector2(269, 31))
	_add_header(8 if _campaign else 9, Vector2(373, 31))
	_add_header(10, Vector2(461, 31))

	# Authentic purple rating panel strip from hiscore.icn frame 11 (50x400 at 538, 54)
	var strip := UiKit.texture_rect(ART + "hiscore/0011.png", Vector2(538, 54))
	strip.name = "RatingStrip"
	add_child(strip)
	_rows.append(strip)

	for i in range(mini(10, entries.size())):
		var row: Dictionary = entries[i]
		var row_y := 54.0 + float(i) * ROW_PITCH
		var text_y := TEXT_TOP + float(i) * ROW_PITCH

		var player_text: String = String(row.get("player", ""))
		_add_label(font, player_text, Vector2(COL_X[0], text_y), COL_W[0])

		var second_col: String = String(CampaignCatalog.LEADER_NAMES[int(row.get("leader", 0))]) \
				if _campaign else String(row.get("land", ""))
		_add_label(font, second_col, Vector2(COL_X[1], text_y), COL_W[1])

		var third_col: String = str(row.get("days", 0) if _campaign else row.get("score", 0))
		_add_label(font, third_col, Vector2(COL_X[2], text_y), COL_W[2])

		var unit := HighScoreStore.creature_for_campaign_days(int(row.get("days", 0))) \
				if _campaign else HighScoreStore.creature_for_score(int(row.get("score", 0)))
		_add_label(font, HighScoreStore.creature_title(unit), Vector2(COL_X[3], text_y), COL_W[3])
		var base_frame := HighScoreStore.minimon_frame_for_creature(unit)
		_add_animated_unit(i, base_frame, Vector2(538, row_y))

func _add_animated_unit(row_index: int, base_frame: int, cell_pos: Vector2) -> void:
	var frames: Array[Dictionary] = []
	var sprites: Array = _minimon_spec.get("sprites", [])
	for j in range(IDLE_FRAMES_PER_UNIT):
		var frame_id := base_frame + j
		var rel := "minimon/%04d.png" % frame_id
		var tex: Texture2D = MapArtResolver.get_atlas_texture(rel)
		if tex == null:
			var path := MINIMON + "%04d.png" % frame_id
			if ResourceLoader.exists(path):
				tex = UiKit.load_texture(path)
		var offset := Vector2.ZERO
		if frame_id < sprites.size():
			var sp: Dictionary = sprites[frame_id]
			offset = Vector2(sp.get("offset", Vector2i.ZERO))
		elif tex != null:
			var spr_size := tex.get_size()
			offset = Vector2(round((50.0 - spr_size.x) * 0.5), round((40.0 - spr_size.y) * 0.5))
		frames.append({"tex": tex, "pos": cell_pos + offset})

	var icon := TextureRect.new()
	icon.name = "UnitIcon%d" % row_index
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)
	_rows.append(icon)
	_unit_nodes.append(icon)
	_unit_frames.append(frames)

	while _counters.size() <= row_index:
		_counters.append(randi_range(0, TOTAL_CYCLE_TICKS - 1))

	_apply_unit_frame(row_index)

func _apply_unit_frame(row_index: int) -> void:
	if row_index >= _unit_nodes.size() or row_index >= _unit_frames.size():
		return
	var frames: Array = _unit_frames[row_index]
	if frames.is_empty():
		return
	var counter: int = _counters[row_index]
	var subframe := (counter / TICKS_PER_FRAME) % frames.size()
	var fr: Dictionary = frames[subframe]
	var icon: TextureRect = _unit_nodes[row_index]
	icon.texture = fr.tex
	icon.position = fr.pos

func get_unit_icon(index: int) -> TextureRect:
	if index >= 0 and index < _unit_nodes.size():
		return _unit_nodes[index]
	return null

func get_unit_counter(index: int) -> int:
	if index >= 0 and index < _counters.size():
		return _counters[index]
	return 0

func get_unit_subframe(index: int) -> int:
	if index >= 0 and index < _counters.size():
		return (_counters[index] / TICKS_PER_FRAME) % IDLE_FRAMES_PER_UNIT
	return 0

func set_unit_counter(index: int, counter: int) -> void:
	if index >= 0 and index < _counters.size():
		_counters[index] = counter % TOTAL_CYCLE_TICKS
		_apply_unit_frame(index)

func _add_header(frame: int, pos: Vector2) -> void:
	var header := UiKit.texture_rect(ART + "hiscore/%04d.png" % frame, pos)
	add_child(header)
	_rows.append(header)

func _add_label(font: Font, text: String, pos: Vector2, width: float,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var label := UiKit.create_label(text, pos, Vector2(width, 18), font, Color.WHITE, align)
	add_child(label)
	_rows.append(label)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Game.to_menu()
