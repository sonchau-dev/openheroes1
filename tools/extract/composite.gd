extends RefCounted

## What a sprite directory is called and what goes in it.
##
## This is deliberately not part of icn.gd. Decoding a frame is one rule that
## holds for all 5535 of them; deciding that frame 5 is a body to composite
## three overlays onto, unless the creature is a dragon, in which case there
## are nine, unless it is a hydra, in which case there are none, is a pile of
## special cases. Folding the second into the first is how the Python extractor
## reached 1116 unreadable lines.
##
## Layouts are in data/knowledge_base/research/agg-format-spec.md; the tables
## they key off are in data/extract_rules.json.

const Icn := preload("res://tools/extract/icn.gd")

const SENTINEL := 1


## Every ICN-family frame shares an anchor at (0, 0), roughly a creature's
## feet, and each frame's offset places its top-left corner against it. A
## composite is the union of its parts' boxes with each part blended at its own
## offset, which is why a four-pixel base under a full-body overlay still comes
## out right and why small frames must never be filtered before this runs.
static func stack(parts: Array) -> Image:
	var min_x := 0
	var min_y := 0
	var max_x := 0
	var max_y := 0
	var first := true
	for part: Dictionary in parts:
		var frame: Dictionary = part["frame"]
		if first:
			min_x = frame["ox"]
			min_y = frame["oy"]
			max_x = frame["ox"] + frame["w"]
			max_y = frame["oy"] + frame["h"]
			first = false
			continue
		min_x = mini(min_x, frame["ox"])
		min_y = mini(min_y, frame["oy"])
		max_x = maxi(max_x, frame["ox"] + frame["w"])
		max_y = maxi(max_y, frame["oy"] + frame["h"])
	if first or max_x <= min_x or max_y <= min_y:
		return null

	var canvas := Image.create_empty(max_x - min_x, max_y - min_y, false, Image.FORMAT_RGBA8)
	for part: Dictionary in parts:
		var img: Image = part["image"]
		var frame: Dictionary = part["frame"]
		canvas.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
			Vector2i(frame["ox"] - min_x, frame["oy"] - min_y))
	return canvas


## The directory an archive entry becomes. Plain ICN drops its extension,
## because `advmice.icn` has no sibling; everything else keeps it, so
## `archer.std`, `archer.atk` and `archer.wlk` stay three directories.
static func dir_name(entry_name: String, family: String) -> String:
	if family == "icn" or family == "til":
		return entry_name.get_basename()
	return "%s.%s" % [entry_name.get_basename(), family]


## Returns {images: [{name, image}], spec: Dictionary}, both ready for the
## writer. `images` holds the decoded frames in header order.
static func build(family: String, stem: String, frames: Array, images: Array,
		rules: Dictionary) -> Dictionary:
	match family:
		"std":
			return _build_std(stem, frames, images, rules)
		"atk":
			return _build_atk(frames, images)
		_:
			return _build_plain(family, frames, images)


## Plain ICN, WLK, WIP, OBJ and XTL: every frame written under its number, no
## compositing. WLK's second half is a run of ground shadows, which the Python
## decoded as mono and then declined to label; they carry the role now, because
## a consumer that cannot see it has to reimplement the extractor's index rules
## to find out.
static func _build_plain(family: String, frames: Array, images: Array) -> Dictionary:
	var out: Array[Dictionary] = []
	var sprites := {}
	var by_file := {}
	for i in frames.size():
		var file := "%04d.png" % i
		out.append({"name": file, "image": images[i]})
		var role := "shadow_gnd" if family == "wlk" and i >= 6 else ""
		sprites[str(i)] = _sprite(file, frames[i], role)
		by_file[file] = i
	return {"images": out, "spec": _spec(frames.size(), sprites, by_file, [])}


