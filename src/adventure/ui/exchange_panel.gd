class_name ExchangePanel
extends CanvasLayer

## Authentic Hero Meeting / Exchange screen reconstructed from swapwin.bin
## and swapwin.bmp (448x448). Features:
## - Title "%s meets %s" in bigfont.fnt
## - Dual hero portraits (101x93 from port%04d.icn)
## - Primary stats (Attack, Defense, Spell Power, Knowledge) with smalfont labels
## - 5 army slots per hero (32x32 mons32.icn) with Shift-click stack splitting (splitwin.bin)
## - 14 artifact slots per hero (32x32 artfx.icn) with trade restrictions
## - Authentic EXIT button (80x25 from swapbtn.icn)
## - The picked slot is framed the way the DOS original frames it: a 1 px
##   yellow-green rectangle over the slot's gold border (HOMM1 palette 236).

const SWAPWIN_TEX := UiKit.ART + "swapwin.png"
const SWAPBTN := UiKit.ART + "swapbtn/"
const PORT := UiKit.ART + "port%04d/0000.png"
const MONS32 := UiKit.ART + "mons32/%04d.png"

const FRAME_POS := Vector2(96, 16)
const FRAME_SIZE := Vector2(448, 448)

## heroes.exe marks the picked stack with a 1 px frame around the 32x32 slot,
## in the yellow-green of the HOMM1 palette (entry 236, rgb 132,168,4). The
## DOS capture of the open split dialog (campaign recording) shows the source
## stack's slot framed in it while the other slots keep their gold border.
const SEL_FRAME_COLOR := Color8(132, 168, 4)
const SEL_FRAME_SIZE := 34.0

const STAT_NAMES: Array[String] = ["Attack Skill", "Defense Skill", "Spell Power", "Knowledge  "]
const STAT_YS: Array[float] = [48.0, 68.0, 88.0, 108.0]

var _hero_a: HeroModel
var _hero_b: HeroModel

var _slots_a: Array = []  # size ArmyData.MAX_SLOTS: Dictionary or null
var _slots_b: Array = []  # size ArmyData.MAX_SLOTS: Dictionary or null
var _artifacts_a: Array = [] # fourteen canonical IDs or null; book reserves slot 0
var _artifacts_b: Array = []

var _sel_row: int = -1  # 0 = A, 1 = B
var _sel_col: int = -1
var _sel_shift: bool = false
var _artifact_sel_row: int = -1
var _artifact_sel_col: int = -1
var _feedback: String = ""
var _split_dialog: SplitDialog = null

var _font_big: Font
var _font_small: Font

var _content: Control
var _title_label: Label

## Built in _init (not _ready) so open() also works when the panel is added
## under a parent that is not yet in the scene tree (headless tests).
func _init() -> void:
	layer = 150

	_font_big = UiKit.font_big()
	_font_small = UiKit.font_small()

	# Transparent / semi-dim click blocker over full screen
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.4)
	dim.size = Vector2(640, 480)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# Main container control centered at native 448x448 position
	_content = Control.new()
	_content.position = FRAME_POS
	_content.size = FRAME_SIZE
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_content)

func open(hero_a: HeroModel, hero_b: HeroModel) -> void:
	_hero_a = hero_a
	_hero_b = hero_b

	# The exchange window is a modal of its own: the adventure map's hover
	# cursors (horse, sword, the two arrows of a friendly hero) must not show
	# through it, the plain HOMM1 pointer does.
	_set_default_cursor()

	# Convert ArmyData to fixed MAX_SLOTS-element arrays (5)
	_slots_a = _hero_a.army.to_columns()

	_slots_b = _hero_b.army.to_columns()

	_artifacts_a = _artifact_slots(_hero_a)
	_artifacts_b = _artifact_slots(_hero_b)

	_redraw()

