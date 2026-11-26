# src/ui/spellbook_view.gd
class_name SpellbookView
extends CanvasLayer

## HOMM1 spellbook popup: two-page spread built from the extracted BOOK.ICN
## page and ribbon sprites, filtered to the caller's mode ("battle"|"map").
## ESC / right-click closes; clicks outside entries are swallowed.

const ART := UiKit.ART
const BOOK_DIR := ART + "book/"
const SPELL_DIR := ART + "spells/"
const FONT := ART + "smalfont/"

const PER_PAGE := 4       # 2 pages x 2 vertically stacked entries
const ROWS := 2

# Native BOOK.ICN geometry measured from the reference capture. The spellbook
# is intentionally left of screen center; the hanging ribbons balance it.
const PAGE_SIZE := Vector2(164, 194)  # book/spec.json sprite 0
const BOOK_POS := Vector2(146, 145)
const BOOK_SIZE := Vector2(PAGE_SIZE.x * 2.0, PAGE_SIZE.y)
const ENTRY_TOP := 8.0
const ENTRY_H := 65.0
const ICON_FRAME := Vector2(44, 46)   # spells/spec.json common source canvas
const SWORD_TAB_POS := Vector2(336, 312)
const HORSE_TAB_POS := Vector2(364, 298)
const EXIT_TAB_POS := Vector2(416, 317)
const PAGE_TURN_HIT_SIZE := Vector2(36, 36)

const SpellInfoDialogS := preload("res://src/ui/spell_info_dialog.gd")

signal spell_picked(id: String)
signal closed
## Text for the caller's status bar as the mouse moves over the book: the
## battle bar in combat (heroes.exe 0xc4f91), the hero screen's bar in "view"
## mode (0x7e444). The adventure map's book prints nothing (0xcfd90).
signal status_changed(text: String)

## Right-click popups on the book's controls (heroes.exe 0x7e0cc, table at
## 0x7e08c); a spell shows its description instead.
const CONTROL_POPUPS := {
	&"previous": "View previous page",
	&"next": "View next page",
	&"adventure": "View adventure spells",
	&"combat": "View combat spells",
}

var _ids: Array = []
var _page := 0
var _book: Spellbook
var _mode: String = "battle"
var _submode: String = "battle"
var _root: Control
var _font: FontFile
var _spell_spec: Dictionary
var _spell_dialog: CanvasLayer = null
var _last_hover := ""
var _popup: CanvasLayer = null

## Modal chrome (dimmer + root Control) is built here rather than in _ready():
## open() is called synchronously right after add_child() (see battle.gd /
## the brief's test), before this node's _ready() notification is guaranteed
## to have run — mirrors system_menu.gd / kingdom_overview.gd, which build
## everything in open() for the same reason.
func open(book: Spellbook, mode: String = "battle") -> void:
	if _root == null:
		layer = 200
		_font = Homm1Font.load_font(FONT)
		_spell_spec = SpecLoader.load_spec(SPELL_DIR + "spec.json")
		_root = Control.new()
		_root.set_anchors_preset(Control.PRESET_FULL_RECT)
		_root.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(_root)

	_book = book
	_mode = mode
	if mode == "map":
		_submode = "map"
	elif mode == "battle":
		_submode = "battle"
	elif mode == "view":
		# The hero screen's book opens on the adventure spells (heroes.exe
		# 0x7dd59).
		_submode = "map"

	_update_ids()
	_page = 0
	_rebuild()

func _update_ids() -> void:
	if _book == null:
		_ids = []
		return
	if _submode == "battle":
		_ids = _book.battle_spells()
	else:
		_ids = _book.map_spells()

func visible_spell_ids() -> Array:
	return _ids

func page_count() -> int:
	return max(1, ceili(float(_ids.size()) / PER_PAGE))

func current_page() -> int:
	return _page

func current_page_spell_ids() -> Array:
	var start := _page * PER_PAGE
	return _ids.slice(start, mini(start + PER_PAGE, _ids.size()))

func next_page_rect() -> Rect2:
	return Rect2(
			BOOK_POS + Vector2(BOOK_SIZE.x - PAGE_TURN_HIT_SIZE.x, 0),
			PAGE_TURN_HIT_SIZE)

func previous_page_rect() -> Rect2:
	return Rect2(BOOK_POS, PAGE_TURN_HIT_SIZE)

func pick(index: int) -> void:
	var i := _page * PER_PAGE + index
	if i >= 0 and i < _ids.size():
		spell_picked.emit(_ids[i])
		close()

func close() -> void:
	if _spell_dialog != null:
		_spell_dialog.close()
		_spell_dialog = null
	closed.emit()
	queue_free()

