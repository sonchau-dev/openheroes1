# src/adventure/button_bar.gd
class_name ButtonBar
extends Control

## 6 adventure buttons from advbtns.icn. Renders up/pressed states; emits action(slot).
## Only End Turn / To Town are wired by the HUD; the rest are cosmetic.

const ADVBTNS := UiKit.ART + "advbtns/"
const CELL := Vector2(48, 36)
const COLS := 3
const ROWS := 2

# slot -> semantic action name; slots fill ROW-major like the original
# (top: 0 helmet=next hero, 1 horse=move, 2 castle=kingdom; bottom: 3 hourglass=end turn, 4 flag=adventure_options, 5 disk=system).
const ACTIONS := ["next_hero", "move", "kingdom", "end_turn", "flag", "system"]


signal action(act: String)
signal inspect_requested(button_idx: int, screen_pos: Vector2)
signal inspect_dismissed

var _slots: Array = []   # [{rect:Rect2, sprite:Sprite2D, enabled:bool}]
var _rect: Rect2
static var _disabled_cache: Dictionary = {}   # slot -> darkened icon, kept across map reloads

static func icon_index(slot: int, pressed: bool) -> int:
	return slot * 2 + (1 if pressed else 0)

static func cell_origin(rect: Rect2, slot: int) -> Vector2:
	var col := slot % COLS
	var row := slot / COLS
	var left := rect.position.x + (rect.size.x - COLS * CELL.x) * 0.5
	var top := rect.position.y + (rect.size.y - ROWS * CELL.y) * 0.5
	return Vector2(left + col * CELL.x, top + row * CELL.y)

func setup(rect: Rect2) -> void:
	_rect = rect
	_slots.clear()
	for slot in 6:
		var spr := Sprite2D.new()
		spr.centered = false
		spr.texture = _icon(slot, false)
		var origin := cell_origin(rect, slot)
		spr.position = origin
		add_child(spr)
		_slots.append({"rect": Rect2(origin, CELL), "sprite": spr, "enabled": true})

func _icon(slot: int, pressed: bool) -> Texture2D:
	return UiKit.load_texture(ADVBTNS + "%04d.png" % icon_index(slot, pressed))

func _disabled_icon(slot: int) -> Texture2D:
	if _disabled_cache.has(slot):
		return _disabled_cache[slot]
	var path := ADVBTNS + "%04d_disabled.png" % icon_index(slot, false)
	var tex := UiKit.load_texture(path)
	_disabled_cache[slot] = tex
	return tex

func set_button_enabled(slot: int, enabled: bool) -> void:
	if slot < 0 or slot >= _slots.size():
		return
	var s: Dictionary = _slots[slot]
	if s.get("enabled", true) == enabled:
		return
	s["enabled"] = enabled
	var spr: Sprite2D = s["sprite"]
	if enabled:
		spr.texture = _icon(slot, false)
	else:
		spr.texture = _disabled_icon(slot)

func is_button_enabled(slot: int) -> bool:
	if slot < 0 or slot >= _slots.size():
		return false
	return _slots[slot].get("enabled", true)

## Claim input ONLY on the 6 button slots. The bar is a full-screen Control, but if it
## reported every point as inside it would shadow the minimap / roster panel layered with
## it — the viewport delivers _gui_input to just the topmost claiming control, and clicks
## outside the slots fall through to the map's _unhandled_input.
func _has_point(point: Vector2) -> bool:
	for s in _slots:
		if (s.rect as Rect2).has_point(point):
			return true
	return false

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		if mb.pressed:
			for slot in _slots.size():
				var s: Dictionary = _slots[slot]
				if (s.rect as Rect2).has_point(mb.position):
					inspect_requested.emit(slot, mb.position)
					accept_event()
					return
		else:
			inspect_dismissed.emit()
			accept_event()
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	for slot in _slots.size():
		var s: Dictionary = _slots[slot]
		# Control is at (0,0), so mb.position is already screen-space, matching the
		# absolute slot rects from cell_origin — no band offset to add.
		if (s.rect as Rect2).has_point(mb.position):
			if not s.get("enabled", true):
				accept_event()
				return
			if mb.pressed:
				(s.sprite as Sprite2D).texture = _icon(slot, true)
			else:
				(s.sprite as Sprite2D).texture = _icon(slot, false)
				action.emit(ACTIONS[slot])
			accept_event()
			return
