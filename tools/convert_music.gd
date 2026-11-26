extends SceneTree

## Turns HOMM1's streamed music (HEROES\SOUND\heroesNN.82m) into the WAV files
## MusicPlayer plays.
##
##   godot --headless --path . --script tools/convert_music.gd
##   godot --headless --path . --script tools/convert_music.gd -- --sound-dir=/path/to/sound
##
## Flags:
##   --sound-dir=DIR  where the .82m files are, default the first of SOUND_DIRS
##   --out-dir=DIR    where the .wav files go, default assets/music
##
## Only the 8-bit mono set is read: it is the only one the 1995 CD demo has,
## and the DOS Compendium kept only it (homm1-native-data.md 6.1). A track is
## headerless signed 8-bit PCM at 22050 Hz, the same bytes as the sound
## effects, so it goes through the extractor's own sound decoder and writer.

const Sound := preload("res://tools/extract/sound.gd")
const Writer := preload("res://tools/extract/writer.gd")

# The demo on-ramp unpacks to the first; a retail install keeps the second.
const SOUND_DIRS := [
	"res://external_resources/homm1game/sound",
	"res://external_resources/homm1game/game/Resources/hmm/sound",
]
const DEFAULT_OUT := "res://assets/music"
const RATE := 22050


func _initialize() -> void:
	var sound_dir := ""
	var out_dir := DEFAULT_OUT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sound-dir="):
			sound_dir = arg.trim_prefix("--sound-dir=")
		elif arg.begins_with("--out-dir="):
			out_dir = arg.trim_prefix("--out-dir=")
		else:
			push_error("unknown argument: %s" % arg)
			quit(2)
			return
	if sound_dir == "":
		for candidate: String in SOUND_DIRS:
			if DirAccess.dir_exists_absolute(candidate):
				sound_dir = candidate
				break
	if sound_dir == "" or not DirAccess.dir_exists_absolute(sound_dir):
		print("No sound directory found; no music converted. Pass --sound-dir, or put the CD's HEROES\\SOUND files in one of:")
		for candidate: String in SOUND_DIRS:
			print("  %s" % ProjectSettings.globalize_path(candidate))
		quit(0)
		return

	var writer := Writer.new(out_dir)
	var converted := 0
	var seconds := 0.0
	for file in DirAccess.get_files_at(sound_dir):
		var stem := file.get_basename().to_lower()
		if file.get_extension().to_lower() != "82m" or not stem.begins_with("heroes"):
			continue
		var decoded := Sound.decode(FileAccess.get_file_as_bytes(sound_dir.path_join(file)))
		if not decoded["ok"]:
			print("  [FAIL] %s: %s" % [file, decoded["error"]])
			continue
		var pcm: PackedByteArray = decoded["pcm"]
		if writer.wav(stem + ".wav", pcm, RATE):
			converted += 1
			seconds += pcm.size() / float(RATE)
	for error in writer.errors:
		print("  [FAIL] %s" % error)
	print("converted %d music tracks (%.0f minutes) -> %s" % [converted, seconds / 60.0,
			ProjectSettings.globalize_path(out_dir)])
	quit(1 if not writer.errors.is_empty() else 0)
