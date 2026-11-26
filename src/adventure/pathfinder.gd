class_name Pathfinder
extends RefCounted

## Deterministic raw-cost route field over PassabilityGrid.
##
## HOMM1 expands the lowest accumulated movement cost first and retains the
## first predecessor when two routes have equal raw cost. Both details are
## visible in route.icn: a FIFO flood or goal-directed A* chooses different
## equal-cost turns. Current movement points color/execute the selected route;
## they do not change its geometry.

const DIR_DELTAS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
	Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
]

const DIR_IS_DIAG: Array[bool] = [
	true, false, true, false,
	true, false, true, false,
]

const INF_COST: int = 1073741824 # 1 << 30

class Heap:
	var costs := PackedInt32Array()
	var seqs := PackedInt32Array()
	var nodes := PackedInt64Array()
	var pop_cost: int = 0
	var pop_node: int = 0

	func push(cost: int, seq: int, node: int) -> void:
		costs.append(cost)
		seqs.append(seq)
		nodes.append(node)
		var i := costs.size() - 1
		while i > 0:
			@warning_ignore("integer_division")
			var parent_i := (i - 1) / 2
			var p_cost := costs[parent_i]
			if not (cost < p_cost or (cost == p_cost and seq < seqs[parent_i])):
				break
			costs[i] = p_cost
			seqs[i] = seqs[parent_i]
			nodes[i] = nodes[parent_i]
			i = parent_i
		costs[i] = cost
		seqs[i] = seq
		nodes[i] = node

	func pop() -> void:
		pop_cost = costs[0]
		pop_node = nodes[0]
		var last_idx := costs.size() - 1
		var tail_cost := costs[last_idx]
		var tail_seq := seqs[last_idx]
		var tail_node := nodes[last_idx]
		costs.resize(last_idx)
		seqs.resize(last_idx)
		nodes.resize(last_idx)
		if last_idx > 0:
			var i := 0
			while true:
				var left := i * 2 + 1
				if left >= last_idx:
					break
				var child := left
				var right := left + 1
				if right < last_idx:
					var r_cost := costs[right]
					var l_cost := costs[left]
					if r_cost < l_cost or (r_cost == l_cost and seqs[right] < seqs[left]):
						child = right
				var c_cost := costs[child]
				if not (c_cost < tail_cost or (c_cost == tail_cost and seqs[child] < tail_seq)):
					break
				costs[i] = c_cost
				seqs[i] = seqs[child]
				nodes[i] = nodes[child]
				i = child
			costs[i] = tail_cost
			seqs[i] = tail_seq
			nodes[i] = tail_node

	func is_empty() -> bool:
		return costs.is_empty()

static func build(map: MapData) -> PassabilityGrid:
	return PassabilityGrid.new(map)

## Inclusive land path from -> to. Movement values remain in the public
## signature for callers that also use them while rendering/executing a route;
## native route geometry is selected from raw movement costs only.
static func find(grid: PassabilityGrid, from: Vector2i, to: Vector2i,
		map: MapData = null, hero_class: String = "",
		current_move_points: int = -1, max_move_points: int = -1,
		seen: PackedByteArray = PackedByteArray(),
		blocked: Dictionary = {}) -> Array:
	if not _valid_endpoints(grid, from, to):
		return []
	if from == to:
		return [from]
	var target_guard := grid.action_object_at(to) as NeutralStack
	if target_guard != null and not target_guard.is_armed():
		target_guard = null
	var field := build_land_field(grid, from, hero_class,
			current_move_points, max_move_points, target_guard,
			-1, {}, to, blocked, false, seen)
	return path_from_field(field, to)

