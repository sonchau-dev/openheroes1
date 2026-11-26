class_name TravelRules
extends RefCounted

const INVALID := &"invalid"
const MOVE := &"move"
const BOARD := &"board"
const DISEMBARK := &"disembark"
## A land hero's last step onto a sailing hero beside the shore: the hero stays
## ashore and meets or attacks the boat. Costs a normal step, unlike BOARD.
const ENGAGE := &"engage"

## True for steps charged and walked like ordinary movement.
static func is_walk(kind: StringName) -> bool:
	return kind == MOVE or kind == ENGAGE

static func step_kind(map: MapData, grid: PassabilityGrid, state: GameState,
		mode: StringName, from: Vector2i, to: Vector2i) -> StringName:
	if not grid.is_in_boundsv(from) or not grid.is_in_boundsv(to):
		return INVALID
	var delta := to - from
	if absi(delta.x) > 1 or absi(delta.y) > 1 or delta == Vector2i.ZERO:
		return INVALID
	if mode == &"sea":
		if map.is_water(to):
			if state != null and state.boat_at(to) != null:
				return INVALID
			if delta.x != 0 and delta.y != 0:
				if not map.is_water(from + Vector2i(delta.x, 0)) \
						or not map.is_water(from + Vector2i(0, delta.y)):
					return INVALID
			return MOVE
		# heroes.exe 0x87a98, 0xa89f2: a hero at sea lands only on coast, and
		# a hero ashore is not coast, so it cannot be attacked from a boat.
		if map.is_land(to) and grid.can_enter(from, to) and grid.terminal_at(to) == null \
				and (state == null or state.hero_at(to) == null):
			return DISEMBARK
		return INVALID
	if map.is_water(to):
		if state == null:
			return INVALID
		var boat := state.boat_at(to)
		# A sailing hero's boat leaves state.boats, so look for the hero too.
		var sailor := state.hero_at(to) if boat == null else null
		if boat == null and (sailor == null or sailor.travel_mode != &"sea"):
			return INVALID
		var move_dir := Direction.from_delta(delta.x, delta.y)
		if grid._source_masked.has(from) \
				and (grid.entry_mask(from) & Direction.bit(move_dir)) == 0:
			return INVALID
		return BOARD if boat != null else ENGAGE
	return MOVE if grid.can_enter(from, to) else INVALID

static func step_cost(kind: StringName, from: Vector2i, to: Vector2i,
		map: MapData, hero_class: String = "") -> int:
	if kind == BOARD or kind == DISEMBARK:
		return 0
	return Hero.step_cost(from, to, map,
			kind == MOVE and map.is_water(from), hero_class)
