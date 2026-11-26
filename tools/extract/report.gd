extends RefCounted

## What the run did, in a form a test can assert on.
##
## The counts are not decoration. The corpus reconciles exactly: 5535 header
## frames, less 50 one-pixel sentinels the STD path drops, plus 99 STD
## composites, 24 ATK composites, 30 ATK projectile copies, 165 TIL tiles and
## 52 top-level images, equals 5855 PNGs. A test reads report.json and checks
## that, so a decoder that quietly stops writing a family is caught by a number
## rather than by someone noticing a missing sprite in a battle.

var counts := {"entries": 0, "frames": 0, "images": 0, "sounds": 0, "raw": 0, "specs": 0}
var skipped: Array[Dictionary] = []
var mismatches: Array[Dictionary] = []
var manifest: PackedStringArray = PackedStringArray()
var removed: PackedStringArray = PackedStringArray()
var extensions := {}


func count(key: String, by := 1) -> void:
	counts[key] = int(counts.get(key, 0)) + by


func saw_extension(ext: String) -> void:
	extensions[ext] = int(extensions.get(ext, 0)) + 1


## `stage` says how far the entry got: reading it, decoding it, or writing it.
## A reason without a stage is the kind of report that leaves someone guessing
## whether the file was bad or the disk was full.
func skip(name: String, stage: String, reason: String) -> void:
	skipped.append({"name": name, "stage": stage, "reason": reason})


## Something the output can live with but nobody should discover by accident.
func mismatch(where: String, what: String, detail: String) -> void:
	mismatches.append({"dir": where, "check": what, "detail": detail})


func to_dict() -> Dictionary:
	return {
		"counts": counts,
		"extensions": extensions,
		"skipped": skipped,
		"mismatches": mismatches,
		"removed": Array(removed),
		"manifest": Array(manifest),
	}


## `wrote` is false when the run was asked to decode and check without
## persisting anything. Saying "wrote 5855 images" after writing none is the
## kind of report that teaches people not to read reports.
func summary(wrote := true) -> String:
	var lines: Array[String] = []
	lines.append("%d archive entries, %d sprite frames" % [counts["entries"], counts["frames"]])
	lines.append("%s %d images, %d sounds, %d raw files, %d specs" % [
		"wrote" if wrote else "would write",
		counts["images"], counts["sounds"], counts["raw"], counts["specs"]])
	if not removed.is_empty():
		lines.append("removed %d stale files" % removed.size())
	if not mismatches.is_empty():
		lines.append("%d expectation mismatches:" % mismatches.size())
		for m: Dictionary in mismatches.slice(0, 20):
			lines.append("  %s  %s: %s" % [m["dir"], m["check"], m["detail"]])
		if mismatches.size() > 20:
			lines.append("  ... and %d more, see report.json" % (mismatches.size() - 20))
	if not skipped.is_empty():
		lines.append("%d entries skipped:" % skipped.size())
		for s: Dictionary in skipped.slice(0, 20):
			lines.append("  %s  (%s) %s" % [s["name"], s["stage"], s["reason"]])
		if skipped.size() > 20:
			lines.append("  ... and %d more, see report.json" % (skipped.size() - 20))
	return "\n".join(lines)


## Printed when a run skipped something, because the difference between
## "3 entries skipped" and "this is not a HOMM1 archive" is the difference
## between a player carrying on and a player giving up.
func diagnosis(agg_path: String) -> String:
	if skipped.is_empty():
		return ""
	var stages := {}
	for s: Dictionary in skipped:
		stages[s["stage"]] = int(stages.get(s["stage"], 0)) + 1
	if int(stages.get("extension", 0)) == skipped.size():
		return "Every skip was an entry type this extractor does not know. %s is \
probably from a different game or a different release." % agg_path
	return "If most of these are decode failures, %s is probably not a HOMM1 \
heroes.agg: a partial install, a different release, or HOMM2's heroes2.agg. \
If it is the archive you expect, this is a bug in the extractor." % agg_path