## Build one complete route field. It can reconstruct every ordinary land
## destination without rerunning the flood (important for mouse-hover and AI
## scoring). Terminal tiles enter the field but are never expanded.
##
## `boats` (tile -> anything) lists free boats: a route may end on one, as the
## computer's route search lets a land hero step into a boat's cell.
## `target` stops the flood as soon as the target tile is popped.
## `blocked` (tile -> anything) prevents expanding out of blocked tiles (e.g. other heroes).
## `seen` is a human player's explored cells (row-major, 1 = explored): a
## human's route never steps onto an unexplored cell (heroes.exe 0x87bc5), so a
## target under fog has no route (0x86bd7). Empty for the computer, which
## routes through fog.
static func build_land_field(grid: PassabilityGrid, from: Vector2i,
		hero_class: String = "", current_move_points: int = -1,
		max_move_points: int = -1, target_guard: NeutralStack = null,
		max_cost: int = -1, boats: Dictionary = {},
		target: Vector2i = Vector2i(-1, -1),
		blocked: Dictionary = {}, ai_route := false,
		seen: PackedByteArray = PackedByteArray()) -> Dictionary:
	if not grid.is_in_boundsv(from):
		return {}
	var w := grid.map.width
	var n := grid.map.width * grid.map.height
	if grid.terrain_costs.size() != n:
		grid.rebuild()
	var start := from.y * w + from.x
	var target_flat := target.y * w + target.x if target != Vector2i(-1, -1) and grid.is_in_boundsv(target) else -1
	var costs := PackedInt32Array()
	costs.resize(n)
	costs.fill(INF_COST)
	costs[start] = 0

	var parent := PackedInt32Array()
	parent.resize(n)
	parent.fill(-1)

	var reached := PackedInt32Array()
	reached.append(start)

	var frontier := Heap.new()
	var sequence := 0
	var zones := grid.guard_zones()
	var is_barbarian := hero_class == "barbarian"
	# The computer's searches keep the oasis rule of build_guarded_field.
	var no_entry_from_above := grid.no_entry_from_above if ai_route else {}
	frontier.push(0, sequence, start)
	while not frontier.is_empty():
		frontier.pop()
		var cur_cost := frontier.pop_cost
		var flat := frontier.pop_node
		if cur_cost != costs[flat]:
			continue
		if target_flat >= 0 and flat == target_flat:
			break
		@warning_ignore("integer_division")
		var cur := Vector2i(flat % w, flat / w)
		var cur_terminal := grid.terminal_in(cur, zones)
		if cur != from and ((cur_terminal != null and cur_terminal != target_guard)
				or blocked.has(cur) or boats.has(cur)):
			continue
		var straight: int = 4 if is_barbarian else int(grid.terrain_costs[flat])
		var diagonal: int = 6 if is_barbarian else straight + (straight >> 1)
		for d in 8:
			var delta: Vector2i = DIR_DELTAS[d]
			var nxt: Vector2i = cur + delta
			if not grid.can_enter(cur, nxt) and not (boats.has(nxt) and can_board(grid, cur, nxt)):
				continue
			if delta.y > 0 and no_entry_from_above.has(nxt):
				continue
			var raw_cost: int = diagonal if DIR_IS_DIAG[d] else straight
			var next_cost := cur_cost + raw_cost
			if max_cost >= 0 and next_cost > max_cost:
				continue
			var nflat := nxt.y * w + nxt.x
			if seen.size() == n and seen[nflat] == 0:
				continue
			if next_cost >= costs[nflat]:
				continue
			if costs[nflat] == INF_COST:
				reached.append(nflat)
			costs[nflat] = next_cost
			parent[nflat] = flat
			sequence += 1
			frontier.push(next_cost, sequence, nflat)
	var costs_dict: Dictionary = {}
	var parent_dict: Dictionary = {}
	for f: int in reached:
		costs_dict[f] = costs[f]
		if f != start:
			parent_dict[f] = parent[f]
	return {"parent": parent_dict, "costs": costs_dict, "start": start, "width": w}

## Movement points within which a zone cell's route past its guard holds off
## a detour round it (heroes.exe 0x8720a).
const GUARD_PRUNE := 12

