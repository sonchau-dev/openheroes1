extends RefCounted

## Smacker (.smk) decoder, the format of HOMM1's cinematics.
##
##   104 bytes                header: signature, size, frame count, rate,
##                            flags, audio sizes, tree sizes, audio rates
##   frames * u32             frame sizes; the low two bits are flags
##   frames * u8              frame types: bit 0 palette, bit 1+n audio track n
##   trees_size bytes         four Huffman trees: mono map, mono colour, full, type
##   frames                   back to back: palette chunk, audio chunks, video
##
## Every bitstream is read least significant bit first. Video is 4x4 blocks
## of palette indices kept from frame to frame; a block run is mono (two
## colours and a 16-bit mask), full (16 literal pixels), skip or fill.
##
## Written from the public format description (wiki.multimedia.cx, "Smacker").
## HOMM1's six CD videos are all SMK2 with no line doubling or interlacing, so
## only that is decoded; anything else is refused rather than drawn wrong.
##
## Use: `open(bytes)`, then `next_frame()` once per frame for an RGB Image,
## and `audio()` for the whole first audio track.

const HEADER_SIZE := 104
const TRACKS := 7
const NODE := 1 << 30  # stays positive in a PackedInt32Array; values are 16-bit

const AUDIO_PACKED := 0x80000000
const AUDIO_16BIT := 0x20000000
const AUDIO_STEREO := 0x10000000
const AUDIO_RATE_MASK := 0xFFFFFF
# One frame of 48 kHz stereo 16-bit is 19 KB; a chunk past this is a bad header.
const AUDIO_CHUNK_MAX := 1 << 20

const BLOCK_MONO := 0
const BLOCK_FULL := 1
const BLOCK_SKIP := 2
const BLOCK_FILL := 3

var width := 0
var height := 0
var frame_count := 0
## Milliseconds per frame.
var frame_ms := 100.0
var audio_rate := 0
var audio_channels := 0
var audio_16bit := false

var _data: PackedByteArray
var _audio_flags := 0
var _offsets: PackedInt32Array
var _sizes: PackedInt32Array
var _types: PackedByteArray
var _mmap: Dictionary
var _mclr: Dictionary
var _full: Dictionary
var _type: Dictionary
var _palette := PackedByteArray()
var _pixels := PackedByteArray()
var _next := 0


## Parses the header and the four trees. Returns {ok, error}.
func open(data: PackedByteArray) -> Dictionary:
	_data = data
	if data.size() < HEADER_SIZE:
		return _fail("%d bytes is too small for a Smacker header" % data.size())
	var signature := data.slice(0, 4).get_string_from_ascii()
	if signature != "SMK2":
		return _fail("signature %s is not SMK2" % signature)
	width = data.decode_u32(4)
	height = data.decode_u32(8)
	frame_count = data.decode_u32(12)
	var rate := data.decode_s32(16)
	frame_ms = rate if rate > 0 else (-rate / 100.0 if rate < 0 else 100.0)
	var flags := data.decode_u32(20)
	if flags & 6:
		return _fail("flags 0x%x ask for line doubling or interlacing" % flags)
	if width % 4 or height % 4 or width == 0 or height == 0:
		return _fail("%dx%d is not a whole number of 4x4 blocks" % [width, height])
	if width * height > 640 * 480:  # the game's screen; every shipped video is 640x480
		return _fail("%dx%d is larger than the screen" % [width, height])
	var trees_size := data.decode_u32(52)
	_audio_flags = data.decode_u32(72)
	audio_rate = _audio_flags & AUDIO_RATE_MASK
	audio_channels = 2 if _audio_flags & AUDIO_STEREO else 1
	audio_16bit = (_audio_flags & AUDIO_16BIT) != 0

	# A ring frame (flag bit 0) repeats the first at the end; it is never shown.
	var stored := frame_count + (flags & 1)
	var at := HEADER_SIZE
	var trees_at := at + stored * 5
	var frames_at := trees_at + trees_size
	if data.size() < frames_at:
		return _fail("file ends before its frame tables")
	_sizes.resize(frame_count)
	_offsets.resize(frame_count)
	var offset := frames_at
	for i in frame_count:
		_offsets[i] = offset
		_sizes[i] = data.decode_u32(at + i * 4) & ~3
		offset += _sizes[i]
	if offset > data.size():
		return _fail("frames run %d bytes past the end of the file" % (offset - data.size()))
	_types = data.slice(at + stored * 4, at + stored * 4 + frame_count)

	var bits := BitReader.new(data, trees_at, trees_size)
	_mmap = _read_header_tree(bits)
	_mclr = _read_header_tree(bits)
	_full = _read_header_tree(bits)
	_type = _read_header_tree(bits)
	if bits.overrun:
		return _fail("the Huffman trees run past their %d bytes" % trees_size)
	_palette.resize(768)
	_palette.fill(0)
	_pixels.resize(width * height)
	_pixels.fill(0)
	_next = 0
	return {"ok": true, "error": ""}


