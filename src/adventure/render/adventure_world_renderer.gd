class_name AdventureWorldRenderer
extends Node2D

## The sole owner of the adventure world canvas. Scenery, objects and actors are
## painted at the depths heroes.exe paints them (AdventureDepth): row by row,
## layer 1 of a row under its actors, each actor under the layer 2 of its own
## cell and of the cells after it, and everything of a row under the rows below.
##
## Tree order matters where z ties (see AdventureDepth): terrain, scenery and
## objects come before the actors.

var terrain: MapRenderer
var scenery: WorldStaticCanvas
var objects: DynamicObjectProvider
var actors: Node2D
var boats: BoatLayer
var routes: Node2D
var fog: FogLayer
## The hero the view follows. While any hero walks, the walking one leads.
var focus_hero: Hero
var _resolver := MapArtResolver.new()
var _map: MapData
var _reverse := false
var _depths_dirty := false

func setup(map: MapData, state: GameState, player: PlayerState, nofog := false) -> void:
	_map = map
	terrain = MapRenderer.new()
	terrain.name = "Terrain"
	terrain.z_index = AdventureDepth.Z_TERRAIN
	add_child(terrain)
	terrain.render(map)

	scenery = WorldStaticCanvas.new()
	scenery.name = "Scenery"
	add_child(scenery)
	scenery.setup(map, _resolver)
	if state != null:
		scenery.holes = state.dug_tiles
	objects = DynamicObjectProvider.new()
	objects.name = "DynamicObjects"
	add_child(objects)
	objects.setup(map, null, _resolver)

	actors = Node2D.new()
	actors.name = "Actors"
	add_child(actors)
	boats = BoatLayer.new()
	boats.name = "Boats"
	actors.add_child(boats)
	boats.setup(state, map.tile_size)
	objects.set_actor_parent(actors)
	# Callers add a hero before setup() gives it a tile; re-depth once they are done.
	actors.child_entered_tree.connect(func(_n: Node) -> void:
			_update_actor_depths.call_deferred())

	routes = Node2D.new()
	routes.name = "Routes"
	routes.z_index = AdventureDepth.Z_ROUTE
	add_child(routes)

	fog = FogLayer.new()
	fog.name = "Fog"
	fog.z_index = AdventureDepth.Z_FOG
	add_child(fog)
	fog.setup(map, player)
	objects.set_fog(fog)
	if nofog:
		fog.explore_everything()
	_update_actor_depths()

func add_actor(actor: Node2D) -> void:
	actors.add_child(actor)
	_update_actor_depths()

func refresh_object(object_id: int) -> void:
	if scenery != null:
		scenery.refresh_object(object_id)
	if objects != null:
		objects.refresh_object(object_id)
	_update_actor_depths()

func dissolve_object(obj: MapObject, delay: float = 0.24, duration: float = 0.24) -> Tween:
	if obj == null:
		return null
	if scenery != null:
		scenery.refresh_object(obj.id)
	if objects != null:
		return objects.dissolve_object(obj, delay, duration, get_tree())
	return null

func refresh_boats() -> void:
	if boats != null:
		boats.refresh()
		_update_actor_depths()

func play_attack_flourish(stack: NeutralStack, hero_tile: Vector2i) -> void:
	await objects.play_attack_flourish(stack, hero_tile)

func resume_stack_idle(stack: NeutralStack) -> void:
	if objects != null:
		objects.resume_stack_idle(stack)

## Whether rows are currently painted right to left.
func reversed() -> bool:
	return _reverse

func _process(_delta: float) -> void:
	# Depths only change while a hero walks or turns; structural changes call
	# _update_actor_depths() themselves. One extra pass after a walk ends so
	# paint_tile() settles on the arrival cell.
	var leader := _leading_hero()
	var moving := leader != null \
			and AdventureDepth.reverse_for(leader.get_direction()) != _reverse
	if not moving and actors != null:
		for child: Node in actors.get_children():
			if child is Hero and (child as Hero).is_moving():
				moving = true
				break
	if moving or _depths_dirty:
		_update_actor_depths()
	_depths_dirty = moving
	if scenery != null:
		scenery.sync_holes()

## Depth of every actor from the cell it is painted on, and the row direction
## from the focused hero's facing.
func _update_actor_depths() -> void:
	if actors == null:
		return
	var leader := _leading_hero()
	if leader != null:
		_set_reverse(AdventureDepth.reverse_for(leader.get_direction()))
	for child: Node in actors.get_children():
		if child is Hero:
			var hero := child as Hero
			hero.z_as_relative = false
			hero.z_index = AdventureDepth.actor_z(hero.paint_tile(), _reverse)
		elif child is BoatLayer:
			for holder: Node in child.get_children():
				_place_actor(holder)
		else:
			_place_actor(child)

func _place_actor(node: Node) -> void:
	if node is CanvasItem and node.has_meta("depth_tile"):
		var item := node as CanvasItem
		item.z_as_relative = false
		item.z_index = AdventureDepth.actor_z(node.get_meta("depth_tile"), _reverse)

func _leading_hero() -> Hero:
	for child: Node in actors.get_children():
		if child is Hero and (child as Hero).is_moving() and (child as Hero).visible:
			return child as Hero
	if focus_hero != null and is_instance_valid(focus_hero):
		return focus_hero
	return null

func _set_reverse(reverse: bool) -> void:
	if reverse == _reverse:
		return
	_reverse = reverse
	scenery.set_reverse(reverse)
	objects.set_reverse(reverse)