## heroes.exe's direction order (data 0x1f828): N, NE, E, SE, S, SW, W, NW.
## The planning search relaxes neighbours in it, which settles ties.
const ORIG_DELTAS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]

## The original's own planning search (heroes.exe 0x86b64 with 0x877e8),
## on our grid. One record per cell holding its cost, whether its route has
## passed a monster, and which: a record that passed a monster never
## replaces one that did not, one that did not replaces one that did at any
## cost, and otherwise the cheaper wins. Labels wait in a queue sorted by
## cost (at most 1024; a new label goes behind equal costs), and a popped
## label expands even if its cell's record has been replaced since. On
## popping: a monster's cell is passed if nothing has been, else the route
## ends there; an object for which `ends` holds ends it; a cell in a
## monster's zone ends it when another monster guards it than the one
## passed, and otherwise makes its first guard the passed one. A zone
## neighbour holding a record that passed its own guard for less than the
## current cost + GUARD_PRUNE is not relaxed (0x87195); checking one makes its
## guard the passed one for the directions after it. Same result shape as
## guarded_path: state = (passed ? tiles : 0) + flat.
static func build_guarded_field(grid: PassabilityGrid, from: Vector2i,
		hero_class: String, passable: Callable, max_cost: int = -1,
		boats: Dictionary = {}, move_left: int = -1,
		blocked: Dictionary = {}, ends: Callable = Callable()) -> Dictionary:
	if not grid.is_in_boundsv(from):
		return {}
	var w := grid.map.width
	var h := grid.map.height
	var n := w * h
	if grid.terrain_costs.size() != n:
		grid.rebuild()
	var is_barbarian := hero_class == "barbarian"
	# The armed stacks by cell and, per cell, its guards in 0x84138's order
	# (x outer, y inner).
	var stack_at: Dictionary = {}
	for o: MapObject in grid.map.objects:
		if o is NeutralStack and bool(passable.call(o)):
			stack_at[o.action_tile] = o
	var guards_of := func(t: Vector2i) -> Array:
		var out: Array = []
		for gx in range(t.x - 1, t.x + 2):
			for gy in range(t.y - 1, t.y + 2):
				var st: NeutralStack = stack_at.get(Vector2i(gx, gy))
				if st == null:
					continue
				if Vector2i(gx, gy) == t or grid._guards(st.action_tile, t):
					out.append(st)
		return out
	var guard_cache: Dictionary = {}
	var rec_cost := PackedInt32Array()
	rec_cost.resize(n)
	var rec_flags := PackedByteArray()   # bit 0 reached, bit 2 passed
	rec_flags.resize(n)
	var rec_dir := PackedInt32Array()
	rec_dir.resize(n)
	rec_dir.fill(-1)
	var rec_guard: Array = []
	rec_guard.resize(n)
	var rec_night := PackedInt32Array()
	rec_night.resize(n)
	rec_night.fill(-1)
	# Queue entries: [cost, flat, dir, passed stack or null, passed?, night flat or -1]
	var queue: Array = []
	var relax := func(flat: int, c: int, d: int, guard_stack: NeutralStack, passed_flag: bool, night_at: int) -> void:
		if max_cost >= 0 and c > max_cost:
			return
		if queue.size() >= 0x400:
			return
		if rec_flags[flat] & 1:
			var old_passed := (rec_flags[flat] & 4) != 0
			if not old_passed and passed_flag:
				return
			if rec_cost[flat] <= c and not (old_passed and not passed_flag):
				return
		var na := night_at
		if na < 0 and move_left >= 0 and c > move_left and d >= 0:
			var nd: Vector2i = ORIG_DELTAS[d]
			na = (flat / w - nd.y) * w + (flat % w - nd.x)
		rec_cost[flat] = c
		rec_flags[flat] = 1 | (4 if passed_flag else 0)
		rec_dir[flat] = d
		rec_guard[flat] = guard_stack if passed_flag else null
		rec_night[flat] = na
		var lo := 0
		var hi := queue.size()
		while lo < hi:
			var mid := (lo + hi) >> 1
			if c >= int(queue[mid][0]):
				hi = mid
			else:
				lo = mid + 1
		queue.insert(lo, [c, flat, d, rec_guard[flat], passed_flag, na])
	# heroes.exe 0x87a98 refuses a step from above into an oasis: its cell
	# holds a standing sprite and class 0x1c is not a walk-on class (0x87d60).
	# DOS still lets a hero visit one from there, so the grid stays open.
	var no_entry_from_above := grid.no_entry_from_above
	var start := from.y * w + from.x
	relax.call(start, 0, -1, null, false, -1)
	while not queue.is_empty():
		var rec: Array = queue.pop_back()
		var cur_cost: int = rec[0]
		var flat: int = rec[1]
		if max_cost >= 0 and cur_cost > max_cost:
			continue
		var cur := Vector2i(flat % w, flat / w)
		var rec_passed: bool = rec[4]
		var rec_stack: NeutralStack = rec[3]
		var passed: bool = rec_passed
		var passed_stack: NeutralStack = rec_stack
		if cur != from:
			if boats.has(cur) or blocked.has(cur):
				continue
			var obj := grid.action_object_at(cur)
			if obj is NeutralStack and stack_at.has(cur):
				if rec_passed:
					continue
				passed = true
				passed_stack = obj as NeutralStack
			elif obj != null and not (obj is NeutralStack) and (not ends.is_valid() or bool(ends.call(obj))):
				continue
			if not guard_cache.has(flat):
				guard_cache[flat] = guards_of.call(cur)
			var gs: Array = guard_cache[flat]
			if not gs.is_empty():
				if rec_passed:
					var other := false
					for st: NeutralStack in gs:
						if st != rec_stack:
							other = true
							break
					if other:
						continue
				else:
					passed = true
					passed_stack = gs[0]
		var straight: int = 4 if is_barbarian else int(grid.terrain_costs[flat])
		var diagonal: int = 6 if is_barbarian else straight + (straight >> 1)
		var left := move_left - cur_cost
		var diag_price := diagonal
		if move_left >= 0 and left < diagonal and left >= straight:
			diag_price = straight
		for d in 8:
			var nxt: Vector2i = cur + ORIG_DELTAS[d]
			# A hero's cell is an object cell to the original (class 0xbd):
			# a route may end there though our grid makes teammates solid.
			var onto_hero := blocked.has(nxt) and grid.is_in_boundsv(nxt) and not grid.map.is_water(nxt)
			if not grid.can_enter(cur, nxt, true, onto_hero) and not (boats.has(nxt) and can_board(grid, cur, nxt)):
				continue
			if ORIG_DELTAS[d].y > 0 and no_entry_from_above.has(nxt):
				continue
			var nflat := nxt.y * w + nxt.x
			# 0x87195: pruning in a zone. Its guard lookup (0x8722c) writes the
			# guard it finds into the running passed monster (0x3fd44/48), so
			# this and the later directions carry that monster.
			if (rec_flags[nflat] & 1) and (rec_flags[nflat] & 4) and rec_cost[nflat] < cur_cost + GUARD_PRUNE:
				if not guard_cache.has(nflat):
					guard_cache[nflat] = guards_of.call(nxt)
				var ngs: Array = guard_cache[nflat]
				if not ngs.is_empty():
					passed_stack = ngs[0]
					if ngs[0] == rec_guard[nflat]:
						continue
			var step := diag_price if (d & 1) == 1 else straight
			relax.call(nflat, cur_cost + step, d, passed_stack, passed, int(rec[5]))
	# The result in the shape guarded_path reads; a path follows the final
	# records' directions.
	var costs_dict: Dictionary = {}
	var parent_dict: Dictionary = {}
	var guard: Dictionary = {}
	var night: Dictionary = {}
	for f in n:
		if not (rec_flags[f] & 1):
			continue
		var st_i := (n if rec_flags[f] & 4 else 0) + f
		costs_dict[st_i] = rec_cost[f]
		if rec_flags[f] & 4 and rec_guard[f] != null:
			guard[st_i] = rec_guard[f]
		if rec_night[f] >= 0:
			night[st_i] = Vector2i(rec_night[f] % w, rec_night[f] / w)
		var d := rec_dir[f]
		if f != start and d >= 0:
			var pd: Vector2i = ORIG_DELTAS[d]
			var pf := (f / w - pd.y) * w + (f % w - pd.x)
			parent_dict[st_i] = (n if rec_flags[pf] & 4 else 0) + pf
	var start_state := start
	return {"parent": parent_dict, "costs": costs_dict, "start": start_state, "width": w,
			"tiles": n, "guard": guard, "night": night}

