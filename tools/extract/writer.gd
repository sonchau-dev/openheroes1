extends RefCounted

## Everything that touches disk.
##
## No decoder writes a file and no writer decodes one. That split is what lets
## the parity check decode the whole archive and compare it in memory instead
## of writing 62 MB to a temporary tree to diff it, and it is what lets the
## expectation checker inspect a directory before any of it lands.
##
## The writer also remembers what it produced, so a rerun can delete whatever
## it did not. Wiping the tree instead would be simpler and wrong: it throws
## away Godot's .import sidecars and turns every run into a full reimport.

var root: String
var dry_run: bool
var written: PackedStringArray = PackedStringArray()
var errors: Array[String] = []

## Optional flat copy of every PNG, one directory deep, for browsing 5855
## frames without opening 338 folders. Nothing loads from it.
var mirror_root := ""
var mirrored := 0

var _dirs := {}


func _init(out_root: String, dry := false, flat_mirror := "") -> void:
	root = out_root.trim_suffix("/")
	dry_run = dry
	mirror_root = flat_mirror.trim_suffix("/")
	if not dry_run:
		DirAccess.make_dir_recursive_absolute(_absolute(""))
		if mirror_root != "":
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(mirror_root))


## `as_image` imports the PNG as an Image rather than a texture, for code that
## needs the pixels: reading a texture's back from the GPU is slow on phones.
func image(path: String, img: Image, as_image := false) -> bool:
	if not _prepare(path):
		return false
	if dry_run:
		return _record(path)
	var err := img.save_png(_absolute(path))
	if err != OK:
		return _failed(path, "save_png returned %d" % err)
	if as_image:
		var sidecar_path := _absolute(path) + ".import"
		# Godot fills in the rest on import; rewriting it each run would reimport.
		if not FileAccess.file_exists(sidecar_path) \
				or not FileAccess.get_file_as_string(sidecar_path).contains("importer=\"image\""):
			var sidecar := FileAccess.open(sidecar_path, FileAccess.WRITE)
			if sidecar == null:
				return _failed(path, "cannot write its .import (error %d)" % FileAccess.get_open_error())
			sidecar.store_string("[remap]\n\nimporter=\"image\"\n")
			sidecar.close()
	_mirror(path)
	return _record(path)


## Mono, 8-bit unsigned, one byte per sample, so the byte rate is the sample
## rate and the block align is one.
func wav(path: String, pcm: PackedByteArray, rate: int) -> bool:
	if not _prepare(path):
		return false
	if dry_run:
		return _record(path)
	var f := FileAccess.open(_absolute(path), FileAccess.WRITE)
	if f == null:
		return _failed(path, "cannot open for writing (error %d)" % FileAccess.get_open_error())
	# RIFF pads an odd-sized chunk to an even length; Godot's importer seeks past it.
	var pad := pcm.size() % 2
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + pcm.size() + pad)
	f.store_buffer("WAVE".to_ascii_buffer())
	f.store_buffer("fmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(1)
	f.store_32(rate)
	f.store_32(rate)
	f.store_16(1)
	f.store_16(8)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(pcm.size())
	f.store_buffer(pcm)
	if pad:
		f.store_8(0)
	f.close()
	return _record(path)


func raw(path: String, data: PackedByteArray) -> bool:
	if not _prepare(path):
		return false
	if dry_run:
		return _record(path)
	var f := FileAccess.open(_absolute(path), FileAccess.WRITE)
	if f == null:
		return _failed(path, "cannot open for writing (error %d)" % FileAccess.get_open_error())
	f.store_buffer(data)
	f.close()
	if path.ends_with(".fnt"):
		# Godot would import a HOMM1 .fnt as a BMFont and crashes on it on Windows.
		var sidecar := FileAccess.open(_absolute(path) + ".import", FileAccess.WRITE)
		if sidecar == null:
			return _failed(path, "cannot write its .import (error %d)" % FileAccess.get_open_error())
		sidecar.store_string("[remap]\n\nimporter=\"skip\"\n")
		sidecar.close()
	return _record(path)


func json(path: String, value: Variant) -> bool:
	return raw(path, (JSON.stringify(value, "", false) + "\n").to_utf8_buffer())


## Deletes anything under the output root this run did not produce, and
## reports what went. A sidecar goes only when the file it belongs to has
## gone, so an untouched tree survives a rerun with its import cache intact.
func sweep() -> PackedStringArray:
	var keep := {}
	for path in written:
		keep[path] = true
	var removed := PackedStringArray()
	for path in _walk(""):
		if keep.has(path):
			continue
		if path.ends_with(".import") or path.ends_with(".uid"):
			if keep.has(path.get_basename() if path.ends_with(".uid") else path.trim_suffix(".import")):
				continue
		removed.append(path)
		if not dry_run:
			DirAccess.remove_absolute(_absolute(path))
	removed.sort()
	return removed


func _walk(relative: String) -> PackedStringArray:
	var found := PackedStringArray()
	var base := _absolute(relative).trim_suffix("/")
	if not DirAccess.dir_exists_absolute(base):
		return found
	for file in DirAccess.get_files_at(base):
		found.append(file if relative == "" else "%s/%s" % [relative, file])
	for dir in DirAccess.get_directories_at(base):
		found.append_array(_walk(dir if relative == "" else "%s/%s" % [relative, dir]))
	return found


func _prepare(path: String) -> bool:
	var dir := path.get_base_dir()
	if dir == "" or _dirs.has(dir) or dry_run:
		return true
	var err := DirAccess.make_dir_recursive_absolute(_absolute(dir))
	if err != OK:
		return _failed(path, "cannot create %s (error %d)" % [dir, err])
	_dirs[dir] = true
	return true


## The mirror name keeps the directory in it, so art/archer.std/0001.png
## browses as art_archer.std_0001.png and still says where it came from.
func _mirror(path: String) -> void:
	if mirror_root == "" or not path.ends_with(".png"):
		return
	var flat := "art_%s" % path.replace("/", "_")
	var err := DirAccess.copy_absolute(_absolute(path),
		ProjectSettings.globalize_path("%s/%s" % [mirror_root, flat]))
	if err == OK:
		mirrored += 1
	else:
		_failed(flat, "cannot copy into the flat mirror (error %d)" % err)


func _record(path: String) -> bool:
	written.append(path)
	return true


func _failed(path: String, reason: String) -> bool:
	errors.append("%s: %s" % [path, reason])
	return false


func _absolute(path: String) -> String:
	var joined := root if path == "" else "%s/%s" % [root, path]
	return ProjectSettings.globalize_path(joined) if joined.begins_with("res://") \
		or joined.begins_with("user://") else joined
