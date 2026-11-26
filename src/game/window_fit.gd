extends Node
## Opens the window at the largest whole multiple of the 640x480 base that fits
## the screen, centred, and toggles fullscreen on F11. Runs per machine at
## launch so one committed project.godot works on a Mac Retina screen and a
## 1920x1080 Linux one alike. SharpScaler then puts the frame on screen.
## On Linux the window starts fixed-size (project.godot) so a tiling desktop
## floats it at that size instead of tiling it at a fraction, and it becomes
## resizable once it is on screen.
## F12 saves the 640x480 frame as drawn, before any window scaling, to a
## numbered PNG on the desktop (user://screenshots where there is none).

const SharpScaler := preload("res://src/game/sharp_scaler.gd")

const BASE := Vector2i(640, 480)
## Room left for the title bar, in points; multiplied by the screen scale.
const TITLE_BAR := 40
## Frames the window stays fixed-size, long enough for the desktop to place it.
const UNLOCK_FRAMES := 30

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	add_child(SharpScaler.new())
	# Screenshot runs read the 640x480 frame, not the window; leave it alone.
	var size := Vector2i.ZERO
	if not (OS.has_feature("mobile") or DevFlags.shot_mode()) \
			and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_min_size(BASE)
		var screen := DisplayServer.window_get_current_screen()
		var usable := DisplayServer.screen_get_usable_rect(screen)
		var chrome := int(TITLE_BAR * DisplayServer.screen_get_scale(screen))
		size = BASE * fit_scale(usable.size - Vector2i(0, chrome))
		DisplayServer.window_set_size(size)
		DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)
	_unlock_resize(size)

## Keeps the window fixed at `size` (zero: whatever it has) while the desktop
## places it, then hands resizing back to the player. The size is asked for
## again each frame because a desktop's first placement can arrive after ours
## and undo it.
func _unlock_resize(size: Vector2i) -> void:
	for _i in UNLOCK_FRAMES:
		await get_tree().process_frame
		if size != Vector2i.ZERO and DisplayServer.window_get_size() != size \
				and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_size(size)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, false)

## The largest whole multiple of BASE that fits in `available`, at least 1.
static func fit_scale(available: Vector2i) -> int:
	return maxi(1, mini(available.x / BASE.x, available.y / BASE.y))

func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_F11:
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		KEY_F12:
			_save_screenshot()
		_:
			return
	get_viewport().set_input_as_handled()

func _save_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	if dir.is_empty() or not DirAccess.dir_exists_absolute(dir):
		dir = ProjectSettings.globalize_path("user://screenshots")
		DirAccess.make_dir_recursive_absolute(dir)
	var path := next_screenshot_path(dir)
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("SCREENSHOT ", path if err == OK else "failed: %s" % error_string(err))

## The first homm1_NNNN.png in `dir` that does not exist yet.
static func next_screenshot_path(dir: String) -> String:
	var n := 1
	while FileAccess.file_exists(dir.path_join("homm1_%04d.png" % n)):
		n += 1
	return dir.path_join("homm1_%04d.png" % n)
