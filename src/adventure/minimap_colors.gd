# src/adventure/minimap_colors.gd
class_name MinimapColors
extends RefCounted

## ground32 tile index -> HOMM1 radar color. Index ranges follow the ground32 TIL
## layout (water first, then grass, etc.). The current test map uses only water (0)
## and grass (30); ranges cover the full terrain set for later real .map loads.

## Radar colours measured from the DOS original (Claw and Badlands with the
## 101495 reveal) and matched to heroes' palette (kb.pal, 6-bit values x4):
## one flat colour per ground tile class. Tiles that carry a mountain or tree
## on their base layer use the palette entry three places further on, which
## is the darker `_SHADED` colour. Frames of ground6 group in fives: frames
## 0-4 water, 5-9 grass, 10-14 snow, 15-19 swamp, 20-24 rock, 25-29 desert,
## 30 and up dirt; a ground32 tile index is four times its frame.
const WATER   := Color8(24, 32, 168)
const GRASS   := Color8(68, 152, 52)
const SNOW    := Color8(200, 200, 200)
const SWAMP   := Color8(32, 76, 84)
const ROCK    := Color8(40, 40, 40)
const DESERT  := Color8(216, 184, 16)
const DIRT    := Color8(120, 72, 36)
const UNKNOWN := Color8(96, 96, 96)

const WATER_SHADED  := Color8(4, 8, 128)
const GRASS_SHADED  := Color8(40, 128, 32)
const SNOW_SHADED   := Color8(176, 176, 176)
const SWAMP_SHADED  := Color8(20, 52, 60)
const ROCK_SHADED   := Color8(16, 16, 16)   # palette rule, not seen on a map
const DESERT_SHADED := Color8(192, 144, 0)
const DIRT_SHADED   := Color8(96, 56, 24)

## Kingdom colours on the radar, measured from the DOS original (blue, green,
## red, yellow); neutral towns and mines, and heroes of other kingdoms, are gray.
const PLAYER_COLORS := [
	Color8(60, 72, 212),   # blue
	Color8(20, 100, 12),   # green
	Color8(156, 24, 24),   # red
	Color8(164, 108, 0),   # yellow
]
const NEUTRAL_OBJECT := Color8(176, 176, 176)
const OTHER_HERO := Color8(176, 176, 176)

# [first tile index, last tile index, base colour, shaded colour]
const _RANGES := [
	[0, 19, WATER, WATER_SHADED],
	[20, 39, GRASS, GRASS_SHADED],
	[40, 59, SNOW, SNOW_SHADED],
	[60, 79, SWAMP, SWAMP_SHADED],
	[80, 99, ROCK, ROCK_SHADED],
	[100, 119, DESERT, DESERT_SHADED],
	[120, 247, DIRT, DIRT_SHADED],
]

## Radar colour of a ground32 tile index; `shaded` is the darker variant used
## under a base-layer mountain or tree.
static func radar_color(tile_index: int, shaded: bool = false) -> Color:
	for r: Array in _RANGES:
		if tile_index >= r[0] and tile_index <= r[1]:
			return r[3] if shaded else r[2]
	return UNKNOWN

static func color_for(tile_index: int) -> Color:
	return radar_color(tile_index, false)

static func player_color(color_index: int) -> Color:
	if color_index < 0 or color_index >= PLAYER_COLORS.size():
		return NEUTRAL_OBJECT
	return PLAYER_COLORS[color_index]
