extends Control

## Plays one Smacker file for Movie Maker to record, so a cinematic becomes a
## Theora .ogv with no ffmpeg. tools/convert_videos.gd runs it as:
##
##   godot --path . --write-movie out.ogv --fixed-fps 30 \
##       res://tools/video/smk_movie.tscn -- --smk=/path/to/video.smk
##
## Movie Maker steps the engine one fixed frame at a time and mixes audio in
## step with it, so decoding speed does not matter. Each recorded frame shows
## the Smacker frame due at that moment, and the scene quits after the last.

const Smk := preload("res://tools/video/smk.gd")

const FPS := 30

var _smk: Smk
var _texture: ImageTexture
var _shown := -1
var _tick := 0
var _ticks := 0


func _ready() -> void:
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--smk="):
			path = arg.trim_prefix("--smk=")
	_smk = Smk.new()
	var opened := _smk.open(FileAccess.get_file_as_bytes(path))
	if not opened["ok"]:
		_abort("%s: %s" % [path, opened["error"]])
		return

	set_anchors_preset(Control.PRESET_FULL_RECT)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	var view := TextureRect.new()
	view.position = (Vector2(640, 480) - Vector2(_smk.width, _smk.height)) / 2
	add_child(view)
	if not _advance_to(0):
		return
	view.texture = _texture
	_ticks = ceili(_smk.frame_count * _smk.frame_ms * FPS / 1000.0)

	var sound := _smk.audio()
	if not sound["ok"]:
		_abort("%s: %s" % [path, sound["error"]])
		return
	var pcm: PackedByteArray = sound["pcm"]
	if pcm.is_empty():
		return
	var wav := AudioStreamWAV.new()
	wav.mix_rate = _smk.audio_rate
	wav.stereo = _smk.audio_channels == 2
	if _smk.audio_16bit:
		wav.format = AudioStreamWAV.FORMAT_16_BITS
	else:
		# Smacker's 8-bit samples are unsigned; AudioStreamWAV's are signed.
		wav.format = AudioStreamWAV.FORMAT_8_BITS
		for i in pcm.size():
			pcm[i] ^= 0x80
	wav.data = pcm
	var player := AudioStreamPlayer.new()
	player.stream = wav
	add_child(player)
	player.play()


func _process(_delta: float) -> void:
	if _ticks == 0:
		return
	_tick += 1
	if _tick >= _ticks:
		get_tree().quit(0)
		return
	var due := mini(int(_tick * 1000.0 / FPS / _smk.frame_ms), _smk.frame_count - 1)
	_advance_to(due)


func _advance_to(frame: int) -> bool:
	while _shown < frame:
		var decoded := _smk.next_frame()
		if not decoded["ok"]:
			_abort(decoded["error"])
			return false
		_shown += 1
		if _shown == frame:
			if _texture == null:
				_texture = ImageTexture.create_from_image(decoded["image"])
			else:
				_texture.update(decoded["image"])
	return true


func _abort(message: String) -> void:
	push_error(message)
	_ticks = 0
	get_tree().quit(1)
