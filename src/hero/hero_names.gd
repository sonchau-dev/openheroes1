class_name HeroNames
extends RefCounted

## The two names every hero carries in the original.
##
## `heroes.exe` stores 72 strings at file offset `0x10f8ca`: for each of the 36
## recruitable heroes a full name and a short name (KB heroes.md 4.2, KB
## strings.md 1). The save record keeps both -- 13 bytes for the full name and
## 9 for the short one (KB save-format.md 4).
##
## The adventure-map status window draws the SHORT name. The DOS capture shows
## "Gallant" for Sir Gallant, drawn in `smalfont` with the pen at (486, 427)
## (KB file-formats-assets.md 11.7, confirmed on a DOS capture).
## Because a short name is at most 8 characters, it always fits the 64 px
## information cell under the crest; the original never had to shorten it.

const CATALOG_PATH := "res://data/heroes/catalog.json"

## Titles the original's own short names drop ("Sir Gallant" -> "Gallant").
const TITLES := ["Lord ", "Sir ", "Queen ", "Warlock "]

static var _short_names: Dictionary = {}


## The short name of `full_name`, or the name itself when it is not one of the
## 36 recruitable heroes. Names outside that pool (campaign rulers, custom
## heroes) fall back to the original's own shape: drop the title, keep the
## rest, so "Lord Ironfist" reads as "Ironfist".
static func short_for(full_name: String) -> String:
	if full_name.is_empty():
		return full_name
	var table := _table()
	if table.has(full_name):
		return String(table[full_name])
	for title in TITLES:
		if full_name.begins_with(title):
			var rest := full_name.substr(title.length())
			if not rest.is_empty():
				return rest
	return full_name


## The full table, keyed by full name. Loaded once from the hero catalog.
static func table() -> Dictionary:
	return _table()


static func _table() -> Dictionary:
	if not _short_names.is_empty():
		return _short_names
	var parsed := JsonFile.read_dict(CATALOG_PATH)
	_short_names = parsed.get("short_names", {})
	return _short_names
