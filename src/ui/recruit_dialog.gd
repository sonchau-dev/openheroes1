class_name RecruitDialog
extends CanvasLayer

## The native recruit window for town dwellings and paid adventure dwellings.
## heroes.exe loads recruit0.bin (gold only) or recruit1.bin (gold and one
## other resource) at screen (160, 16) for both (0xa92db). Every position below
## is a record of those files (tools/bin_layouts.gd); sprites add their ICN
## offset to the record position. Keys: Up, Down, Enter (OKAY) and Esc
## (CANCEL); MAX has none.

## Emitted on OKAY with a count above zero; the caller makes the purchase.
signal confirmed(quantity: int)
signal closed

const ORIGIN := Vector2(160, 16)
const RESOURCE_FRAMES := {"wood": 0, "mercury": 1, "ore": 2, "sulfur": 3,
		"crystal": 4, "gems": 5, "gold": 6}
## [cost sprite, cost text, total sprite, total text] per file.
const GOLD_ONLY := [Vector2(166, 74), Rect2(166, 99, 80, 12),
		Vector2(123, 198), Rect2(123, 223, 80, 12)]
const GOLD_WITH_RARE := [Vector2(146, 74), Rect2(146, 99, 80, 12),
		Vector2(103, 203), Rect2(103, 228, 80, 12)]
const RARE := [Vector2(226, 67), Rect2(226, 99, 40, 12),
		Vector2(183, 196), Rect2(183, 228, 40, 12)]
## The original's bigfont baseline is 12 px below the line top, Homm1Font's 10
## (data/knowledge_base/research/fonts.md); smalfont matches.
const BIGFONT_DROP := 2.0

var unit := ""
var quantity := 0

var _max_quantity := 0
var _gold := 0
var _rare := ""
var _rare_cost := 0
var _font_big: FontFile
var _font_small: FontFile
var _quantity_label: Label
var _total_label: Label
var _rare_total_label: Label

## `costs` is the price of one creature, e.g. {"gold": 650, "gems": 1}.
## `max_quantity` is what the buyer can afford and fit.
func open(p_unit: String, available: int, costs: Dictionary, max_quantity: int) -> void:
	unit = p_unit
	quantity = 0
	_max_quantity = max_quantity
	_gold = int(costs.get("gold", 0))
	for resource: String in costs:
		if resource != "gold" and int(costs[resource]) > 0:
			_rare = resource
			_rare_cost = int(costs[resource])
	_font_big = UiKit.font_big()
	_font_small = UiKit.font_small()
	layer = 200
	name = "RecruitDialog"

	var blocker := ColorRect.new()
	blocker.name = "InputBlocker"
	blocker.color = Color(0, 0, 0, 0)
	blocker.size = Vector2(640, 480)
	add_child(blocker)

	_shadow(Rect2(16, 294, 320, 16))
	_shadow(Rect2(320, 16, 16, 278))
	UiKit.add_sprite(self, UiKit.ART + "recruit.png", ORIGIN, 0, "RecruitBackground")
	var singular := CreatureCatalog.singular(unit)
	UiKit.add_label(self, "Recruit " + singular.left(1).to_upper() + singular.substr(1),
			ORIGIN + Vector2(0, 20 + BIGFONT_DROP), Vector2(320, 16), _font_big, Color.WHITE,
			HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, "Title")
	UiKit.add_label(self, "Total resource cost:", ORIGIN + Vector2(0, 180 + BIGFONT_DROP),
			Vector2(320, 16), _font_big, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER,
			VERTICAL_ALIGNMENT_TOP, "TotalPrompt")
	_frame("Creature", "monsters", CreatureCatalog.native_id(unit), Vector2(47, 46))
	UiKit.add_label(self, "Available: %d" % available, ORIGIN + Vector2(37, 121),
			Vector2(90, 12), _font_small, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER,
			VERTICAL_ALIGNMENT_TOP, "Available")
	UiKit.add_sprite(self, UiKit.ART + "townwind/0003.png", ORIGIN + Vector2(140, 49), 0, "CostBox")

	var gold_layout: Array = GOLD_ONLY if _rare == "" else GOLD_WITH_RARE
	_frame("CostGoldIcon", "resource", RESOURCE_FRAMES.gold, gold_layout[0])
	UiKit.add_label(self, str(_gold), ORIGIN + gold_layout[1].position, gold_layout[1].size,
			_font_small, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, "UnitCost")
	_frame("TotalGoldIcon", "resource", RESOURCE_FRAMES.gold, gold_layout[2])
	_total_label = UiKit.add_label(self, "0", ORIGIN + gold_layout[3].position, gold_layout[3].size,
			_font_small, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, "Total")
	if _rare != "":
		_frame("CostRareIcon", "resource", RESOURCE_FRAMES[_rare], RARE[0])
		UiKit.add_label(self, str(_rare_cost), ORIGIN + RARE[1].position, RARE[1].size,
				_font_small, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, "UnitCostRare")
		_frame("TotalRareIcon", "resource", RESOURCE_FRAMES[_rare], RARE[2])
		_rare_total_label = UiKit.add_label(self, "0", ORIGIN + RARE[3].position, RARE[3].size,
				_font_small, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, "TotalRare")

	var prompt := UiKit.add_label(self, "Number to buy:", ORIGIN + Vector2(20, 148),
			Vector2(105, 12), _font_small, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT,
			VERTICAL_ALIGNMENT_TOP, "NumberPrompt")
	UiKit.add_sprite(self, UiKit.ART + "townwind/0004.png", ORIGIN + Vector2(136, 145), 0, "QuantityBox")
	_quantity_label = UiKit.add_label(self, "0", ORIGIN + Vector2(136, 145 + BIGFONT_DROP),
			Vector2(68, 19), _font_big, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER,
			VERTICAL_ALIGNMENT_TOP, "Quantity")

	_button("Increase", 0, Vector2(207, 140), increase)
	_button("Decrease", 2, Vector2(207, 155), decrease)
	_button("Maximum", 4, Vector2(236, 142), maximum)
	_button("Okay", 8, Vector2(36, 245), confirm)
	_button("Cancel", 6, Vector2(189, 245), close)