## Decodes the next frame. Returns {ok, error, image}.
func next_frame() -> Dictionary:
	if _next >= frame_count:
		return _fail("no frame %d in %d" % [_next, frame_count])
	var at := _offsets[_next]
	var end := at + _sizes[_next]
	var type := _types[_next]
	_next += 1
	if type & 1:
		at = _read_palette(at)
	for track in TRACKS:
		if type & (2 << track):
			at += _data.decode_u32(at)
	if at > end:
		return _fail("frame %d: palette and audio overrun the frame" % (_next - 1))
	var bits := BitReader.new(_data, at, end - at)
	_decode_video(bits)
	if bits.overrun:
		return _fail("frame %d: video data overruns the frame" % (_next - 1))
	var rgb := PackedByteArray()
	rgb.resize(width * height * 3)
	var o := 0
	for index in _pixels:
		var p := index * 3
		rgb[o] = _palette[p]
		rgb[o + 1] = _palette[p + 1]
		rgb[o + 2] = _palette[p + 2]
		o += 3
	var image := Image.create_from_data(width, height, false, Image.FORMAT_RGB8, rgb)
	return {"ok": true, "error": "", "image": image}


## Decodes audio track 0 across every frame as interleaved PCM: unsigned
## 8-bit or signed 16-bit little-endian, as `audio_16bit` says.
## Returns {ok, error, pcm}.
func audio() -> Dictionary:
	var pcm := PackedByteArray()
	if audio_rate == 0:
		return {"ok": true, "error": "", "pcm": pcm}
	for i in frame_count:
		if not (_types[i] & 2):
			continue
		var at := _offsets[i]
		if _types[i] & 1:
			at += _data[at] * 4
		var length := _data.decode_u32(at)
		if _audio_flags & AUDIO_PACKED:
			var chunk := _unpack_audio(at + 4, length - 4)
			if not chunk["ok"]:
				return _fail("frame %d: %s" % [i, chunk["error"]])
			pcm.append_array(chunk["pcm"])
		else:
			pcm.append_array(_data.slice(at + 4, at + length))
	return {"ok": true, "error": "", "pcm": pcm}


func _read_palette(at: int) -> int:
	var end := at + _data[at] * 4
	var old := _palette.duplicate()
	var p := at + 1
	var entry := 0
	while entry < 256 and p < end:
		var t := _data[p]
		if t & 0x80:
			entry += (t & 0x7F) + 1
			p += 1
		elif t & 0x40:
			var count := (t & 0x3F) + 1
			var from := _data[p + 1]
			for k in count:
				if entry >= 256 or from + k >= 256:
					break
				for c in 3:
					_palette[entry * 3 + c] = old[(from + k) * 3 + c]
				entry += 1
			p += 2
		else:
			_palette[entry * 3] = _six_to_eight(t)
			_palette[entry * 3 + 1] = _six_to_eight(_data[p + 1])
			_palette[entry * 3 + 2] = _six_to_eight(_data[p + 2])
			entry += 1
			p += 3
	return end


static func _six_to_eight(v: int) -> int:
	return ((v & 0x3F) * 255 + 31) / 63


func _decode_video(bits: BitReader) -> void:
	for tree: Dictionary in [_mmap, _mclr, _full, _type]:
		var table: PackedInt32Array = tree["table"]
		for slot: int in tree["last"]:
			table[slot] = 0
	var across := width / 4
	var blocks := across * (height / 4)
	var block := 0
	while block < blocks:
		var type := _get_code(bits, _type)
		var kind := type & 3
		var run := _block_run((type >> 2) & 0x3F)
		while run > 0 and block < blocks:
			var o := (block / across) * width * 4 + (block % across) * 4
			match kind:
				BLOCK_MONO:
					var colours := _get_code(bits, _mclr)
					var mask := _get_code(bits, _mmap)
					var hi := colours >> 8
					var lo := colours & 0xFF
					for row in 4:
						for col in 4:
							_pixels[o + col] = hi if mask & (1 << col) else lo
						mask >>= 4
						o += width
				BLOCK_FULL:
					for row in 4:
						var right := _get_code(bits, _full)
						var left := _get_code(bits, _full)
						_pixels[o] = left & 0xFF
						_pixels[o + 1] = left >> 8
						_pixels[o + 2] = right & 0xFF
						_pixels[o + 3] = right >> 8
						o += width
				BLOCK_FILL:
					var colour := type >> 8
					for row in 4:
						for col in 4:
							_pixels[o + col] = colour
						o += width
			block += 1
			run -= 1


## Run lengths 1 to 59, then 128, 256, 512, 1024 and 2048.
static func _block_run(code: int) -> int:
	return code + 1 if code < 59 else 128 << (code - 59)


