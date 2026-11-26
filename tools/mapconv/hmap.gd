extends RefCounted

## A HOMM1 .map or .cmp binary.
##
##   0x000  scenario header, 0x554 bytes, present in .map and absent in .cmp
##   0x554  u16 0x1112, the only magic the format has
##   0x55A  72 * 72 cells of 10 bytes, x-major within a row
##   ...    fixed trailer tables of 3-byte records, then event data
##
## A .cmp campaign file is the same blob with the header cut off, so its name,
## description and objectives come from CampaignCatalog rather than the file.
##
## Cell bytes, from data/knowledge_base/homm1-native-data.md 4.3:
##   B0 ground tile, B1/B2 layer 1 group and sprite, B3/B4 layer 2 group and
##   sprite, B5 resource-cart overlay sprite, B6 flags, B7 the blocked bit
##   (0x80) and a second object class, B8 object class, B9 a per-object
##   quantity. NativePassability reads the blocking from them.

const Tables := preload("res://tools/mapconv/tables.gd")

const MAGIC := 0x1112
const HEADER_BYTES := 0x554
const NAME_AT := 0x004
const NAME_MAX := 15
const DESCRIPTION_AT := 0x09A
const DESCRIPTION_MAX := 121
const TRAILER_RECORD := 3

var ok := false
var error := ""
var headered := false
var name := ""
var description := ""
var difficulty := 0
var size := 2

var _data := PackedByteArray()
var _cells_at := 0
var _trailer_at := 0


func _init(data: PackedByteArray) -> void:
	_data = data
	headered = data.size() > HEADER_BYTES + 2 and data.decode_u16(HEADER_BYTES) == MAGIC
	var headerless := data.size() > 6 and data.decode_u16(0) == MAGIC
	if not headered and not headerless:
		error = "no 0x1112 marker at byte 0 or 0x554, so this is not a HOMM1 map"
		return
	if headered:
		name = _text(NAME_AT, NAME_MAX)
		description = _text(DESCRIPTION_AT, DESCRIPTION_MAX)
		difficulty = data[2]
		size = data[3]
	_cells_at = (HEADER_BYTES + 6) if headered else 6
	_trailer_at = _cells_at + Tables.W * Tables.H * Tables.CELL
	if _trailer_at > data.size():
		error = "file holds %d bytes, too few for a %dx%d cell grid" % [
			data.size(), Tables.W, Tables.H]
		return
	ok = true


## The ten bytes of one cell. Callers index them by their B number.
func cell(x: int, y: int) -> PackedByteArray:
	var at := _cells_at + (y * Tables.W + x) * Tables.CELL
	return _data.slice(at, at + Tables.CELL)


## Overwrite one cell, for the map-start pass (NativePassability.apply_start).
func set_cell(x: int, y: int, bytes: PackedByteArray) -> void:
	var at := _cells_at + (y * Tables.W + x) * Tables.CELL
	for i in Tables.CELL:
		_data[at + i] = bytes[i]


## The 72x72 authored ambient loop grid from the fixed trailer (heroes.exe 0x7a6e6).
## Offset is cells_end + 254 bytes. Each byte is a loop index (0..21) or 0xFF (no sound).
func ambient_sound_grid() -> PackedByteArray:
	var at := _trailer_at + 254
	if at + Tables.W * Tables.H > _data.size():
		return PackedByteArray()
	return _data.slice(at, at + Tables.W * Tables.H)


## Aligned (x, y, value) records from the fixed trailer tables.
##
## Slots 0 to 35 are towns and castles; capture objects start at 38. Matching
## coordinates against the cell objects avoids depending on the padding or on
## the variable-length event data that follows.
func trailer_value_at(screen_x: int, screen_y: int, first: int, count: int,
		allowed: Array = []) -> int:
	var slots := (_data.size() - _trailer_at) / TRAILER_RECORD
	var last: int = mini(first + count, slots)
	for slot in range(first, last):
		var at := _trailer_at + slot * TRAILER_RECORD
		if _data[at] != screen_x or _data[at + 1] != screen_y:
			continue
		var value := _data[at + 2]
		if allowed.is_empty() or allowed.has(value):
			return value
	return -1


## Layer 1 reads B1 and B2, layer 2 reads B3 and B4. Returns [dir, index], or
## an empty array when the cell carries nothing on that layer.
static func sprite(cell_bytes: PackedByteArray, layer: int) -> Array:
	var group := cell_bytes[1] if layer == 1 else cell_bytes[3]
	var index := cell_bytes[2] if layer == 1 else cell_bytes[4]
	if index == 0xFF:
		return []
	# Retail maps use the layer-1 selector 187 on the bottom-right cells of
	# ordinary mines. B2 is the terrain-specific empty-cart underlay in rsrc32
	# (12, 14, 18, 22, 24) and B5 with B6 bit 4 select the filled cart painted
	# over it. Treating 187 as an unknown group dropped the underlay and left
	# restored carts floating without their mountain or track plate. Probed on
	# Claw: crystal (43,37) = 12, ore (42,42) = 18.
	if layer == 1 and group == 187:
		return ["rsrc32", index]
	if not Tables.GROUP_DIR.has(group):
		return []
	# There is no off-by-one on group 11. Hallfiry's demo notes claim resources
	# are stored index minus one; the retail maps are not. The B8=157 resource
	# cells across all 21 scenarios use raw indices 61 to 67, exactly rsrc32's
	# labelled wood through gold piles, B8=153 mines use the mine-mouth tiles
	# 11, 13, 17, 21 and 23, and B8=160 uses sawmill tile 7. Shifting by one
	# turned Claw's wood pile into an alchemist's cauldron on screen.
	return [Tables.GROUP_DIR[group], index]


func _text(at: int, length: int) -> String:
	var raw := _data.slice(at, at + length)
	var nul := raw.find(0)
	if nul >= 0:
		raw = raw.slice(0, nul)
	# The strings are latin1 in the file. Everything the retail maps use is
	# ASCII, and get_string_from_ascii stops at the first byte that is not.
	return raw.get_string_from_ascii()
