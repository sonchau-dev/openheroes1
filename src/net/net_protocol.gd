class_name NetProtocol
extends RefCounted

## Wire framing for remote play.
##
## HOMM1 shipped exactly one game-level message: the whole run, serialized to a
## save file named REMOTE.GAM and mailed down the link at each turn boundary
## (KB homm1-native-data.md §5.1). We carry the same payload — an unmodified
## SaveGame envelope — so this class only has to frame and compress it.
##
## Pure static functions with no engine state, so the frame guards below are
## unit-testable without a peer, a scene, or the Game autoload.
##
## Frame (little-endian):
##   0  u16  magic 'HM'
##   2  u8   protocol version
##   3  u8   kind (KIND_STATE / KIND_FINAL)
##   4  u32  uncompressed payload size
##   8  10 bytes BUILD tag
##  18  ...  zstd-compressed UTF-8 JSON envelope

const MAGIC := 0x484D
const VERSION := 1
## Bump when data/ tables or the map converter change: two builds with
## different rules cannot share one run even on the same protocol version.
const BUILD := "2026-11-07"
const HEADER_SIZE := 8 + 10

## A turn handoff: "here is the run, it is now your move."
const KIND_STATE := 1
## The last packet of a match. Same payload plus a `net_message` key holding the
## game-over text, so both clients end on the same words.
const KIND_FINAL := 2

## Refuse anything larger than this rather than hand a hostile or corrupt length
## to decompress(). Real envelopes measure ~10 KB at scenario start and grow
## with map_object_state; 8 MB is orders of magnitude of headroom.
const MAX_PAYLOAD := 8 * 1024 * 1024

static func encode(envelope: Dictionary, kind: int = KIND_STATE) -> PackedByteArray:
	var raw := JSON.stringify(envelope).to_utf8_buffer()
	var body := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var frame := PackedByteArray()
	frame.resize(8)
	frame.encode_u16(0, MAGIC)
	frame.encode_u8(2, VERSION)
	frame.encode_u8(3, kind)
	frame.encode_u32(4, raw.size())
	frame.append_array(BUILD.to_utf8_buffer())
	frame.append_array(body)
	return frame

## Returns {"kind": int, "envelope": Dictionary} or {"error": String}. Never
## throws and never trusts the header: a truncated, oversized, or non-JSON
## frame comes back as an error the session can report and drop.
static func decode(frame: PackedByteArray) -> Dictionary:
	if frame.size() < HEADER_SIZE:
		return {"error": "Truncated packet"}
	if frame.decode_u16(0) != MAGIC:
		return {"error": "Not a Heroes packet"}
	var version := frame.decode_u8(2)
	if version != VERSION:
		return {"error": "Remote player runs a different version (%d)" % version}
	var build := frame.slice(8, HEADER_SIZE).get_string_from_utf8()
	if build != BUILD:
		return {"error": "Remote player runs a different build (%s)" % build}
	var kind := frame.decode_u8(3)
	if kind != KIND_STATE and kind != KIND_FINAL:
		return {"error": "Unknown packet kind (%d)" % kind}
	var size := frame.decode_u32(4)
	if size <= 0 or size > MAX_PAYLOAD:
		return {"error": "Bad packet size (%d)" % size}
	var body := frame.slice(HEADER_SIZE)
	var raw := body.decompress(size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != size:
		return {"error": "Corrupt packet data"}
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if not (parsed is Dictionary):
		return {"error": "Corrupt packet payload"}
	return {"kind": kind, "envelope": parsed as Dictionary}