func _rebuild() -> void:
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()

	_book_page(BOOK_POS, true)
	_book_page(BOOK_POS + Vector2(PAGE_SIZE.x, 0), false)

	var start := _page * PER_PAGE
	var half := ROWS
	for i in range(start, min(start + PER_PAGE, _ids.size())):
		var slot := i - start
		var col := 0 if slot < half else 1
		var row := slot % half
		var page_pos := BOOK_POS + Vector2(col * PAGE_SIZE.x, 0)
		_build_entry(_ids[i], slot, page_pos, row)

	_build_tabs()

func _book_page(pos: Vector2, flipped: bool) -> void:
	var page := TextureRect.new()
	page.texture = load(BOOK_DIR + "0000.png")
	page.position = pos
	page.size = PAGE_SIZE
	page.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	page.stretch_mode = TextureRect.STRETCH_KEEP
	page.flip_h = flipped
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(page)

func _build_entry(id: String, local_index: int, page_pos: Vector2, row: int) -> void:
	var e := SpellData.get_spell(id)
	if e.is_empty():
		return

	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.position = page_pos + Vector2(8, ENTRY_TOP + row * ENTRY_H)
	btn.size = Vector2(PAGE_SIZE.x - 16, ENTRY_H)
	btn.pressed.connect(_on_entry_pressed.bind(local_index))
	_root.add_child(btn)

	var icon_id := int(e.get("icon", 0))
	var icon_spec: Dictionary = _spell_spec.sprites[icon_id]
	var icon := Sprite2D.new()
	icon.texture = load(SPELL_DIR + "%04d.png" % icon_id)
	icon.centered = false
	var icon_canvas := page_pos + Vector2(
			(PAGE_SIZE.x - ICON_FRAME.x) / 2.0,
			ENTRY_TOP + row * ENTRY_H)
	icon.position = icon_canvas + Vector2(icon_spec.offset)
	_root.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = "%s[%d]" % [String(e.get("name", id)), _book.charges(id)]
	name_lbl.position = page_pos + Vector2(8, ENTRY_TOP + row * ENTRY_H + 44)
	name_lbl.size = Vector2(PAGE_SIZE.x - 16, 18)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_override("font", _font)
	name_lbl.add_theme_font_size_override("font_size", _font.fixed_size)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(name_lbl)

func _on_entry_pressed(local_index: int) -> void:
	var i := _page * PER_PAGE + local_index
	if i >= 0 and i < _ids.size():
		if _mode == "view":
			_open_spell_info(_ids[i])
		else:
			pick(local_index)

func _open_spell_info(spell_id: String, hold := false) -> void:
	if _spell_dialog != null:
		_spell_dialog.close()
	_spell_dialog = SpellInfoDialogS.new()
	add_child(_spell_dialog)
	_spell_dialog.closed.connect(func():
		_spell_dialog = null
	)
	_spell_dialog.setup(spell_id, hold, _mode == "map")

func _build_tabs() -> void:
	# Hanging ribbons: Sword (combat), Horse (adventure), Exit. Combat hides
	# the adventure ribbon and the adventure map hides the combat one
	# (heroes.exe 0x7de2e..0x7de6a); only the hero screen shows both.
	if has_combat_tab():
		var sword_tex: Texture2D = load(BOOK_DIR + "0004.png")
		_tab_sprite(BOOK_DIR + "0004.png", SWORD_TAB_POS)
		var sword_btn := Button.new()
		sword_btn.name = "CombatTab"
		sword_btn.flat = true
		sword_btn.focus_mode = Control.FOCUS_NONE
		sword_btn.position = SWORD_TAB_POS
		sword_btn.size = sword_tex.get_size()
		sword_btn.pressed.connect(_on_sword_tab_pressed)
		_root.add_child(sword_btn)
	if not has_adventure_tab():
		_build_exit_and_paging()
		return
	var horse_tex: Texture2D = load(BOOK_DIR + "0003.png")
	_tab_sprite(BOOK_DIR + "0003.png", HORSE_TAB_POS)
	var horse_btn := Button.new()
	horse_btn.name = "AdventureTab"
	horse_btn.flat = true
	horse_btn.focus_mode = Control.FOCUS_NONE
	horse_btn.position = HORSE_TAB_POS
	horse_btn.size = horse_tex.get_size()
	horse_btn.pressed.connect(_on_horse_tab_pressed)
	_root.add_child(horse_btn)

	_build_exit_and_paging()

func _build_exit_and_paging() -> void:
	var exit_tex: Texture2D = load(BOOK_DIR + "0005.png")
	_tab_sprite(BOOK_DIR + "0005.png", EXIT_TAB_POS)
	var exit_btn := Button.new()
	exit_btn.name = "ExitTab"
	exit_btn.flat = true
	exit_btn.focus_mode = Control.FOCUS_NONE
	exit_btn.position = EXIT_TAB_POS
	exit_btn.size = exit_tex.get_size()
	exit_btn.pressed.connect(close)
	_root.add_child(exit_btn)

	# The page art already contains both visible upper corners. Keep the paging
	# hit targets over those corners without drawing sprites 1/2 on top: those
	# replacement patches produce a doubled, detached corner at fractional
	# viewport scales. Both corners stay live on every spread; past either end
	# a turn does nothing (heroes.exe 0x7e2a1, 0x7e2e9).
	_page_turn_button("PreviousPage", previous_page_rect(), -1)
	_page_turn_button("NextPage", next_page_rect(), 1)

