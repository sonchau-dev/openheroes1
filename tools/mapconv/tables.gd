extends RefCounted

## What a .map cell's bytes mean.
##
## These are a decode contract, not configuration. Every entry was established
## by cross-checking all 21 retail scenarios against the DOS original and is
## pinned by tests/test_native_map_art.gd, so unlike the extractor's
## data/extract_rules.json there is nothing here a different release would
## change. They stay in code because the comments are the evidence, and a JSON
## file would lose them.
##
## Format authority: data/knowledge_base/homm1-native-data.md 4.2 to 4.3.2.

const W := 72
const H := 72
const CELL := 10

## Group selector, cell bytes B1 and B3, to the extracted sprite directory.
const GROUP_DIR := {
	0: "obj32-00", 1: "obj32-01", 2: "obj32-02", 3: "obj32-03", 4: "obj32-04",
	5: "obj32-05", 6: "obj32-06", 7: "obj32-07", 8: "mtn32", 9: "tree32",
	10: "town32", 11: "rsrc32", 12: "mons32", 13: "art32", 14: "flag32",
}

## Ground index B0 / 20 to a terrain character, keyed to data/terrain/terrain.json.
const TERRAIN_BAND := {0: "W", 1: "G", 2: "S", 3: "T", 4: "L", 5: "D", 6: "I"}

## rsrc32 pile sprite to resource, read off a labelled contact sheet and
## matching object_layer.gd's RESOURCE_INDEX. Piles are typed by B8; mines come
## from the trailer instead, because a mine's sprite only says which terrain it
## sits on.
const RESOURCE_PILE := {61: "wood", 62: "mercury", 63: "ore", 64: "sulfur",
	65: "crystal", 66: "gems", 67: "gold"}

## Trailer mine faction byte to resource, in the executable's resource order.
const MINE_RESOURCE := {0: "wood", 1: "mercury", 2: "ore", 3: "sulfur",
	4: "crystal", 5: "gems", 6: "gold"}

## mons32 index to creature. Index 28 is the editor's unrestricted monster
## placeholder and 29 to 33 are its five ascending strength classes; all six are
## rolled at run time, so they are absent here on purpose.
const MONS32_CREATURE := {
	0: "peasant", 1: "archer", 2: "pikeman", 3: "swordsman", 4: "cavalry",
	5: "paladin", 6: "goblin", 7: "orc", 8: "wolf", 9: "ogre", 10: "troll",
	11: "cyclops", 12: "sprite", 13: "dwarf", 14: "elf", 15: "druid",
	16: "unicorn", 17: "phoenix", 18: "centaur", 19: "gargoyle", 20: "griffin",
	21: "minotaur", 22: "hydra", 23: "dragon", 24: "rogue", 25: "nomad",
	26: "ghost", 27: "genie",
}
const RANDOM_STACK_IDS := [191, 195, 196, 197, 198, 199]

## town32 is ten blocks of twelve sprites, four wide and three tall, paired
## town then castle per faction in art order Knight, Sorceress, Barbarian,
## Warlock, then the two purple random placeholder blocks. A map stores only the
## lower eight tiles of a block; the engine composites the top row.
## Our faction ids: 0 Knight, 1 Barbarian, 2 Sorceress, 3 Warlock.
const TOWN32_BLOCK_FACTION := [0, 0, 2, 2, 1, 1, 3, 3, -1, -1]

## Groups emitted as scenery rather than objects.
##
## rsrc32 is in the list on purpose. A native mine, sawmill or lighthouse marks
## only its entrance tile as interactive and leaves the rest of the building on
## ordinary scenery cells, so dropping those cells is what once left every mine
## drawn from a hand-picked stand-in tile. The groups left out are the ones the
## original itself resolves at run time and object_layer.gd draws from game
## state: town32 faction castles, flag32 owner flags, mons32 stacks, art32
## artifacts.
const DECOR_DIRS := ["tree32", "mtn32", "rsrc32", "obj32-00", "obj32-01",
	"obj32-02", "obj32-03", "obj32-04", "obj32-05", "obj32-06", "obj32-07"]

## Interactive classes whose native footprint really does span several cells.
## Everything else is one object per cell: a same-B8 flood fill happily welds
## neighbouring piles, chests and stacks into one blob, which silently deleted
## about 500 objects across the 21 scenarios.
## Types whose upper cell carries the same B8 class without the 0x80 flag.
const BODY_ABOVE_TYPES := ["skeleton"]

const MULTI_TILE_TYPES := ["skeleton", "wagon_camp", "whirlpool", "shipwreck", "faerie_ring", "oasis"]

## obj32 plates in the passive B8 classes 49 and 50 are terrain overlays, not
## obstacles. The old painted-coverage heuristic lost that distinction and made
## flowers, grass tufts, mushrooms and low cave plates solid.
const PASSABLE_SCENERY_CLASSES := [49, 50]

## Sprites the original treats as run-time placeholders rather than final art:
## the purple random town, castle, mine and resource plates, the five
## random-monster classes and the random-artifact frame. Withheld from both art
## and decor so our own resolved sprite draws instead.
static func is_placeholder(dir: String, index: int) -> bool:
	match dir:
		"town32":
			return index >= 96 and index < 120
		"rsrc32":
			return index >= 84 and index < 89
		"mons32":
			return index >= 28 and index < 34
		"art32":
			return index == 37
	return false


