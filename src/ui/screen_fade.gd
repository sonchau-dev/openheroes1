class_name ScreenFade
extends CanvasLayer

## Full-screen black overlay for the original's palette fades. The DOS capture
## (campaign2.mov, 30 fps) fades out and in over 7 frames, 0.23 s, in a
## straight line.

const SECONDS := 0.23
## Black between a fade out and the next fade in, measured from the capture:
## 0.07 s from the congratulation screen to the briefing, 0.5 s from the
## briefing to the map.
const HOLD_BRIEFING := 0.07
const HOLD_MAP := 0.5

var _rect := ColorRect.new()
var _tween: Tween = null

func _init() -> void:
	layer = 400
	_rect.color = Color.BLACK
	_rect.size = Vector2(640, 480)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.modulate.a = 0.0
	add_child(_rect)

func set_black(black: bool) -> void:
	_rect.modulate.a = 1.0 if black else 0.0

func alpha() -> float:
	return _rect.modulate.a

## Fades to black (true) or from black (false); completes when the fade does.
func fade(to_black: bool, seconds: float = SECONDS) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_rect, "modulate:a", 1.0 if to_black else 0.0, seconds)
	await _tween.finished
