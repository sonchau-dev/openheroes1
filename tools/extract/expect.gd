extends RefCounted

## Checks a decoded directory against data/extract_rules.json before it lands.
##
## The point is the failure this whole rewrite exists to prevent: output that
## looks fine and is wrong. Every file count can be correct while the water
## animation is dead, or while four creatures' attack anchors have quietly
## become empty frames. Counting files catches neither.
##
## A mismatch is recorded and the run still exits non-zero. It does not stop
## the directory being written, because an archive we have not seen before is
## allowed to differ, and refusing to extract it would close the door on the
## demo and on releases other than retail.

var rules: Dictionary
var mismatches: Array[Dictionary] = []

var _std: Dictionary
var _dirs_seen := {}


func _init(extract_rules: Dictionary) -> void:
	rules = extract_rules.get("expect", {})
	_std = extract_rules.get("std", {})


func check_sprite_dir(dir: String, family: String, stem: String,
		frames: Array, images: Array, spec: Dictionary) -> void:
	var variant := _std_variant(stem)
	_dirs_seen[family] = int(_dirs_seen.get(family, 0)) + 1
	if family == "std":
		_dirs_seen[variant] = int(_dirs_seen.get(variant, 0)) + 1

	var rule: Dictionary = rules.get("families", {}).get(family, {})
	if family == "std":
		rule = rules.get("std_variants", {}).get(variant, {})
	if rule.has("frames") and frames.size() != int(rule["frames"]):
		_note(dir, "frame count", "%d frames, expected %d" % [frames.size(), rule["frames"]])
	if rule.has("composites"):
		var got: int = (spec.get("composites", []) as Array).size()
		if got != int(rule["composites"]):
			_note(dir, "composites", "%d declared, expected %d" % [got, rule["composites"]])

	var per_icn: Dictionary = rules.get("icn_frames", {})
	if family == "icn" and per_icn.has(stem) and frames.size() != int(per_icn[stem]):
		_note(dir, "frame count", "%d frames, expected %d" % [frames.size(), per_icn[stem]])

	var geometry: Array = rule.get("geometry", [])
	if not geometry.is_empty():
		for i in mini(geometry.size(), frames.size()):
			var got := "%dx%d" % [frames[i]["w"], frames[i]["h"]]
			if got != String(geometry[i]):
				_note(dir, "geometry", "frame %d is %s, expected %s" % [i, got, geometry[i]])

	_check_ids_dense(dir, spec)
	_check_opaque_canary(dir, frames, images)
	_check_duplicates(dir, images)


func check_til_dir(dir: String, images: Array) -> void:
	_dirs_seen["til"] = int(_dirs_seen.get("til", 0)) + 1
	var rule: Dictionary = rules.get("til_geometry", {}).get(dir, {})
	if rule.is_empty():
		return
	if images.size() != int(rule.get("tiles", -1)):
		_note(dir, "tile count", "%d tiles, expected %d" % [images.size(), rule.get("tiles", -1)])
	var sizes := {}
	for entry: Dictionary in images:
		var image: Image = entry["image"]
		var key := "%dx%d" % [image.get_width(), image.get_height()]
		sizes[key] = int(sizes.get(key, 0)) + 1
	var expected: Dictionary = rule.get("sizes", {})
	for key in expected:
		if int(sizes.get(key, 0)) != int(expected[key]):
			_note(dir, "tile sizes", "%d at %s, expected %d" % [
				int(sizes.get(key, 0)), key, expected[key]])
	for key in sizes:
		if not expected.has(key):
			_note(dir, "tile sizes", "%d unexpected tiles at %s" % [sizes[key], key])


## Run once the archive has been walked. Directory and entry counts are
## recorded rather than enforced on their own: a demo or a re-release will
## legitimately hold a different set, and hard-failing on the retail numbers
## would turn a correct archive we have not seen into an unusable one.
func check_totals(counts: Dictionary) -> void:
	var totals: Dictionary = rules.get("totals", {})
	var families: Dictionary = rules.get("families", {})
	var variants: Dictionary = rules.get("std_variants", {})

	var releases: Dictionary = rules.get("releases", {})
	for rel_name in releases:
		var profile: Dictionary = releases[rel_name]
		var rel_totals: Dictionary = profile.get("totals", {})
		if rel_totals.has("entries") and int(counts.get("entries", 0)) == int(rel_totals["entries"]):
			totals = rel_totals
			families = profile.get("families", families)
			variants = profile.get("std_variants", variants)
			break
	for key in totals:
		if counts.has(key) and int(counts[key]) != int(totals[key]):
			_note("(archive)", "total %s" % key, "%d, expected %d" % [counts[key], totals[key]])
	for family in families:
		var rule: Dictionary = families[family]
		if rule.has("dirs") and int(_dirs_seen.get(family, 0)) != int(rule["dirs"]):
			_note("(archive)", "%s directories" % family, "%d, expected %d" % [
				int(_dirs_seen.get(family, 0)), rule["dirs"]])
	for variant in variants:
		var rule: Dictionary = variants[variant]
		if rule.has("dirs") and int(_dirs_seen.get(variant, 0)) != int(rule["dirs"]):
			_note("(archive)", "%s creatures" % variant, "%d, expected %d" % [
				int(_dirs_seen.get(variant, 0)), rule["dirs"]])


func _std_variant(stem: String) -> String:
	if stem in (_std.get("extended", []) as Array):
		return "extended"
	if stem in (_std.get("independent", []) as Array):
		return "independent"
	return "standard"


## Sprite ids are a dense run from zero in all 334 directories today. A gap
## would mean the header table was misread.
func _check_ids_dense(dir: String, spec: Dictionary) -> void:
	var sprites: Dictionary = spec.get("sprites", {})
	for i in int(spec.get("count", 0)):
		if not sprites.has(str(i)):
			_note(dir, "sprite ids", "no entry for id %d" % i)
			return


func _check_opaque_canary(dir: String, frames: Array, images: Array) -> void:
	var canary: Dictionary = rules.get("opaque_canary", {})
	if not dir in (canary.get("dirs", []) as Array):
		return
	var index := int(canary.get("frame", 5))
	if index >= images.size():
		_note(dir, "anchor frame", "no frame %d to check" % index)
		return
	var limit := int(canary.get("max_opaque", 100))
	var opaque := _opaque_pixels(images[index])
	if opaque > limit:
		_note(dir, "anchor frame", "frame %d covers %d opaque pixels, expected under %d" % [
			index, opaque, limit])


func _check_duplicates(dir: String, images: Array) -> void:
	var groups: Array = rules.get("expected_duplicates", {}).get("groups", {}).get(dir, [])
	for group: Array in groups:
		var first := int(group[0])
		if first >= images.size():
			continue
		var reference := (images[first] as Image).get_data()
		for i in range(1, group.size()):
			var other := int(group[i])
			if other >= images.size():
				continue
			if (images[other] as Image).get_data() != reference:
				_note(dir, "expected duplicate", "frame %d no longer matches frame %d" % [
					other, first])


func _opaque_pixels(image: Image) -> int:
	var data := image.get_data()
	var count := 0
	for i in range(3, data.size(), 4):
		if data[i] > 0:
			count += 1
	return count


func _note(dir: String, what: String, detail: String) -> void:
	mismatches.append({"dir": dir, "check": what, "detail": detail})
