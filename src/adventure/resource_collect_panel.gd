# src/adventure/resource_collect_panel.gd
class_name ResourceCollectPanel
extends Control

## Bottom-right popup showing collected resource name, icon, and amount.
## Overlays the HeroPanel, relying on its background, and hides itself after 5 seconds.

const RESOURCE_ICONS := {
	"wood": UiKit.ART + "resource/0000.png",
	"mercury": UiKit.ART + "resource/0001.png",
	"ore": UiKit.ART + "resource/0002.png",
	"sulfur": UiKit.ART + "resource/0003.png",
	"crystal": UiKit.ART + "resource/0004.png",
	"gems": UiKit.ART + "resource/0005.png",
	"gold": UiKit.ART + "resource/0006.png",
}

signal popup_hidden

var _rect: Rect2
var _font: Font
var _current_res: String = ""
var _current_amount: int = 0
var _icon_texture: Texture2D

var _timer: Timer

func setup(rect: Rect2) -> void:
	_rect = rect
	_font = UiKit.font_small()
	
	# Match the target band position and size
	position = rect.position
	size = rect.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 5.0
	_timer.timeout.connect(dismiss)
	add_child(_timer)

func dismiss() -> void:
	if not visible:
		return
	if _timer != null:
		_timer.autostart = false
		_timer.stop()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup_hidden.emit()

func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed:
		accept_event()
		dismiss()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		dismiss()
	elif event is InputEventMouseButton and event.pressed:
		dismiss()

func show_resource(res: String, amount: int) -> void:
	_current_res = res
	_current_amount = amount
	var path: String = RESOURCE_ICONS.get(res, "")
	if path != "" and ResourceLoader.exists(path):
		_icon_texture = UiKit.load_texture(path)
	else:
		_icon_texture = null
		
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = true
	queue_redraw()
	if _timer != null:
		if _timer.is_inside_tree():
			_timer.start()
		else:
			_timer.autostart = true

func _draw() -> void:
	var w := _rect.size.x
	
	var line1 := ""
	var line2 := ""
	# heroes.exe message 0x36 for every resource, gold included.
	line1 = "You find a small"
	line2 = "quantity of %s." % _current_res
		
	# Draw text lines centered horizontally
	draw_string(_font, Vector2(0, 13), line1, HORIZONTAL_ALIGNMENT_CENTER, w, 11, Color.WHITE)
	draw_string(_font, Vector2(0, 23), line2, HORIZONTAL_ALIGNMENT_CENTER, w, 11, Color.WHITE)
	
	# Draw resource icon centered
	if _icon_texture != null:
		var iw := float(_icon_texture.get_width())
		var ih := float(_icon_texture.get_height())
		var ix := (w - iw) * 0.5
		# Center vertically in the space between line 2 (y=23) and bottom text (y=67), approx center y = 43
		var iy := 43.0 - ih * 0.5
		draw_texture_rect(_icon_texture, Rect2(Vector2(ix, iy), Vector2(iw, ih)), false)
		
	# Draw amount centered at the bottom
	draw_string(_font, Vector2(0, 67), str(_current_amount), HORIZONTAL_ALIGNMENT_CENTER, w, 11, Color.WHITE)
