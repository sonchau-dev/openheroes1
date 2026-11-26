# src/ui/icn_button.gd
class_name IcnButton
extends Control

## A HOMM1 ICN button: two sprite states (enabled at base index, pressed at
## base+1) drawn from an extracted ICN dir. Emits `pressed(action_name)` on
## mouse-up inside its rect. `disabled` greys it and swallows clicks.

signal pressed(action_name: String)

var action_name: String = ""
## Local flag — IcnButton extends Control (not BaseButton), so this does not
## shadow an inherited property.
var disabled: bool = false:
	set(v):
		disabled = v
		queue_redraw()

var _dir: String = ""
var _base: int = 0
var _tex_up: Texture2D
var _tex_down: Texture2D
var _held: bool = false

static func frame_index(base: int, is_pressed: bool) -> int:
	return base + (1 if is_pressed else 0)

func setup(icn_dir: String, base_index: int, p_action: String) -> void:
	if not icn_dir.ends_with("/"):
		icn_dir += "/"
	_dir = icn_dir
	_base = base_index
	action_name = p_action
	_tex_up = load(_dir + "%04d.png" % frame_index(_base, false)) as Texture2D
	_tex_down = load(_dir + "%04d.png" % frame_index(_base, true)) as Texture2D
	assert(_tex_up != null, "IcnButton: missing enabled frame at %s" % (_dir + "%04d.png" % frame_index(_base, false)))
	if _tex_up != null:
		custom_minimum_size = _tex_up.get_size()
		size = _tex_up.get_size()
	queue_redraw()

## Enabled-texture size; used by parents to lay out a vertical button stack.
func texture_normal_size() -> Vector2:
	return _tex_up.get_size() if _tex_up != null else Vector2.ZERO

func would_emit() -> bool:
	return not disabled

func _draw() -> void:
	var tex := _tex_down if (_held and not disabled) else _tex_up
	if tex != null:
		draw_texture(tex, Vector2.ZERO, Color(1, 1, 1, 0.45) if disabled else Color.WHITE)

func _gui_input(event: InputEvent) -> void:
	if disabled or not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_held = true
		queue_redraw()
		accept_event()
	else:
		if _held:
			_held = false
			queue_redraw()
			pressed.emit(action_name)
			accept_event()
