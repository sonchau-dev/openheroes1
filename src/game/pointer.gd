class_name Pointer
extends RefCounted
## Where the pointer is, in viewport pixels. Asks the TouchInput autoload by
## node path so scripts using it still compile in tests that skip autoloads.

static func position(vp: Viewport) -> Vector2:
	var touch: Node = null
	if vp != null and vp.get_tree() != null:
		touch = vp.get_tree().root.get_node_or_null("TouchInput")
	if touch != null:
		return touch.pointer_position(vp)
	return vp.get_mouse_position() if vp != null else Vector2.ZERO