## A hero at sea (heroes.exe 0x87a98 with the at-sea flag): the route crosses
## water, never into a boat's cell, and ends on any land cell it may land on
## or on an object in the water. Same shape as build_guarded_field, with no
## guards passed.
## `heroes` holds the tiles heroes occupy: a sailing one may be attacked, one
## ashore may not (heroes.exe 0x87a98 lands only on coast cells). A hero's
## boat also ends the route rather than being sailed through (0x86e46: the
## non-planning route stops expanding at class 0x3d, and even a planning one
## refuses its own side's boats), so a stale route meets a newly occupied
## cell as a destination, never as an intermediate step.
static func build_sea_field(grid: PassabilityGrid, from: Vector2i,
		hero_class: String = "", max_cost: int = -1, boats: Dictionary = {},
		heroes: Dictionary = {},
		seen: PackedByteArray = PackedByteArray()) -> Dictionary:
	if not grid.is_in_boundsv(from):
		return {}
	var map := grid.map
	var w := map.width
	var n := map.width * map.height
	var start := from.y * w + from.x
	var costs := PackedInt32Array()
	costs.resize(n)
	costs.fill(INF_COST)
	costs[start] = 0

	var parent := PackedInt32Array()
	parent.resize(n)
	parent.fill(-1)

	var reached := PackedInt32Array()
	reached.append(start)

	var frontier := Heap.new()
	var sequence := 0
	frontier.push(0, sequence, start)
	while not frontier.is_empty():
		frontier.pop()
		var cur_cost := frontier.pop_cost
		var flat := frontier.pop_node
		if cur_cost != costs[flat]:
			continue
		@warning_ignore("integer_division")
		var cur := Vector2i(flat % w, flat / w)
		if cur != from and (map.is_land(cur) or grid.action_object_at(cur) != null \
				or heroes.has(cur)):
			continue
		for d in 8:
			var delta: Vector2i = DIR_DELTAS[d]
			var nxt: Vector2i = cur + delta
			if not grid.is_in_boundsv(nxt):
				continue
			if map.is_water(nxt):
				if boats.has(nxt):
					continue
				if delta.x != 0 and delta.y != 0 and (not map.is_water(cur + Vector2i(delta.x, 0))
						or not map.is_water(cur + Vector2i(0, delta.y))):
					continue
			elif not map.is_land(nxt) or not grid.can_enter(cur, nxt) \
					or grid.terminal_at(nxt) != null or heroes.has(nxt):
				continue
			var next_cost := cur_cost + (6 if DIR_IS_DIAG[d] else 4)
			if max_cost >= 0 and next_cost > max_cost:
				continue
			var nflat := nxt.y * w + nxt.x
			if seen.size() == n and seen[nflat] == 0:
				continue
			if next_cost >= costs[nflat]:
				continue
			if costs[nflat] == INF_COST:
				reached.append(nflat)
			costs[nflat] = next_cost
			parent[nflat] = flat
			sequence += 1
			frontier.push(next_cost, sequence, nflat)
	var costs_dict: Dictionary = {}
	var parent_dict: Dictionary = {}
	for f: int in reached:
		costs_dict[f] = costs[f]
		if f != start:
			parent_dict[f] = parent[f]
	return {"parent": parent_dict, "costs": costs_dict, "start": start, "width": w,
			"tiles": n, "guard": {}}

