class_name BattlefieldShip
extends RefCounted

const TILE_DIR := "res://assets/art/boat.xtl/"
const OBJECT_DIR := "res://assets/art/boat.obj/"
const TILE_OFFSET := Vector2(-39, -79)
const FIELD_TOP := 102
const FIELD_BOTTOM := 460

static func layout() -> Dictionary:
	return {
		"terrain": "ship",
		"obstacles": [
			{"id": 0, "cells": [Vector2i(2, 0)], "row": 0},
			{"id": 1, "cells": [Vector2i(4, 4)], "row": 4},
		],
	}

static func paint(parent: Node, origin: Vector2, step: Vector2,
		layout_data: Dictionary) -> void:
	var field := Control.new()
	field.name = "ShipDeck"
	field.position = Vector2(0, FIELD_TOP)
	field.size = Vector2(640, FIELD_BOTTOM - FIELD_TOP)
	field.clip_contents = true
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(field)
	for row in range(0, 6):
		for col in range(-2, 8):
			var id := 4 + posmod(col * 37 + row * 61 + col * row * 17, 7)
			var sprite := Sprite2D.new()
			sprite.texture = load(TILE_DIR + "%04d.png" % id) as Texture2D
			sprite.centered = false
			sprite.position = Hex.to_pixel(col, row, origin, step) + TILE_OFFSET - field.position
			sprite.z_index = row
			field.add_child(sprite)
	var spec := SpecLoader.load_spec(OBJECT_DIR + "spec.json")
	for obstacle: Dictionary in layout_data.obstacles:
		var id := int(obstacle.id)
		var sp = spec.sprites[id]
		var cell: Vector2i = obstacle.cells[0]
		var object_sprite := Sprite2D.new()
		object_sprite.name = "ShipObstacle%d" % id
		object_sprite.texture = load(OBJECT_DIR + sp.file) as Texture2D
		object_sprite.centered = false
		object_sprite.position = Hex.to_pixel(cell.x, cell.y, origin, step) + Vector2(sp.offset)
		object_sprite.z_index = 100 + int(obstacle.row)
		parent.add_child(object_sprite)
