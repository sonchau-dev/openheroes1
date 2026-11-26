# src/town/guild_screen.gd
class_name GuildScreen
extends CanvasLayer

## HOMM1 Mage Guild Screen. Layout is a 1:1 recreation of the original
## magewind.bin window definition: the 640x262 stone town viewport contains
## the built Mage Guild tower composite on the left, a 3x3 grid of 9 spell scrolls
## across all 4 levels (levels 1 to 4, bottom-to-top), a purple status banner, and the Exit button.
## The town's lower panel (garrison, visiting hero, resource panel) remains visible below.

signal closed

const BG := UiKit.ART + "stonebak.png"
const MAGEGLD := UiKit.ART + "magegld/"
const TOWNWIND := UiKit.ART + "townwind/"
const SPELLS := UiKit.ART + "spells/"
const SYSTEM := UiKit.ART + "system/"
const TREASURY := UiKit.ART + "treasury/"

const BuySpellbookDialogS := preload("res://src/town/buy_spellbook_dialog.gd")
const SpellInfoDialogS := preload("res://src/ui/spell_info_dialog.gd")

const VIEWPORT_H := 262.0

const ROW_Y := [156, 79, 2]         # Row 0 = Level 1 (bottom), Row 1 = Level 2, Row 2 = Level 3 (top)
const COL_X := [170, 330, 490]      # Columns 0, 1, 2

## 9 scroll slots in magewind.bin (heroes.exe 0xbc6a5): 3 rows of 3.
## Levels wrap across rows: L1 has 3 spells, L2 has 2, L3 has 2, L4 has 2.
const SLOT_MAP: Array[Dictionary] = [
	{"row": 0, "col": 0, "lvl": 0, "idx": 0, "min_level": 1},
	{"row": 0, "col": 1, "lvl": 0, "idx": 1, "min_level": 1},
	{"row": 0, "col": 2, "lvl": 0, "idx": 2, "min_level": 1},
	{"row": 1, "col": 0, "lvl": 1, "idx": 0, "min_level": 2},
	{"row": 1, "col": 1, "lvl": 1, "idx": 1, "min_level": 2},
	{"row": 1, "col": 2, "lvl": 2, "idx": 0, "min_level": 3},
	{"row": 2, "col": 0, "lvl": 2, "idx": 1, "min_level": 3},
	{"row": 2, "col": 1, "lvl": 3, "idx": 0, "min_level": 4},
	{"row": 2, "col": 2, "lvl": 3, "idx": 1, "min_level": 4},
]

const SCROLL_OPEN_SIZE := Vector2(140, 77)
const SCROLL_TIED_SIZE := Vector2(58, 56)
const SCROLL_TIED_OFFSET := Vector2(41, 10)
const SPELL_ICON_BOX_OFFSET := Vector2(52, 10)
const SPELL_ICON_BOX_SIZE := Vector2(40, 40)
const SPELL_NAME_OFFSET := Vector2(12, 50)
const SPELL_NAME_SIZE := Vector2(116, 12)

const BANNER_POS_LEFT := Vector2(10, 239)
const BANNER_POS_RIGHT := Vector2(279, 239)
const BANNER_TEXT_POS := Vector2(10, 240)
const BANNER_TEXT_SIZE := Vector2(538, 16)

const EXIT_BTN_POS := Vector2(550, 236)
const EXIT_BTN_SIZE := Vector2(80, 25)

const MAGEGLD_SHIFT := Vector2(-250, 40)

const GUILD_SPRITE_IDS := {
	1: [0, 1],
	2: [0, 2, 3],
	3: [0, 2, 4, 5],
	4: [0, 2, 4, 6, 7],
}

var _player: PlayerState
var _hero: HeroModel
var _root: Control
var _font_big: FontFile
var _font_small: FontFile
var _spell_spec: Dictionary

var _banner_label: Label = null
var _exit_btn: TextureButton = null
var _scroll_slots: Array = []  # [{ rect: Rect2, spell_id: String, is_open: bool, row: int, col: int }]
var _buy_dialog: CanvasLayer = null
var _spell_dialog: CanvasLayer = null
var _learned_new_spells: bool = false

func open(player: PlayerState, hero: HeroModel) -> void:
	_player = player
	_hero = hero
	_learned_new_spells = false

	if _root == null:
		layer = 200
		_font_big = UiKit.font_big()
		_font_small = UiKit.font_small()
		_spell_spec = SpecLoader.load_spec(SPELLS + "spec.json")
		_root = Control.new()
		_root.set_anchors_preset(Control.PRESET_FULL_RECT)
		_root.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(_root)

	if _hero != null and _hero.has_spellbook:
		_player.town.teach_visiting_hero(_hero)
		_learned_new_spells = true

	_rebuild()

