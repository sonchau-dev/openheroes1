extends SceneTree

## Builds what the game needs from a copy of HOMM1: art, sound effects and
## scenarios. First put one of these under external_resources/:
##
##   - the 1995 CD demo, hommdemo-cd.zip, as downloaded
##   - your own DOS install, unpacked anywhere inside external_resources/homm1game/
##
##   godot --headless --path . --script tools/setup.gd
##   godot --headless --path . --script tools/setup.gd -- --with-music --with-video
##
## Flags:
##   --with-music   also convert the demo's streamed music to .wav (about 60 MB)
##   --with-video   also convert the demo's .smk cinematics to .ogv
##                  (opens a window for a few seconds)
##
## A fresh checkout has no class cache, so this script uses no class_name
## globals and runs every tool that does in its own Godot process.

const AggPaths := preload("res://tools/extract/agg_paths.gd")
const RESOURCES := "res://external_resources"
const INSTALL := "res://external_resources/homm1game"
const MAPS := "res://assets/maps"
## Godot's import first prepares the files, then imports them. Preparing took
## about a third of the import on a Mac, so it fills the first 30% of the bar.
const PREPARE_SHARE := 30


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var with_music := args.has("--with-music")
	var with_video := args.has("--with-video")
	print("==================================================")
	print("  OpenHeroes1 setup")
	print("==================================================")

	var demo := _find_demo_zip()
	if demo != "" and not _unpack_demo(demo, _find_agg(), with_music, with_video):
		quit(1)
		return

	var agg := _find_agg()
	if agg == "":
		printerr("No copy of HOMM1 found. Put one of these in external_resources/ and run this again:")
		printerr("  - the demo, hommdemo-cd.zip, from")
		printerr("    https://www.dosgamesarchive.com/file/heroes-of-might-and-magic-a-strategic-quest/hommdemo-cd")
		printerr("  - your own install, unpacked into external_resources/homm1game/")
		quit(1)
		return
	print("\nUsing %s" % agg.trim_prefix("res://"))
	print("  Copied %d scenarios to assets/maps/" % _copy_maps(agg.get_base_dir().get_base_dir()))

	# The tools use class_name globals, which exist only after an import builds the class cache.
	# Every tool process also starts the game's autoloads, which load the cursor and font
	# art, so the art is imported before the next tool runs.
	for step: Array in [
		["Building the class cache", ["--import"]],
		["Extracting art and sound", ["--script", "tools/extract.gd", "--",
				"--agg=" + ProjectSettings.globalize_path(agg)]],
		["Importing the art", ["--import"]],
		["Converting scenarios", ["--script", "tools/map_convert.gd"]],
	]:
		var code := _godot(step[0], step[1])
		if code != 0:
			printerr("%s failed with exit code %d" % [step[0], code])
			quit(code)
			return
	# Music and cinematics are optional: a failed conversion leaves the game without them.
	if with_music and _godot("Converting music", ["--script", "tools/convert_music.gd"]) != 0:
		print("Some music did not convert; the game plays without it.")
	if with_video and _godot("Converting cinematics", ["--script", "tools/convert_videos.gd"]) != 0:
		print("Some videos did not convert; the game skips missing cinematics.")
	if with_music or with_video:
		var code := _godot("Importing the music and cinematics", ["--import"])
		if code != 0:
			printerr("Godot import failed with exit code %d" % code)
			quit(code)
			return

	print("\n==================================================")
	print("  Setup Complete!")
	print("==================================================")
	print("You can now close this window.\n")
	quit(0)


