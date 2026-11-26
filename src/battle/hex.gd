class_name Hex
extends RefCounted

## Battlefield hex grid: 7 cols x 5 rows, odd-r offset (odd rows shift right).
## Authentic HOMM1 field (KB battle.md §12.2): 35 cells, rows 2/4 shifted right
## half a cell. Cell pitch 78x80, measured from the original DOS game (the
## 78x99 XTL hex tiles tile seamlessly horizontally).

const COLS := 7
const ROWS := 5
## Screen anchor of cell (0, 0) and the cell pitch, measured off a native
## 640x480 DOSBox frame: col-0 anchor x=66, row-0 feet y=139.
const ORIGIN := Vector2(66, 139)
const STEP := Vector2(78, 80)

## Column the castle wall stands in during a siege. KB battle.md 12.3: the wall
## occupies the fifth vertical column of the arena, leaving the defender the two
## columns behind it. Mirrored when the defender holds the left side.
static func wall_col(defender_side: int) -> int:
	return 2 if defender_side == 0 else 4

static func in_bounds(col: int, row: int) -> bool:
	return col >= 0 and col < COLS and row >= 0 and row < ROWS

static func to_cube(col: int, row: int) -> Vector3i:
	var x := col - (row - (row & 1)) / 2
	var z := row
	return Vector3i(x, -x - z, z)

static func from_cube(cube: Vector3i) -> Vector2i:
	var row := cube.z
	var col := cube.x + (row - (row & 1)) / 2
	return Vector2i(col, row)

## Continue one cell past `adjacent` in the direction from `origin`.
static func behind(origin: Vector2i, adjacent: Vector2i) -> Vector2i:
	var a := to_cube(origin.x, origin.y)
	var b := to_cube(adjacent.x, adjacent.y)
	return from_cube(b + (b - a))

static func distance(a_col: int, a_row: int, b_col: int, b_row: int) -> int:
	var a := to_cube(a_col, a_row)
	var b := to_cube(b_col, b_row)
	return int((abs(a.x - b.x) + abs(a.y - b.y) + abs(a.z - b.z)) / 2)

const _EVEN := [Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]
const _ODD := [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 1)]

## Neighbour of `cell` in heroes.exe strike direction `dir` (table 0x1f1f8):
## 0 up-right, 1 right, 2 down-right, 3 down-left, 4 left, 5 up-left.
static func strike_step(cell: Vector2i, dir: int) -> Vector2i:
	var deltas: Array = _ODD if (cell.y & 1) else _EVEN
	return cell + deltas[[1, 0, 5, 4, 3, 2][dir]]

static func neighbors(col: int, row: int) -> Array:
	var deltas: Array = _ODD if (row & 1) else _EVEN
	var out: Array = []
	for d: Vector2i in deltas:
		var c := col + d.x
		var r := row + d.y
		if in_bounds(c, r):
			out.append(Vector2i(c, r))
	return out

## Ground point (feet) of a hex, given grid origin and per-cell pixel step.
static func to_pixel(col: int, row: int, origin: Vector2, step: Vector2) -> Vector2:
	var shift := step.x * 0.5 if (row & 1) else 0.0
	return Vector2(origin.x + col * step.x + shift, origin.y + row * step.y)