func increase() -> void:
	quantity = mini(quantity + 1, _max_quantity)
	_update()

func decrease() -> void:
	quantity = maxi(0, quantity - 1)
	_update()

func maximum() -> void:
	quantity = _max_quantity
	_update()

func confirm() -> void:
	if quantity > 0:
		confirmed.emit(quantity)
	close()

func close() -> void:
	closed.emit()
	queue_free()

func _update() -> void:
	_quantity_label.text = str(quantity)
	_total_label.text = str(quantity * _gold)
	if _rare_total_label != null:
		_rare_total_label.text = str(quantity * _rare_cost)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	var key := event as InputEventKey
	match key.keycode:
		KEY_UP: increase()
		KEY_DOWN: decrease()
		KEY_ENTER, KEY_KP_ENTER: if not key.echo: confirm()
		KEY_ESCAPE: if not key.echo: close()
	get_viewport().set_input_as_handled()

func _shadow(rect: Rect2) -> void:
	var shadow := ColorRect.new()
	shadow.color = Color(0, 0, 0, 0.45)
	shadow.position = ORIGIN + rect.position
	shadow.size = rect.size
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shadow)

## One ICN frame, drawn at the record position plus the frame's own offset.
func _frame(node_name: String, dir: String, id: int, at: Vector2) -> void:
	var sp := SpecLoader.sprite(UiKit.ART + dir, id)
	if not sp.is_empty():
		UiKit.add_sprite(self, UiKit.ART + "%s/%s" % [dir, String(sp.file)], ORIGIN + at + Vector2(sp.offset), 0, node_name)

func _button(node_name: String, frame: int, at: Vector2, callback: Callable) -> void:
	var up := SpecLoader.sprite(UiKit.ART + "recruit", frame)
	var button := TextureButton.new()
	button.name = node_name
	button.texture_normal = load(UiKit.ART + "recruit/%04d.png" % frame) as Texture2D
	button.texture_pressed = load(UiKit.ART + "recruit/%04d.png" % (frame + 1)) as Texture2D
	button.position = ORIGIN + at + Vector2(up.get("offset", Vector2.ZERO))
	button.pressed.connect(callback)
	add_child(button)
