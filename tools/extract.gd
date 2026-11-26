extends SceneTree

## Turns a HOMM1 heroes.agg into the asset tree this game loads.
##
##   godot --headless --path . --script tools/extract.gd
##   godot --headless --path . --script tools/extract.gd -- --agg=/path/to/heroes.agg
##
## Flags:
##   --agg=PATH      the archive, defaulting to the DOS install this repo assumes
##   --out=DIR       where the tree goes, defaulting to res://assets/art
##   --decode-only   decode and check everything, write nothing
##   --dry-run       report what would be written, write nothing
##   --only=NAME     restrict to one archive entry, for debugging. The tree is
##                   left alone: a filtered run does not sweep
##   --no-sweep      keep files this run did not produce
##   --flat-mirror   also copy every PNG into one flat directory for browsing
##   --report=PATH   where the run report goes, defaulting to beside the tree
##   --rules=PATH    the rules and expectation tables, for the test fixture
##
## It does not go looking for the archive. A search that silently succeeds
## against the wrong file is the worst outcome available here, so a player who
## installed the game elsewhere gets one error naming the flag.
##
## Run it before `--import`, which is what lets the roughly 304
## load("res://assets/...") call sites in the game stay as they are.

const Agg := preload("res://tools/extract/agg.gd")
const Palette := preload("res://tools/extract/palette.gd")
const Icn := preload("res://tools/extract/icn.gd")
const Composite := preload("res://tools/extract/composite.gd")
const Til := preload("res://tools/extract/til.gd")
const ImageDecoder := preload("res://tools/extract/image.gd")
const Sound := preload("res://tools/extract/sound.gd")
const Writer := preload("res://tools/extract/writer.gd")
const Expect := preload("res://tools/extract/expect.gd")
const Report := preload("res://tools/extract/report.gd")
const Bake := preload("res://tools/extract/bake.gd")

const DEFAULT_AGG_CANDIDATES := preload("res://tools/extract/agg_paths.gd").CANDIDATES
const DEFAULT_OUT := "res://assets/art"
const DEFAULT_FLAT_MIRROR := "res://external_resources/assets_flat"
const RULES := "res://data/extract_rules.json"

const SPRITE_FAMILIES := ["icn", "std", "atk", "wlk", "wip", "obj", "xtl"]


func _initialize() -> void:
	var config := {"out_dir": DEFAULT_OUT}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--agg="):
			config["agg"] = arg.trim_prefix("--agg=")
		elif arg.begins_with("--out="):
			config["out_dir"] = arg.trim_prefix("--out=")
		elif arg.begins_with("--only="):
			config["only"] = arg.trim_prefix("--only=")
		elif arg == "--decode-only":
			config["decode_only"] = true
		elif arg == "--dry-run":
			config["dry_run"] = true
		elif arg == "--lenient":
			config["lenient"] = true
		elif arg == "--strict":
			config["strict"] = true
		elif arg.begins_with("--rules="):
			config["rules"] = arg.trim_prefix("--rules=")
		elif arg.begins_with("--report="):
			config["report"] = arg.trim_prefix("--report=")
		elif arg == "--flat-mirror":
			config["flat_mirror"] = DEFAULT_FLAT_MIRROR
		elif arg.begins_with("--flat-mirror="):
			config["flat_mirror"] = arg.trim_prefix("--flat-mirror=")
		elif arg == "--no-sweep":
			config["sweep"] = false
		else:
			push_error("unknown argument: %s" % arg)
			quit(2)
			return

	var report := run(config)
	print(report["summary"])
	var diagnosis: String = report.get("diagnosis", "")
	if diagnosis != "":
		print("\n%s" % diagnosis)
	if report["error"] != "":
		push_error(report["error"])
	quit(report["exit_code"])


