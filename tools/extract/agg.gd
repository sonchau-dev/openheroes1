extends RefCounted

## The heroes.agg container.
##
##   u16                       entry count
##   count * 14 bytes          directory records
##   ...                       payloads, back to back, in record order
##   tail: count * 15 bytes    name records
##
## A record carries a name hash, two bytes nobody has needed, and the payload
## size stored twice. It carries no offset, so a payload's position is only
## knowable by accumulating every size before it. That is why `parse` insists
## the accumulated end lands exactly on the name table: if it does not, every
## offset after the first bad record is wrong and the decode that follows would
## produce plausible garbage.
##
## Verified against the retail archive in
## data/knowledge_base/research/agg-format-spec.md.

const INFO_RECORD := 14
const NAME_RECORD := 15
const NAME_CHARS := 13


## Returns {ok: bool, error: String, entries: Array[{name, offset, size}]}.
static func parse(data: PackedByteArray) -> Dictionary:
	if data.size() < 2:
		return _fail("archive is %d bytes, too small to hold a directory" % data.size())
	var count := data.decode_u16(0)
	if count == 0:
		return _fail("archive declares zero entries")

	var payload_start := 2 + INFO_RECORD * count
	var name_table := data.size() - NAME_RECORD * count
	if name_table < payload_start:
		return _fail("directory of %d entries does not fit in %d bytes" % [count, data.size()])

	var entries: Array[Dictionary] = []
	var offset := payload_start
	for i in count:
		var record := 2 + INFO_RECORD * i
		var size := data.decode_u32(record + 6)
		entries.append({"name": _name_at(data, name_table, i), "offset": offset, "size": size})
		offset += size

	if offset != name_table:
		return _fail("payloads end at %d but the name table starts at %d" % [offset, name_table])
	return {"ok": true, "error": "", "entries": entries}


## Names are 13 characters cut at the first NUL. The two bytes after them are
## whatever was in the build machine's buffer, not padding, so they are never
## read: `poof.icn\0 85WAV` is a real record.
static func _name_at(data: PackedByteArray, table: int, index: int) -> String:
	var start := table + NAME_RECORD * index
	var raw := data.slice(start, start + NAME_CHARS)
	var nul := raw.find(0)
	if nul >= 0:
		raw = raw.slice(0, nul)
	return raw.get_string_from_ascii().strip_edges()


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "error": reason, "entries": [] as Array[Dictionary]}
