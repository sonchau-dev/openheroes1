class_name Direction
extends RefCounted

## 8 compass facings, clockwise from south. Screen coordinates (y grows downward).
enum { S, SE, E, NE, N, NW, W, SW }

const DELTAS := {
	S: Vector2i(0, 1), SE: Vector2i(1, 1), E: Vector2i(1, 0), NE: Vector2i(1, -1),
	N: Vector2i(0, -1), NW: Vector2i(-1, -1), W: Vector2i(-1, 0), SW: Vector2i(-1, 1),
}

static func from_delta(dx: int, dy: int) -> int:
	var s := Vector2i(signi(dx), signi(dy))
	for d in DELTAS:
		if DELTAS[d] == s:
			return d
	return S

## 1 << d — for building entry-direction masks. Bit d set on a tile's mask
## means the tile may be entered from its neighbor in direction d.
static func bit(d: int) -> int:
	return 1 << d

## The opposite compass direction (N<->S, SE<->NW, ...).
static func reflect(d: int) -> int:
	return (d + 4) % 8

const MASK_ALL := 0b11111111

## A Faerie Ring has two visible openings at its left and right ends.
const MASK_HORIZONTAL := (1 << W) | (1 << E)

## A visitable building is entered from its side and southern neighbors,
## never from above.
const MASK_BUILDING := (1 << W) | (1 << E) | (1 << SW) | (1 << S) | (1 << SE)