# --- testable API -----------------------------------------------------------

func build_button_enabled() -> bool:
	return _player != null and _player.town != null \
			and _player.town.can_build("mage_guild", _player) == "buildable"

func do_build() -> void:
	if _player != null and _player.town != null and _player.town.build("mage_guild", _player):
		if _hero != null and _hero.has_spellbook:
			_player.town.teach_visiting_hero(_hero)
			_learned_new_spells = true
		_rebuild()

func buy_book_visible() -> bool:
	return _buy_dialog != null or (_hero != null and not _hero.has_spellbook)

func buy_book_button() -> Button:
	if _buy_dialog != null:
		return _buy_dialog.buy_button()
	return null

func do_buy_book() -> void:
	if _player != null and _hero != null:
		if _player.buy_spellbook(_hero):
			_player.town.teach_visiting_hero(_hero)
			_learned_new_spells = true
			if _buy_dialog != null:
				_buy_dialog.close()
				_buy_dialog = null
			_rebuild()

func slot_rect(row: int, col: int) -> Rect2:
	for slot in _scroll_slots:
		if slot.row == row and slot.col == col:
			return slot.rect
	return Rect2()

func slot_is_open(row: int, col: int) -> bool:
	for slot in _scroll_slots:
		if slot.row == row and slot.col == col:
			return slot.is_open
	return false

func slot_spell_id(row: int, col: int) -> String:
	for slot in _scroll_slots:
		if slot.row == row and slot.col == col:
			return slot.spell_id
	return ""

func exit_button_rect() -> Rect2:
	return Rect2(EXIT_BTN_POS, EXIT_BTN_SIZE)

func banner_text() -> String:
	return _banner_label.text if _banner_label != null else ""

func dialog_open() -> bool:
	return _buy_dialog != null or _spell_dialog != null

func open_buy_book_dialog() -> void:
	if _buy_dialog != null:
		return
	_buy_dialog = BuySpellbookDialogS.new()
	add_child(_buy_dialog)
	_buy_dialog.closed.connect(func():
		_buy_dialog = null
		_rebuild()
	)
	_buy_dialog.bought.connect(func():
		_learned_new_spells = true
		_buy_dialog = null
		_rebuild()
	)
	_buy_dialog.open(_player, _hero)

func open_spell_info(spell_id: String) -> void:
	if _spell_dialog != null:
		_spell_dialog.close()
	_spell_dialog = SpellInfoDialogS.new()
	add_child(_spell_dialog)
	_spell_dialog.closed.connect(func():
		_spell_dialog = null
	)
	_spell_dialog.setup(spell_id)

func close() -> void:
	_close()

# --- layout & rendering -----------------------------------------------------

func _rebuild() -> void:
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()
	_scroll_slots.clear()
	_exit_btn = null
	_banner_label = null

	_draw_background()
	_draw_tower()
	_draw_scrolls()
	_draw_banner_and_exit()

func _draw_background() -> void:
	# Top town viewport background (640x262 stone texture)
	UiKit.add_sprite(_root, BG, Vector2.ZERO)

func _draw_tower() -> void:
	var town: TownModel = _player.town if _player != null else null
	var lvl: int = town.mage_guild_level if town != null else 1
	if lvl <= 0:
		return

	var ids: Array = GUILD_SPRITE_IDS.get(lvl, [])
	var spec := SpecLoader.load_spec(MAGEGLD + "spec.json")
	for id in ids:
		if id >= spec.sprites.size():
			continue
		var sp = spec.sprites[id]
		var pos: Vector2 = Vector2(sp.offset.x, sp.offset.y) + MAGEGLD_SHIFT
		UiKit.add_sprite(_root, MAGEGLD + sp.file, pos)

