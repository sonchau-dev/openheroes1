# src/ui/quick_hero_info.gd
class_name QuickHeroInfo
extends CanvasLayer

## Transient right-click inspection popup for heroes on the adventure map.
## Supports both own heroes (qhero0.bin: primary stats + exact army counts)
## and enemy heroes (qhero1.bin: no stats + approximate army counts).

const ART := UiKit.ART
const QWIKHERO := ART + "qwikhero.png"
const SMALL_FONT := ART + "smalfont/"
const LOCATORS := ART + "locators/%04d.png"
const MINIPORT := ART + "miniport/%04d.png"
const FLAG32 := ART + "flag32/%04d.png"
const MONS32 := ART + "mons32/%04d.png"

const DIALOG_WIDTH := 178.0
const DIALOG_HEIGHT := 162.0
const MAP_VIEW_RECT := Rect2(16, 16, 448, 448)
const TEXT_COLOR := Color8(240, 240, 240)

var _dialog: Control
var _bg: TextureRect
var _title_label: Label
var _frame_rect: TextureRect
var _port_rect: TextureRect
var _left_flag: TextureRect
var _right_flag: TextureRect
var _stats_container: Control
var _atk_val: Label
var _def_val: Label
var _pow_val: Label
var _kno_val: Label
var _army_container: Control
var _font: Font

