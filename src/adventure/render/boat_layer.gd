class_name BoatLayer
extends Node2D

## Renders only free boats. Embarked boats are rendered by the Hero node.

var _state: GameState
var _tile_size: int = 32

func setup(state: GameState, tile_size: int) -> void:
	_state = state
	_tile_size = tile_size
	refresh()

func refresh() -> void:
	for child in get_children():
		child.queue_free()
	if _state == null:
		return
	for boat: BoatState in _state.boats:
		var holder := Node2D.new()
		holder.position = Vector2(boat.tile.x * _tile_size, boat.tile.y * _tile_size)
		holder.set_meta("depth_tile", boat.tile)
		holder.set_meta("boat_id", boat.id)
		var sprite := HeroSprite.new()
		holder.add_child(sprite)
		# boat.owner stays (Summon Boat calls only your own), but an empty hull flies no flag.
		sprite.show_flag = false
		sprite.setup("knight", _tile_size)
		sprite.set_travel_mode(&"sea")
		sprite.set_direction(boat.direction)
		sprite.stop()
		add_child(holder)

## Resolve clicks anywhere on the rendered hull/flag back to the boat's
## logical water tile. Iterate topmost-first when sprites overlap.
func boat_tile_at_world(world_position: Vector2) -> Vector2i:
	var children := get_children()
	children.reverse()
	for holder: Node in children:
		if holder.is_queued_for_deletion() or not holder.has_meta("boat_id"):
			continue
		var boat := _state.boat_by_id(int(holder.get_meta("boat_id"))) if _state != null else null
		if boat == null:
			continue
		for child: Node in holder.get_children():
			if child is HeroSprite and (child as HeroSprite).hit_test_world(world_position):
				return boat.tile
	return Vector2i(-1, -1)