func _draw_scrolls() -> void:
	var town: TownModel = _player.town if _player != null else null
	var guild_level: int = town.mage_guild_level if town != null else 0
	var guild_spells: Array = town.guild_spells if town != null else []

	for slot_info in SLOT_MAP:
		var row_idx: int = int(slot_info.row)
		var col_idx: int = int(slot_info.col)
		var lvl: int = int(slot_info.lvl)
		var spell_idx: int = int(slot_info.idx)
		var min_level: int = int(slot_info.min_level)

		var x: int = COL_X[col_idx]
		var y: int = ROW_Y[row_idx]
		var has_spell := false
		var spell_id := ""

		if guild_level >= min_level and lvl < guild_spells.size():
			var spells_in_lvl: Array = guild_spells[lvl]
			if spell_idx < spells_in_lvl.size():
				spell_id = String(spells_in_lvl[spell_idx])
				has_spell = (spell_id != "")

		if has_spell:
			# Open parchment scroll
			UiKit.add_sprite(_root, TOWNWIND + "0000.png", Vector2(x, y))

			var slot_rect := Rect2(Vector2(x, y), SCROLL_OPEN_SIZE)
			_scroll_slots.append({
				"rect": slot_rect,
				"spell_id": spell_id,
				"is_open": true,
				"row": row_idx,
				"col": col_idx,
			})

			# Spell icon
			var spell := SpellData.get_spell(spell_id)
			var icon_idx := int(spell.get("icon", 0))
			var icon_tex := UiKit.load_texture(SPELLS + "%04d.png" % icon_idx)
			if icon_tex != null:
				var icon_spr := Sprite2D.new()
				icon_spr.texture = icon_tex
				icon_spr.centered = false
				var sp_offset := Vector2.ZERO
				var sp_size := icon_tex.get_size()
				if icon_idx < _spell_spec.get("sprites", []).size():
					var sp_info = _spell_spec["sprites"][icon_idx]
					sp_offset = Vector2(sp_info.offset.x, sp_info.offset.y)
					sp_size = Vector2(sp_info.size.x, sp_info.size.y)
				var icon_box_pos := Vector2(x, y) + SPELL_ICON_BOX_OFFSET
				# Center icon within the 40x40 box
				icon_spr.position = icon_box_pos + Vector2(
					(SPELL_ICON_BOX_SIZE.x - sp_size.x) / 2.0,
					(SPELL_ICON_BOX_SIZE.y - sp_size.y) / 2.0
				)
				_root.add_child(icon_spr)

			# Spell name
			var name_str := String(spell.get("name", spell_id))
			UiKit.add_label(_root, name_str, Vector2(x, y) + SPELL_NAME_OFFSET, SPELL_NAME_SIZE,
					_font_small, Color8(240, 240, 240), HORIZONTAL_ALIGNMENT_CENTER)
		else:
			# Tied / rolled scroll
			var tied_pos := Vector2(x, y) + SCROLL_TIED_OFFSET
			UiKit.add_sprite(_root, TOWNWIND + "0001.png", tied_pos)

			_scroll_slots.append({
				"rect": Rect2(tied_pos, SCROLL_TIED_SIZE),
				"spell_id": "",
				"is_open": false,
				"row": row_idx,
				"col": col_idx,
			})

func _draw_banner_and_exit() -> void:
	# Purple banner strip (two segments 269x19)
	# system/0000 is one 269px half of the native status bar with the gold cap
	# on the right and open seam on the left. Mirror the left half so its gold
	# cap is on the far left and the open seam meets in the center at x=279.
	var ban_left := UiKit.add_sprite(_root, SYSTEM + "0000.png", BANNER_POS_LEFT)
	ban_left.flip_h = true

	var ban_right := UiKit.add_sprite(_root, SYSTEM + "0000.png", BANNER_POS_RIGHT)
	ban_right.flip_h = false

	# Banner status text
	var text_msg := "The above spells are available here."
	if _learned_new_spells or (_hero != null and _hero.has_spellbook):
		text_msg = "The above spells have been added to your book."

	_banner_label = UiKit.add_label(_root, text_msg, BANNER_TEXT_POS, BANNER_TEXT_SIZE, _font_big,
			Color8(240, 240, 240), HORIZONTAL_ALIGNMENT_CENTER)

	# Exit button (treasury 0001 up, 0002 pressed)
	_exit_btn = TextureButton.new()
	_exit_btn.texture_normal = UiKit.load_texture(TREASURY + "0001.png")
	_exit_btn.texture_pressed = UiKit.load_texture(TREASURY + "0002.png")
	_exit_btn.position = EXIT_BTN_POS
	_exit_btn.pressed.connect(_close)
	_root.add_child(_exit_btn)

func _close() -> void:
	closed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if _spell_dialog != null or _buy_dialog != null:
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed:
		var p := (event as InputEventMouseButton).position
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Check if Exit button was clicked
			if Rect2(EXIT_BTN_POS, EXIT_BTN_SIZE).has_point(p):
				return  # let TextureButton handle pressed signal

			# Check if an open scroll was clicked
			for slot in _scroll_slots:
				if slot.is_open and (slot.rect as Rect2).has_point(p):
					open_spell_info(slot.spell_id)
					get_viewport().set_input_as_handled()
					return

			# Swallow clicks in the upper viewport so they don't hit background town
			if p.y < VIEWPORT_H:
				get_viewport().set_input_as_handled()
				return

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Check if right-clicking an open scroll for info
			for slot in _scroll_slots:
				if slot.is_open and (slot.rect as Rect2).has_point(p):
					open_spell_info(slot.spell_id)
					get_viewport().set_input_as_handled()
					return

			# Right-clicking outside closes the screen
			if p.y < VIEWPORT_H:
				_close()
				get_viewport().set_input_as_handled()
				return