func _redraw() -> void:
	for child in _content.get_children():
		child.queue_free()

	# Backdrop swapwin.png (448x448)
	UiKit.add_texture(_content, SWAPWIN_TEX, Vector2.ZERO)

	# Title banner: "%s meets %s" in bigfont.fnt
	_title_label = UiKit.create_label(
		"%s meets %s" % [
			_hero_a.hero_name if _hero_a != null else "Hero 1",
			_hero_b.hero_name if _hero_b != null else "Hero 2"
		],
		Vector2(0, 12),
		Vector2(448, 20),
		_font_big,
		Color8(240, 240, 240),
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_content.add_child(_title_label)

	# Hero Portraits
	if _hero_a != null:
		_draw_portrait(0, _hero_a, Vector2(28, 44))
	if _hero_b != null:
		_draw_portrait(1, _hero_b, Vector2(319, 44))

	# Primary Stats
	for idx in 4:
		var y: float = STAT_YS[idx]
		UiKit.add_label(_content, STAT_NAMES[idx].strip_edges(), Vector2(181, y), Vector2(102, 12), _font_small, Color8(220, 200, 160), HORIZONTAL_ALIGNMENT_CENTER)
		UiKit.add_label(_content, str(_get_stat(_hero_a, idx)) if _hero_a != null else "0", Vector2(141, y), Vector2(32, 12), _font_small, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		UiKit.add_label(_content, str(_get_stat(_hero_b, idx)) if _hero_b != null else "0", Vector2(276, y), Vector2(32, 12), _font_small, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)

	# Army Slots
	_draw_army_slots(0, _slots_a)
	_draw_army_slots(1, _slots_b)

	# Artifact Slots
	_draw_artifact_slots(0, _artifacts_a)
	_draw_artifact_slots(1, _artifacts_b)

	# Feedback message
	if _feedback != "":
		var fb := UiKit.create_label(_feedback, Vector2(148, 360), Vector2(152, 48), _font_small, Color(1.0, 0.6, 0.3), HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)
		fb.autowrap_mode = TextServer.AUTOWRAP_WORD
		_content.add_child(fb)

	# Authentic OK / EXIT button from swapbtn.icn (80x25 at local 184, 413)
	var exit_btn := TextureButton.new()
	exit_btn.texture_normal = UiKit.load_texture(SWAPBTN + "0000.png")
	exit_btn.texture_pressed = UiKit.load_texture(SWAPBTN + "0001.png")
	exit_btn.position = Vector2(184, 413)
	exit_btn.size = Vector2(80, 25)
	exit_btn.pressed.connect(_on_ok_pressed)
	_content.add_child(exit_btn)

func _draw_portrait(row: int, hero: HeroModel, pos: Vector2) -> void:
	var port_tex := UiKit.load_texture(PORT % hero.portrait_idx)
	if port_tex != null:
		var port_rect := TextureRect.new()
		port_rect.texture = port_tex
		port_rect.position = pos
		port_rect.size = Vector2(101, 93)
		port_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		port_rect.stretch_mode = TextureRect.STRETCH_KEEP
		port_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(port_rect)

func _get_stat(hero: HeroModel, idx: int) -> int:
	match idx:
		0: return hero.effective_attack()
		1: return hero.effective_defense()
		2: return hero.effective_spell_power()
		3: return hero.effective_knowledge()
	return 0

static func army_slot_pos(row: int, col_idx: int) -> Vector2:
	var start_x := 24.0 if row == 0 else 252.0
	return Vector2(start_x + float(col_idx) * 35.0, 148.0)

## The plain HOMM1 pointer, fetched through the scene tree. Naming the
## "Game" autoload directly from this script would make the compiler resolve
## the autoload while the class is still loading, which breaks every test
## that names ExchangePanel as a type.
func _set_default_cursor() -> void:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null or not loop.root.has_node("Game"):
		return
	var game := loop.root.get_node("Game")
	if game.has_method("set_default_cursor"):
		game.call("set_default_cursor")

func _draw_army_slots(row: int, slots: Array) -> void:
	for col in ArmyData.MAX_SLOTS:
		var pos := army_slot_pos(row, col)
		var slot = slots[col]

		var btn := TextureButton.new()
		btn.position = pos
		btn.size = Vector2(32, 32)
		# The modifier is read from the press event: a button's `pressed`
		# signal only arrives on release, by which time the player may have
		# let go of Shift, and the split dialog would never open.
		btn.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed \
					and event.button_index == MOUSE_BUTTON_LEFT:
				_on_slot_pressed(row, col, event.shift_pressed or Input.is_key_pressed(KEY_SHIFT))
		)
		_content.add_child(btn)

		if slot != null:
			var idx: int = CreatureCatalog.native_id(String(slot.unit))
			var m_tex := HeroPanel.get_mons32_texture(idx)
			if m_tex != null:
				var m_rect := TextureRect.new()
				m_rect.texture = m_tex
				m_rect.position = pos
				m_rect.size = Vector2(32, 32)
				m_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				m_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
				m_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
				_content.add_child(m_rect)

			UiKit.add_label(_content, str(slot.count), Vector2(pos.x, 181.0), Vector2(32, 12), _font_small, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_TOP, "", 2, Color.BLACK)

		if _sel_row == row and _sel_col == col:
			_draw_selection_frame(pos)

## The frame the DOS original draws around the picked slot: a 1 px
## yellow-green rectangle around the 32x32 slot, over its gold border.
func _draw_selection_frame(pos: Vector2) -> void:
	var p := pos - Vector2.ONE
	_frame_line(Rect2(p, Vector2(SEL_FRAME_SIZE, 1)))
	_frame_line(Rect2(p + Vector2(0, SEL_FRAME_SIZE - 1), Vector2(SEL_FRAME_SIZE, 1)))
	_frame_line(Rect2(p, Vector2(1, SEL_FRAME_SIZE)))
	_frame_line(Rect2(p + Vector2(SEL_FRAME_SIZE - 1, 0), Vector2(1, SEL_FRAME_SIZE)))

func _frame_line(r: Rect2) -> void:
	var line := ColorRect.new()
	line.color = SEL_FRAME_COLOR
	line.position = r.position
	line.size = r.size
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(line)

static func artifact_slot_pos(row: int, slot_idx: int) -> Vector2:
	var base_x := 76.0 if row == 0 else 305.0
	var col := 0 if slot_idx < 7 else 1
	var row_in_col := slot_idx if slot_idx < 7 else (slot_idx - 7)
	var sx := base_x + float(col) * 35.0
	var sy := 194.0 + float(row_in_col) * 35.0
	return Vector2(sx, sy)

func _draw_artifact_slots(row: int, slots: Array) -> void:
	for i in 14:
		var pos := artifact_slot_pos(row, i)
		var item = slots[i]

		var btn := Button.new()
		btn.flat = true
		btn.position = pos
		btn.size = Vector2(32, 32)
		btn.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed \
					and event.button_index == MOUSE_BUTTON_LEFT:
				_on_artifact_pressed(row, i)
		)
		_content.add_child(btn)

		if item != null:
			var icon := TextureRect.new()
			icon.texture = UiKit.load_texture(ArtifactCatalog.shared().artifact_small_icon_path(String(item)))
			icon.position = pos
			icon.size = Vector2(32, 32)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_content.add_child(icon)

		if _artifact_sel_row == row and _artifact_sel_col == i:
			_draw_selection_frame(pos)

