extends RefCounted

## Sprite frames. ICN, WLK, WIP, STD, ATK, OBJ and XTL are all this format;
## they differ only in what the frames mean and which of them are monochrome.
##
##   u16                       frame count
##   u32                       total size, always file size minus 6
##   count * 12 bytes          frame headers
##   ...                       pixel streams
##
## Frame header: s16 offsetX, s16 offsetY, u16 width, u16 height, u32 stream
## offset relative to byte 6. That last word is a plain offset. The README's
## type byte in its high bits does not exist: those bits are zero in all 5535
## frames of the retail archive, and `type=32` is a HOMM2 idea that leaked into
## the notes. Which frames are monochrome is therefore knowledge the caller has
## to supply, from data/extract_rules.json.
##
## The decoder is strict. The retail archive has zero malformed frames, so an
## overflow or a missing terminator means the decoder is wrong, not the asset.
## Clamping silently, which is what the Python does, is how a broken decode
## ships looking fine.

const HEADER_BYTES := 12
const PIXELS_START := 6


## Returns {ok, error, frames}. Each frame is {ox, oy, w, h, start, end},
## where start and end bracket its stream inside `blob`.
static func read_headers(blob: PackedByteArray) -> Dictionary:
	if blob.size() < PIXELS_START:
		return _fail("file is %d bytes, too small for a header" % blob.size())
	var count := blob.decode_u16(0)
	if count == 0:
		return _fail("file declares zero frames")
	var declared := blob.decode_u32(2)
	if declared != blob.size() - PIXELS_START:
		return _fail("header declares %d bytes of data, file holds %d" % [
			declared, blob.size() - PIXELS_START])
	if PIXELS_START + count * HEADER_BYTES > blob.size():
		return _fail("%d frame headers do not fit in %d bytes" % [count, blob.size()])

	var frames: Array[Dictionary] = []
	var starts: Array[int] = []
	for i in count:
		var p := PIXELS_START + i * HEADER_BYTES
		var start := PIXELS_START + blob.decode_u32(p + 8)
		if start > blob.size():
			return _fail("frame %d points past the end of the file" % i)
		var w := blob.decode_u16(p + 4)
		var h := blob.decode_u16(p + 6)
		if w > 640 or h > 480:  # nothing is larger than the screen
			return _fail("frame %d declares %dx%d" % [i, w, h])
		frames.append({
			"ox": blob.decode_s16(p),
			"oy": blob.decode_s16(p + 2),
			"w": w,
			"h": h,
			"start": start,
		})
		starts.append(start)

	# A frame's stream runs to the next larger start, or to end of file. The
	# offsets are already ascending in every retail file, but sorting costs
	# nothing and the README warns that editor.agg may not be so tidy.
	starts.sort()
	for frame in frames:
		var at := starts.bsearch(frame["start"])
		while at < starts.size() and starts[at] <= frame["start"]:
			at += 1
		frame["end"] = starts[at] if at < starts.size() else blob.size()
	return {"ok": true, "error": "", "frames": frames}


## Returns {ok, error, image}. `rgb` is the 768-byte palette, ignored in mono.
##
##   0x00        end of line
##   0x01-0x7F   a run of N pixels: N palette bytes follow, or N black pixels
##               with nothing following when the frame is mono
##   0x80        end of stream
##   0x81-0xFF   leave N minus 0x80 pixels transparent
##
## There are no HOMM2 sub-commands. The whole 0x81 to 0xFF range is a skip.
static func decode_frame(blob: PackedByteArray, frame: Dictionary, mono: bool,
		rgb: PackedByteArray, lenient: bool = false, white: bool = false) -> Dictionary:
	var w: int = frame["w"]
	var h: int = frame["h"]
	if w <= 0 or h <= 0:
		return _bad("declares a %dx%d frame" % [w, h])

	var pixels := PackedByteArray()
	pixels.resize(w * h * 4)  # zero filled, so every pixel starts transparent

	var p: int = frame["start"]
	var end: int = frame["end"]
	var x := 0
	var y := 0
	var terminated := false
	while p < end:
		var op := blob[p]
		p += 1
		if op == 0x00:
			x = 0
			y += 1
			continue
		if op == 0x80:
			terminated = true
			break
		if op > 0x80:
			x += op - 0x80
			if x > w and not lenient:
				return _bad("skip runs %d past the right edge on row %d" % [x - w, y])
			continue
		if y >= h:
			if not lenient:
				return _bad("writes to row %d of a %d-row frame" % [y, h])
			if not mono:
				if p + op > end:
					return _bad("run of %d reads past the end of the stream" % op)
				p += op
			x += op
			continue
		if x + op > w and not lenient:
			return _bad("run of %d at column %d overflows a %d-wide frame" % [op, x, w])

		if mono:
			if x < w:
				var run_end := mini(x + op, w)
				var at := (y * w + x) * 4
				var ink: int = 255 if white else 0
				for _col in range(x, run_end):
					pixels[at + 0] = ink
					pixels[at + 1] = ink
					pixels[at + 2] = ink
					pixels[at + 3] = 255
					at += 4
		else:
			if p + op > end:
				return _bad("run of %d reads past the end of the stream" % op)
			var at := (y * w + x) * 4
			for col in range(x, x + op):
				var c := blob[p] * 3
				p += 1
				if col < w:
					pixels[at + 0] = rgb[c + 0]
					pixels[at + 1] = rgb[c + 1]
					pixels[at + 2] = rgb[c + 2]
					pixels[at + 3] = 255
					at += 4
		x += op

	if not terminated:
		return _bad("stream ends without a 0x80 terminator")
	if p != end:
		return _bad("%d bytes trail the 0x80 terminator" % (end - p))
	return {"ok": true, "error": "",
		"image": Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, pixels)}


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "error": reason, "frames": [] as Array[Dictionary]}


static func _bad(reason: String) -> Dictionary:
	return {"ok": false, "error": reason, "image": null}


## Whether a frame is monochrome. Nothing in the archive says, so this reads
## the hand-verified table in data/extract_rules.json. Applied as written it
## produces zero anomalous frames out of 5535; disabled it produces 662 broken
## ones, and forced on it produces 4552. It is load-bearing, and it cannot be
## replaced by trying both and keeping whichever parses: 85 frames decode
## cleanly either way.
static func is_mono(family: String, stem: String, index: int, rules: Dictionary) -> bool:
	var mono: Dictionary = rules.get("mono", {})
	match family:
		"std":
			var extended: Array = rules.get("std", {}).get("extended", [])
			var starts: Dictionary = mono.get("std_shadow_start", {})
			var first: int = int(starts.get("extended" if stem in extended else "default", 9))
			return index == 0 or index >= first
		"atk":
			return index >= int(mono.get("atk_first_mono", 10))
		"wlk":
			return index >= int(mono.get("wlk_first_mono", 6))
		"icn":
			if stem in (mono.get("whole_icn", []) as Array):
				return true
			var per_frame: Dictionary = mono.get("icn_frames", {})
			if not per_frame.has(stem):
				return false
			# JSON numbers arrive as floats, and Array.has compares types, so
			# `index in [15.0]` is quietly false for every integer index.
			for listed: float in (per_frame[stem] as Array):
				if int(listed) == index:
					return true
			return false
		_:
			return false


static func is_white_mono(family: String, stem: String, _index: int, rules: Dictionary) -> bool:
	var mono: Dictionary = rules.get("mono", {})
	var white_list: Array = mono.get("white_mono", ["font", "smalfont"])
	return family == "icn" and stem in white_list
