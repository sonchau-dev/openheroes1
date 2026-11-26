class_name BuildingCatalog
extends RefCounted

## Static loader for data/towns/<faction>_buildings.json (Castle Options rules).
## Mirrors ObjectCatalog's pattern: JSON cached per faction, pure lookups.

const PATH := "res://data/towns/%s_buildings.json"
const TOWN_PATH := "res://data/towns/%s_town.json"

## Original town-type / hero-class order used by map objects and crests.
## Background numbers differ: Sorceress uses townbkg1, Barbarian townbkg2.
const FACTIONS := ["knight", "barbarian", "sorceress", "warlock"]

## Castle Options common cells, column-major (decoded from caslwind.bin).
## Six faction dwellings follow; the screen appends "recruit_hero".
const COMMON_GRID_ORDER := [
	"mage_guild", "thieves_guild", "tavern",
	"shipyard", "well",
]
## Back-compat for Knight-only callers/tests.
const GRID_ORDER := [
	"mage_guild", "thieves_guild", "tavern",
	"shipyard", "well", "thatched_hut",
	"archery_range", "blacksmith", "armory",
	"jousting_arena", "cathedral",
]

static func faction_for_type(town_type: int) -> String:
	return FACTIONS[clampi(town_type, 0, FACTIONS.size() - 1)]

static func type_for_faction(faction: String) -> int:
	var i := FACTIONS.find(faction)
	return i if i >= 0 else 0

static func data(faction := "knight") -> Dictionary:
	return JsonFile.read_dict(PATH % faction)

static func entry(id: String, faction := "knight") -> Dictionary:
	return data(faction).get(id, {})

## The dwelling building that produces `unit`, or "" (non-dwelling units).
static func dwelling_for_unit(unit: String, faction := "knight") -> String:
	for id: String in data(faction):
		if String(data(faction)[id].get("unit", "")) == unit:
			return id
	return ""

static func town_data(faction := "knight") -> Dictionary:
	return JsonFile.read_dict(TOWN_PATH % faction)

static func dwelling_ids(faction := "knight") -> Array:
	var ids: Array = []
	for id: String in data(faction):
		if String(data(faction)[id].get("unit", "")) != "":
			ids.append(id)
	ids.sort_custom(func(a: String, b: String):
		return int(entry(a, faction).get("tier", 0)) < int(entry(b, faction).get("tier", 0)))
	return ids

static func units(faction := "knight") -> Array:
	var out: Array = []
	for id: String in dwelling_ids(faction):
		out.append(String(entry(id, faction).get("unit", "")))
	return out

static func grid_order(faction := "knight") -> Array:
	var ids := COMMON_GRID_ORDER.duplicate()
	ids.append_array(dwelling_ids(faction))
	return ids

## Return the LOCATORS.ICN sprite ID for the town/castle locator icon.
## 0 (knight): 12 (town) / 16 (castle)
## 1 (barbarian): 14 (town) / 18 (castle)
## 2 (sorceress): 13 (town) / 17 (castle)
## 3 (warlock): 15 (town) / 19 (castle)
static func locator_sprite_id(faction_or_type: Variant, has_castle: bool = true) -> int:
	var type_idx: int = 0
	if faction_or_type is String:
		type_idx = type_for_faction(faction_or_type)
	elif faction_or_type is int:
		type_idx = clampi(faction_or_type, 0, FACTIONS.size() - 1)

	var offset := 0
	match type_idx:
		0:
			offset = 0
		1:
			offset = 2
		2:
			offset = 1
		3:
			offset = 3
		_:
			offset = 0

	return (16 + offset) if has_castle else (12 + offset)

