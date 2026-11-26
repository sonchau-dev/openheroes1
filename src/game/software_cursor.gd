class_name SoftwareCursor
extends CanvasLayer

## In-engine software cursor (HOMM1 advmice.icn id 0).
## Renders a pixel-perfect 1:1 cursor sprite at layer 4096.

const POINTER := "res://assets/art/advmice/0000.png"

var _cursor_sprite: Sprite2D = null
var _cursor_hotspot: Vector2 = Vector2.ZERO
var _cursor_hidden_override: bool = false

## The cursor the game asked for last. The sprite only exists when there is a
## window, so headless tests read this instead of the sprite.
var current_texture: Texture2D = null
var current_hotspot: Vector2 = Vector2.ZERO

func _init() -> void:
	layer = 4096

func setup() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _cursor_sprite != null:
		return
	_cursor_sprite = Sprite2D.new()
	_cursor_sprite.centered = false
	_cursor_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_cursor_sprite)
	# Clear any OS custom hardware cursors so only the in-engine software cursor is used.
	Input.set_custom_mouse_cursor(null)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)
	if DevFlags.shot_mode():
		_cursor_sprite.visible = false
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

## Explicitly hide or show the in-game cursor (e.g. during resource pickup animation).
## When hidden via override, mouse motion events will not restore visibility until unhidden.
func set_cursor_visible(p_visible: bool) -> void:
	_cursor_hidden_override = not p_visible
	if DisplayServer.get_name() == "headless":
		return
	if _cursor_sprite != null and not DevFlags.shot_mode():
		_cursor_sprite.visible = p_visible and (_cursor_sprite.texture != null)
		if p_visible:
			_cursor_sprite.position = Pointer.position(get_viewport()) - _cursor_hotspot
	if not DevFlags.shot_mode():
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

func is_cursor_visible() -> bool:
	return not _cursor_hidden_override

## Sets the in-game cursor texture and hotspot, ensuring pixel-perfect 1:1 ratio
## relative to the 640x480 game resolution regardless of window/Retina display scaling.
func set_cursor(tex: Texture2D, hotspot: Vector2 = Vector2.ZERO) -> void:
	current_texture = tex
	current_hotspot = hotspot
	if DisplayServer.get_name() == "headless":
		return
	_cursor_hotspot = hotspot
	if _cursor_sprite != null:
		_cursor_sprite.texture = tex
		_cursor_sprite.position = Pointer.position(get_viewport()) - _cursor_hotspot
		if not DevFlags.shot_mode():
			_cursor_sprite.visible = (tex != null) and not _cursor_hidden_override
	if not DevFlags.shot_mode() and Input.get_mouse_mode() != Input.MOUSE_MODE_HIDDEN:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

## Apply the HOMM1 pointer as the game-wide default cursor. Scenes that swap in
## context cursors (e.g. the adventure map) should call this on exit to restore it.
func set_default_cursor() -> void:
	# Absent until the art is imported, as in the tool processes tools/setup.gd runs.
	if not ResourceLoader.exists(POINTER):
		return
	var tex := load(POINTER) as Texture2D
	if tex != null:
		set_cursor(tex, Vector2.ZERO)

func _notification(what: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	match what:
		NOTIFICATION_WM_MOUSE_EXIT, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if _cursor_sprite != null:
				_cursor_sprite.visible = false
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		NOTIFICATION_WM_MOUSE_ENTER, NOTIFICATION_APPLICATION_FOCUS_IN:
			if _cursor_sprite != null and not DevFlags.shot_mode() and _cursor_sprite.texture != null and not _cursor_hidden_override:
				_cursor_sprite.visible = true
				Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

func _input(event: InputEvent) -> void:
	if _cursor_sprite == null or DevFlags.shot_mode():
		return
	if event is InputEventMouseMotion:
		var mpos := Pointer.position(get_viewport())
		_cursor_sprite.position = mpos - _cursor_hotspot
		if not _cursor_hidden_override and _cursor_sprite.texture != null:
			if not _cursor_sprite.visible:
				_cursor_sprite.visible = true
			if Input.get_mouse_mode() != Input.MOUSE_MODE_HIDDEN:
				Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

func _process(_delta: float) -> void:
	if _cursor_sprite != null and _cursor_sprite.visible and not DevFlags.shot_mode():
		_cursor_sprite.position = Pointer.position(get_viewport()) - _cursor_hotspot
