extends Node

## Handles touch screen input (iOS, Android) and translates touch gestures into
## mouse events for HOMM1's mouse-driven interface.
##
## On touch devices:
## - A quick tap produces a Left Mouse Button press and release (click).
## - Two quick taps produce a Left Mouse Button double-click.
## - A long press (held for 0.5s without dragging) registers as a Right Mouse Button press;
##   releasing the touch releases the Right Mouse Button.
## - A touch drag (> 12 px before long-press) registers as Left Mouse Button down + motion.
## - A hold (0.25 s) in the map's edge band pans the map. A hold that moved the
##   map, or slid off its spot, sends no click on release; one the map could not
##   follow is still a tap or a long press.
##
## Physical mouse events bypass this handler entirely.

## Duration in seconds before a stationary touch registers as a right click.
const LONG_PRESS_DURATION: float = 0.5

## Maximum movement in viewport pixels before a touch is considered a drag
## rather than a tap or long press.
const DRAG_THRESHOLD: float = 12.0

## Maximum interval between taps to register as a double-click.
const DOUBLE_TAP_TIMEOUT_SEC: float = 0.35

## Seconds a finger must be held down before a hold becomes a pan. A quicker
## touch is a tap on whatever is under the finger: the map's edge band sits on
## the outer ring of the visible map, so without this a tap there would scroll
## the map instead of picking the object up.
const PAN_HOLD_DURATION: float = 0.25

var enabled: bool = false
var long_press_duration: float = LONG_PRESS_DURATION
var drag_threshold: float = DRAG_THRESHOLD
var double_tap_timeout: float = DOUBLE_TAP_TIMEOUT_SEC
var pan_hold_duration: float = PAN_HOLD_DURATION

# Active primary touch state
var _active: bool = false
var _touch_index: int = -1
var _start_pos: Vector2 = Vector2.ZERO
var _current_pos: Vector2 = Vector2.ZERO
# Ticks (ms) of the touch-down. The hold is timed from it, not summed from
# frame times, so a long first frame cannot turn a quick tap into a pan.
var _down_msec: int = 0
var _long_press_triggered: bool = false
var _drag_started: bool = false
# True once the held finger has taken the map over as a pan; the drag is then
# dropped.
var _panning: bool = false
# True when the map actually moved under the finger, or the finger slid off its
# spot during a pan: the tap and the long press are then dropped. The pan
# gesture alone does not veto them: a hold at the map's edge scrolls nothing, so
# the finger was still a tap or a long press.
var _tap_vetoed: bool = false

# Last position sent to the game. Viewport.get_mouse_position() follows the OS
# pointer and ignores pushed events, so a touch screen leaves it at the origin.
var _pointer: Vector2 = Vector2.ZERO
var _has_pointer: bool = false

# Double tap tracking
var _last_tap_time: float = -10.0
var _last_tap_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	process_priority = -100
	if is_touch_device():
		set_enabled(true)

## Returns true if running on a mobile / touch platform (iOS, Android).
static func is_touch_device() -> bool:
	if OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("mobile"):
		return true
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg == "--touch":
			return true
	return false

func set_enabled(value: bool) -> void:
	enabled = value
	if enabled:
		Input.set_emulate_mouse_from_touch(false)
	else:
		_cancel_touch()
		Input.set_emulate_mouse_from_touch(true)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_cancel_touch()

## Where the pointer is, in viewport pixels. Use this instead of
## `Viewport.get_mouse_position()` anywhere a touch must resolve to its own spot.
func pointer_position(vp: Viewport) -> Vector2:
	if enabled and _has_pointer:
		return _pointer
	return vp.get_mouse_position() if vp != null else Vector2.ZERO

## True while a finger sits down and is not already a drag or a long press, so
## the map may scroll under it. A real mouse, or no finger, returns false.
func is_edge_hold_active() -> bool:
	return enabled and _has_pointer and _active \
			and not _long_press_triggered and not _drag_started

## True when a touch (not a real mouse) owns the pointer.
func owns_pointer() -> bool:
	return enabled and _has_pointer

## How long the finger has been held, in seconds.
func hold_seconds() -> float:
	return (Time.get_ticks_msec() - _down_msec) / 1000.0 if _active else 0.0

## The map took the finger over as a pan: drop the drag.
func mark_pan() -> void:
	_panning = true

## Pans the map camera by `step`. When the map really moved under a panning
## finger, the hold was a pan and not a tap: drop the tap. A hold at the map's
## limit moves nothing and stays a tap or a long press.
func pan_map(cam: MapCamera, step: Vector2) -> void:
	var before := cam.position
	cam.center_on(cam.position + step)
	if _panning and cam.position != before:
		veto_tap()

## The map actually moved under the finger, so the hold was a pan and not a
## tap: drop the tap as well.
func veto_tap() -> void:
	_tap_vetoed = true

func _input(event: InputEvent) -> void:
	if not enabled:
		return
	# A real mouse (desktop with --touch) takes the pointer back.
	if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		_has_pointer = false
	if event is InputEventScreenTouch:
		_handle_screen_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event as InputEventScreenDrag)

func _process(_delta: float) -> void:
	tick(0.0)

## Checks the held finger for a long press. Called each frame in `_process`.
## For deterministic testing, `delta` moves the touch-down back that many seconds.
func tick(delta: float) -> void:
	if not enabled or not _active:
		return
	_down_msec -= roundi(delta * 1000.0)
	if not _long_press_triggered and not _drag_started and not _tap_vetoed:
		if hold_seconds() >= long_press_duration:
			_long_press_triggered = true
			_send_mouse_motion(_current_pos, Vector2.ZERO, 0)
			_send_mouse_button(MOUSE_BUTTON_RIGHT, true, _current_pos)

