class_name ObjectArtData
extends RefCounted

## Static art tables, layout constants, and animation metrics for interactive
## map objects, town sprites, mines, monster stacks, and ownership flags.
## Moved out of object_layer.gd.

const WorldStaticCanvas := preload("res://src/adventure/render/world_static_canvas.gd")

## mons32 = small (32px) adventure-map monster icons, one per creature in Knight order.
const MONS32 := UiKit.ART + "mons32/"
const MONS32_INDEX := {
	"peasant": 0, "archer": 1, "pikeman": 2, "swordsman": 3, "cavalry": 4, "paladin": 5,
	"goblin": 6, "orc": 7, "wolf": 8, "ogre": 9, "troll": 10, "cyclops": 11,
	"sprite": 12, "dwarf": 13, "elf": 14, "druid": 15, "unicorn": 16, "phoenix": 17,
	"centaur": 18, "gargoyle": 19, "griffin": 20, "minotaur": 21, "hydra": 22, "dragon": 23,
	"rogue": 24, "nomad": 25, "ghost": 26, "genie": 27,
}

## minimon = animated adventure-map monster sprites, 7 frames per creature (Knight order).
const MINIMON := UiKit.ART + "minimon/"
const MINIMON_FRAMES := 7

const DISSOLVE_SHADER := preload("res://src/town/building_reveal.gdshader")
const PICKUP_DISSOLVE_DELAY := 0.24
const PICKUP_DISSOLVE_DURATION := 0.24
const PICKUP_DISSOLVE_STEPS := 8.0
const PICKUP_TOTAL_DURATION := 0.48

## How long a guarding stack holds each idle pose.
##
## Measured in DOSBox on five creatures across two scenarios: the druid and the
## hydra on the sea shore, and the swordsman, pikeman and archer guarding
## Shangri-La. All five loop their six idle frames in 1.54 s, which is 0.257 s
## a pose, exactly two of the engine's sprite ticks. It is written as two ticks
## rather than as a bare number. The 0.6 s here before was invented and ran
## stacks 2.3x too slow.
##
## Five creatures with different art all landing on 1.54 s is what makes this
## the clock rather than the sprites: the druid's six frames are all distinct,
## the hydra's are a ping-pong of four, and the pikeman's are two images shown
## twice each.
const MINIMON_FRAME_S := 2.0 / WorldStaticCanvas.NATIVE_FPS

## Which frames the one-shot flourish plays when a hero attacks a stack.
##
## This is NOT the inverse of the idle loop, though it used to be. A DOSBox
## capture of Shangri-La's pikeman shows it thrusting its pike horizontally
## while merely standing guard, which is frame 2 or 5, and the loop it does it
## in is six poses long. So the original idles over every frame but the last,
## and only the seventh is held back. See MINIMON_IDLE_FRAMES.
##
## The lists below stay as the flourish's own choice of poses, which is a
## design call nothing has measured: a pikeman swinging through its two thrust
## frames reads better than a single freeze. They are no longer subtracted from
## the idle loop.
const MINIMON_ATTACK_FRAMES := {
	"peasant": [2, 5, 6],
	"archer": [6],
	"pikeman": [2, 5, 6],
	"swordsman": [4, 5, 6],
	"cavalry": [3, 4, 5, 6],
	"paladin": [6],
	"goblin": [6],
	"orc": [6],
	"wolf": [6],
	"ogre": [6],
	"troll": [6],
	"cyclops": [6],
	"sprite": [6],
	"dwarf": [6],
	"elf": [6],
	"druid": [6],
	"unicorn": [6],
	"phoenix": [6],
	"centaur": [6],
	"gargoyle": [6],
	"griffin": [6],
	"minotaur": [6],
	"hydra": [6],
	"dragon": [6],
	"rogue": [6],
	"nomad": [6],
	"ghost": [6],
	"genie": [6],
}

## minimon art is drawn facing screen-right (weapon/lance leans right in every
## idle+attack frame); flip_h mirrors a stack to face a hero approaching from
## the left.
const ATTACK_FLOURISH_FPS := 0.1     # fast swing, distinct from the calm idle pace
const ATTACK_BATTLE_DELAY := 0.35    # brief pause after the flourish (or freeze) before battle

## resource.icn pile sprites, one frame per resource.
const RESOURCE := UiKit.ART + "rsrc32/"
const RESOURCE_INDEX := {
	"wood": 61, "mercury": 62, "ore": 63, "sulfur": 64, "crystal": 65, "gems": 66, "gold": 67,
}

## Mine building pieces from rsrc32: [TL, TR, BL, BR, cart].
## 2x2 grid with BL anchored at the mine's action tile.
const MINE_PIECES := {
	"wood":    [5, 6, 7, 8],          # Sawmill (no cart)
	"ore":     [15, 16, 17, 18, 0],   # Ore Mine (Grass)
	"mercury": [25, 26, 27, 28],      # Alchemist's Lab (no cart)
	"sulfur":  [15, 16, 17, 18, 1],   # Sulfur Mine (Grass)
	"crystal": [15, 16, 17, 18, 2],   # Crystal Mine (Grass)
	"gems":    [15, 16, 17, 18, 3],   # Gems Mine (Grass)
	"gold":    [15, 16, 17, 18, 4],   # Gold Mine (Grass)
}