## Sprites that map to an engine type but are not in data/objects/catalog.json,
## confirmed off contact sheets.
const EXTRA_SPRITE_TYPE := {
	"art32/37": "artifact", "art32/26": "artifact", "art32/29": "artifact",
	"obj32-07/0": "sign",
}

## B8 object class to engine type. B8 is a stable global class id, so this is
## the primary lookup: it catches every terrain variant of a known object,
## grass, snow, lava and the rest, which a per-sprite catalog lookup misses.
const B8_TYPE := {
	129: "mine", 130: "sign", 131: "buoy", 132: "skeleton", 133: "demon_cave",
	134: "chest", 135: "faerie_ring", 136: "campfire", 137: "fountain",
	138: "gazebo", 139: "dwelling", 140: "graveyard", 141: "dwelling",
	142: "dwelling", 143: "dwelling", 144: "dwelling", 145: "dwelling",
	150: "dragon_city", 151: "lighthouse", 152: "watermill", 153: "mine",
	154: "stack", 155: "obelisk", 156: "oasis", 157: "resource", 160: "mine",
	161: "oracle", 162: "shrine", 163: "shipwreck", 164: "statue",
	167: "dwelling", 169: "stone_liths", 170: "wagon_camp", 172: "whirlpool",
	173: "windmill", 176: "artifact", 189: "artifact", 190: "resource",
	191: "stack", 192: "town", 193: "town", 195: "stack", 196: "stack",
	197: "stack", 198: "stack", 199: "stack",
}

## Editor inspection and scenery classes that carry a high B8 but have no visit
## behaviour: rosebush, sandpit, tree stump, oak, "nothing", mountains. Their
## cells stay in the decor pass, and they are deliberately not counted as
## skipped objects.
const B8_DECOR_ONLY := [158, 159, 165, 166, 174, 175, 177, 178, 179, 180, 181,
	182, 183, 184, 185, 186]

## Flat swamp cover: B8 178 holds only obj32-03 bog pools and bush patches.
## Its plates block a hero from above like any obstacle, but they lie on the
## ground, so every one of their cells is a lowest row and none of them is
## upper body for the cell above. Probed in DOS on 2026-09-24 with
## Continentia's crystal mine copied into Claw: the hero stood on both rows
## of the bog under the mine, left each cell only to the sides or below, and
## reached the mine through the forest corner and the cart cell above the bog.
const FLAT_OBSTACLE_CLASSES := [178]

## Which creature each dwelling class recruits, and what heroes.exe calls it.
##
## The executable's object name table lists the five map dwellings in class
## order: Straw Hut, House, Cabin, Log Cabin, Log Cabin, strings 5328 to 5332,
## and the art agrees. 141 is the conical straw hovel, 142 the plastered house
## with the red roof, 143 the log cabin with the thatched roof, 144 and 145 the
## two snow huts. Thatched Hut, Cottage and Archery Range are town buildings
## from the same table, not map objects; naming 142 and 143 after those left
## both 141 and 143 recruiting goblins.
const DWELLING_UNIT := {139: "genie", 141: "goblin", 142: "peasant",
	143: "archer", 144: "dwarf", 145: "peasant", 167: "nomad"}
const DWELLING_TITLE := {139: "Ancient Lamp", 141: "Straw Hut", 142: "House",
	143: "Cabin", 144: "Log Cabin", 145: "Log Cabin", 167: "Desert Tent"}

## Adventure map dwelling stats, from KB objects.md 7.1 and 7.3.
const DWELLING_STATS := {
	"peasant": {"weekly_min": 5, "weekly_max": 10, "initial_min": 20, "initial_max": 50},
	"archer": {"weekly_min": 1, "weekly_max": 4, "initial_min": 1, "initial_max": 4},
	"goblin": {"weekly_min": 3, "weekly_max": 6, "initial_min": 10, "initial_max": 30},
	"dwarf": {"weekly_min": 1, "weekly_max": 3, "initial_min": 1, "initial_max": 3},
	"nomad": {"cost": 200, "weekly_min": 1, "weekly_max": 3, "initial_min": 10,
		"initial_max": 20},
	"genie": {"cost": 650, "cost_resources": {"gold": 650, "gems": 1}, "weekly": 0,
		"weekly_min": 0, "weekly_max": 0, "initial_min": 2, "initial_max": 5,
		"disappears_when_empty": true},
}

## Native maps use art32 frame 37 as a random-artifact placeholder; 26 and 29
## are explicit placements.
const NATIVE_ARTIFACTS := {26: "bottomless_sack", 29: "nomad_boots"}


## The trailer's faction byte follows town32's art order (0 Knight, 1 Sorceress,
## 2 Barbarian, 3 Warlock, 4 random); our ids swap Sorceress and Barbarian.
## Across all 94 explicit castles and towns in the 30 scenarios, trailer 1 sits
## on Sorceress sprites and trailer 2 on Barbarian sprites, never the reverse,
## and a DOS capture of Claw shows the same.
static func town_type_from_trailer(byte: int) -> int:
	match byte:
		1:
			return 2
		2:
			return 1
	return byte


## Canonical town faction from any explicit town32 footprint tile.
## 0 Knight, 1 Barbarian, 2 Sorceress, 3 Warlock, -1 random or unknown.
static func town_type_from_sprite(sprite: Array) -> int:
	if sprite.is_empty() or String(sprite[0]) != "town32":
		return -1
	var block := int(sprite[1]) / 12
	if block >= 0 and block < TOWN32_BLOCK_FACTION.size():
		return TOWN32_BLOCK_FACTION[block]
	return -1