## Runs this Godot binary on the project and returns its exit code. Output is
## echoed line by line as it comes, minus the import's progress lines: the
## Windows console draws the 12000 of them slowly. An import prints its
## overall percentage every 10% instead, so it never looks stuck.
func _godot(title: String, args: Array) -> int:
	print("\n--- %s ---" % title)
	var started := Time.get_ticks_msec()
	var proc := OS.execute_with_pipe(OS.get_executable_path(),
			["--headless", "--path", ProjectSettings.globalize_path("res://")] + args, false)
	if proc.is_empty():
		return -1
	# Both pipes are drained in turn: one left full would stall the child.
	var pipes: Array[FileAccess] = [proc["stdio"], proc["stderr"]]
	var partial: Array[String] = ["", ""]
	var shown := 0
	while true:
		var running := OS.is_process_running(proc["pid"])
		var got := false
		for i in pipes.size():
			var chunk := pipes[i].get_buffer(65536)
			if chunk.is_empty():
				continue
			got = true
			var lines: PackedStringArray = (partial[i] + chunk.get_string_from_utf8()).split("\n")
			partial[i] = lines[lines.size() - 1]
			for line in lines.slice(0, lines.size() - 1):
				if not _is_progress(line):
					print(line)
					continue
				var progress := _import_progress(line)
				if progress.is_empty():
					continue
				# Godot prepares the files, then imports them, each counting from 0%.
				# One overall figure that only climbs reads better than two.
				var overall: int = 100 if progress[0] == "done" \
						else progress[1] * PREPARE_SHARE / 100 if progress[0] == "preparing" \
						else PREPARE_SHARE + progress[1] * (100 - PREPARE_SHARE) / 100
				if overall >= shown + 10 or (overall == 100 and shown < 100):
					shown = overall - overall % 10
					print("  importing: %d%%" % shown)
		if not got:
			if not running:
				break
			OS.delay_msec(50)
	for rest: String in partial:
		if rest != "" and not _is_progress(rest):
			print(rest)
	print("  took %d s" % ((Time.get_ticks_msec() - started) / 1000))
	return OS.get_process_exit_code(proc["pid"])


## The import's progress bar, "[  97% ] reimport | 0010.png" and "[ DONE ]",
## drawn in colour.
static func _is_progress(line: String) -> bool:
	var plain := _plain(line)
	return plain.begins_with("[") or plain == ""


## `line` without its colour codes. They go before the trim: strip_edges also
## drops the escape character that starts one and leaves the rest behind.
static func _plain(line: String) -> String:
	return RegEx.create_from_string("\u001b\\[[0-9;]*m").sub(line, "", true).strip_edges()


## ["preparing" or "importing", percent] for an import progress line,
## "[  45% ] reimport | Preparing files to reimport..." or
## "[  45% ] reimport | 0010.png"; ["done", 100] for "[ DONE ] reimport";
## else [].
static func _import_progress(line: String) -> Array:
	var plain := _plain(line)
	if plain.begins_with("[ DONE ] reimport"):
		return ["done", 100]
	var found := RegEx.create_from_string("^\\[\\s*(\\d+)% \\]\\s+reimport \\| (.*)").search(plain)
	if found == null:
		return []
	# "Started (Re)Importing Assets" opens the task at 0%, before preparing.
	var text := found.get_string(2)
	var phase := "preparing" if text.begins_with("Preparing") or text.begins_with("Started") else "importing"
	return [phase, int(found.get_string(1))]


## The install's heroes.agg: a known layout first, else the first one found
## anywhere under external_resources/homm1game/, so any unpacked copy works.
func _find_agg() -> String:
	for candidate: String in AggPaths.CANDIDATES:
		if FileAccess.file_exists(candidate):
			return candidate
	return _search(INSTALL, "heroes.agg")


func _search(dir: String, lower_name: String) -> String:
	if not DirAccess.dir_exists_absolute(dir):
		return ""
	for file in DirAccess.get_files_at(dir):
		if file.to_lower() == lower_name:
			return dir.path_join(file)
	for sub in DirAccess.get_directories_at(dir):
		var found := _search(dir.path_join(sub), lower_name)
		if found != "":
			return found
	return ""