func _handle_screen_touch(touch: InputEventScreenTouch) -> void:
	if touch.canceled:
		_cancel_touch()
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()
		return

	if touch.pressed:
		if not _active and touch.index == 0:
			_active = true
			_touch_index = touch.index
			_start_pos = touch.position
			_current_pos = touch.position
			_set_pointer(touch.position)
			_down_msec = Time.get_ticks_msec()
			_long_press_triggered = false
			_drag_started = false
			_panning = false
			_tap_vetoed = false
	else:
		if _active and touch.index == _touch_index:
			_current_pos = touch.position
			if _long_press_triggered:
				_send_mouse_button(MOUSE_BUTTON_RIGHT, false, _current_pos)
			elif _drag_started:
				_send_mouse_button(MOUSE_BUTTON_LEFT, false, _current_pos)
			elif _tap_vetoed:
				pass    # the map moved under the finger: the hold was a pan
			else:
				# Short tap without drag
				var is_double := false
				var now := Time.get_ticks_msec() / 1000.0
				if (now - _last_tap_time) <= double_tap_timeout and _current_pos.distance_to(_last_tap_pos) <= drag_threshold:
					is_double = true
					_last_tap_time = -10.0
				else:
					_last_tap_time = now
					_last_tap_pos = _current_pos

				_send_mouse_motion(_current_pos, Vector2.ZERO, 0)
				_send_mouse_button(MOUSE_BUTTON_LEFT, true, _current_pos, is_double)
				_send_mouse_button(MOUSE_BUTTON_LEFT, false, _current_pos, is_double)
			_reset_touch()

	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()

func _handle_screen_drag(drag: InputEventScreenDrag) -> void:
	if _active and drag.index == _touch_index:
		_current_pos = drag.position
		_set_pointer(drag.position)
		if _long_press_triggered:
			_send_mouse_motion(_current_pos, drag.relative, MOUSE_BUTTON_MASK_RIGHT)
		elif _panning:
			# A pan that slid off its spot is no tap on the spot it ends on.
			if _current_pos.distance_to(_start_pos) > drag_threshold:
				_tap_vetoed = true
		elif not _drag_started:
			if _current_pos.distance_to(_start_pos) > drag_threshold:
				_drag_started = true
				_send_mouse_motion(_start_pos, Vector2.ZERO, 0)
				_send_mouse_button(MOUSE_BUTTON_LEFT, true, _start_pos)
				_send_mouse_motion(_current_pos, drag.relative, MOUSE_BUTTON_MASK_LEFT)
		else:
			_send_mouse_motion(_current_pos, drag.relative, MOUSE_BUTTON_MASK_LEFT)

	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()

func _cancel_touch() -> void:
	if not _active:
		return
	if _long_press_triggered:
		_send_mouse_button(MOUSE_BUTTON_RIGHT, false, _current_pos)
	elif _drag_started:
		_send_mouse_button(MOUSE_BUTTON_LEFT, false, _current_pos)
	_reset_touch()

func _set_pointer(pos: Vector2) -> void:
	_pointer = pos
	_has_pointer = true

func _reset_touch() -> void:
	_active = false
	_touch_index = -1
	_down_msec = 0
	_long_press_triggered = false
	_drag_started = false
	_panning = false
	_tap_vetoed = false

func _get_target_viewport() -> Viewport:
	var vp := get_viewport()
	if vp != null:
		return vp
	var tree := get_tree()
	if tree != null and tree.root != null:
		return tree.root
	var main_loop := Engine.get_main_loop() as SceneTree
	if main_loop != null:
		return main_loop.root
	return null

func _send_mouse_button(button_index: MouseButton, pressed: bool, pos: Vector2, double_click: bool = false) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = button_index
	mb.pressed = pressed
	mb.double_click = double_click
	_set_pointer(pos)
	mb.position = pos
	mb.global_position = pos
	mb.device = InputEvent.DEVICE_ID_EMULATION
	var mask := 0
	if pressed:
		if button_index == MOUSE_BUTTON_LEFT:
			mask = MOUSE_BUTTON_MASK_LEFT
		elif button_index == MOUSE_BUTTON_RIGHT:
			mask = MOUSE_BUTTON_MASK_RIGHT
	mb.button_mask = mask
	var vp := _get_target_viewport()
	if vp != null:
		vp.push_input(mb, true)

func _send_mouse_motion(pos: Vector2, relative: Vector2, button_mask: int) -> void:
	_set_pointer(pos)
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	mm.relative = relative
	mm.button_mask = button_mask
	mm.device = InputEvent.DEVICE_ID_EMULATION
	var vp := _get_target_viewport()
	if vp != null:
		vp.push_input(mm, true)

## Helper for unit tests to simulate a touch down event.
func simulate_touch_down(pos: Vector2, index: int = 0) -> void:
	var touch := InputEventScreenTouch.new()
	touch.position = pos
	touch.pressed = true
	touch.index = index
	_input(touch)

## Helper for unit tests to simulate a touch up event.
func simulate_touch_up(pos: Vector2, index: int = 0) -> void:
	var touch := InputEventScreenTouch.new()
	touch.position = pos
	touch.pressed = false
	touch.index = index
	_input(touch)

## Helper for unit tests to simulate a touch drag event.
func simulate_touch_drag(pos: Vector2, rel: Vector2 = Vector2.ZERO, index: int = 0) -> void:
	var drag := InputEventScreenDrag.new()
	drag.position = pos
	drag.relative = rel
	drag.index = index
	_input(drag)
