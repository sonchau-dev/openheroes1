# src/town/build_screen.gd
class_name BuildScreen
extends CanvasLayer

## HOMM1 Castle Options screen ("Town Improvements/Recruit Hero"). Layout is a
## 1:1 recreation of the original caslwind.bin window definition: the 262px
## stone town viewport contains a 4x3 column-major grid of building cells
## (picture + name plate + status icon) and its own status bar + EXIT. The
## town's army/resource panel remains visible below. Cell click opens the buy dialog
## (open_cell); the 12th cell delegates hero hiring back to the town screen.

const BG := UiKit.ART + "stonebak.png"
const BUILDING := UiKit.ART + "building/"     # 0 name plate 137x14, 1..34 pictures 137x61
const TOWNWIND := UiKit.ART + "townwind/"     # 11 check, 12 X, 13 coins-with-red-slash (can't afford)
const SYSTEM := UiKit.ART + "system/"         # 9/10 OKAY, 11/12 CANCEL (96x25)
const EXIT_BTN := UiKit.ART + "swapbtn/"      # 0 EXIT up, 1 pressed (80x25)
const EXIT_POS := Vector2(550, 236)
const RES := UiKit.ART + "resource/"          # 0 wood 1 mercury 2 ore 3 sulfur 4 crystal 5 gems 6 gold

const BUYBUILD := UiKit.ART + "buybuild/"     # 0 top-half 143x77, 1 mid 140x45, 2 bottom 141x48
const DLG_W := 286.0
const DLG_X := (640.0 - DLG_W) / 2.0     # 177
## buybuil3..7.bin: top 78, then 3..7 middle rows of 45, then the bottom
## piece; the window is 280 + 45 per row past three tall.
const DLG_FIRST_MID_Y := 78
const DLG_ROW_H := 45
## heroes.exe 0xbb447 wraps the description at 238 px to choose the window.
const DLG_TEXT_W := 238.0
const DLG_TEXT_Y := 152.0   # DOS captures: the text starts 8 px above where it used to

var _dlg_rows := 5
## Every height hangs from the same top: the gold ball sits at y 18 for five-
## and six-row windows alike (campaign 1 recording, 2026-10-12).
const DLG_Y := 17.0
var DLG_BOTTOM_Y := 303

const CELL_X := [10, 171, 332, 493]
const CELL_Y := [0, 79, 158]
const CELL_W := 137
const PIC_H := 61
const PLATE_H := 14
const STATUS_OFF := Vector2(128, 42)    # status icon, cell-relative
## "buildable" gets no icon (absence = ready to build); "no_resources" shows the
## coins-with-red-slash (can't afford); every other blocker shows the X.
const STATUS_FRAME := {"built": 11, "no_resources": 13}   # anything else -> 12 (X)

signal closed
signal recruit_hero_requested
signal building_built(id: String)
signal recruit_hero_viewed       # right click on the Recruit Hero cell
signal recruit_hero_view_ended   # ...and the button was let go

var _player: PlayerState
var _hero: HeroModel
var _root: Control
var _font_big: FontFile
var _font_small: FontFile
var _cells: Dictionary = {}   # id -> Rect2 (includes "recruit_hero")
var _status_label: Label

var _dlg: Control = null
var _dlg_id := ""
var _dialog_only := false
var _view_hero := false   # right-click Recruit Hero window is up
var _view_only := false   # right-click window: no buttons, gone on release

func open(player: PlayerState, hero: HeroModel) -> void:
	_player = player
	_hero = hero
	if _root == null:
		layer = 200
		_font_big = UiKit.font_big()
		_font_small = UiKit.font_small()
		_root = Control.new()
		_root.set_anchors_preset(Control.PRESET_FULL_RECT)
		_root.mouse_filter = Control.MOUSE_FILTER_STOP   # full-screen: swallow town clicks
		add_child(_root)
	_rebuild()

func cell_status(id: String) -> String:
	return _player.town.can_build(id, _player)

