extends RefCounted

## Terrain tiles.
##
##   u16 tile count, u16 width, u16 height, then one palette index per pixel,
##   row-major, repeated per tile.
##
## Four files, not the three the README lists: ground32 (124 at 32x32),
## clof32 (4), ston (36) and herologo (1 at 144x144).
##
## ground32's first twenty tiles are water, and water is the one thing HOMM1
## animates by cycling its palette. Each of those tiles is written as a
## horizontal strip of five palette-rotation steps, 160 by 32, which
## src/adventure/map/tileset_builder.gd feeds straight to a Godot atlas
## animation. Nothing documents this outside a Python docstring, and an
## extractor that follows the README instead emits 124 plain tiles, kills the
## water animation, and leaves every file count looking correct.

const Palette := preload("res://tools/extract/palette.gd")

const HEADER_BYTES := 6


## Returns {ok, error, images: [{name, image}]}. `cycle` is
## {tiles, frames, start, length} for a directory whose leading tiles animate,
## or empty for one whose tiles are plain.
static func decode(data: PackedByteArray, rgb: PackedByteArray, cycle: Dictionary) -> Dictionary:
	if data.size() < HEADER_BYTES:
		return _fail("file is %d bytes, too small for a header" % data.size())
	var count := data.decode_u16(0)
	var width := data.decode_u16(2)
	var height := data.decode_u16(4)
	if count == 0 or width == 0 or height == 0:
		return _fail("declares %d tiles of %dx%d" % [count, width, height])
	var tile_bytes := width * height
	if HEADER_BYTES + count * tile_bytes > data.size():
		return _fail("%d tiles of %dx%d need %d bytes, file holds %d" % [
			count, width, height, HEADER_BYTES + count * tile_bytes, data.size()])

	var animated := int(cycle.get("tiles", 0))
	var steps := int(cycle.get("frames", 0))
	var start := int(cycle.get("start", 0))
	var length := int(cycle.get("length", 0))

	var images: Array[Dictionary] = []
	for i in count:
		var at := HEADER_BYTES + i * tile_bytes
		var chunk := data.slice(at, at + tile_bytes)
		var image: Image
		if i < animated and steps > 1:
			image = Image.create_empty(width * steps, height, false, Image.FORMAT_RGB8)
			for step in steps:
				var frame := Palette.paint(chunk, width, height,
					Palette.cycled(rgb, step, start, length))
				image.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()),
					Vector2i(step * width, 0))
		else:
			image = Palette.paint(chunk, width, height, rgb)
		images.append({"name": "%04d.png" % i, "image": image})
	return {"ok": true, "error": "", "images": images}


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "error": reason, "images": [] as Array[Dictionary]}
