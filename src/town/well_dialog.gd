# src/town/well_dialog.gd
class_name WellDialog
extends CanvasLayer

## HOMM1 Well window ("Town Population Information and Statistics"), laid out
## from wellwind.bin (640x262 over the town view) and filled as heroes.exe
## fills it (0xbc47d). Each of the six dwellings gets its building picture and
## name plate, the creature's picture and singular name, and a four-line
## "Available / Growth Rate" box. The right column mirrors the left.

const BG := UiKit.ART + "stonebak.png"
const BUILDING := UiKit.ART + "building/"
const MONSTERS := UiKit.ART + "monsters/"
const TOWNWIND := UiKit.ART + "townwind/"
const TREASURY := UiKit.ART + "treasury/"

const TITLE := "Town Population Information and Statistics"
## Rows of the left (dwellings 0-2) and right (3-5) columns.
const ROW_Y := [2, 81, 160]
const BUILDING_X := [10, 493]
const MONSTER_X := [150, 420]     # the right picture is drawn mirrored
const NAME_BAR_X := [223, 328]
const MONSTER_BOX := Vector2(70, 70)
const LINE_PITCH := 13.0
const EXIT_POS := Vector2(550, 236)
## heroes.exe strings 0x10738d and 0x10736c.
const INFO_BUILT := "Available:\n%d\nGrowth Rate:\n%d/week"
const INFO_NOT_BUILT := "Available:\nNONE\nGrowth Rate:\nN/A"

signal closed

var _root: Control
var _exit_rect: Rect2
var _info_texts: Array[String] = []

func open(town: TownModel, faction_arg: Variant = "knight") -> void:
	layer = 210
	var faction_str := "knight"
	if town != null and town.faction != "":
		faction_str = town.faction
	elif faction_arg is int:
		faction_str = BuildingCatalog.faction_for_type(int(faction_arg))
	elif faction_arg is String:
		faction_str = String(faction_arg)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	UiKit.add_sprite(_root, BG, Vector2.ZERO)

	var font_big := UiKit.font_big()
	var font_small := UiKit.font_small()

	var dwellings := BuildingCatalog.dwelling_ids(faction_str)
	for i in mini(6, dwellings.size()):
		var col := i / 3
		var y: float = ROW_Y[i % 3]
		var dw_id: String = dwellings[i]
		var entry: Dictionary = BuildingCatalog.entry(dw_id, faction_str)
		var unit := String(entry.get("unit", ""))

		var bx: float = BUILDING_X[col]
		UiKit.add_sprite(_root, BUILDING + "%04d.png" % int(entry.get("frame", 0)), Vector2(bx, y))
		UiKit.add_sprite(_root, BUILDING + "0000.png", Vector2(bx, y + 61))
		var plate := UiKit.add_label_rect(_root, String(entry.get("name", dw_id)), Rect2(bx, y + 61, 137, 12), font_small, Color.WHITE)
		plate.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

		_monster(unit, Vector2(MONSTER_X[col], y + 3), col == 1)

		var nx: float = NAME_BAR_X[col]
		UiKit.add_sprite(_root, TOWNWIND + "0002.png", Vector2(nx, y + 3))
		UiKit.add_label_rect(_root, _first_upper(CreatureCatalog.singular(unit)), Rect2(nx + 6, y + 4, 77, 12), font_small, Color.WHITE)

		# The 89x53 MonsterInfo box holds four smalfont lines.
		var text := info_text(town, dw_id, unit, faction_str)
		_info_texts.append(text)
		var lines := text.split("\n")
		var top: float = y + 19 + (53.0 - LINE_PITCH * lines.size()) / 2.0
		for li in lines.size():
			UiKit.add_label_rect(_root, lines[li], Rect2(nx, top + li * LINE_PITCH, 89, 12), font_small, Color.WHITE)

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
	UiKit.add_label_rect(_root, TITLE, Rect2(10, 241, 538, 16), font_big, Color.WHITE)

	var exit_btn := TextureButton.new()
	exit_btn.texture_normal = UiKit.load_texture(TREASURY + "0001.png")
	exit_btn.texture_pressed = UiKit.load_texture(TREASURY + "0002.png")
	exit_btn.position = EXIT_POS
	exit_btn.size = exit_btn.texture_normal.get_size()
	exit_btn.pressed.connect(_close)
	_root.add_child(exit_btn)
	_exit_rect = Rect2(EXIT_POS, exit_btn.size)

## heroes.exe 0xbc5ee: NONE/N/A only for an unbuilt dwelling; growth is the
## creature's base growth plus the Well's 2 (the window opens from the Well).
static func info_text(town: TownModel, dw_id: String, unit: String, faction: String) -> String:
	if town == null or not town.is_built(dw_id):
		return INFO_NOT_BUILT
	var recruit: Dictionary = TownModel._recruit_data(faction).get(unit, {}) as Dictionary
	return INFO_BUILT % [int(town.available.get(unit, 0)), int(recruit.get("growth", 0)) + 2]

static func _first_upper(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1)

func _monster(unit: String, box: Vector2, mirrored: bool) -> void:
	var native_id := CreatureCatalog.native_id(unit)
	if native_id < 0:
		return
	var spec := SpecLoader.sprite(MONSTERS, native_id)
	var path := MONSTERS + "%04d.png" % native_id
	if spec.is_empty() or not ResourceLoader.exists(path):
		return
	var s := UiKit.add_sprite(_root, path, Vector2.ZERO)
	var offset: Vector2i = spec["offset"]
	var size: Vector2i = spec["size"]
	s.flip_h = mirrored
	var x: float = box.x + (MONSTER_BOX.x - offset.x - size.x if mirrored else float(offset.x))
	s.position = Vector2(x, box.y + offset.y)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _exit_rect.has_point((event as InputEventMouseButton).position):
				_close()
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_close()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed:
		if event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_close()
			get_viewport().set_input_as_handled()

func _close() -> void:
	closed.emit()
	queue_free()
