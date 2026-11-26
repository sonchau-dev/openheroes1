extends SceneTree

## Turns HOMM1's Smacker (.smk) cinematics into the Theora .ogv files
## CinematicPlayer plays, with no ffmpeg.
##
##   godot --headless --path . --script tools/convert_videos.gd
##   godot --headless --path . --script tools/convert_videos.gd -- --anim-dir=/path/to/anim
##
## Flags:
##   --anim-dir=DIR   where the .smk files are, default the first of ANIM_DIRS
##   --out-dir=DIR    where the .ogv files go, default assets/video
##
## Only the eight videos heroes.exe plays are converted (CinematicPlayer's
## slots, homm1-native-data.md section 6.3); other .smk files are reported and
## skipped. Each video is decoded by tools/video/smk.gd and recorded by a
## second Godot run in Movie Maker mode (tools/video/smk_movie.tscn). Movie
## Maker needs a renderer, so that run opens a window for a few seconds even
## when this one is headless. Without a display the videos are skipped and the
## game plays none, as it does without the files.

const Cinematics := preload("res://src/ui/cinematic_player.gd")

# The demo on-ramp unpacks to the first; a retail install keeps the second.
const ANIM_DIRS := [
	"res://external_resources/homm1game/anim",
	"res://external_resources/homm1game/game/Resources/hmm/anim",
]
const DEFAULT_OUT := "res://assets/video"
const MOVIE_SCENE := "res://tools/video/smk_movie.tscn"
const MOVIE_FPS := "30"


func _initialize() -> void:
	var anim_dir := ""
	var out_dir := DEFAULT_OUT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--anim-dir="):
			anim_dir = arg.trim_prefix("--anim-dir=")
		elif arg.begins_with("--out-dir="):
			out_dir = arg.trim_prefix("--out-dir=")
		else:
			push_error("unknown argument: %s" % arg)
			quit(2)
			return
	if anim_dir == "":
		for candidate: String in ANIM_DIRS:
			if DirAccess.dir_exists_absolute(candidate):
				anim_dir = candidate
				break
	if anim_dir == "" or not DirAccess.dir_exists_absolute(anim_dir):
		print("No anim directory found; no videos converted. Pass --anim-dir, or put the CD's HEROES\\ANIM files in one of:")
		for candidate: String in ANIM_DIRS:
			print("  %s" % ProjectSettings.globalize_path(candidate))
		quit(0)
		return

	var by_stem := {}
	for file in DirAccess.get_files_at(anim_dir):
		if file.get_extension().to_lower() == "smk":
			by_stem[file.get_basename().to_lower()] = anim_dir.path_join(file)
	var wanted: Array[String] = []
	wanted.append_array(Cinematics.LOGO)
	wanted.append_array(Cinematics.INTRO)
	wanted.append_array(Cinematics.CAMPAIGN_WIN)
	wanted.append_array([Cinematics.CAMPAIGN_WIN_2, Cinematics.DEFEAT])
	for stem: String in by_stem:
		if stem not in wanted:
			print("  [SKIP] %s: not one of heroes.exe's eight videos" % by_stem[stem].get_file())

	DirAccess.make_dir_recursive_absolute(out_dir)
	var godot := OS.get_executable_path()
	var root := ProjectSettings.globalize_path("res://")
	var converted := 0
	var failed := 0
	var missing: Array[String] = []
	for stem in wanted:
		if not by_stem.has(stem):
			missing.append(stem)
			continue
		var src := ProjectSettings.globalize_path(by_stem[stem])
		var dst := ProjectSettings.globalize_path(out_dir.path_join(stem + ".ogv"))
		var out: Array = []
		var code := OS.execute(godot, ["--path", root, "--write-movie", dst, "--fixed-fps", MOVIE_FPS,
				MOVIE_SCENE, "--", "--smk=" + src], out, true)
		if code == 0 and FileAccess.file_exists(dst):
			print("  [OK] %s -> %s (%d KB)" % [src.get_file(), dst.get_file(),
					FileAccess.get_file_as_bytes(dst).size() / 1024])
			converted += 1
		else:
			var log := str(out[0]) if not out.is_empty() else ""
			print("  [FAIL] %s (exit %d): %s" % [src.get_file(), code, log.strip_edges().right(300)])
			failed += 1
	if not missing.is_empty():
		print("  Not in this install: %s" % ", ".join(missing))
	print("converted %d of %d videos" % [converted, converted + failed])
	quit(1 if failed > 0 else 0)
