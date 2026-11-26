extends RefCounted

## kb.pal: 768 bytes, 256 entries of red, green, blue, each channel 0 to 63.
##
## Output scaling is `channel * 4`, not `channel * 255 / 63`. No channel in
## this palette exceeds 63, so the brightest output is 252 and the two formulas
## differ on almost every colour. The corpus was built with the first one.

const ENTRIES := 256
const BYTES := ENTRIES * 3


## Returns {ok, error, rgb}. `rgb` is 768 bytes of 8-bit RGB, ready to index
## with `palette_index * 3`.
static func parse(pal: PackedByteArray) -> Dictionary:
	if pal.size() < BYTES:
		return {"ok": false, "error": "palette is %d bytes, needs %d" % [pal.size(), BYTES],
			"rgb": PackedByteArray()}
	var rgb := PackedByteArray()
	rgb.resize(BYTES)
	for i in BYTES:
		rgb[i] = mini(pal[i] * 4, 255)
	return {"ok": true, "error": "", "rgb": rgb}


## The palette rotated forward by `step` over one cycling band. HOMM1 animates
## exactly one band, the water ramp at 240 length 5, measured off every
## ground32 water tile. The README's 231 to 237 band is used by zero water
## pixels; do not restore it without re-deriving it.
static func cycled(rgb: PackedByteArray, step: int, start: int, length: int) -> PackedByteArray:
	var out := rgb.duplicate()
	for id in length:
		var src := start + ((id + step) % length)
		var dst := start + id
		out[dst * 3 + 0] = rgb[src * 3 + 0]
		out[dst * 3 + 1] = rgb[src * 3 + 1]
		out[dst * 3 + 2] = rgb[src * 3 + 2]
	return out


## A 256 by 32 strip of every entry, so a palette can be eyeballed. Diagnostic,
## not a game asset, but the corpus has shipped it since the Python extractor.
static func swatch(rgb: PackedByteArray) -> Image:
	var pixels := PackedByteArray()
	pixels.resize(ENTRIES * 32 * 3)
	for y in 32:
		for x in ENTRIES:
			var d := (y * ENTRIES + x) * 3
			pixels[d + 0] = rgb[x * 3 + 0]
			pixels[d + 1] = rgb[x * 3 + 1]
			pixels[d + 2] = rgb[x * 3 + 2]
	return Image.create_from_data(ENTRIES, 32, false, Image.FORMAT_RGB8, pixels)


## Paints palette indices into an opaque RGB image. Shared by TIL, BMP and BKG,
## which differ only in where their pixels start.
static func paint(indices: PackedByteArray, width: int, height: int,
		rgb: PackedByteArray) -> Image:
	var pixels := PackedByteArray()
	pixels.resize(width * height * 3)
	for i in width * height:
		var c := indices[i] * 3
		pixels[i * 3 + 0] = rgb[c + 0]
		pixels[i * 3 + 1] = rgb[c + 1]
		pixels[i * 3 + 2] = rgb[c + 2]
	return Image.create_from_data(width, height, false, Image.FORMAT_RGB8, pixels)