func _init() -> void:
	layer = 300
	visible = false

	_font = Homm1Font.load_font(SMALL_FONT)

	_dialog = Control.new()
	_dialog.name = "QuickHeroPanel"
	_dialog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.size = Vector2(DIALOG_WIDTH, DIALOG_HEIGHT)
	_dialog.custom_minimum_size = Vector2(DIALOG_WIDTH, DIALOG_HEIGHT)
	add_child(_dialog)

	# Background parchment (178x162)
	_bg = TextureRect.new()
	_bg.name = "Background"
	_bg.texture = load(QWIKHERO) as Texture2D
	_bg.position = Vector2.ZERO
	_bg.size = Vector2(DIALOG_WIDTH, DIALOG_HEIGHT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(_bg)

	# Title (Hero Name)
	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _font != null:
		_title_label.add_theme_font_override("font", _font)
		_title_label.add_theme_font_size_override("font_size", 12)
	_title_label.add_theme_color_override("font_color", TEXT_COLOR)
	_title_label.position = Vector2(0, 7)
	_title_label.size = Vector2(DIALOG_WIDTH, 14)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(_title_label)

	# Left & Right player color flags
	_left_flag = TextureRect.new()
	_left_flag.name = "LeftFlag"
	_left_flag.position = Vector2(44, 25)
	_left_flag.size = Vector2(18, 21)
	_left_flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_left_flag.stretch_mode = TextureRect.STRETCH_KEEP
	_left_flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(_left_flag)

	_right_flag = TextureRect.new()
	_right_flag.name = "RightFlag"
	_right_flag.position = Vector2(116, 25)
	_right_flag.size = Vector2(18, 21)
	_right_flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_right_flag.stretch_mode = TextureRect.STRETCH_KEEP
	_right_flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(_right_flag)

	# Locator frame around portrait
	_frame_rect = TextureRect.new()
	_frame_rect.name = "PortraitFrame"
	_frame_rect.texture = load(LOCATORS % 21) as Texture2D
	_frame_rect.position = Vector2(69, 23)
	_frame_rect.size = Vector2(40, 30)
	_frame_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame_rect.stretch_mode = TextureRect.STRETCH_KEEP
	_frame_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(_frame_rect)

	# Mini portrait
	_port_rect = TextureRect.new()
	_port_rect.name = "MiniPortrait"
	_port_rect.position = Vector2(73, 27)
	_port_rect.size = Vector2(32, 22)
	_port_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_port_rect.stretch_mode = TextureRect.STRETCH_KEEP
	_port_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(_port_rect)

	# Primary Stats Container (for own heroes)
	_stats_container = Control.new()
	_stats_container.name = "StatsContainer"
	_stats_container.position = Vector2.ZERO
	_stats_container.size = Vector2(DIALOG_WIDTH, DIALOG_HEIGHT)
	_stats_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(_stats_container)

	var stat_names := ["Attack:", "Defense:", "Spell Power:", "Knowledge:"]
	var stat_ys := [57.0, 68.0, 79.0, 90.0]
	for i in range(4):
		var lbl := Label.new()
		lbl.text = stat_names[i]
		lbl.position = Vector2(45, stat_ys[i])
		lbl.size = Vector2(80, 12)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if _font != null:
			lbl.add_theme_font_override("font", _font)
			lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", TEXT_COLOR)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stats_container.add_child(lbl)

	_atk_val = _create_stat_val(stat_ys[0])
	_def_val = _create_stat_val(stat_ys[1])
	_pow_val = _create_stat_val(stat_ys[2])
	_kno_val = _create_stat_val(stat_ys[3])
	_stats_container.add_child(_atk_val)
	_stats_container.add_child(_def_val)
	_stats_container.add_child(_pow_val)
	_stats_container.add_child(_kno_val)

	# Army container
	_army_container = Control.new()
	_army_container.name = "ArmyContainer"
	_army_container.position = Vector2.ZERO
	_army_container.size = Vector2(DIALOG_WIDTH, DIALOG_HEIGHT)
	_army_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(_army_container)

func _create_stat_val(y_pos: float) -> Label:
	var val_lbl := Label.new()
	val_lbl.position = Vector2(128, y_pos)
	val_lbl.size = Vector2(25, 12)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _font != null:
		val_lbl.add_theme_font_override("font", _font)
		val_lbl.add_theme_font_size_override("font_size", 12)
	val_lbl.add_theme_color_override("font_color", TEXT_COLOR)
	val_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return val_lbl

func show_hero(hero: HeroModel, side: int, is_own: bool, mouse_pos: Vector2, full_info: bool = false) -> void:
	if hero == null:
		hide_info()
		return

	_title_label.text = hero.hero_name
	_port_rect.texture = load(MINIPORT % maxi(0, hero.portrait_idx)) as Texture2D

	_frame_rect.texture = load(LOCATORS % 21) as Texture2D

	var s := clampi(side, 0, 3)
	var flag_l: Texture2D = MapArtResolver.get_atlas_texture("flag32/%04d.png" % (s * 2))
	_left_flag.texture = flag_l if flag_l != null else load(FLAG32 % (s * 2)) as Texture2D
	var flag_r: Texture2D = MapArtResolver.get_atlas_texture("flag32/%04d.png" % (s * 2 + 1))
	_right_flag.texture = flag_r if flag_r != null else load(FLAG32 % (s * 2 + 1)) as Texture2D

	var show_full := is_own or full_info
	if show_full:
		_stats_container.visible = true
		_atk_val.text = str(hero.effective_attack())
		_def_val.text = str(hero.effective_defense())
		_pow_val.text = str(hero.effective_spell_power())
		_kno_val.text = str(hero.effective_knowledge())
	else:
		_stats_container.visible = false

	# Rebuild army slots
	for child in _army_container.get_children():
		_army_container.remove_child(child)
		child.queue_free()

	var active_stacks: Array = []
	if hero.army != null:
		for slot: Dictionary in hero.army.slots:
			if int(slot.get("count", 0)) > 0:
				active_stacks.append(slot)

	var n := active_stacks.size()
	if n > 0:
		for i in range(n):
			var slot: Dictionary = active_stacks[i]
			var unit_name: String = String(slot.get("unit", ""))
			var count: int = int(slot.get("count", 0))
			var native_id := CreatureCatalog.native_id(unit_name)
			var cell := stack_cell(i, n, show_full)
			var center_x := cell.x + 16.0

			var mon_tex := HeroPanel.get_mons32_texture(native_id)
			if mon_tex != null:
				var mon_rect := TextureRect.new()
				mon_rect.texture = mon_tex
				mon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				mon_rect.stretch_mode = TextureRect.STRETCH_KEEP
				mon_rect.size = mon_tex.get_size()
				# Bottom of the 32 px icon cell.
				mon_rect.position = Vector2(
					roundf(center_x - mon_tex.get_width() / 2.0),
					cell.y + 32 - mon_tex.get_height()
				)
				mon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
				_army_container.add_child(mon_rect)

			var count_label := Label.new()
			count_label.text = str(count) if show_full else AdventureInspector.short_quantity(count)
			count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			# Top-aligned like heroes.exe's text box (cap tops 3 px down); a
			# centred Label sits 5 px lower and runs into the bottom frame.
			count_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			if _font != null:
				count_label.add_theme_font_override("font", _font)
				count_label.add_theme_font_size_override("font_size", 12)
			count_label.add_theme_color_override("font_color", TEXT_COLOR)
			# The original's 12 px count box sits 30 px below the icon cell.
			count_label.position = Vector2(roundf(center_x - 30.0), cell.y + 30)
			count_label.size = Vector2(60.0, 12.0)
			count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_army_container.add_child(count_label)

	var pos := mouse_pos - Vector2(DIALOG_WIDTH / 2.0, DIALOG_HEIGHT / 2.0)
	pos.x = clampf(pos.x, MAP_VIEW_RECT.position.x, MAP_VIEW_RECT.end.x - DIALOG_WIDTH)
	pos.y = clampf(pos.y, MAP_VIEW_RECT.position.y, MAP_VIEW_RECT.end.y - DIALOG_HEIGHT)
	_dialog.position = pos
	visible = true

## Top-left of stack `i`'s 32 x 32 icon cell out of `count` (heroes.exe
## 0x9dd46 and 0x9df07). Your own hero, or one under Identify Hero, packs its
## army into one row at y=110, 32 px apart and centred over 160 px from x=9.
## Any other hero spreads one to three stacks over those 160 px at y=87; four
## draw as two over two and five as two over three, the rows at y=65 and y=109.
@warning_ignore("integer_division")
static func stack_cell(i: int, count: int, full: bool) -> Vector2i:
	if full:
		return Vector2i(9 + (160 - count * 32) / 2 + i * 32, 110)
	var first := count if count <= 3 else 2
	var row := 0 if i < first else 1
	var n := first if row == 0 else count - first
	var j := i if row == 0 else i - first
	var step := 160 / n
	var y := 87 if count <= 3 else 65 + 44 * row
	return Vector2i(9 + (step - 32) / 2 + j * step, y)

func hide_info() -> void:
	visible = false