func _on_slot_pressed(row: int, col: int, shift_pressed: bool = false) -> void:
	if _split_dialog != null:
		return
	_feedback = ""
	if _sel_row < 0:
		var slots = _slots_a if row == 0 else _slots_b
		if slots[col] != null:
			_sel_row = row
			_sel_col = col
			_sel_shift = shift_pressed or Input.is_key_pressed(KEY_SHIFT)
			_redraw()
	elif _sel_row == row and _sel_col == col:
		_sel_row = -1
		_sel_col = -1
		_sel_shift = false
		_redraw()
	else:
		var is_shift: bool = shift_pressed or _sel_shift or Input.is_key_pressed(KEY_SHIFT)
		_sel_shift = false
		var src_slots := _slots_a if _sel_row == 0 else _slots_b
		var dst_slots := _slots_a if row == 0 else _slots_b
		var src_val = src_slots[_sel_col]
		var dst_val = dst_slots[col]

		if is_shift and _sel_row != row and src_val != null and int(src_val.get("count", 0)) > 1:
			var src_unit := String(src_val["unit"])
			var target_col := -1
			for i in dst_slots.size():
				if dst_slots[i] != null and String(dst_slots[i]["unit"]) == src_unit:
					target_col = i
					break
			if target_col >= 0 or dst_val == null:
				var other_units := 0
				for i in src_slots.size():
					if i != _sel_col and src_slots[i] != null:
						other_units += int(src_slots[i]["count"])
				var src_count := int(src_val["count"])
				var max_move := src_count if other_units > 0 else (src_count - 1)
				if max_move >= 1:
					var hero_from := _hero_a if _sel_row == 0 else _hero_b
					var hero_to := _hero_b if _sel_row == 0 else _hero_a
					var chosen_dst := target_col if target_col >= 0 else col
					_open_split_dialog(src_unit, hero_from.hero_name, hero_to.hero_name, max_move, _sel_row, _sel_col, row, chosen_dst)
					return
				else:
					# heroes.exe's swapwin has no text for this; it just refuses.
					_sel_row = -1
					_sel_col = -1
					_redraw()
					return

		# Attempt exchange / move
		if apply_move(src_slots, _sel_col, dst_slots, col):
			_sel_row = -1
			_sel_col = -1
			_redraw()
		else:
			# A hero can't give away his last troop; refused without a word.
			_sel_row = -1
			_sel_col = -1
			_redraw()