func cell_rect(id: String) -> Rect2:
	return _cells.get(id, Rect2())

## Status-bar text, worded as heroes.exe words it (strings 0x10e9ec..0x10eb22).
func hover_text(id: String) -> String:
	if id == "recruit_hero":
		# heroes.exe 0xcfaae checks in this order.
		if _player.town == null or _player.town.gold < HeroPool.COST:
			return "Cannot afford a Hero."
		if _player.heroes.size() >= 8:
			return "Cannot recruit - you already have %d Heroes." % _player.heroes.size()
		if _hero != null:
			return "Cannot recruit - you already have a Hero in this town."
		return "Recruit a new Hero"
	var name := String(BuildingCatalog.entry(id, _player.town.faction).get("name", id))
	var status := cell_status(id)
	# heroes.exe 0xcf7eb tests "allowed" and "affordable" before the guild's
	# own text, so a top-level guild reads "Cannot build Mage Guild" and an
	# unaffordable level "Cannot afford Mage Guild".
	if id == "mage_guild" and _player.town.mage_guild_level >= 1:
		if _player.town.mage_guild_level >= TownModel.GUILD_COSTS.size():
			return "Cannot build %s" % name
		if status == "no_resources":
			return "Cannot afford %s" % name
		if status == "buildable":
			return "Add another level to Mage Guild"
		return "Cannot build %s" % name
	match status:
		"built":
			return "%s is already built" % name
		"buildable":
			return "Build %s" % name
		"no_resources":
			return "Cannot afford %s" % name
	return "Cannot build %s" % name

func _exit_rect() -> Rect2:
	return Rect2(EXIT_POS, UiKit.load_texture(EXIT_BTN + "0000.png").get_size())

func current_status_text() -> String:
	return _status_label.text if _status_label != null else ""

func dialog_open() -> bool:
	return _dlg != null

## Buy dialog without the grid (tent -> "build castle?" offer).
func open_dialog_only(player: PlayerState, id: String) -> void:
	_player = player
	_hero = null
	_dialog_only = true
	if _root == null:
		layer = 200
		_font_big = UiKit.font_big()
		_font_small = UiKit.font_small()
		_root = Control.new()
		_root.set_anchors_preset(Control.PRESET_FULL_RECT)
		_root.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(_root)
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.5)
		dim.size = Vector2(640, 480)
		_root.add_child(dim)
	_open_dialog(id)

func dialog_okay() -> void:
	if _dlg == null:
		return
	if _player.town.can_build(_dlg_id, _player) == "buildable":
		var built_id := _dlg_id
		if not _player.town.build(built_id, _player):
			return
		# The original closes both the confirmation dialog and Castle Options,
		# then reveals the new structure on the town scene.
		_dlg.queue_free()
		_dlg = null
		_dlg_id = ""
		building_built.emit(built_id)
		_close()
	# not buildable: OKAY isn't shown, programmatic call is inert

func dialog_cancel() -> void:
	if _dlg != null:
		_dlg.queue_free()
		_dlg = null
		_dlg_id = ""
		_view_only = false
		if _dialog_only:
			_close()

func open_cell(id: String) -> void:
	if _dlg != null:
		return
	if id == "recruit_hero":
		# A refused click does nothing (0xcfc85); the hover text says why.
		if _status_label != null:
			_status_label.text = hover_text(id)
		if hover_text(id) == "Recruit a new Hero":
			recruit_hero_requested.emit()
		return
	# A built or not-allowed cell ignores a left click (heroes.exe 0xcfbee);
	# only a cell you may build, affordable or not, opens the window.
	if not cell_status(id) in ["buildable", "no_resources"]:
		return
	_open_dialog(id)

## Right-click on any building cell, built ones too: the same window with no
## buttons, closed when the button is let go (heroes.exe 0xcfc23, 0xbbad5).
func view_cell(id: String) -> void:
	if _dlg != null or not _cells.has(id):
		return
	if id == "recruit_hero":
		_view_hero = true
		recruit_hero_viewed.emit()
		return
	_open_dialog(id, true)

