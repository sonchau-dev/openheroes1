class_name BattlefieldLayout
extends RefCounted

## Terrain decoration and its rules footprint.
##
## Features authentic HOMM1 battlefield obstacle generation matching DOS heroes.exe (0x89ca8-0x8a11f):
## - Siege / castle defense: 0 natural obstacles (skipped).
## - Open field: 0..3 obstacles placed in the middle three columns (cols 2..4 in 7-col grid)
##   and any row (0..4).
## - If a cell is occupied by an obstacle, heroes.exe re-rolls once.
## - Chooses random sprite frame 0..2 from the terrain's .obj ICN asset.
## - For boat and lava, sprite 2 is an empty 10x1 filler frame, so heroes.exe forces sprite 2 to 0.
## - Screen position is Hex.to_pixel(col, row, Hex.ORIGIN, Hex.STEP) + offset from spec.json.
## - Depth sorting: z_index = 100 + row.

const OBJECT_DIR := "res://assets/art/%s.obj/"

const TERRAIN_MAP: Dictionary = {
	"water": "boat",
	"ship": "boat",
	"boat": "boat",
	"grass": "grass",
	"snow": "snow",
	"swamp": "swamp",
	"lava": "lava",
	"desert": "desert",
	"dirt": "dgrass",
	"dgrass": "dgrass",
}

static func obj_name_for_terrain(terrain: String) -> String:
	return String(TERRAIN_MAP.get(terrain.to_lower(), "grass"))

static func generate(terrain: String = "grass", rng: RandomNumberGenerator = null) -> Dictionary:
	var obj_name := obj_name_for_terrain(terrain)
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var count := rng.randi_range(0, 3)
	var spec_dir := OBJECT_DIR % obj_name
	var spec := SpecLoader.load_spec(spec_dir + "spec.json")

	var obstacles: Array = []
	var occupied := {}

	for i in range(count):
		var col := rng.randi_range(2, 4)
		var row := rng.randi_range(0, 4)
		var cell := Vector2i(col, row)
		if occupied.has(cell):
			col = rng.randi_range(2, 4)
			row = rng.randi_range(0, 4)
			cell = Vector2i(col, row)

		occupied[cell] = true
		var sprite_id := rng.randi_range(0, 2)
		if (obj_name == "boat" or obj_name == "lava") and sprite_id == 2:
			sprite_id = 0

		var offset := Vector2.ZERO
		if not spec.sprites.is_empty() and sprite_id < spec.sprites.size():
			offset = Vector2(spec.sprites[sprite_id].offset)

		var pos := Hex.to_pixel(col, row, Hex.ORIGIN, Hex.STEP) + offset
		var obs := {
			"id": sprite_id,
			"position": pos,
			"cells": [cell],
			"row": row,
			"terrain": obj_name,
		}

		var replaced := false
		for idx in range(obstacles.size()):
			if obstacles[idx].cells[0] == cell:
				obstacles[idx] = obs
				replaced = true
				break
		if not replaced:
			obstacles.append(obs)

	return {
		"terrain": obj_name,
		"obstacles": obstacles,
	}

static func grass_reference() -> Dictionary:
	return {
		"terrain": "grass",
		"obstacles": [
			{
				"id": 1,                         # stump, grass.obj/spec.json
				"position": Vector2(219, 102),
				"cells": [Vector2i(2, 0)],
				"row": 0,
				"terrain": "grass",
			},
			{
				"id": 2,                         # large tree
				"position": Vector2(260, 316),
				"cells": [Vector2i(3, 4)],
				"row": 4,
				"terrain": "grass",
			},
		],
	}

static func blocked_cells(layout: Dictionary) -> Dictionary:
	var blocked := {}
	for obstacle: Dictionary in layout.get("obstacles", []):
		for cell: Vector2i in obstacle.get("cells", []):
			blocked[cell] = true
	return blocked

static func paint_obstacles(parent: Node, layout: Dictionary) -> void:
	var layout_terrain: String = layout.get("terrain", "grass")
	for obstacle: Dictionary in layout.get("obstacles", []):
		var id := int(obstacle.get("id", -1))
		if id < 0:
			continue
		var terrain: String = obstacle.get("terrain", layout_terrain)
		var obj_name := obj_name_for_terrain(terrain)
		var spec_dir := OBJECT_DIR % obj_name
		var spec := SpecLoader.load_spec(spec_dir + "spec.json")
		var filename := "%04d.png" % id
		if not spec.sprites.is_empty() and id < spec.sprites.size():
			filename = spec.sprites[id].file
		var tex := load(spec_dir + filename) as Texture2D
		if tex == null:
			continue
		var sprite := Sprite2D.new()
		sprite.name = "BattleObstacle%d" % id
		sprite.texture = tex
		sprite.centered = false
		sprite.position = Vector2(obstacle.get("position", Vector2.ZERO))
		# Match unit feet sorting. Obstacles are added before BattleView, so a
		# unit on the same row draws in front while lower-row art draws above.
		sprite.z_index = 100 + int(obstacle.get("row", 0))
		parent.add_child(sprite)