func _open_split_dialog(unit: String, from_name: String, to_name: String, max_move: int,
		s_row: int, s_col: int, d_row: int, d_col: int) -> void:
	if _split_dialog != null:
		return
	var dlg := SplitDialog.new()
	add_child(dlg)
	_split_dialog = dlg
	dlg.open(unit, from_name, to_name, 1, max_move)
	dlg.confirmed.connect(func(qty: int):
		var src_slots := _slots_a if s_row == 0 else _slots_b
		var dst_slots := _slots_a if d_row == 0 else _slots_b
		apply_split(src_slots, s_col, dst_slots, d_col, qty)
		_sel_row = -1
		_sel_col = -1
		_redraw()
	)
	dlg.closed.connect(func():
		_split_dialog = null
		_sel_row = -1
		_sel_col = -1
		_redraw()
	)

## heroes.exe's message box for a Magic Book or Fizbin slot (data 0x24e2).
const UNTRADABLE := "This item can't be traded."

func _on_artifact_pressed(row: int, col: int) -> void:
	_feedback = ""
	var slots := _artifacts_a if row == 0 else _artifacts_b
	# Clicking a Magic Book or Fizbin refuses at once (heroes.exe 0xaa6ac).
	if slots[col] != null and not ArtifactCatalog.shared().is_transferable(String(slots[col])):
		MapDialogs.info(self, {"lines": [UNTRADABLE], "centered": true})
		return
	if _artifact_sel_row < 0:
		if slots[col] != null:
			_artifact_sel_row = row
			_artifact_sel_col = col
			_redraw()
		return
	if _artifact_sel_row == row and _artifact_sel_col == col:
		# Clicking the picked artifact again shows its info (0xaa79c).
		MapDialogs.artifact_info(self, String(slots[col]))
		return
	var source := _artifacts_a if _artifact_sel_row == 0 else _artifacts_b
	var error := apply_artifact_move(source, _artifact_sel_col, slots, col)
	if error == "":
		_artifact_sel_row = -1
		_artifact_sel_col = -1
	else:
		_feedback = error
	_redraw()

static func _artifact_slots(hero: HeroModel) -> Array:
	var slots: Array = []
	slots.resize(14)
	slots.fill(null)
	if hero.has_spellbook:
		slots[0] = "spell_book"
		for i in mini(hero.artifacts.size(), hero.artifact_capacity()):
			slots[i + 1] = ArtifactCatalog.shared().normalize(String(hero.artifacts[i]))
	else:
		for i in mini(hero.artifacts.size(), hero.artifact_capacity()):
			slots[i] = ArtifactCatalog.shared().normalize(String(hero.artifacts[i]))
	return slots

## Empty string means success; otherwise the returned text is safe to display.
static func apply_artifact_move(source: Array, source_index: int,
		destination: Array, destination_index: int) -> String:
	if source_index < 0 or source_index >= source.size() \
			or destination_index < 0 or destination_index >= destination.size():
		return "Invalid artifact slot."
	if source[source_index] == null:
		return "No artifact selected."
	var source_id := String(source[source_index])
	if not ArtifactCatalog.shared().is_transferable(source_id):
		return UNTRADABLE
	var destination_id := String(destination[destination_index]) if destination[destination_index] != null else ""
	if destination_id != "" and not ArtifactCatalog.shared().is_transferable(destination_id):
		return UNTRADABLE
	if destination_id == "":
		destination[destination_index] = source_id
		source[source_index] = null
	else:
		destination[destination_index] = source_id
		source[source_index] = destination_id
	return ""

static func apply_move(a_slots: Array, ai: int, b_slots: Array, bi: int) -> bool:
	if ai < 0 or ai >= a_slots.size() or bi < 0 or bi >= b_slots.size():
		return false
	var src_val = a_slots[ai]
	if src_val == null:
		return false
	# heroes.exe 0xb8b90/0xba614: if the other army already holds this creature,
	# any slot clicked there combines into that stack.
	if not is_same(a_slots, b_slots):
		for i in b_slots.size():
			if b_slots[i] != null and b_slots[i]["unit"] == src_val["unit"]:
				bi = i
				break

	var dst_val = b_slots[bi]

	# Simulate move/merge
	var a_temp := a_slots.duplicate()
	var b_temp := b_slots.duplicate()

	if dst_val == null:
		# Move
		b_temp[bi] = src_val
		a_temp[ai] = null
	elif dst_val["unit"] == src_val["unit"]:
		# Merge
		b_temp[bi] = {"unit": dst_val["unit"], "count": dst_val["count"] + src_val["count"]}
		a_temp[ai] = null
	else:
		# Swap
		b_temp[bi] = src_val
		a_temp[ai] = dst_val

	# Check if either simulated army is empty
	var a_empty := true
	for s in a_temp:
		if s != null and int(s["count"]) > 0:
			a_empty = false
			break
	var b_empty := true
	for s in b_temp:
		if s != null and int(s["count"]) > 0:
			b_empty = false
			break

	if not is_same(a_slots, b_slots) and (a_empty or b_empty):
		return false # Blocked! One army would end up empty.

	# Commit the simulated change
	if dst_val == null:
		b_slots[bi] = src_val
		a_slots[ai] = null
	elif dst_val["unit"] == src_val["unit"]:
		b_slots[bi] = {"unit": dst_val["unit"], "count": dst_val["count"] + src_val["count"]}
		a_slots[ai] = null
	else:
		a_slots[ai] = dst_val
		b_slots[bi] = src_val

	return true