# --- layout ----------------------------------------------------------------

func _rebuild() -> void:
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()
	_cells.clear()

	UiKit.add_sprite(_root, BG, Vector2.ZERO)

	var ids: Array = BuildingCatalog.grid_order(_player.town.faction)
	ids.append("recruit_hero")
	for i in ids.size():
		var id: String = ids[i]
		var pos := Vector2(CELL_X[i / 3], CELL_Y[i % 3])
		_cells[id] = Rect2(pos, Vector2(CELL_W, PIC_H + PLATE_H))
		_draw_cell(id, pos)

	# Castle Options occupies the town viewport only. Its bottom bar and EXIT sit
	# directly above the unchanged army/resource panel, as in the DOS screen.
	var bar := NinePatchRect.new()
	bar.texture = UiKit.load_texture(BUILDING + "0000.png")
	bar.position = Vector2(10, 236)
	bar.size = Vector2(540, 20)
	bar.patch_margin_left = 5
	bar.patch_margin_top = 3
	bar.patch_margin_right = 5
	bar.patch_margin_bottom = 3
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bar)
	# caslwind.bin's bar text until the mouse first moves (data 0xae7d).
	_status_label = UiKit.add_label(_root, "Castle Options:  Town Improvements/Recruit Hero",
			Vector2(10, 241), Vector2(538, 16), _font_big, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)

	var exit_btn := TextureButton.new()
	exit_btn.texture_normal = UiKit.load_texture(EXIT_BTN + "0000.png")
	exit_btn.texture_pressed = UiKit.load_texture(EXIT_BTN + "0001.png")
	exit_btn.size = exit_btn.texture_normal.get_size()
	exit_btn.position = EXIT_POS
	exit_btn.pressed.connect(_close)
	_root.add_child(exit_btn)

func _draw_cell(id: String, pos: Vector2) -> void:
	var frame := 6 if id == "recruit_hero" \
			else int(BuildingCatalog.entry(id, _player.town.faction).get("frame", 0))
	var name := "Recruit Hero" if id == "recruit_hero" \
			else String(BuildingCatalog.entry(id, _player.town.faction).get("name", id))
	UiKit.add_sprite(_root, BUILDING + "%04d.png" % frame, pos)
	UiKit.add_sprite(_root, BUILDING + "0000.png", pos + Vector2(0, PIC_H))
	UiKit.add_label(_root, name, pos + Vector2(0, PIC_H + 2), Vector2(CELL_W, 12), _font_small,
			Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, "", 2, Color.BLACK)
	if id == "recruit_hero":
		# heroes.exe 0xbc3c2: coins when gold is short, else X for eight heroes
		# or a hero already in town.
		var icon := -1
		if _player.town == null or _player.town.gold < HeroPool.COST:
			icon = 13
		elif _player.heroes.size() >= 8 or _hero != null:
			icon = 12
		if icon >= 0:
			UiKit.add_sprite(_root, TOWNWIND + "%04d.png" % icon, pos + STATUS_OFF)
	else:
		var status := cell_status(id)
		if status != "buildable":
			var icon: int = STATUS_FRAME.get(status, 12)
			UiKit.add_sprite(_root, TOWNWIND + "%04d.png" % icon, pos + STATUS_OFF)

# --- buy dialog ----------------------------------------------------------------