func _unpack_audio(at: int, length: int) -> Dictionary:
	var out_size := _data.decode_u32(at)
	if out_size > AUDIO_CHUNK_MAX:
		return _fail("audio chunk declares %d bytes of PCM" % out_size)
	var bits := BitReader.new(_data, at + 4, length - 4)
	var pcm := PackedByteArray()
	if not bits.bit():
		return {"ok": true, "error": "", "pcm": pcm}
	var stereo := bits.bit()
	var wide := bits.bit()
	if stereo != (audio_channels - 1) or wide != int(audio_16bit):
		return _fail("audio chunk format disagrees with the header")
	var trees: Array[PackedInt32Array] = []
	for i in 1 << (stereo + wide):
		var tree := PackedInt32Array()
		if bits.bit():
			_read_byte_tree(bits, tree)
			bits.bit()
		trees.append(tree)
	pcm.resize(out_size)
	var pred := [0, 0]
	if wide:
		for ch in range(stereo, -1, -1):
			var high := bits.bits(8)
			pred[ch] = _signed((high << 8) | bits.bits(8), 16)
		var count := out_size / 2
		for i in count:
			var ch := i & stereo
			if i > stereo:
				var lo := _walk(bits, trees[ch * 2])
				var hi := _walk(bits, trees[ch * 2 + 1])
				pred[ch] = _signed(pred[ch] + _signed(lo | (hi << 8), 16), 16)
			pcm.encode_s16(i * 2, pred[ch])
	else:
		for ch in range(stereo, -1, -1):
			pred[ch] = bits.bits(8)
		for i in out_size:
			var ch := i & stereo
			if i > stereo:
				pred[ch] = (pred[ch] + _signed(_walk(bits, trees[ch]), 8)) & 0xFF
			pcm[i] = pred[ch]
	if bits.overrun:
		return _fail("audio data overruns its chunk")
	return {"ok": true, "error": "", "pcm": pcm}


static func _signed(v: int, width_bits: int) -> int:
	var m := 1 << width_bits
	v &= m - 1
	return v - m if v >= m >> 1 else v


## A header tree: two 8-bit trees for the low and high bytes, three escape
## codes, then a 16-bit tree in the flattened layout `_get_code` walks. A leaf
## matching an escape becomes one of three recently-used value slots.
static func _read_header_tree(bits: BitReader) -> Dictionary:
	if not bits.bit():
		return {"table": PackedInt32Array([0, 0, 0, 0]), "last": [0, 0, 0]}
	var low := PackedInt32Array()
	if bits.bit():
		_read_byte_tree(bits, low)
		bits.bit()
	var high := PackedInt32Array()
	if bits.bit():
		_read_byte_tree(bits, high)
		bits.bit()
	var escapes := [bits.bits(16), bits.bits(16), bits.bits(16)]
	var last := [-1, -1, -1]
	var table := PackedInt32Array()
	_read_big_tree(bits, table, low, high, escapes, last)
	bits.bit()
	for k in 3:
		if last[k] == -1:
			last[k] = table.size()
			table.append(0)
	return {"table": table, "last": last}


## Appends a tree to `table`: a 1 bit is a node, stored as NODE | the size of
## its left subtree, a 0 bit a leaf. Returns the subtree's size.
static func _read_byte_tree(bits: BitReader, table: PackedInt32Array) -> int:
	if bits.bit():
		var at := table.size()
		table.append(0)
		var left := _read_byte_tree(bits, table)
		table[at] = NODE | left
		return left + 1 + _read_byte_tree(bits, table)
	table.append(bits.bits(8))
	return 1


static func _read_big_tree(bits: BitReader, table: PackedInt32Array, low: PackedInt32Array,
		high: PackedInt32Array, escapes: Array, last: Array) -> int:
	if bits.bit():
		var at := table.size()
		table.append(0)
		var left := _read_big_tree(bits, table, low, high, escapes, last)
		table[at] = NODE | left
		return left + 1 + _read_big_tree(bits, table, low, high, escapes, last)
	var value := _walk(bits, low) | (_walk(bits, high) << 8)
	for k in 3:
		if value == escapes[k]:
			last[k] = table.size()
			value = 0
			break
	table.append(value)
	return 1


## Walks a flattened tree; an empty tree always yields 0.
static func _walk(bits: BitReader, table: PackedInt32Array) -> int:
	if table.is_empty():
		return 0
	var i := 0
	while table[i] & NODE:
		if bits.bit():
			i += table[i] & ~NODE
		i += 1
	return table[i]


## Reads a 16-bit value and moves it to the front of the three recent slots.
static func _get_code(bits: BitReader, tree: Dictionary) -> int:
	var table: PackedInt32Array = tree["table"]
	var last: Array = tree["last"]
	var v := _walk(bits, table)
	if v != table[last[0]]:
		table[last[2]] = table[last[1]]
		table[last[1]] = table[last[0]]
		table[last[0]] = v
	return v


func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}


## Least-significant-bit-first reader. Reading past the end yields zeros and
## sets `overrun`, so a truncated stream is reported, not crashed on.
class BitReader:
	var overrun := false
	var _buf: PackedByteArray
	var _pos := 0
	var _end := 0

	func _init(buf: PackedByteArray, start: int, length: int) -> void:
		_buf = buf
		_pos = start * 8
		_end = (start + maxi(length, 0)) * 8

	func bit() -> int:
		if _pos >= _end:
			overrun = true
			return 0
		var v := (_buf[_pos >> 3] >> (_pos & 7)) & 1
		_pos += 1
		return v

	func bits(n: int) -> int:
		var v := 0
		for i in n:
			v |= bit() << i
		return v