static func apply_split(a_slots: Array, ai: int, b_slots: Array, bi: int, count: int) -> bool:
	if a_slots == b_slots:
		return false
	if ai < 0 or ai >= a_slots.size() or bi < 0 or bi >= b_slots.size():
		return false
	var src_val = a_slots[ai]
	if src_val == null or count <= 0:
		return false
	var src_count := int(src_val.get("count", 0))
	if count > src_count:
		return false

	var remaining_in_source := 0
	for i in a_slots.size():
		var s = a_slots[i]
		if s != null:
			if i == ai:
				remaining_in_source += int(s.get("count", 0)) - count
			else:
				remaining_in_source += int(s.get("count", 0))
	if remaining_in_source <= 0:
		return false

	var src_unit := String(src_val.get("unit", ""))
	var target_col := -1
	for i in b_slots.size():
		if b_slots[i] != null and String(b_slots[i].get("unit", "")) == src_unit:
			target_col = i
			break

	if target_col < 0:
		if b_slots[bi] != null:
			return false
		target_col = bi

	# Perform split transfer
	if b_slots[target_col] == null:
		b_slots[target_col] = {"unit": src_unit, "count": count}
	else:
		b_slots[target_col] = {
			"unit": src_unit,
			"count": int(b_slots[target_col].get("count", 0)) + count
		}

	if count == src_count:
		a_slots[ai] = null
	else:
		a_slots[ai] = {"unit": src_unit, "count": src_count - count}

	return true

func _on_ok_pressed() -> void:
	if _split_dialog != null:
		return
	# Sync back to ArmyData
	if _hero_a != null and _hero_a.army != null:
		_hero_a.army.set_columns(_slots_a)
	if _hero_b != null and _hero_b.army != null:
		_hero_b.army.set_columns(_slots_b)

	if _hero_a != null:
		_hero_a.artifacts = _artifacts_a.filter(func(id): return id != null and String(id) != "spell_book")
	if _hero_b != null:
		_hero_b.artifacts = _artifacts_b.filter(func(id): return id != null and String(id) != "spell_book")

	queue_free()

## Right-clicking an artifact shows its info as a hold popup (heroes.exe
## 0xaa6f9, 0xaa87e). Handled here because the slot buttons stop GUI input.
func _input(event: InputEvent) -> void:
	if _split_dialog != null or not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	for row in 2:
		var slots := _artifacts_a if row == 0 else _artifacts_b
		for i in slots.size():
			if slots[i] != null and artifact_slot_rect(row, i).has_point(mb.position):
				MapDialogs.artifact_info(self, String(slots[i]), true)
				get_viewport().set_input_as_handled()
				return

func _unhandled_input(event: InputEvent) -> void:
	if _split_dialog != null:
		return
	if event is InputEventKey and event.pressed:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ESCAPE or key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER or key_event.keycode == KEY_SPACE:
			_on_ok_pressed()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and not dialog_rect().has_point(mb.position):
			_on_ok_pressed()
			get_viewport().set_input_as_handled()

func dialog_rect() -> Rect2:
	return Rect2(FRAME_POS, FRAME_SIZE)

func portrait_rect(row: int) -> Rect2:
	return Rect2(FRAME_POS + Vector2(28.0 if row == 0 else 319.0, 44.0), Vector2(101, 93))

func army_slot_rect(row: int, col: int) -> Rect2:
	return Rect2(FRAME_POS + army_slot_pos(row, col), Vector2(32, 32))

func artifact_slot_rect(row: int, slot_idx: int) -> Rect2:
	return Rect2(FRAME_POS + artifact_slot_pos(row, slot_idx), Vector2(32, 32))

func exit_button_rect() -> Rect2:
	return Rect2(FRAME_POS + Vector2(184, 413), Vector2(80, 25))

func title_text() -> String:
	return _title_label.text if _title_label != null else ""