## The first zip in external_resources/ that holds a heroes.agg, or "".
func _find_demo_zip() -> String:
	if not DirAccess.dir_exists_absolute(RESOURCES):
		return ""
	for file in DirAccess.get_files_at(RESOURCES):
		if not file.to_lower().ends_with(".zip"):
			continue
		var reader := ZIPReader.new()
		if reader.open(RESOURCES.path_join(file)) != OK:
			continue
		var found := _agg_entry(reader) != ""
		reader.close()
		if found:
			return RESOURCES.path_join(file)
	return ""


func _agg_entry(reader: ZIPReader) -> String:
	for file_path in reader.get_files():
		var lower := file_path.to_lower()
		if lower == "heroes/data/heroes.agg" or lower == "data/heroes.agg":
			return file_path
	return ""


## Unpacks the demo into external_resources/homm1game/ in the flat install layout.
func _unpack_demo(zip_path: String, tree_agg: String, with_music: bool, with_video: bool) -> bool:
	print("\nUnpacking %s..." % zip_path.trim_prefix("res://"))
	var reader := ZIPReader.new()
	var err := reader.open(zip_path)
	if err != OK:
		printerr("Cannot open %s (error %d)" % [zip_path, err])
		return false

	# The 1995 CD demo and the retail DOS install are two different builds of
	# HOMM1. The demo's heroes.agg, heroes.exe and maps are only the right ones
	# to install when the tree holds no install of its own: the retail build is
	# the reference the knowledge base decodes offsets from, and the demo's extra
	# "Civil War" scenario is not part of this port. A tree archive with a
	# different hash is a player install, so only the media the demo has and
	# retail does not is added: the streamed music and the slot cinematics.
	var media_only := tree_agg != "" and FileAccess.get_sha256(ProjectSettings.globalize_path(tree_agg)) \
			!= _sha256(reader.read_file(_agg_entry(reader)))
	if media_only:
		print("  external_resources/homm1game/ holds your own install, so only the")
		print("  demo's music and cinematics are added. Your game data is left alone.")

	for dir in ["data", "maps", "sound", "anim"]:
		DirAccess.make_dir_recursive_absolute(INSTALL.path_join(dir))
	for file_path in reader.get_files():
		var lower := file_path.to_lower()
		var dest := ""
		if lower == "heroes/data/heroes.agg" or lower == "data/heroes.agg":
			dest = "data/heroes.agg"
		elif lower == "heroes/heroes.exe" or lower == "heroes.exe":
			dest = "heroes.exe"
		elif (lower.begins_with("heroes/maps/") or lower.begins_with("maps/")) \
				and (lower.ends_with(".map") or lower.ends_with(".cmp")):
			dest = "maps/" + lower.get_file()
		elif with_music and "/sound/heroes" in lower and lower.ends_with(".82m"):
			dest = "sound/" + lower.get_file()
		elif with_video and "anim/" in lower and lower.ends_with(".smk"):
			dest = "anim/" + lower.get_file()
		if dest == "" or (media_only and not (dest.begins_with("sound/") or dest.begins_with("anim/"))):
			continue
		var f := FileAccess.open(INSTALL.path_join(dest), FileAccess.WRITE)
		if f == null:
			printerr("Cannot write %s (error %d)" % [dest, FileAccess.get_open_error()])
			reader.close()
			return false
		f.store_buffer(reader.read_file(file_path))
		f.close()
	reader.close()
	return true


## Copies the install's .map and .cmp files into assets/maps/, lower case,
## since the scenarios are read by name. Returns how many it copied.
func _copy_maps(install_root: String) -> int:
	DirAccess.make_dir_recursive_absolute(MAPS)
	var copied := 0
	for dir in DirAccess.get_directories_at(install_root):
		if dir.to_lower() != "maps":
			continue
		var src := install_root.path_join(dir)
		for file in DirAccess.get_files_at(src):
			var lower := file.to_lower()
			if (lower.ends_with(".map") or lower.ends_with(".cmp")) \
					and DirAccess.copy_absolute(src.path_join(file), MAPS.path_join(lower)) == OK:
				copied += 1
	return copied


## SHA256 of a byte buffer, as hex. PackedByteArray has no hash method.
func _sha256(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish().hex_encode()