func has_combat_tab() -> bool:
	return _mode != "map"

func has_adventure_tab() -> bool:
	return _mode != "battle"

## The control under `pos`: &"previous", &"next", &"exit", &"combat",
## &"adventure", &"spell", or &"" for anything else.
func item_at(pos: Vector2) -> StringName:
	if previous_page_rect().has_point(pos):
		return &"previous"
	if next_page_rect().has_point(pos):
		return &"next"
	if _tab_rect(EXIT_TAB_POS, "0005").has_point(pos):
		return &"exit"
	if has_combat_tab() and _tab_rect(SWORD_TAB_POS, "0004").has_point(pos):
		return &"combat"
	if has_adventure_tab() and _tab_rect(HORSE_TAB_POS, "0003").has_point(pos):
		return &"adventure"
	if entry_at(pos) >= 0:
		return &"spell"
	return &""

## Index into _ids of the spell entry under `pos`, or -1.
func entry_at(pos: Vector2) -> int:
	var start := _page * PER_PAGE
	for i in range(start, mini(start + PER_PAGE, _ids.size())):
		var slot := i - start
		var col := 0 if slot < ROWS else 1
		var row := slot % ROWS
		var page_pos := BOOK_POS + Vector2(col * PAGE_SIZE.x, 0)
		if Rect2(page_pos + Vector2(8, ENTRY_TOP + row * ENTRY_H),
				Vector2(PAGE_SIZE.x - 16, ENTRY_H)).has_point(pos):
			return i
	return -1

## Status bar text for the mouse at `pos` (heroes.exe tables at data 0x21290).
func hover_text(pos: Vector2) -> String:
	var item := item_at(pos)
	match item:
		&"previous": return "View previous page"
		&"next": return "View next page"
		&"exit": return "Close Spellbook"
	if _mode == "battle":
		return "Select Spell" if item == &"spell" else "View Combat Spells"
	if _mode == "view":
		match item:
			&"adventure": return "View adventure spells"
			&"combat": return "View combat spells"
		return "View Spells"
	return ""

func _tab_rect(pos: Vector2, frame: String) -> Rect2:
	var tex := load(BOOK_DIR + frame + ".png") as Texture2D
	return Rect2(pos, tex.get_size() if tex != null else Vector2.ZERO)

func _on_sword_tab_pressed() -> void:
	if _submode != "battle":
		_submode = "battle"
		_update_ids()
		_page = 0
		_rebuild()

func _on_horse_tab_pressed() -> void:
	if _submode != "map":
		_submode = "map"
		_update_ids()
		_page = 0
		_rebuild()

func _page_turn_button(button_name: String, rect: Rect2, delta: int) -> void:
	var button := Button.new()
	button.name = button_name
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	button.position = rect.position
	button.size = rect.size
	# Entries overlap the curled paper corner by a few pixels. Keep paging
	# explicitly above them so the corner cannot select a spell instead.
	button.z_index = 10
	button.pressed.connect(_flip.bind(delta))
	_root.add_child(button)

func _flip(delta: int) -> void:
	_page = clampi(_page + delta, 0, page_count() - 1)
	_rebuild()

func _tab_sprite(path: String, pos: Vector2) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = load(path)
	spr.centered = false
	spr.position = pos
	_root.add_child(spr)
	return spr

func _input(event: InputEvent) -> void:
	if _spell_dialog != null or _popup != null:
		return

	if event is InputEventMouseMotion:
		var text := hover_text((event as InputEventMouseMotion).position)
		if text != _last_hover:
			_last_hover = text
			status_changed.emit(text)
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
		return
	# spellwin.bin gives the page corners PgUp and PgDn.
	if event is InputEventKey and event.pressed and event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
		_flip(-1 if event.keycode == KEY_PAGEUP else 1)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			# A spell shows its description and a page corner or ribbon
			# names itself, both as hold popups; anywhere else does nothing
			# (heroes.exe 0x7e0cc).
			var item := item_at(mb.position)
			if item == &"spell":
				_open_spell_info(_ids[entry_at(mb.position)], true)
			elif CONTROL_POPUPS.has(item):
				_popup = MapDialogs.info(self, {"text": CONTROL_POPUPS[item], "hold": true, "centered": true})
				_popup.tree_exited.connect(func(): _popup = null)
			get_viewport().set_input_as_handled()