func _open_dialog(id: String, view_only := false) -> void:
	if cell_status(id) == "built" and not view_only:
		return
	_view_only = view_only
	_dlg_id = id
	_dlg = Control.new()
	_dlg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dlg.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_dlg)

	var e := BuildingCatalog.entry(id, _player.town.faction)
	var text := _dlg_text(id)
	_size_dialog(text, _player.town.build_cost(id))

	# frame: mirrored halves — right piece at local x=143, left piece flipped
	# at x = 143 - w (pieces are trim-cropped to 143/140/141 px).
	_dlg_piece(0, 0)
	_dlg_fill_top_seam()
	for row in _dlg_rows:
		_dlg_piece(1, DLG_FIRST_MID_Y + row * DLG_ROW_H)
	_dlg_piece(2, DLG_BOTTOM_Y)

	var title := _dlg_label("Build improvement:", Vector2(23, 53), _font_big)
	title.size = Vector2(240, 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var frame := int(e.get("frame", 0))
	_dlg_sprite(BUILDING + "%04d.png" % frame, Vector2(73, 74))
	_dlg_sprite(BUILDING + "0000.png", Vector2(73, 135))
	var name := String(e.get("name", id))
	if id == "mage_guild":
		if _player.town.mage_guild_level < TownModel.GUILD_COSTS.size():
			name = "Mage Guild, Level %d" % (_player.town.mage_guild_level + 1)
		else:
			name = "Mage Guild, Level %d" % _player.town.mage_guild_level
	var nlbl := _dlg_wrapped_label(name, Vector2(73, 134), Vector2(137, 12), _font_small)
	nlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var desc := _dlg_wrapped_label(text,
			Vector2((DLG_W - DLG_TEXT_W) / 2.0, DLG_TEXT_Y),
			Vector2(DLG_TEXT_W, DLG_BOTTOM_Y - COST_ROW_BOTTOM - DLG_TEXT_Y - _dlg_extra_cost_h(id)), _font_big)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_dlg_cost_row(_player.town.build_cost(id), DLG_BOTTOM_Y - COST_ROW_BOTTOM)

	if view_only:
		return
	# An unaffordable build erases OKAY and leaves CANCEL where it always is
	# (heroes.exe 0xbbb9c sets OKAY's erase flag and clears its enabled flag).
	if _player.town.can_build(id, _player) == "buildable":
		_dlg_button(9, 10, Vector2(23, DLG_BOTTOM_Y), dialog_okay)      # OKAY
	_dlg_button(11, 12, Vector2(165, DLG_BOTTOM_Y), dialog_cancel)      # CANCEL

## The description and its prerequisites as heroes.exe builds them
## (0xbb33f): "\n\nRequires:", then "\n" + each missing-or-not prerequisite,
## then a closing "\n ".
func _dlg_text(id: String) -> String:
	var e := BuildingCatalog.entry(id, _player.town.faction)
	var text := String(e.get("desc", ""))
	var prereqs: Array = e.get("prereq", [])
	if not prereqs.is_empty():
		text += "\n\nRequires:"
		for pre: String in prereqs:
			text += "\n" + String(BuildingCatalog.entry(pre, _player.town.faction).get("name", pre))
	return text + "\n "

## Pick the buybuil%d.bin height the way heroes.exe does (0xbb447): 151 px
## above the text, 16 per wrapped line, 44 for one row of costs or 88 for
## two, 39 for the buttons, then (height - 53) / 45 rows, kept to 3..7.
func _size_dialog(text: String, cost: Dictionary) -> void:
	var para := TextParagraph.new()
	para.width = DLG_TEXT_W + _wrap_slack(_font_big)
	para.add_string(text, _font_big, _font_big.fixed_size)
	var kinds := 0
	for k: String in cost:
		if int(cost[k]) > 0:
			kinds += 1
	var height := 151 + 16 * para.get_line_count() + (44 if kinds <= 4 else 88) + 39
	_dlg_rows = clampi((height - 53) / DLG_ROW_H, 3, 7)
	DLG_BOTTOM_Y = DLG_FIRST_MID_Y + _dlg_rows * DLG_ROW_H

func _dlg_extra_cost_h(id: String) -> float:
	var kinds := 0
	for k: String in _player.town.build_cost(id):
		if int(_player.town.build_cost(id)[k]) > 0:
			kinds += 1
	return COST_ROW_H if kinds > 4 else 0.0

## One mirrored frame row: right half normal, left half flip_h.
func _dlg_piece(frame: int, y: float) -> void:
	var tex := UiKit.load_texture(BUYBUILD + "%04d.png" % frame)
	var right := Sprite2D.new()
	right.texture = tex
	right.centered = false
	right.position = Vector2(DLG_X + 143, DLG_Y + y)
	_dlg.add_child(right)
	var left := Sprite2D.new()
	left.texture = tex
	left.centered = false
	left.flip_h = true
	left.position = Vector2(DLG_X + 143 - tex.get_width(), DLG_Y + y)
	_dlg.add_child(left)

func _dlg_fill_top_seam() -> void:
	var tex := UiKit.load_texture(BUYBUILD + "0000.png")
	if tex == null:
		return
	var final_row := AtlasTexture.new()
	final_row.atlas = tex
	final_row.region = Rect2(0, tex.get_height() - 1, tex.get_width(), 1)
	var right := Sprite2D.new()
	right.texture = final_row
	right.centered = false
	right.position = Vector2(DLG_X + 143, DLG_Y + 77)
	_dlg.add_child(right)
	var left := Sprite2D.new()
	left.texture = final_row
	left.centered = false
	left.flip_h = true
	left.position = Vector2(DLG_X + 143 - tex.get_width(), DLG_Y + 77)
	_dlg.add_child(left)

func _dlg_sprite(path: String, local: Vector2) -> void:
	UiKit.add_sprite(_dlg, path, Vector2(DLG_X, DLG_Y) + local)

func _dlg_label(text: String, local: Vector2, font: FontFile) -> Label:
	return UiKit.add_label(_dlg, text, Vector2(DLG_X, DLG_Y) + local, Vector2.ZERO, font, Color.WHITE,
			HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP, "", 2, Color.BLACK)

## Width of the space a wrapped line ends with, which the engine's wrap counts.
func _wrap_slack(font: FontFile) -> float:
	return font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, font.fixed_size).x

