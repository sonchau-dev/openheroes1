# src/town/dwelling_info_dialog.gd
class_name DwellingInfoDialog
extends CanvasLayer

## Authentic HOMM1 Quick Dwelling Inspection dialog decoded from recruiq0.bin / recruiq1.bin
## (336x181 window, 320x165 inner canvas using recruit2.png).
## Displays creature portrait (monsters.icn), Available count, weekly Growth rate,
## and authentic single or dual resource costs (recruiq0.bin vs recruiq1.bin).

signal closed

const BG_TEX := UiKit.ART + "recruit2.png"
const COST_BOX := UiKit.ART + "townwind/0003.png"
const MONSTERS := UiKit.ART + "monsters/"
const RESOURCE := UiKit.ART + "resource/"

const DLG_SIZE := Vector2(320, 165)
const DEFAULT_POS := Vector2(160, 50)
const RES_FRAME := {
	"wood": 0, "mercury": 1, "ore": 2, "sulfur": 3,
	"crystal": 4, "gems": 5, "gold": 6
}

var _unit: String = ""
var _available: int = 0
var _growth: int = 0
var _is_built: bool = false
var _gold_cost: int = 0
var _sec_res: String = ""
var _sec_cost: int = 0
var _closing: bool = false

var _root: Control
var _dialog_rect: Rect2
var _font_big: FontFile
var _font_small: FontFile
var _title_label: Label
var _avail_label: Label
var _gold_label: Label
var _sec_label: Label

func open(unit: String, available: int, growth: int, is_built: bool, cost: Dictionary, pos := Vector2(-1, -1)) -> void:
	layer = 220
	_closing = false
	_unit = unit
	_available = available
	_growth = growth
	_is_built = is_built
	_gold_cost = int(cost.get("gold", 0))

	_sec_res = ""
	_sec_cost = 0
	for r: String in ["wood", "mercury", "ore", "sulfur", "crystal", "gems"]:
		var amt: int = int(cost.get(r, 0))
		if amt > 0:
			_sec_res = r
			_sec_cost = amt
			break

	var origin: Vector2 = pos if pos.x >= 0 else DEFAULT_POS
	_dialog_rect = Rect2(origin, DLG_SIZE)

	_font_big = UiKit.font_big()
	_font_small = UiKit.font_small()

	# Full-screen dim blocker
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.45)
	dim.position = Vector2.ZERO
	dim.size = Vector2(640, 480)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			close()
	)

	# Dialog root container
	_root = Control.new()
	_root.name = "DialogRoot"
	_root.position = origin
	_root.size = DLG_SIZE
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# Background (recruit2.png 320x165)
	UiKit.add_sprite(_root, BG_TEX, Vector2.ZERO, 0, "Background")

	# Title: "Recruit %s" at (0, 20, 320, 16)
	# heroes.exe 0xa9145: the singular name with only its first letter raised.
	var singular := CreatureCatalog.singular(unit)
	_title_label = UiKit.add_label(_root, "Recruit %s" % (singular.substr(0, 1).to_upper() + singular.substr(1)),
			Vector2(0, 20), Vector2(320, 16), _font_big, Color8(240, 240, 240),
			HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, "Title")

	# Creature portrait at (47, 46, 70, 70)
	var native_id: int = CreatureCatalog.native_id(unit)
	var portrait_tex: Texture2D = null
	if native_id >= 0 and ResourceLoader.exists(MONSTERS + "%04d.png" % native_id):
		portrait_tex = UiKit.load_texture(MONSTERS + "%04d.png" % native_id)
	if portrait_tex == null:
		var std_file := String(CreatureCatalog.art(unit).get("std", unit + ".std"))
		var std_dir := std_file.trim_suffix(".std")
		if ResourceLoader.exists(UiKit.ART + std_dir + ".std/0001.png"):
			portrait_tex = UiKit.load_texture(UiKit.ART + std_dir + ".std/0001.png")

	if portrait_tex != null:
		var por := Sprite2D.new()
		por.name = "Portrait"
		por.texture = portrait_tex
		por.centered = false
		var card_offset := Vector2.ZERO
		if native_id >= 0:
			card_offset = Vector2(SpecLoader.sprite(MONSTERS, native_id).get("offset", Vector2i.ZERO))
		por.position = Vector2(47.0, 46.0) + card_offset
		_root.add_child(por)

	# Available count at (37, 121, 90, 12)
	# recruiq0/1.bin: "Available: " and the count, always a number (0xa9110);
	# the window has no growth line.
	_avail_label = UiKit.add_label(_root, "Available: %d" % _available, Vector2(37, 121), Vector2(90, 12),
			_font_small, Color8(220, 220, 220), HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER,
			"AvailableLabel")

	# Cost Box (townwind/0003.png 132x68 at (140, 49))
	UiKit.add_sprite(_root, COST_BOX, Vector2(140, 49), 0, "CostBox")

	if _sec_res == "":
		# Single resource cost (recruiq0.bin): centered gold icon at (166, 74)
		UiKit.add_sprite(_root, RESOURCE + "0006.png", Vector2(166, 74), 0, "GoldIcon")

		_gold_label = UiKit.add_label(_root, "%d" % _gold_cost, Vector2(166, 99), Vector2(80, 12),
				_font_small, Color8(255, 230, 150), HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER,
				"GoldCost")
	else:
		# Dual resource cost (recruiq1.bin): gold at (146, 74), special at (226, 67)
		UiKit.add_sprite(_root, RESOURCE + "0006.png", Vector2(146, 74), 0, "GoldIcon")

		_gold_label = UiKit.add_label(_root, "%d" % _gold_cost, Vector2(146, 99), Vector2(80, 12),
				_font_small, Color8(255, 230, 150), HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER,
				"GoldCost")

		var sec_frame: int = int(RES_FRAME.get(_sec_res, 0))
		UiKit.add_sprite(_root, RESOURCE + "%04d.png" % sec_frame, Vector2(226, 67), 0, "SecondaryIcon")

		_sec_label = UiKit.add_label(_root, "%d" % _sec_cost, Vector2(226, 99), Vector2(40, 12),
				_font_small, Color8(255, 230, 150), HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER,
				"SecondaryCost")

func dialog_rect() -> Rect2:
	return _dialog_rect

func title_text() -> String:
	return _title_label.text if _title_label != null else ""

func available_text() -> String:
	return _avail_label.text if _avail_label != null else ""


func gold_cost_text() -> String:
	return _gold_label.text if _gold_label != null else ""

func secondary_cost_text() -> String:
	return _sec_label.text if _sec_label != null else ""

func unit_name() -> String:
	return _unit

func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if _closing:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			close()
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.pressed:
			close()
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
		elif not event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			close()
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
