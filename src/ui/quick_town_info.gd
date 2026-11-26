# src/ui/quick_town_info.gd
class_name QuickTownInfo
extends CanvasLayer

## Transient right-click inspection popup for towns and castles on the adventure map.
## Uses the authentic HOMM1 qtown layout (qwiktown.png 210x172).
## Shows town name, locators frame with town/castle icon, player flags, and defenders.

const ART := UiKit.ART
const SMALL_FONT := ART + "smalfont/"
const BG_TEX_PATH := ART + "qwiktown.png"
const LOCATOR_PATH := ART + "locators/%04d.png"
const FLAG_PATH := ART + "flag32/%04d.png"

const MAP_VIEW_RECT := Rect2(16, 16, 448, 448)
const DIALOG_SIZE := Vector2(210, 172)
const TEXT_COLOR := Color8(240, 240, 240)

var _dialog: Control
var _bg: TextureRect
var _title_label: Label
var _town_icon: TextureRect
var _left_flag: TextureRect
var _right_flag: TextureRect
var _defenders_header: Label
var _none_label: Label
var _army_container: Control
var _font: Font

func _init() -> void:
	layer = 300
	visible = false

	_font = Homm1Font.load_font(SMALL_FONT)

	_dialog = Control.new()
	_dialog.name = "QuickTownPanel"
	_dialog.size = DIALOG_SIZE
	_dialog.custom_minimum_size = DIALOG_SIZE
	_dialog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dialog)

	# Background texture (qwiktown.png 210x172)
	_bg = TextureRect.new()
	_bg.name = "Background"
	_bg.texture = load(BG_TEX_PATH) as Texture2D
	_bg.position = Vector2.ZERO
	_bg.size = DIALOG_SIZE
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(_bg)

	# Town name header (centered horizontally at y=7)
	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.position = Vector2(0, 7)
	_title_label.size = Vector2(DIALOG_SIZE.x, 14)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _font != null:
		_title_label.add_theme_font_override("font", _font)
		_title_label.add_theme_font_size_override("font_size", 12)
	_title_label.add_theme_color_override("font_color", TEXT_COLOR)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(_title_label)

	# Left & Right player color flags (flanking town icon at y=25)
	_left_flag = TextureRect.new()
	_left_flag.name = "LeftFlag"
	_left_flag.position = Vector2(50, 25)
	_left_flag.size = Vector2(18, 21)
	_left_flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_left_flag.stretch_mode = TextureRect.STRETCH_KEEP
	_left_flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(_left_flag)

	_right_flag = TextureRect.new()
	_right_flag.name = "RightFlag"
	_right_flag.position = Vector2(142, 25)
	_right_flag.size = Vector2(18, 21)
	_right_flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_right_flag.stretch_mode = TextureRect.STRETCH_KEEP
	_right_flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(_right_flag)

	# Town / Castle icon (locators 12..19, 54x30 at (78, 21))
	_town_icon = TextureRect.new()
	_town_icon.name = "TownIcon"
	_town_icon.position = Vector2(78, 21)
	_town_icon.size = Vector2(54, 30)
	_town_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_town_icon.stretch_mode = TextureRect.STRETCH_KEEP
	_town_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(_town_icon)

	# "Defenders:" subtitle (centered at y=54)
	_defenders_header = Label.new()
	_defenders_header.name = "DefendersHeader"
	_defenders_header.position = Vector2(0, 54)
	_defenders_header.size = Vector2(DIALOG_SIZE.x, 14)
	_defenders_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_defenders_header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_defenders_header.text = "Defenders:"
	if _font != null:
		_defenders_header.add_theme_font_override("font", _font)
		_defenders_header.add_theme_font_size_override("font_size", 12)
	_defenders_header.add_theme_color_override("font_color", TEXT_COLOR)
	_defenders_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(_defenders_header)

	# "None" label (shown when garrison is empty, centered at y=104)
	_none_label = Label.new()
	_none_label.name = "NoneLabel"
	_none_label.position = Vector2(0, 104)
	_none_label.size = Vector2(DIALOG_SIZE.x, 14)
	_none_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_none_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_none_label.text = "None"
	if _font != null:
		_none_label.add_theme_font_override("font", _font)
		_none_label.add_theme_font_size_override("font_size", 12)
	_none_label.add_theme_color_override("font_color", TEXT_COLOR)
	_none_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(_none_label)

	# Army container for garrison creature stacks
	_army_container = Control.new()
	_army_container.name = "ArmyContainer"
	_army_container.position = Vector2.ZERO
	_army_container.size = DIALOG_SIZE
	_army_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(_army_container)

