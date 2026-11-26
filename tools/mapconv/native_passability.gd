extends RefCounted

## The original's land passability, read from the cells the way heroes.exe
## does it. Decoded 2026-10-04 (data/knowledge_base/research/ai-planner-decodes.md, "Passability").
##
## A cell is blocked when its B7 bit 0x80 is set. The .map stores most of
## those bits; the map-start pass (0x7b45f) adds:
##   - a cell whose two layers are both mountain or forest (groups 8 and 9);
##   - a cell with a layer-2 sprite only, of class 53 or 57, whose east
##     neighbour is in its class group (52-55 mountain, 56-60 forest), or of
##     class 55 or 59 whose east neighbour is not. The other cells of those
##     four classes drop their sprite to layer 1;
##   - a mountain or forest cell (class 52-60) on the map's edge.
## It also sets B6 bit 0x80 on class-50 cells, the flat ground decals the
## adventure map paints with the ground tile (heroes.exe 0x9a85e).
##
## The step check (0x87a98) then refuses a blocked cell, a step north (N, NE,
## NW) out of a cell with a layer-1 sprite and no B6 bit 0x80, and a step
## south (S, SE, SW) into such a cell unless it holds a walk-on object. So
## those cells are entered and left from the sides and from below only.
##
## Checked bit for bit against saves of Claw, the siege test and Shangri-La,
## and against every step nine days of the original's computer heroes took.
##
## Taking an object off a cell (0xb46d8) clears B8 and the layer-1 sprite.
## When the cell's second class (B7's low 7 bits) is 1..0x7e, that class
## becomes B8, B7 keeps only its blocked bit, and the cell gets the
## mountain and forest rule above again (0x7ca6c): it ends blocked, or with
## its layer-2 sprite on layer 1. So a pickup lying on the edge of a forest
## leaves a blocked or one-way cell behind (data/knowledge_base/
## homm1-native-data.md 4.3.3).

const W := 72

## Object classes (B8 - 128) a hero may step onto from above (0x87d60).
const WALK_ON := [0x1a, 0x1d, 6, 8, 0xb, 0x30, 2, 3, 4, 9, 0x1b, 0x24, 0x2c, 0x2b]

## {"blocked": {Vector2i: true}, "directional": {Vector2i: true},
## "sprites": {Vector2i: true}, "objects": {Vector2i: true},
## "after_removal": {Vector2i: true when blocked, false when one-way}}, screen
## coordinates. Directional cells take Direction.MASK_BUILDING; sprite cells are
## every cell with a layer-1 sprite and no B6 bit 0x80, walk-on objects
## included; object cells are every cell whose B8 is not 0, scenery included,
## which the creature-month spawn (0x8026b) skips.
static func analyse(m: RefCounted) -> Dictionary:
	var cells := start_cells(m)
	var blocked := {}
	var directional := {}
	var sprites := {}
	var objects := {}
	var after_removal := {}
	for sx in W:
		for sy in W:
			var c: PackedByteArray = cells[sx * W + sy]
			var tile := Vector2i(sx, sy)
			# A layer-1 sprite with no B6 bit 0x80 (the map-start pass sets it
			# on class 50): the cell a monster above it does not guard (0x84138).
			var sprite := c[2] != 0xFF and c[8] != 0x32 and not (c[6] & 0x80)
			if sprite:
				sprites[tile] = true
			if c[8] != 0:
				objects[tile] = true
			if c[7] & 0x80:
				blocked[tile] = true
			elif sprite and not ((c[8] & 0x80) and (c[8] & 0x7F) in WALK_ON):
				directional[tile] = true
			var left := _after_removal(cells, sx, sy)
			if left >= 0:
				after_removal[tile] = left == 1
	return {"blocked": blocked, "directional": directional, "sprites": sprites,
			"objects": objects, "after_removal": after_removal}


## What the removal routine (0xb46d8, 0x7ca6c) leaves of an object cell:
## 1 blocked, 0 its layer-2 sprite dropped to layer 1 (entered and left from
## the sides and below), -1 open ground.
static func _after_removal(cells: Array, sx: int, sy: int) -> int:
	var c: PackedByteArray = cells[sx * W + sy]
	var second := c[7] & 0x7F
	if not (c[8] & 0x80) or second == 0 or second == 0x7F:
		return -1
	if c[7] & 0x80:
		return 1
	var k := second - 0x35
	if c[4] == 0xFF or not (k in [0, 2, 4, 6]) or sx + 1 >= W:
		return -1
	var east: PackedByteArray = cells[(sx + 1) * W + sy]
	return 1 if (k in [0, 4]) == (_group(east[8]) == _group(second)) else 0


## The cells as the game holds them after the map-start pass, indexed
## [screen x * W + screen y]. The pass is idempotent, so it is safe on cells
## apply_start() already rewrote.
static func start_cells(m: RefCounted) -> Array:
	var cells: Array = []
	cells.resize(W * W)
	for sx in W:
		for sy in W:
			# HMap's cell stream has the screen row as its x.
			cells[sx * W + sy] = m.cell(sy, sx)
	for sy in W:
		for sx in W:
			var c: PackedByteArray = cells[sx * W + sy]
			if c[2] != 0xFF and c[4] != 0xFF and (c[1] & 15) in [8, 9] and (c[3] & 15) in [8, 9]:
				c[7] |= 0x80
			var k := c[8] - 0x35
			if c[2] == 0xFF and c[4] != 0xFF and k in [0, 2, 4, 6] and sx + 1 < W:
				var east: PackedByteArray = cells[(sx + 1) * W + sy]
				var same := _group(east[8]) == _group(c[8])
				if (k in [0, 4]) == same:
					c[7] |= 0x80
				else:
					c[1] = c[3]
					c[2] = c[4]
					c[3] = 0
					c[4] = 0xFF
			if (sx == 0 or sy == 0 or sx == W - 1 or sy == W - 1) and c[8] >= 0x34 and c[8] <= 0x3C:
				c[7] |= 0x80
			if c[8] == 0x32:
				c[6] |= 0x80
			cells[sx * W + sy] = c
	return cells


## Rewrite the HMap's cells with the map-start pass, so the converter paints
## each sprite on the layer the game paints it on: the moved mountain and forest
## sprites on layer 1, and the class-50 decals flat with the ground.
static func apply_start(m: RefCounted) -> void:
	var cells := start_cells(m)
	for sx in W:
		for sy in W:
			m.set_cell(sy, sx, cells[sx * W + sy])


static func _group(object_class: int) -> int:
	if object_class >= 0x34 and object_class <= 0x37:
		return 0x34
	if object_class >= 0x38 and object_class <= 0x3C:
		return 0x38
	return object_class
