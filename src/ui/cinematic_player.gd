class_name CinematicPlayer
extends Control

## Full-screen player for HOMM1's Smacker cinematics, transcoded to Theora
## .ogv by tools/convert_videos.gd.
##
## heroes.exe has eight video slots (name table at data 0x218f0, played by
## 0xd6ad3). Startup plays slot 0 or 1, then 2 or 3; finishing the campaign
## plays 4 or 5, then 6; a defeat plays 7; winning a scenario or a mission
## plays nothing (homm1-native-data.md section 6.3). Our heroes.exe has the
## slot names blanked, so the names below are the 1995 CD's HEROES\ANIM
## listing, paired in the order it gives. Within a pair the original picks by
## a machine-speed flag; we play the first variant the player has.
##
## Skip-on-input: any key (Esc, Space, Enter) or mouse button skips. A missing
## video finishes on the next step without stalling game flow or tests.

signal playback_finished(skipped: bool)

const DEFAULT_SIZE := Vector2(640, 480)
const VIDEO_DIR := "res://assets/video/"

## Each slot pair, in slot order.
const LOGO: Array[String] = ["nwclogo", "nwclogo1"]
const INTRO: Array[String] = ["intro02c", "intro02u"]
const CAMPAIGN_WIN: Array[String] = ["win01c", "win01u"]
const CAMPAIGN_WIN_2 := "win02"
const DEFEAT := "lose1"

var _bg: ColorRect = null
var _player: VideoStreamPlayer = null
var _queue: Array[String] = []
var _current_id: String = ""
var _is_playing: bool = false
var _skipped: bool = false


static func video_path(video_id: String) -> String:
	return VIDEO_DIR + video_id + ".ogv"


static func has_video(video_id: String) -> bool:
	return FileAccess.file_exists(video_path(video_id))


## The first video of a slot pair that `exists` accepts, or "".
static func pick(pair: Array[String], exists: Callable = has_video) -> String:
	for id: String in pair:
		if exists.call(id):
			return id
	return ""


static func intro_sequence(exists: Callable = has_video) -> Array[String]:
	return _present([pick(LOGO, exists), pick(INTRO, exists)])


static func campaign_win_sequence(exists: Callable = has_video) -> Array[String]:
	var second := CAMPAIGN_WIN_2 if exists.call(CAMPAIGN_WIN_2) else ""
	return _present([pick(CAMPAIGN_WIN, exists), second])


static func defeat_sequence(exists: Callable = has_video) -> Array[String]:
	return _present([DEFEAT if exists.call(DEFEAT) else ""])


static func _present(ids: Array) -> Array[String]:
	var out: Array[String] = []
	for id: String in ids:
		if id != "":
			out.append(id)
	return out


func _init() -> void:
	name = "CinematicPlayer"
	custom_minimum_size = DEFAULT_SIZE
	size = DEFAULT_SIZE
	mouse_filter = MOUSE_FILTER_STOP

	_bg = ColorRect.new()
	_bg.name = "Background"
	_bg.color = Color.BLACK
	_bg.size = DEFAULT_SIZE
	_bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_bg)

	_player = VideoStreamPlayer.new()
	_player.name = "StreamPlayer"
	_player.size = DEFAULT_SIZE
	_player.expand = true
	_player.bus = &"Master"
	_player.mouse_filter = MOUSE_FILTER_IGNORE
	_player.finished.connect(_on_stream_finished)
	add_child(_player)


func _ready() -> void:
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_playing:
		return
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key := (event as InputEventKey).keycode
		if key in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			get_viewport().set_input_as_handled()
			_skip()
	elif event is InputEventMouseButton and event.is_pressed():
		get_viewport().set_input_as_handled()
		_skip()


func play_video(video_id: String) -> void:
	_queue = [video_id]
	_play_next()


func play_sequence(video_ids: Array[String]) -> void:
	_queue = video_ids.duplicate()
	_play_next()

func _skip() -> void:
	_skipped = true
	if _player != null and _player.is_playing():
		_player.stop()
	# Skipping advances queue or ends if queue empty
	if not _queue.is_empty():
		_play_next()
	else:
		_finish_all()


func _play_next() -> void:
	if _queue.is_empty():
		_finish_all()
		return

	_current_id = _queue.pop_front()
	var path := video_path(_current_id)
	if not FileAccess.file_exists(path):
		_play_next()
		return

	var stream := load(path) as VideoStream
	if stream == null:
		_play_next()
		return


	# In headless mode (test runner / CI), VideoStreamPlayer has no display or audio clock to advance.
	# Instantly progress so headless runs never stall.
	if DisplayServer.get_name() == "headless":
		_play_next()
		return

	if not is_inside_tree():
		await tree_entered

	_is_playing = true
	_player.stream = stream
	_player.play()


func _on_stream_finished() -> void:
	if not _queue.is_empty():
		_play_next()
	else:
		_finish_all()


func _finish_all() -> void:
	_is_playing = false
	if _player != null:
		_player.stop()
	playback_finished.emit(_skipped)
