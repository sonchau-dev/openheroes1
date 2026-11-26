class_name MapCamera
extends Camera2D

## Map camera clamped so the view never shows past map edges.

const PAN_SPEED := 400.0   # px/sec

var _map_px: Vector2 = Vector2.ZERO
var view_override: Vector2 = Vector2.ZERO   # when set, used for clamping instead of window

func setup(map: MapData) -> void:
	_map_px = map.pixel_size()
	position = clamp_pos(_map_px * 0.5, _view_size(), _map_px)

func effective_view(viewport: Vector2) -> Vector2:
	return view_override if view_override != Vector2.ZERO else viewport

func _view_size() -> Vector2:
	return effective_view(get_viewport_rect().size)

## Pure: keep camera center so the view stays inside [0, map_px]. Centers if map < view.
static func clamp_pos(pos: Vector2, view: Vector2, map_px: Vector2) -> Vector2:
	return Vector2(
		_clamp_axis(pos.x, view.x * 0.5, map_px.x),
		_clamp_axis(pos.y, view.y * 0.5, map_px.y)
	)

static func _clamp_axis(c: float, half: float, total: float) -> float:
	if total <= half * 2.0:
		return total * 0.5
	return clampf(c, half, total - half)

## Center on a world position, clamped to map bounds. Driven externally when following.
func center_on(world_pos: Vector2) -> void:
	position = clamp_pos(world_pos, _view_size(), _map_px)