## Opens the quick info box for the given town/castle.
##
## `thieves_guilds` is how many Thieves' Guilds the viewing kingdom owns
## (heroes.exe 0x9e4bc, KB homm1-native-data.md 6.8). Without a guild an enemy
## garrison reads "Unknown", empty or not; one guild shows the creature types
## over "???", two the approximate quantity. Your own town shows exact counts.
func show_town(town_name: String, town_type: int, has_castle: bool, owner: int,
		army: ArmyData, is_own_town: bool, mouse_pos: Vector2,
		thieves_guilds: int = 0) -> void:
	_title_label.text = town_name

	# The locator sheet orders factions differently from town_type.
	_town_icon.texture = load(LOCATOR_PATH % BuildingCatalog.locator_sprite_id(town_type, has_castle)) as Texture2D

	# Set player flags if owned (sides 0..3), hide for neutral (-1)
	if owner >= 0 and owner <= 3:
		var flag_l: Texture2D = MapArtResolver.get_atlas_texture("flag32/%04d.png" % (owner * 2))
		_left_flag.texture = flag_l if flag_l != null else load(FLAG_PATH % (owner * 2)) as Texture2D
		var flag_r: Texture2D = MapArtResolver.get_atlas_texture("flag32/%04d.png" % (owner * 2 + 1))
		_right_flag.texture = flag_r if flag_r != null else load(FLAG_PATH % (owner * 2 + 1)) as Texture2D
		_left_flag.visible = true
		_right_flag.visible = true
	else:
		_left_flag.visible = false
		_right_flag.visible = false

	# Clear previous army stack nodes
	for child in _army_container.get_children():
		_army_container.remove_child(child)
		child.queue_free()

	# One guild reveals the creature types, two the approximate quantity.
	var reveal_types := is_own_town or thieves_guilds >= 1
	var reveal_quantity := is_own_town or thieves_guilds >= 2

	var active_slots: Array[Dictionary] = []
	if reveal_types and army != null:
		for slot in army.slots:
			if slot.count > 0:
				active_slots.append(slot)

	if active_slots.is_empty():
		# "Unknown" keeps an empty enemy garrison a secret too.
		_none_label.text = "None" if reveal_types else "Unknown"
		_none_label.visible = true
		_army_container.visible = false
	else:
		_none_label.visible = false
		_army_container.visible = true

		var num_stacks := active_slots.size()
		for i in range(num_stacks):
			var slot := active_slots[i]
			var cell := stack_cell(i, num_stacks)
			var center_x := cell.x + 16.0

			var native_id := CreatureCatalog.native_id(slot.unit)
			var tex := HeroPanel.get_mons32_texture(native_id)
			if tex != null:
				var c_rect := TextureRect.new()
				c_rect.texture = tex
				c_rect.size = tex.get_size()
				c_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				c_rect.stretch_mode = TextureRect.STRETCH_KEEP
				# Bottom of the 32 px icon cell.
				c_rect.position = Vector2(round(center_x - tex.get_width() / 2.0), cell.y + 32 - tex.get_height())
				c_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
				_army_container.add_child(c_rect)

			# The original's 60 x 12 count box sits 30 px below the icon cell.
			var q_label := Label.new()
			q_label.position = Vector2(round(center_x - 30.0), cell.y + 30)
			q_label.size = Vector2(60, 12)
			q_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			# Top-aligned like heroes.exe's text box; centred sits 5 px low.
			q_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			if _font != null:
				q_label.add_theme_font_override("font", _font)
				q_label.add_theme_font_size_override("font_size", 12)
			q_label.add_theme_color_override("font_color", TEXT_COLOR)
			if is_own_town:
				q_label.text = str(slot.count)
			elif reveal_quantity:
				# "composition and approximate size of the enemy army"
				# (KB basic-concepts.md 3.3.2.1).
				q_label.text = AdventureInspector.short_quantity(slot.count)
			else:
				q_label.text = "???"
			q_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_army_container.add_child(q_label)

	# Position popup centered around mouse click, clamped within map view
	var clamped_x := clampf(mouse_pos.x - DIALOG_SIZE.x / 2.0, MAP_VIEW_RECT.position.x, MAP_VIEW_RECT.end.x - DIALOG_SIZE.x)
	var clamped_y := clampf(mouse_pos.y - DIALOG_SIZE.y / 2.0, MAP_VIEW_RECT.position.y, MAP_VIEW_RECT.end.y - DIALOG_SIZE.y)
	_dialog.position = Vector2(clamped_x, clamped_y)

	visible = true

## Top-left of stack `i`'s 32 x 32 icon cell out of `count` (heroes.exe
## 0x9e8d3). One to three stacks sit in one row at y=97; four draw as two over
## two and five as two over three, the rows at y=75 and y=119. A row of n
## spreads over 192 px from x=9, and the pair over three closes in by 12 px.
@warning_ignore("integer_division")
static func stack_cell(i: int, count: int) -> Vector2i:
	var first := count if count <= 3 else 2
	var row := 0 if i < first else 1
	var n := first if row == 0 else count - first
	var j := i if row == 0 else i - first
	var step := 192 / n
	var x := 9 + (step - 32) / 2 + j * step
	if count == 5 and row == 0:
		x += 12 if j == 0 else -12
	var y := 97 if count <= 3 else 75 + 44 * row
	return Vector2i(x, y)

func hide_info() -> void:
	visible = false
