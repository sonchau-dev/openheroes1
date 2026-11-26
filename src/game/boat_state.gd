class_name BoatState
extends RefCounted

## A free adventure-map boat. While a hero is embarked the boat is removed
## from GameState.boats and its stable id is kept on HeroModel.

var id: int = -1
var tile: Vector2i = Vector2i(-1, -1)
var owner: int = -1
var direction: int = Direction.E

static func create(p_id: int, p_tile: Vector2i, p_owner: int,
		p_direction: int = Direction.E) -> BoatState:
	var boat := BoatState.new()
	boat.id = p_id
	boat.tile = p_tile
	boat.owner = p_owner
	boat.direction = p_direction
	return boat

func to_dict() -> Dictionary:
	return {
		"id": id,
		"tile": [tile.x, tile.y],
		"owner": owner,
		"direction": direction,
	}

static func from_dict(d: Dictionary) -> BoatState:
	var tile_value: Variant = d.get("tile", [-1, -1])
	var restored_tile := Vector2i(-1, -1)
	if tile_value is Array and tile_value.size() == 2:
		restored_tile = Vector2i(int(tile_value[0]), int(tile_value[1]))
	return create(int(d.get("id", -1)), restored_tile,
			int(d.get("owner", -1)), int(d.get("direction", Direction.E)))
