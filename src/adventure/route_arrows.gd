class_name RouteArrows
extends RefCounted

## Selects the route.icn arrow for one path step.
##
## Green set = indices 14..27 (red set = green - 14). Only right-facing
## sprites exist in the ICN; left-side directions reuse them mirrored
## (flip_h). Semantics verified against the sprite art: the arrow HEAD
## points where the path leaves the tile (v_out), the TAIL points back
## at the previous tile (-v_in).
##
## Exact sprites exist for straight runs and the eight 45-degree turns.
## Sharper turns (90/135 degrees) have no dedicated art, so we pick the
## sprite whose head matches v_out exactly and whose tail is nearest to
## the previous tile.

const _N := Vector2i(0, -1)
const _NE := Vector2i(1, -1)
const _E := Vector2i(1, 0)
const _SE := Vector2i(1, 1)
const _S := Vector2i(0, 1)
const _SW := Vector2i(-1, 1)
const _W := Vector2i(-1, 0)
const _NW := Vector2i(-1, -1)

## Straight arrows: step delta -> [green_index, flip_h].
const STRAIGHT := {
	_N: [14, false], _NE: [15, false], _E: [16, false], _SE: [17, false],
	_S: [18, false], _SW: [17, true], _W: [16, true], _NW: [15, true],
}

## Turn arrows: [v_in][v_out] -> [green_index, flip_h].
## Curve heads/tails (unflipped): 19 N/SW, 20 NE/W, 21 E/NW, 22 E/SW,
## 23 SE/W, 24 S/NW, 25 NE/S, 26 SE/N.
const _TURN := {
	_N: { _NE: [25, false], _NW: [25, true], _E: [22, false], _W: [22, true] },
	_NE: { _N: [19, false], _E: [22, false], _SE: [23, false], _NW: [25, true] },
	_E: { _NE: [20, false], _SE: [23, false], _N: [19, false], _S: [24, false] },
	_SE: { _E: [21, false], _S: [24, false], _NE: [20, false], _SW: [26, true] },
	_S: { _SE: [26, false], _SW: [26, true], _E: [21, false], _W: [21, true] },
	_SW: { _S: [24, true], _W: [21, true], _SE: [26, false], _NW: [20, true] },
	_W: { _SW: [23, true], _NW: [20, true], _N: [19, true], _S: [24, true] },
	_NW: { _W: [22, true], _N: [19, true], _NE: [25, false], _SW: [23, true] },
}

const DEST_GREEN := 27
const DEST_RED := 13

## Arrow for a step entering a tile along v_in and leaving along v_out.
## Returns [green_index, flip_h]; red variant = green_index - 14.
static func select(v_in: Vector2i, v_out: Vector2i) -> Array:
	if _TURN.has(v_in) and _TURN[v_in].has(v_out):
		return _TURN[v_in][v_out]
	# 135-degree turns and anything unexpected: no curve art fits, so use
	# the straight arrow that points where the path goes next.
	return STRAIGHT.get(v_out, [16, false])