## STD: one file per creature, holding the idle and attack poses, a full-height
## body silhouette, and a ground shadow for each pose.
##
## Three layouts. Twenty-four creatures use 18 frames with one attack overlay
## set; dragon, cyclops and phoenix use 33 with three sets; hydra uses 16
## independent body poses and composites nothing.
##
## The shadow names are wrong for hydra and have been since the corpus was
## built: the 18-frame name table is applied to a 16-frame creature, so every
## name lands one pose early and hydra gets a death shadow for a pose it does
## not have. They are kept, because data/creatures/anim_table.json references
## them by name and renaming files to fix a label nobody reads would break the
## battle renderer. What changed is that the pairing is now pinned by
## tests/test_creature_shadow_pairing.gd, which derives the body frame from the
## layout instead of trusting the name.
static func _build_std(stem: String, frames: Array, images: Array,
		rules: Dictionary) -> Dictionary:
	var std: Dictionary = rules.get("std", {})
	var extended: bool = stem in (std.get("extended", []) as Array)
	var independent: bool = stem in (std.get("independent", []) as Array)
	var shadow_start := int(rules.get("mono", {}).get("std_shadow_start", {}).get(
		"extended" if extended else "default", 9))
	var names: Dictionary = std.get("shadow_names", {}).get(
		"extended" if extended else "standard", {})

	var out: Array[Dictionary] = []
	var shadow_by_index := {}

	# The silhouette is always frame 0 and always written.
	if frames.size() > 0:
		shadow_by_index[0] = "shadow_body"
		out.append({"name": "shadow_body.png", "image": images[0]})

	for i in range(shadow_start, frames.size()):
		if _is_sentinel(frames[i]):
			continue
		var name: String = names.get(str(i), "shadow_gnd_F%d" % i)
		shadow_by_index[i] = name
		out.append({"name": "%s.png" % name, "image": images[i]})

	for i in frames.size():
		if i == 0 or i >= shadow_start:
			continue
		out.append({"name": "%04d.png" % i, "image": images[i]})

	var composites: Array[String] = []
	if not independent:
		for entry: Array in (std.get("overlay_sets", {}).get(
				"extended" if extended else "standard", []) as Array):
			var base := int(entry[0])
			var label := String(entry[4])
			for slot in [[1, "up"], [2, "across"], [3, "down"]]:
				var overlay := int(entry[int(slot[0])])
				if base >= frames.size() or overlay >= frames.size():
					continue
				var image := stack([
					{"image": images[base], "frame": frames[base]},
					{"image": images[overlay], "frame": frames[overlay]},
				])
				if image == null:
					continue
				var name := "composite_%s_%s.png" % [label, slot[1]]
				out.append({"name": name, "image": image})
				composites.append(name)

	var sprites := {}
	var by_file := {}
	for i in frames.size():
		var file: String = "%s.png" % shadow_by_index[i] if shadow_by_index.has(i) \
			else "%04d.png" % i
		var role := ""
		if shadow_by_index.has(i):
			role = "shadow_body" if i == 0 else "shadow_gnd"
		sprites[str(i)] = _sprite(file, frames[i], role)
		by_file[file] = i
	return {"images": out, "spec": _spec(frames.size(), sprites, by_file, composites)}


## ATK: six ranged creatures, 14 frames each. Frame 0 is the body, 1 to 4 are
## overlays composited onto it, 5 to 9 are the projectiles it throws, 10 to 13
## are ground shadows.
##
## The projectile copies are kept. They duplicate frames 5 to 9 byte for byte
## under a friendlier name, but anim_table.json names them, so deleting 30
## files to save a few hundred kilobytes means editing an animation table in
## lockstep with a format change for nothing a player can see. What is fixed is
## the labelling: the Python listed all nine as composites, and a projectile is
## a plain sprite, not a stack of anything.
static func _build_atk(frames: Array, images: Array) -> Dictionary:
	var out: Array[Dictionary] = []
	var sprites := {}
	var by_file := {}
	for i in frames.size():
		var file := "%04d.png" % i
		out.append({"name": file, "image": images[i]})
		var role := ""
		if i == 0:
			role = "base"
		elif i <= 4:
			role = "overlay"
		elif i <= 9:
			role = "projectile"
		sprites[str(i)] = _sprite(file, frames[i], role)
		by_file[file] = i

	var composites: Array[String] = []
	for i in range(1, mini(5, frames.size())):
		var image := stack([
			{"image": images[0], "frame": frames[0]},
			{"image": images[i], "frame": frames[i]},
		])
		if image == null:
			continue
		var name := "composite_atk_F%d.png" % i
		out.append({"name": name, "image": image})
		composites.append(name)

	for i in range(5, mini(10, frames.size())):
		out.append({"name": "projectile_F%d.png" % i, "image": images[i]})

	return {"images": out, "spec": _spec(frames.size(), sprites, by_file, composites)}


## A one-pixel frame at the origin is a filler slot, not art. Only the STD
## shadow run drops them; plain ICN writes them, because smalfont's 1x7 and
## 5x1 glyphs are real and obj32-04 has a genuine 1x8 frame.
static func _is_sentinel(frame: Dictionary) -> bool:
	return frame["w"] <= SENTINEL and frame["h"] <= SENTINEL


static func _sprite(file: String, frame: Dictionary, role: String) -> Dictionary:
	return {"file": file, "ox": frame["ox"], "oy": frame["oy"],
		"w": frame["w"], "h": frame["h"], "role": role}


static func _spec(count: int, sprites: Dictionary, by_file: Dictionary,
		composites: Array) -> Dictionary:
	return {"count": count, "sprites": sprites, "by_file": by_file,
		"composites": composites}