## Whether a land hero on `from` may step into the boat on `to`: the same
## source-side mask TravelRules applies to boarding.
static func can_board(grid: PassabilityGrid, from: Vector2i, to: Vector2i) -> bool:
	var d := to - from
	if maxi(absi(d.x), absi(d.y)) != 1 or not grid.is_in_boundsv(to):
		return false
	var move_dir := Direction.from_delta(d.x, d.y)
	return not (grid._source_masked.has(from)
			and (grid.entry_mask(from) & Direction.bit(move_dir)) == 0)

## The guarded field's route to `to`: {"path", "guard"}, guard null on the
## direct route. `layer` 0 asks for the direct route only, 1 for the route
## past a guard only, -1 for the direct route when there is one, else the one
## past a guard: heroes.exe 0x877e8 never lets a label that passed a monster
## replace one that did not, whatever it costs. {} when none.
static func guarded_path(field: Dictionary, to: Vector2i, layer: int = -1) -> Dictionary:
	if field.is_empty() or not Rect2i(0, 0, int(field.width),
			int(field.tiles) / int(field.width)).has_point(to):
		return {}
	var w := int(field.width)
	var n := int(field.tiles)
	var flat := to.y * w + to.x
	var states: Array = [flat, n + flat] if layer < 0 else [layer * n + flat]
	var best := -1
	for state: int in states:
		if field.costs.has(state):
			best = state
			break
	if best < 0:
		return {}
	var path: Array = []
	var cur := best
	while true:
		var f := cur % n
		path.push_front(Vector2i(f % w, f / w))
		if cur == int(field.start):
			break
		if not field.parent.has(cur):
			return {}
		cur = int(field.parent[cur])
	return {"path": path, "guard": field.guard.get(best),
			"night": (field.get("night", {}) as Dictionary).get(best, Vector2i(-1, -1))}