## Returns {counts, skipped, mismatches, manifest, error, summary, exit_code}.
##
## Aborts only when nothing downstream can work: the archive will not read, its
## directory is not self-consistent, or the palette is missing. Everything else
## records a reason and carries on, because the dividing line that matters is
## whether continuing would produce output that looks fine and is wrong.
static func run(config: Dictionary) -> Dictionary:
	var agg_path := String(config.get("agg", ""))
	if agg_path == "":
		for candidate in DEFAULT_AGG_CANDIDATES:
			if FileAccess.file_exists(candidate):
				agg_path = candidate
				break
		if agg_path == "":
			agg_path = DEFAULT_AGG_CANDIDATES[0]
	var out_dir := String(config.get("out_dir", DEFAULT_OUT))
	var decode_only := bool(config.get("decode_only", false))
	var dry_run := bool(config.get("dry_run", false))
	var only := String(config.get("only", ""))
	var do_sweep := bool(config.get("sweep", true)) and not decode_only
	# A run restricted to one entry produces one entry. Sweeping on top of
	# that would delete the rest of the tree, so a filtered debug run never
	# prunes: --only is for looking at one sprite, not for rebuilding.
	if only != "":
		do_sweep = false
	var report_path := String(config.get("report",
		"%s/report.json" % out_dir.trim_suffix("/").get_base_dir()))

	var report := Report.new()

	var rules_path := String(config.get("rules", RULES))
	var rules := _read_json(rules_path)
	if rules.is_empty():
		return _abort(report, "cannot read the extraction rules at %s" % rules_path)

	var data := _read_bytes(agg_path)
	if data.is_empty():
		return _abort(report, "cannot read %s" % agg_path)

	var parsed: Dictionary = Agg.parse(data)
	if not parsed["ok"]:
		return _abort(report, "%s is not a readable AGG archive: %s" % [agg_path, parsed["error"]])
	var entries: Array = parsed["entries"]
	report.counts["entries"] = entries.size()

	var by_name := {}
	for entry: Dictionary in entries:
		by_name[String(entry["name"]).to_lower()] = entry
	for required in (rules.get("required_entries", []) as Array):
		var req_name := String(required).to_lower()
		var found := by_name.has(req_name)
		if not found and req_name == "kb.pal" and by_name.has("heroes.pal"):
			found = true
		if not found:
			return _abort(report, "%s holds no %s, so it is not a HOMM1 heroes.agg" % [
				agg_path, required])

	var lenient := bool(config.get("lenient", false))
	if not lenient and not bool(config.get("strict", false)):
		if by_name.has("heroes.pal") and not by_name.has("kb.pal"):
			lenient = true

	var palette := PackedByteArray()
	for entry: Dictionary in entries:
		if String(entry["name"]).get_extension().to_lower() != "pal":
			continue
		var loaded: Dictionary = Palette.parse(_slice(data, entry))
		if not loaded["ok"]:
			return _abort(report, "%s is unusable: %s" % [entry["name"], loaded["error"]])
		palette = loaded["rgb"]
		break
	if palette.is_empty():
		return _abort(report, "%s holds no palette, so nothing can be decoded" % agg_path)

	# The sweep deletes everything this run did not write, so it only runs on a
	# tree the extractor built: every full run writes palette_swatch.png first.
	if do_sweep and not FileAccess.file_exists(out_dir.path_join("palette_swatch.png")):
		do_sweep = false
		print("%s was not written by the extractor, so nothing in it is swept" % out_dir)
	var writer := Writer.new(out_dir, dry_run or decode_only,
		String(config.get("flat_mirror", "")))
	var expect := Expect.new(rules)

	if only == "":
		writer.image("palette_swatch.png", Palette.swatch(palette))
		report.count("images")

	for entry: Dictionary in entries:
		var name := String(entry["name"])
		if only != "" and name.to_lower() != only.to_lower():
			continue
		var ext := name.get_extension().to_lower()
		report.saw_extension(ext)
		var payload := _slice(data, entry)
		if payload.size() != int(entry["size"]):
			report.skip(name, "read", "wanted %d bytes, got %d" % [entry["size"], payload.size()])
			continue

		if ext in SPRITE_FAMILIES:
			_extract_sprites(name, ext, payload, palette, rules, writer, expect, report, lenient)
		elif ext == "til":
			_extract_tiles(name, payload, palette, rules, writer, expect, report)
		elif ext == "bmp" or ext == "bkg":
			_extract_image(name, ext, payload, palette, writer, report)
		elif ext == "82m":
			_extract_sound(name, payload, rules, writer, report)
		else:
			var raw_name := name
			if name.to_lower() == "heroes.pal" and not by_name.has("kb.pal"):
				raw_name = "kb.pal"
			if writer.raw(raw_name, payload):
				report.count("raw")

	if only == "":
		expect.check_totals(report.counts)
		Bake.run(out_dir, rules, writer)
	report.mismatches.append_array(expect.mismatches)
	report.manifest = writer.written

	if do_sweep:
		report.removed = writer.sweep()
	if not decode_only and not dry_run and only == "":
		_write_report(report_path, report)

	for error in writer.errors:
		report.skip(error, "write", "output failed")

	var failed := not report.skipped.is_empty() or not report.mismatches.is_empty()
	return {
		"counts": report.counts,
		"skipped": report.skipped,
		"mismatches": report.mismatches,
		"manifest": report.manifest,
		"error": "",
		"summary": report.summary(not decode_only and not dry_run),
		"diagnosis": report.diagnosis(agg_path),
		"exit_code": 1 if failed else 0,
	}