## Pin wrapped text to a fixed box. A directly sized Label can expand back to
## its font-derived minimum width after layout, which lets long lines cross the
## dialog pillars even when autowrap is enabled.
func _dlg_wrapped_label(text: String, local: Vector2, size: Vector2,
		font: FontFile) -> Label:
	# Label wrap counts the space that ends a line, so a line of exactly 237 of
	# 238 px ("heroes to learn and replenish") breaks early. heroes.exe wraps on
	# the text alone: widen the box by one space, keeping the text centered.
	var pad := _wrap_slack(font)
	var box := Control.new()
	box.position = Vector2(DLG_X, DLG_Y) + local - Vector2(floorf(pad / 2.0), 0.0)
	box.size = size + Vector2(pad, 0.0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dlg.add_child(box)

	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 2)
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font.fixed_size)
	box.add_child(l)
	l.text = text
	return l

## Icons + amounts, centered row. resource/ order: wood mercury ore sulfur crystal gems gold.
const RES_FRAME := {"wood": 0, "mercury": 1, "ore": 2, "sulfur": 3, "crystal": 4, "gems": 5, "gold": 6}

const COST_ROW_H := 44.0
## Distance from the dialog's button row up to the top of the last cost row
## (DOS captures: the amounts sit 38 px above OKAY).
const COST_ROW_BOTTOM := 77.0
## Width the icons of one row share, measured off the DOS buy dialog: the gaps
## between icons and at both ends are all equal, (width - icons) / (count + 1).
const COST_ROW_SPAN := 260.0
## The DOS rows sit 2 px left of the dialog's geometric center in all three captures.
const COST_ROW_SHIFT := 2.0

## Up to four kinds fit one row; more wrap to two (three above, the rest below),
## the last row ending at y.
func _dlg_cost_row(cost: Dictionary, y: float) -> void:
	var keys: Array = []
	for k: String in ["wood", "mercury", "ore", "sulfur", "crystal", "gems", "gold"]:
		if int(cost.get(k, 0)) > 0:
			keys.append(k)
	if keys.size() <= 4:
		_dlg_cost_line(cost, keys, y)
		return
	var first := keys.size() / 2
	_dlg_cost_line(cost, keys.slice(0, first), y - COST_ROW_H)
	_dlg_cost_line(cost, keys.slice(first), y)