## Mine idle animation configurations (overlays from rsrc32).
const MINE_ANIMATIONS := {
	"mercury": {
		"rel_tile": "action_tile",
		"offset_tile": Vector2i(1, 0),     # BR (over the bubbling flask)
		"frames": [29, 30, 31, 32, 33, 34],
		"fps": 8.0
	}
}

## A monster stack hangs 5 px above its cell; mirrored, it runs leftward from
## cell x + 36 (heroes.exe 0x9aa5b, 0x9aab5; measured on DOSBox, 2026-10-15).
const STACK_ANCHOR_Y := -5
const STACK_MIRROR_X := 36

## flag32.icn player-color flags for owned ownable objects.
const FLAG32 := UiKit.ART + "flag32/"

## Owner flag per mine kind: the first flag32 frame (blue; +1 per player) and
## the tile it hangs on relative to the action tile. The Alchemist's Lab pole
## stands on the tile two above the doorway (frame 12, offset 9,12), measured on
## a DOS capture of Claw's lab at (29,48); the other mines keep the shared
## placement until they are captured the same way.
const FLAG_DEFAULT := {"frame": 8, "tile": Vector2i(0, -1)}
const FLAG_BY_RES := {
	# heroes.exe 0x7dae0 picks the flag by owned-site type: 0 sawmill 16+,
	# 1 alchemist lab 12+ at (x, y-2), 0x16 Dragon City, 0x17 Lighthouse, rest 8+.
	"wood": {"frame": 16, "tile": Vector2i(0, -1)},
	"mercury": {"frame": 12, "tile": Vector2i(0, -2)},
	# heroes.exe 0x7db26/0x7dbd3: owned-site type 0x16 flies flag32 20+ on the roof cell.
	"dragon_city": {"frame": 20, "tile": Vector2i(-1, -3)},
	# heroes.exe 0x7dc28: owned-site type 0x17 flies flag32 24+ two cells west.
	"lighthouse": {"frame": 24, "tile": Vector2i(-2, 0)},
}

## Shrine (Sanctuary): small wayside hut with an idol inside, found identically
## across obj32-01 id17 / obj32-03 id8 / obj32-06 id14 (the [G, Sw, Di] terrain
## variants per KB objects.md:126). Grass variant used regardless of underlying
## terrain (matches this codebase's other terrain-agnostic object sprites).
const SHRINE_SPRITE := UiKit.ART + "obj32-01/0017.png"

## Dragon City / Dragon Utopia is stored as ten rsrc32 tiles in native HOMM1
## maps. The B8=150 interaction cell is piece 60 at the bottom-right; pieces
## 51..59 are scenery cells around it. Keeping the native offsets makes the
## hand-authored fallback pixel-identical to the original composite.
const DRAGON_CITY_PIECES := [
	[51, Vector2i(-1, -3)],
	[52, Vector2i(-2, -2)], [53, Vector2i(-1, -2)], [54, Vector2i(0, -2)],
	[55, Vector2i(-2, -1)], [56, Vector2i(-1, -1)], [57, Vector2i(0, -1)],
	[58, Vector2i(-2, 0)], [59, Vector2i(-1, 0)], [60, Vector2i(0, 0)],
]

## town32 = adventure-map castle tiles (32px). The file is ten 12-sprite blocks,
## each a 4-wide x 3-tall settlement: top row = towers, middle = keep, bottom =
## moat/walls with the gate at col 2 (the gate tile is the town's action tile —
## the hero rides into the arch). The blocks run town/castle per faction in ART
## order Knight, Sorceress, Barbarian, Warlock, then Random Town / Random Castle.
## (Confirmed by rendering all ten: block 3 is the white-and-blue Sorceress
## castle, blocks 8-9 are the purple "Random Town"/"Random Castle" plates.)
const TOWN32 := UiKit.ART + "town32/"
const TOWN_BLOCK := {0: 1, 1: 5, 2: 3, 3: 7}   # our faction id -> castle block
const TOWN_BLOCK_UNWALLED := {0: 0, 1: 4, 2: 2, 3: 6}   # town (no castle) block

static func town_rows(faction: int, has_castle: bool = true) -> Array:
	var table := TOWN_BLOCK if has_castle else TOWN_BLOCK_UNWALLED
	var base: int = int(table.get(faction, table[0])) * 12
	return [[base, base + 1, base + 2, base + 3],
			[base + 4, base + 5, base + 6, base + 7],
			[base + 8, base + 9, base + 10, base + 11]]

## A guarding stack cycles every frame but the last.
##
## Measured in DOSBox on five creatures across two scenarios: the druid, the
## hydra, the swordsman, the pikeman and the archer all loop in 1.54 s, which
## at the 0.257 s pose length is six of the seven frames. Watching the pikeman
## through one loop confirms it: the horizontal pike thrust this table once
## called attack-only appears while it is doing nothing but standing there.
static func minimon_idle_frame_indices(_unit: String, frame_count: int = MINIMON_FRAMES) -> Array:
	var idle_indices: Array = []
	for i in maxi(frame_count - 1, 1):
		idle_indices.append(i)
	return idle_indices