## ICN, STD, ATK, WLK, WIP, OBJ and XTL. One directory of numbered PNGs, plus
## whatever composites and shadow names the family calls for, plus a spec.json.
##
## A frame that will not decode takes the whole directory with it. Half a
## creature is worse than none: the missing frame would surface later as a
## silently absent pose rather than as an error here.
static func _extract_sprites(name: String, family: String, payload: PackedByteArray,
		palette: PackedByteArray, rules: Dictionary, writer: Writer,
		expect: Expect, report: Report, lenient: bool = false) -> void:
	var headers: Dictionary = Icn.read_headers(payload)
	if not headers["ok"]:
		report.skip(name, "header", headers["error"])
		return
	var frames: Array = headers["frames"]
	var stem := name.get_basename().to_lower()

	var images: Array[Image] = []
	for i in frames.size():
		var mono: bool = Icn.is_mono(family, stem, i, rules)
		var is_white: bool = Icn.is_white_mono(family, stem, i, rules)
		var decoded: Dictionary = Icn.decode_frame(payload, frames[i], mono, palette, lenient, is_white)
		if not decoded["ok"]:
			report.skip(name, "frame %d" % i, decoded["error"])
			return
		images.append(decoded["image"])
	report.count("frames", frames.size())

	var dir: String = Composite.dir_name(name, family)
	var built: Dictionary = Composite.build(family, stem, frames, images, rules)
	expect.check_sprite_dir(dir, family, stem, frames, images, built["spec"])

	for out: Dictionary in built["images"]:
		if writer.image("%s/%s" % [dir, out["name"]], out["image"]):
			report.count("images")
	if writer.json("%s/spec.json" % dir, built["spec"]):
		report.count("specs")


static func _extract_tiles(name: String, payload: PackedByteArray, palette: PackedByteArray,
		rules: Dictionary, writer: Writer, expect: Expect, report: Report) -> void:
	var dir := name.get_basename()
	var cycle: Dictionary = rules.get("palette", {}).get("cycle", {}).get(dir, {})
	var decoded: Dictionary = Til.decode(payload, palette, cycle)
	if not decoded["ok"]:
		report.skip(name, "decode", decoded["error"])
		return
	expect.check_til_dir(dir, decoded["images"])
	for out: Dictionary in decoded["images"]:
		if writer.image("%s/%s" % [dir, out["name"]], out["image"]):
			report.count("images")


static func _extract_image(name: String, family: String, payload: PackedByteArray,
		palette: PackedByteArray, writer: Writer, report: Report) -> void:
	var decoded: Dictionary = ImageDecoder.decode(payload, palette)
	if not decoded["ok"]:
		report.skip(name, "decode", decoded["error"])
		return
	if decoded["warning"] != "":
		report.mismatch(name, "magic", decoded["warning"])
	var suffix := "_bkg.png" if family == "bkg" else ".png"
	if writer.image(name.get_basename() + suffix, decoded["image"]):
		report.count("images")


static func _extract_sound(name: String, payload: PackedByteArray, rules: Dictionary,
		writer: Writer, report: Report) -> void:
	var decoded: Dictionary = Sound.decode(payload)
	if not decoded["ok"]:
		report.skip(name, "decode", decoded["error"])
		return
	var rate := int(rules.get("sound", {}).get("rate", 22050))
	if writer.wav(name.get_basename() + ".wav", decoded["pcm"], rate):
		report.count("sounds")


## The report lands beside the output tree rather than inside it, so it is not
## itself an asset the next run has to decide whether to sweep.
static func _write_report(path: String, report: Report) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("cannot write %s" % path)
		return
	f.store_string(JSON.stringify(report.to_dict(), "  ") + "\n")
	f.close()


static func _abort(report: Report, reason: String) -> Dictionary:
	return {"counts": report.counts, "skipped": report.skipped, "mismatches": [],
		"manifest": PackedStringArray(), "error": reason, "summary": reason,
		"diagnosis": "", "exit_code": 1}


static func _slice(data: PackedByteArray, entry: Dictionary) -> PackedByteArray:
	return data.slice(entry["offset"], int(entry["offset"]) + int(entry["size"]))


static func _read_bytes(path: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var data := f.get_buffer(f.get_length())
	f.close()
	return data


static func _read_json(path: String) -> Dictionary:
	var text := _read_bytes(path).get_string_from_utf8()
	if text == "":
		return {}
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}