## Icons sit on a common baseline (offset + height = 32 for all but gold) and
## the amount is centered under each icon's box, as in the DOS dialog.
func _dlg_cost_line(cost: Dictionary, keys: Array, y: float) -> void:
	var boxes: Array[float] = []
	var total := 0.0
	for k: String in keys:
		var spr := SpecLoader.sprite(RES, int(RES_FRAME[k]))
		var box := float(spr.get("offset", Vector2i.ZERO).x + spr.get("size", Vector2i(39, 0)).x)
		boxes.append(box)
		total += box
	var gap := (COST_ROW_SPAN - total) / (keys.size() + 1)
	var x := (DLG_W - COST_ROW_SPAN) / 2.0 - COST_ROW_SHIFT + gap
	for i in keys.size():
		var k: String = keys[i]
		var spr := SpecLoader.sprite(RES, int(RES_FRAME[k]))
		var off: Vector2i = spr.get("offset", Vector2i.ZERO)
		UiKit.add_sprite(_dlg, RES + "%04d.png" % int(RES_FRAME[k]), Vector2(DLG_X + roundf(x) + off.x, DLG_Y + y + off.y))
		var amt := _dlg_label(str(int(cost[k])), Vector2(roundf(x) + boxes[i] / 2.0 - 31.0, y + 32), _font_small)
		amt.size = Vector2(62, 12)
		amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		x += boxes[i] + gap

func _dlg_button(up: int, down: int, local: Vector2, cb: Callable) -> void:
	var b := TextureButton.new()
	b.texture_normal = UiKit.load_texture(SYSTEM + "%04d.png" % up)
	b.texture_pressed = UiKit.load_texture(SYSTEM + "%04d.png" % down)
	b.size = b.texture_normal.get_size()
	b.position = Vector2(DLG_X, DLG_Y) + local
	b.pressed.connect(cb)
	_dlg.add_child(b)

# --- input -------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# TextureButtons handle clicks through their own GUI-input path, but
	# _input still runs first: skip any point that lands inside a
	# TextureButton child so those buttons stay clickable, then hit-test the
	# remaining cells (plain sprites, not Controls) ourselves.
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _dlg != null:
			dialog_cancel()
		else:
			_close()
		get_viewport().set_input_as_handled()
		return
	# buybuil*.bin: the build dialog's OKAY is Enter.
	if event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER] \
			and _dlg != null and not _view_only:
		dialog_okay()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if not event.pressed:
			if _dlg != null and _view_only:
				dialog_cancel()
			if _view_hero:
				_view_hero = false
				recruit_hero_view_ended.emit()
			get_viewport().set_input_as_handled()
			return
		# Right-click on a cell shows it; anywhere else does nothing (0xcfd5e).
		if _dlg == null and not _dialog_only:
			var rp: Vector2 = (event as InputEventMouseButton).position
			for id: String in _cells:
				if (_cells[id] as Rect2).has_point(rp):
					view_cell(id)
					break
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _dlg == null and _status_label != null:
		var p: Vector2 = (event as InputEventMouseMotion).position
		for id: String in _cells:
			if (_cells[id] as Rect2).has_point(p):
				_status_label.text = hover_text(id)
				return
		_status_label.text = "Exit Castle" if _exit_rect().has_point(p) else "Castle Options"
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if _dlg != null:
			return   # dialog buttons handle themselves
		var p: Vector2 = (event as InputEventMouseButton).position
		for c in _root.get_children():
			if c is TextureButton and Rect2((c as Control).position, (c as Control).size).has_point(p):
				return   # let the button handle it
		for id: String in _cells:
			if (_cells[id] as Rect2).has_point(p):
				open_cell(id)
				get_viewport().set_input_as_handled()
				return

# --- helpers -----------------------------------------------------------------

func _close() -> void:
	closed.emit()
	queue_free()
