class_name AdventureDepth
extends RefCounted

## The adventure map's paint order, as heroes.exe paints it.
##
## The full redraw (0x99d4c) and the dirty-cell redraw (0xa3e05) call the cell
## routine 0x9a398 over the 15x15 view with a mask that picks its passes:
##   1  ground tile, then a layer-1 sprite on a cell with B6 bit 0x80 flat on
##      top of it (the class-50 decals: flowers, dunes, cracks, small hills);
##   2  layer 1 with its animation and its B5 overlay (mine carts, town flags);
##   8  the monster, hero or boat on the cell;
##   4  layer 2 with its B5 overlay (mine flags);
##   32 fog.
## The redraw runs pass 1 over every cell, pass 2 over row 0, then for each row
## r passes 8+4 over row r followed by pass 2 over row r + 1, and fog last.
## Within a row the cells go left to right, or right to left while the focused
## hero faces SW, W or NW (0x164 > 4, directions numbered clockwise from N).
##
## So a hero is painted on its cell's turn: over layer 1 of its own row and the
## rows above, over layer 2 of the rows above and of the cells before it in its
## row; under layer 2 of its own cell and the cells after it, and under all of
## the rows below. A walking hero is painted on the cell it left until half the
## step and on the cell it enters from then on (0xa83e8 scrolls the view one
## tile at the halfway frame and restarts the offset at -16 px).
##
## Godot sorts by z and breaks ties by tree order. Each row owns a band of z
## values: layer 1 at the bottom, then one slot per cell in drawing order. An
## actor takes its cell's slot and layer 2 takes the next one, so layer 2 of the
## cell before an actor shares the actor's z; the renderer keeps scenery ahead
## of actors in the tree so that tie goes to the scenery underneath.

const Z_TERRAIN := -4090
const Z_GROUND := -4080
const Z_ROW0 := -4000
## Layer 1, then one slot per column of a 72-wide map, then the last layer 2.
const ROW_BAND := 75
const MAX_COLUMNS := 72
const Z_ROUTE := 3000
const Z_FOG := 3100

## Phases a map's render_parts use.
const GROUND := "ground"
const LAYER_1 := "base"
const LAYER_2 := "top"

static func layer1_z(row: int) -> int:
	return Z_ROW0 + clampi(row, 0, 71) * ROW_BAND

## z of a hero, boat or monster painted on `cell`.
static func actor_z(cell: Vector2i, reverse: bool) -> int:
	return layer1_z(cell.y) + 1 + _slot(cell.x, reverse)

## z of the layer-2 sprite (and its overlay) on `cell`.
static func layer2_z(cell: Vector2i, reverse: bool) -> int:
	return actor_z(cell, reverse) + 1

## z of a render part or object sprite of `phase` painted on `cell`.
static func phase_z(phase: String, cell: Vector2i, reverse: bool) -> int:
	match phase:
		GROUND:
			return Z_GROUND
		LAYER_2:
			return layer2_z(cell, reverse)
		_:
			return layer1_z(cell.y)

## Rows are painted right to left while the focused hero faces SW, W or NW.
static func reverse_for(direction: int) -> bool:
	return direction == Direction.SW or direction == Direction.W or direction == Direction.NW

static func _slot(column: int, reverse: bool) -> int:
	var x := clampi(column, 0, MAX_COLUMNS - 1)
	return MAX_COLUMNS - 1 - x if reverse else x