static func path_from_field(field: Dictionary, to: Vector2i) -> Array:
	if field.is_empty():
		return []
	var w := int(field.width)
	return _path_to(field.parent, field.costs, int(field.start),
			to.y * w + to.x, w)

## Current-mode route. Boarding/disembarking may be the final step only; the
## strategic naval planner handles routes containing multiple transitions.
static func find_for(grid: PassabilityGrid, from: Vector2i, to: Vector2i,
		map: MapData, state: GameState, mode: StringName,
		hero_class: String = "", current_move_points: int = -1,
		max_move_points: int = -1,
		seen: PackedByteArray = PackedByteArray()) -> Array:
	if mode == &"land" and map.is_land(to) and state.boat_at(to) == null:
		# A hero's cell ends a route (meet or attack); it is never crossed.
		return find(grid, from, to, map, hero_class,
				current_move_points, max_move_points, seen, state.hero_tiles())
	if not _valid_endpoints(grid, from, to, false):
		return []
	if from == to:
		return [from]
	var w := map.width
	var n := map.width * map.height
	var start := from.y * w + from.x
	var costs := PackedInt32Array()
	costs.resize(n)
	costs.fill(INF_COST)
	costs[start] = 0

	var remaining := PackedInt32Array()
	remaining.resize(n)
	remaining.fill(-1)
	remaining[start] = current_move_points

	var parent := PackedInt32Array()
	parent.resize(n)
	parent.fill(-1)

	var frontier := Heap.new()
	var sequence := 0
	var target := to.y * w + to.x
	frontier.push(0, sequence, start)
	while not frontier.is_empty():
		frontier.pop()
		var flat := frontier.pop_node
		if frontier.pop_cost != costs[flat]:
			continue
		if flat == target:
			break
		@warning_ignore("integer_division")
		var cur := Vector2i(flat % w, flat / w)
		if cur != from and grid.terminal_at(cur) != null:
			continue
		for d in 8:
			var nxt: Vector2i = cur + DIR_DELTAS[d]
			var kind := TravelRules.step_kind(map, grid, state, mode, cur, nxt)
			if kind == TravelRules.INVALID:
				continue
			if seen.size() == n and seen[nxt.y * w + nxt.x] == 0:
				continue
			if kind == TravelRules.ENGAGE and nxt != to:
				continue
			if not TravelRules.is_walk(kind) and nxt != to:
				continue
			if nxt != to and grid.terminal_at(nxt) != null:
				continue
			# A hero's cell ends a route (meet or attack); it is never crossed.
			if nxt != to and state != null and map.is_land(nxt) and state.hero_at(nxt) != null:
				continue
			var raw_cost := TravelRules.step_cost(kind, cur, nxt, map, hero_class)
			var straight_cost := raw_cost
			if TravelRules.is_walk(kind):
				straight_cost = Hero.step_cost(cur, cur + Vector2i.RIGHT, map,
						map.is_water(cur), hero_class)
			var edge_cost := planned_step_cost(raw_cost, straight_cost,
					remaining[flat], max_move_points)
			var next_cost := costs[flat] + edge_cost
			var nflat := nxt.y * w + nxt.x
			if next_cost >= costs[nflat]:
				continue
			costs[nflat] = next_cost
			remaining[nflat] = remaining_after_step(remaining[flat],
					max_move_points, edge_cost)
			parent[nflat] = flat
			sequence += 1
			frontier.push(next_cost, sequence, nflat)
	return _path_to(parent, costs, start, target, w)

