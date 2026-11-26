class_name CreatureCatalog
extends RefCounted

## Single source for all 28 native HOMM1 creatures. Native IDs are shared by
## MONSTERS/MONS32 artwork and the ATKSND/MOVE/WINCE/SHOOT sound banks.

const STATS_PATH := "res://data/creatures/stats.json"
const UNITS_PATH := "res://data/creatures/units.json"

static var _stats_cache: Dictionary = {}
static var _units_cache: Dictionary = {}

static func all_stats() -> Dictionary:
	if _stats_cache.is_empty():
		_stats_cache = JsonFile.read_dict(STATS_PATH)
	return _stats_cache

static func all_units() -> Dictionary:
	if _units_cache.is_empty():
		_units_cache = JsonFile.read_dict(UNITS_PATH)
	return _units_cache

static func stats(unit: String) -> Dictionary:
	return all_stats().get(unit, {})

static func art(unit: String) -> Dictionary:
	return all_units().get(unit, {})

static func native_id(unit: String) -> int:
	return int(stats(unit).get("native_id", -1))

const CARD_DIR := "res://assets/art/monsters/"
## monsters.icn frames are cropped to the creature. Each carries an offset inside
## a 70x70 card whose feet sit on the bottom edge, so a card has to be drawn at
## its own offset or tall and short creatures stand at different heights.
## The card sits at (6, 13) inside the 82x93 army slot (DOS hero screen, 2026-10-13).
const CARD_SLOT_ORIGIN := Vector2(6, 13)

## Top-left of a monsters.icn frame for a slot whose top-left is `slot_pos`.
static func card_position(native: int, slot_pos: Vector2) -> Vector2:
	var spec := SpecLoader.sprite(CARD_DIR, native)
	var offset: Vector2i = spec.get("offset", Vector2i.ZERO)
	return slot_pos + CARD_SLOT_ORIGIN + Vector2(offset)

static func singular(unit: String) -> String:
	return String(stats(unit).get("singular", unit.replace("_", " ")))

const FACTION_SLOT_BG := {
	"knight": "res://assets/art/strip/0003.png",
	"barbarian": "res://assets/art/strip/0004.png",
	"sorceress": "res://assets/art/strip/0005.png",
	"warlock": "res://assets/art/strip/0006.png",
	"neutral": "res://assets/art/strip/0007.png",
}

static func faction(unit: String) -> String:
	return String(stats(unit).get("faction", "neutral")).to_lower()

static func slot_background(unit: String) -> String:
	var fac := faction(unit)
	return FACTION_SLOT_BG.get(fac, "res://assets/art/strip/0003.png")

static func plural(unit: String) -> String:
	var entry := stats(unit)
	if entry.has("plural"):
		return String(entry.plural)
	var name := singular(unit)
	return name if name.ends_with("s") else name + "s"


