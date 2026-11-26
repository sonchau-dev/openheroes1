extends Node
## Puts the 640x480 frame on screen with sharp-bilinear scaling.
##
## The root window keeps rendering at 640x480 (stretch mode "viewport"), so
## input, layout and screenshots never see the window size. Godot's own
## upscale is nearest-neighbour at a fractional factor, which makes some source
## pixels one screen pixel wider than others (at 2.25x every fourth row is 3 px
## tall and the rest 2 px). This node draws a second, window-sized viewport on
## top of the root's, where a screen pixel that straddles two source pixels
## shows its share of each: every source pixel comes out the same size, flat
## inside, with one screen pixel of blend at its edges. At a whole-number scale
## the result is plain nearest-neighbour.

const SHADER := preload("res://src/game/sharp_bilinear.gdshader")
const BASE := Vector2i(640, 480)

var _viewport: RID
var _canvas: RID
var _backdrop: RID
var _frame: RID
var _material: ShaderMaterial
var _window_size := Vector2i.ZERO

func _ready() -> void:
	var rs := RenderingServer
	var root_viewport := get_tree().root.get_viewport_rid()
	_viewport = rs.viewport_create()
	rs.viewport_set_active(_viewport, true)
	rs.viewport_set_update_mode(_viewport, RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	rs.viewport_set_transparent_background(_viewport, false)
	rs.viewport_set_disable_3d(_viewport, true)
	# Viewports render children first, so this makes the root's frame ready
	# before it is sampled and keeps our blit after the root's on screen.
	rs.viewport_set_parent_viewport(root_viewport, _viewport)
	_canvas = rs.canvas_create()
	rs.viewport_attach_canvas(_viewport, _canvas)
	_backdrop = rs.canvas_item_create()
	rs.canvas_item_set_parent(_backdrop, _canvas)
	_frame = rs.canvas_item_create()
	rs.canvas_item_set_parent(_frame, _canvas)
	# The shader blends texels itself; it reads them at their centres, so the
	# filter must not mix in a neighbour.
	rs.canvas_item_set_default_texture_filter(_frame, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	rs.canvas_item_set_material(_frame, _material.get_rid())
	_layout()

func _process(_delta: float) -> void:
	if DisplayServer.window_get_size() != _window_size:
		_layout()

func _exit_tree() -> void:
	var rs := RenderingServer
	rs.viewport_set_parent_viewport(get_tree().root.get_viewport_rid(), RID())
	for rid in [_frame, _backdrop, _canvas, _viewport]:
		rs.free_rid(rid)

func _layout() -> void:
	var rs := RenderingServer
	_window_size = DisplayServer.window_get_size()
	var rect := present_rect(_window_size)
	rs.viewport_set_size(_viewport, _window_size.x, _window_size.y)
	rs.canvas_item_clear(_backdrop)
	rs.canvas_item_add_rect(_backdrop, Rect2(Vector2.ZERO, _window_size), Color.BLACK)
	rs.canvas_item_clear(_frame)
	var texture := rs.viewport_get_texture(get_tree().root.get_viewport_rid())
	rs.canvas_item_add_texture_rect(_frame, rect, texture)
	_material.set_shader_parameter("scale", Vector2(rect.size) / Vector2(BASE))
	rs.viewport_attach_to_screen(_viewport, Rect2(Vector2.ZERO, _window_size), DisplayServer.MAIN_WINDOW_ID)

## Where the root window puts its 640x480 frame in a window of `window` pixels:
## Window._update_viewport_size's arithmetic for stretch mode "viewport",
## aspect "keep", fractional scale. Mouse input is mapped through that rect, so
## the frame must land on exactly the same pixels.
static func present_rect(window: Vector2i) -> Rect2i:
	var base := Vector2(BASE)
	var video := Vector2(window)
	var screen := video
	var base_aspect := base.aspect()
	if not is_equal_approx(base_aspect, video.aspect()):
		if base_aspect < video.aspect():
			screen = Vector2(video.y * base_aspect, video.y)
		else:
			screen = Vector2(video.x, video.x / base_aspect)
	screen = screen.floor()
	var margin := Vector2.ZERO
	if screen.x < video.x:
		margin.x = roundf((video.x - screen.x) / 2.0)
	if screen.y < video.y:
		margin.y = roundf((video.y - screen.y) / 2.0)
	return Rect2i(Vector2i(margin), Vector2i(screen))