## Cost used while planning across days. If the hero can afford a straight
## departure from this terrain but not the requested diagonal, the original
## consumes the remainder of the current day and allows that final step.
static func planned_step_cost(raw_cost: int, straight_cost: int,
		remaining: int, max_move_points: int) -> int:
	if max_move_points > 0 and remaining >= straight_cost and remaining < raw_cost:
		return remaining
	return raw_cost

static func remaining_after_step(remaining: int, max_move_points: int,
		charged_cost: int) -> int:
	if remaining < 0 or max_move_points <= 0:
		return -1
	if remaining < charged_cost:
		return maxi(0, max_move_points - charged_cost)
	return remaining - charged_cost

## Whether this step belongs to today's green prefix. `straight_cost` is the
## source terrain's cardinal cost, even when `raw_cost` is diagonal.
static func can_take_today(raw_cost: int, straight_cost: int,
		remaining: int) -> bool:
	return remaining >= raw_cost \
			or (remaining >= straight_cost and remaining < raw_cost)

static func current_day_step_cost(raw_cost: int, straight_cost: int,
		remaining: int) -> int:
	return remaining if remaining >= straight_cost and remaining < raw_cost \
			else raw_cost

static func _valid_endpoints(grid: PassabilityGrid, from: Vector2i,
		to: Vector2i, require_land_mask: bool = true) -> bool:
	if not grid.is_in_boundsv(from) or not grid.is_in_boundsv(to):
		return false
	return not require_land_mask or (grid.entry_mask(to) != 0
			and not grid.is_point_solid(to))

static func _path_to(parent, costs, start: int,
		target: int, w: int) -> Array:
	if costs is PackedInt32Array:
		if target < 0 or target >= costs.size() or costs[target] >= INF_COST:
			return []
	elif not costs.has(target):
		return []
	var out: Array = []
	var cur := target
	while cur != start:
		@warning_ignore("integer_division")
		out.push_front(Vector2i(cur % w, cur / w))
		cur = int(parent[cur])
	@warning_ignore("integer_division")
	out.push_front(Vector2i(start % w, start / w))
	return out
