extends RefCounted

## BMP and BKG, which are one format with two names and nothing to do with
## Windows bitmaps.
##
##   0x21 0x00, u16 width, u16 height, then one palette index per pixel.
##
## BMP is 40 full-screen images and BKG is 11 battle sky strips, all 640x102.
## The only real difference is the output name, `<stem>.png` against
## `<stem>_bkg.png`.
##
## One anomaly, recruit2.bmp: it declares 320x165 and carries 8000 bytes more
## than that needs. Read exactly width times height and drop the tail.

const Palette := preload("res://tools/extract/palette.gd")

const HEADER_BYTES := 6
const MAGIC := [0x21, 0x00]


## Returns {ok, error, image, warning}.
static func decode(data: PackedByteArray, rgb: PackedByteArray) -> Dictionary:
	if data.size() < HEADER_BYTES:
		return _fail("file is %d bytes, too small for a header" % data.size())
	var warning := ""
	if data[0] != MAGIC[0] or data[1] != MAGIC[1]:
		warning = "magic is 0x%02X 0x%02X, expected 0x21 0x00" % [data[0], data[1]]
	var width := data.decode_u16(2)
	var height := data.decode_u16(4)
	if width == 0 or height == 0:
		return _fail("declares a %dx%d image" % [width, height])
	var needed := width * height
	if HEADER_BYTES + needed > data.size():
		return _fail("%dx%d needs %d bytes, file holds %d" % [
			width, height, HEADER_BYTES + needed, data.size()])
	return {"ok": true, "error": "", "warning": warning,
		"image": Palette.paint(data.slice(HEADER_BYTES, HEADER_BYTES + needed),
			width, height, rgb)}


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "error": reason, "image": null, "warning": ""}
