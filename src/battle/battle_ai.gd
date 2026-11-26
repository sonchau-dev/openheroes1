class_name BattleAI
extends RefCounted

## HOMM1 battle AI, the stack routine decoded from heroes.exe (0xaf2ce,
## auto-combat-ai.md section 2): enemy stacks split into shooters with shots,
## flyers and the rest, and within a tier the most valuable (count x V) comes
## first. `choose` documents each kind of actor. The one hold-back is the
## shooter guard (`_guard_on`): while a side has arrows, its walking
## stacks stand in front of their shooter. No kiting or retreat.
## Returns one of:
##   {action:"shoot",  target}
##   {action:"melee",  target}
##   {action:"move_melee", dest, target}
##   {action:"move",   dest}
##   {action:"pass"}

## heroes.exe 0xaf2ce. A shooter with arrows strikes its most valuable
## neighbour when blocked, else shoots the most valuable enemy shooter, then
## the most valuable flyer, then the nearest of the rest. A flyer attacks the
## first stack it can reach among shooters, flyers, then the rest, each tier
## most valuable first. A walker strikes its most valuable neighbour, then
## guards, then attacks the first stack it can reach among shooters, the rest,
## then flyers, and otherwise walks toward the nearest stack in that order.
static func choose(state: BattleState, actor: BattleStack) -> Dictionary:
	if actor.has_effect("berserk"):
		return berserk_action(state, actor)
	var enemies: Array = []
	for s: BattleStack in state.stacks:
		if s.is_alive() and s.side != actor.side:
			enemies.append(s)
	if enemies.is_empty():
		return {"action": "pass"}
	var tiers := _target_tiers(enemies)
	var ghost := actor.unit == "ghost"

	if actor.is_ranged() and actor.shots > 0:
		var beside := _adjacent_by_value(state, actor, enemies, ghost)
		if not beside.is_empty():
			return {"action": "melee", "target": beside[0]}
		for tier: Array in [tiers.shooters, tiers.flyers]:
			if not tier.is_empty():
				return {"action": "shoot", "target": _by_value(tier, ghost)[0]}
		var nearest := _nearest(actor, tiers.others)
		if nearest != null:
			return {"action": "shoot", "target": nearest}
		return {"action": "pass"}

	var reach: Dictionary = state.reachable_for(actor)
	if actor.is_flying():
		for tier: Array in [tiers.shooters, tiers.flyers, tiers.others]:
			var hit := _attack_first_reachable(state, actor, _by_value(tier, ghost), reach)
			if not hit.is_empty():
				return hit
		return {"action": "pass"}

	var beside := _adjacent_by_value(state, actor, enemies, ghost)
	if not beside.is_empty():
		return {"action": "melee", "target": beside[0]}
	var order := [tiers.shooters, tiers.others, tiers.flyers]
	if _guard_on(state, actor):
		return _engage(state, actor,
				_guard_action(state, actor, order, _friendly_shooters(state, actor)))
	for tier: Array in order:
		var hit := _attack_first_reachable(state, actor, _by_value(tier, ghost), reach)
		if not hit.is_empty():
			return hit
	return _engage(state, actor, _walk_toward_tiers(state, actor, order))

## heroes.exe 0xafa37, the end of the stack routine: a walk that ends on a free
## cell next to an enemy becomes an attack on the first enemy among that
## cell's neighbours, in the cell table's order. The attack routine 0x9062b
## routes to it afresh (unlimited search, 0xad730) and strikes when the route
## is within the stack's speed. Seen in a DOS recording of the siege arena
## (2026-10-13, frames 183-191): the Goblins,
## guarding with no shooter of their own, walked from (6,0) to (5,1) and
## struck the Cavalry in the same turn.
static func _engage(state: BattleState, actor: BattleStack,
		action: Dictionary) -> Dictionary:
	if action.get("action") != "move":
		return action
	var dest: Vector2i = action.dest
	var dirs: Array = _ROUTE_ODD if (dest.y & 1) else _ROUTE_EVEN
	for d: Vector2i in dirs:
		var n: Vector2i = dest + d
		if not Hex.in_bounds(n.x, n.y):
			continue
		var enemy := state.stack_at(n)
		if enemy == null or enemy.side == actor.side or enemy == actor:
			continue
		if state.adjacent(actor, enemy):
			return {"action": "melee", "target": enemy}
		var route := _route(state, actor, enemy)
		if route.is_empty():
			return action
		if route.size() > maxi(actor.effective_speed(), 1):
			return {"action": "move", "dest": _walk_end(actor, route)}
		return {"action": "move_melee", "dest": route[route.size() - 1], "target": enemy}
	return action

## heroes.exe 0xafae8 / 0xafbb3 / 0xafc68: shooters with shots, flyers, and
## every other stack (walkers and shooters out of shots), in army-slot order.
static func _target_tiers(enemies: Array) -> Dictionary:
	var tiers := {"shooters": [], "flyers": [], "others": []}
	for e: BattleStack in enemies:
		if e.is_shooter() and e.shots > 0:
			tiers.shooters.append(e)
		elif e.is_flying():
			tiers.flyers.append(e)
		else:
			tiers.others.append(e)
	return tiers

## heroes.exe 0xb0059: try each stack in turn and attack the first one with a
## free side in reach; a stack with none is dropped and the next one tried.
static func _attack_first_reachable(state: BattleState, actor: BattleStack,
		targets: Array, reach: Dictionary) -> Dictionary:
	for e: BattleStack in targets:
		if state.adjacent(actor, e):
			return {"action": "melee", "target": e}
		var dest = _best_melee_dest(state, actor, e, reach)
		if dest != null:
			return {"action": "move_melee", "dest": dest, "target": e}
	return {}

## heroes.exe 0xb01e0: the enemy stacks next to `actor`, best first.
static func _adjacent_by_value(state: BattleState, actor: BattleStack,
		enemies: Array, ghost: bool) -> Array:
	var beside: Array = enemies.filter(func(e: BattleStack) -> bool:
		return state.adjacent(actor, e))
	return _by_value(beside, ghost)

## Shooter guard: while a side still has a shooter with arrows, its walking
## stacks hold in front of it rather than march out. First seen in a DOS
## recording of a defence; the 2026-09-23 captures show it also
## holds when the enemy shoots back (Wolves and Ogres stand in front of their
## Orcs and Trolls while enemy Orcs fire every round) and that flyers do not
## guard (Sprites fly straight at the enemy beside guarding Dwarves and Elves).
## Both sides guard; in the 2026-09-24 Arena AI capture defending Minotaurs step
## in front of the Centaurs and hold while Goblins hold in row.
## heroes.exe 0xaf2ce decides it before choosing any target (0xaf5a6..0xaf5ca):
## friendly shooters must be worth more than a fifth of the whole army, and the
## enemy's shooters no more than ours (creature value table V). In a siege the
## castle counts as a shooter of the defending side worth 100 x tower_k
## (0xaf502: 5, plus 4 per dwelling and 1 per other building, the sum the
## tower's damage uses). The exe puts the town's garrison on its side 0
## (battle setup 0x89180..0x892fb), and 0xaf58f adds the castle to side 0.
static func _guard_on(state: BattleState, actor: BattleStack) -> bool:
	if actor.is_flying() or (actor.is_shooter() and actor.shots > 0):
		return false
	var our_shooters_val := 0
	var our_total_val := 0
	var enemy_shooters_val := 0
	for s: BattleStack in state.stacks:
		if not s.is_alive():
			continue
		var val := BattleAISpell.stack_value(s)
		var shoots := s.is_shooter() and s.shots > 0
		if s.side == actor.side:
			our_total_val += val
			if shoots:
				our_shooters_val += val
		elif shoots:
			enemy_shooters_val += val
	if state.siege_defender_side >= 0:
		if actor.side == state.siege_defender_side:
			our_shooters_val += 100 * state.tower_k
		else:
			enemy_shooters_val += 100 * state.tower_k
	return our_shooters_val > (our_total_val + 4) / 5 \
			and enemy_shooters_val <= our_shooters_val

## The actor's own shooters with arrows, in army-slot order.
static func _friendly_shooters(state: BattleState, actor: BattleStack) -> Array:
	return state.stacks.filter(func(s: BattleStack) -> bool:
		return s.is_alive() and s != actor and s.side == actor.side \
				and s.is_shooter() and s.shots > 0)

## heroes.exe 0xb045c. The guard walks to the cell in front of its nearest
## shooter along the route there, as far as its speed allows. With no route
## (the cell is held or blocked, or the guard already stands on it) it walks
## to the shooter instead (0xb064b), which leaves a guard already beside the
## shooter in place. Failing that, 0xaf2ce walks it toward the nearest enemy
## stack (0xaf8f0) instead of trying the attack calls; a walk that ends
## beside an enemy still strikes it (`_engage`).
static func _guard_action(state: BattleState, actor: BattleStack,
		order: Array, shooters: Array) -> Dictionary:
	var shooter := _nearest(actor, shooters)
	if shooter == null:
		return _walk_toward_tiers(state, actor, order)
	var front := _front_cell(shooter)
	if Hex.in_bounds(front.x, front.y):
		var route := _route(state, actor, null, front)
		if not route.is_empty():
			return {"action": "move", "dest": _walk_end(actor, route)}
	var to_shooter := _walk_toward(state, actor, shooter)
	if not to_shooter.is_empty():
		return to_shooter
	return _walk_toward_tiers(state, actor, order)

## heroes.exe 0xaf8f0: 0xb064b on the nearest stack of each tier in turn; the
## stack skips when no tier has a nearest stack it can find a route to.
static func _walk_toward_tiers(state: BattleState, actor: BattleStack,
		order: Array) -> Dictionary:
	for tier: Array in order:
		if tier.is_empty():
			continue
		var walk := _walk_toward(state, actor, _nearest(actor, tier))
		if not walk.is_empty():
			return walk
	return _wall_approach(state, actor)

## heroes.exe 0xaf956: in a siege, an attacking walker with no route to any
## stack goes to the cell in front of the wall in its own row, when it stands
## short of that column and the cell is free. The move routine 0x904dd
## carries the order out: it searches with unlimited range (0xad730 sets the
## movement byte to 99) and walks the route at most the stack's speed. When
## a wide stack has no route there, 0xad730 tries again one cell back, so a
## Cavalry stack ends with its front cell before the wall (Arena Siege
## recording, frames 105-112: cells (0,2)-(1,2) to (2,2)-(3,2)).
static func _wall_approach(state: BattleState, actor: BattleStack) -> Dictionary:
	var castle := state.siege_defender_side
	if castle < 0 or actor.side == castle:
		return {"action": "pass"}
	var front_col := state.wall_col() + (-1 if castle == 1 else 1)
	var short := actor.hex.x < front_col if castle == 1 else actor.hex.x > front_col
	var cell := Vector2i(front_col, actor.hex.y)
	if not short or state.stack_at(cell) != null:
		return {"action": "pass"}
	var route := _route(state, actor, null, cell)
	if route.is_empty() and actor.wide:
		route = _route(state, actor, null, cell - Vector2i(actor.body_dx(), 0))
	if route.is_empty():
		return {"action": "pass"}
	return {"action": "move", "dest": _walk_end(actor, route)}

## heroes.exe 0xb064b: walk the route to `target` as far as the actor's speed
## goes, stopping beside it at the latest (`_engage` then turns a walk that
## ends beside an enemy into an attack). Already
## beside the target, the stack skips. Empty when no route exists, which sends
## the caller on to the next tier. The route is the real one around stacks and
## walls, so a walker heads through a breach even when that takes it no
## closer in a straight line, and it always uses its full speed.
static func _walk_toward(state: BattleState, actor: BattleStack,
		target: BattleStack) -> Dictionary:
	if target == null:
		return {}
	if state.adjacent(actor, target):
		return {"action": "pass"}
	var route := _route(state, actor, target)
	if route.is_empty():
		return {}
	return {"action": "move", "dest": _walk_end(actor, route)}

## The cell the actor reaches walking `route` (cells after its own) at full
## speed.
static func _walk_end(actor: BattleStack, route: Array) -> Vector2i:
	return route[mini(maxi(actor.effective_speed(), 1), route.size()) - 1]

## The search's neighbour order, the exe's cell table at data 0x1f1f8 (six
## neighbours per cell): up-right, right, down-right, down-left, left, up-left.
## Its 9-column grid is ours plus an unused column each side.
const _ROUTE_EVEN := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1),
		Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]
const _ROUTE_ODD := [Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
		Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

## heroes.exe 0x87ea0 as 0xb064b and 0xb045c call it: the movement byte is set
## to 0x7f for the search, so range is unlimited, and every stack blocks, friend
## or foe. Breadth first, first found wins. With a `target` the search ends at
## the first cell from which the actor stands beside it; without one it ends at
## `goal`. Returns the anchor cells after the actor's own, empty when there is
## no route.
static func _route(state: BattleState, actor: BattleStack, target: BattleStack,
		goal := Vector2i(-1, -1)) -> Array:
	var blocked := state._movement_blockers(actor, state.occupancy(actor))
	var prev := {actor.hex: actor.hex}
	var frontier: Array = [actor.hex]
	var head := 0
	var found = null
	while head < frontier.size():
		var cur: Vector2i = frontier[head]
		head += 1
		if cur != actor.hex and (state.dest_adjacent(actor, cur, target)
				if target != null else cur == goal):
			found = cur
			break
		var dirs: Array = _ROUTE_ODD if (cur.y & 1) else _ROUTE_EVEN
		for d: Vector2i in dirs:
			var n: Vector2i = cur + d
			if not Hex.in_bounds(n.x, n.y) or prev.has(n) or blocked.has(n):
				continue
			prev[n] = cur
			frontier.append(n)
	if found == null:
		return []
	var out: Array = []
	var c: Vector2i = found
	while c != actor.hex:
		out.push_front(c)
		c = prev[c]
	return out

## The cell in `stack`'s row just past its enemy-facing edge.
static func _front_cell(stack: BattleStack) -> Vector2i:
	var dx := 1 if stack.side == 0 else -1
	var edge: Vector2i = stack.hex
	for c: Vector2i in stack.cells():
		if c.x * dx > edge.x * dx:
			edge = c
	return edge + Vector2i(dx, 0)

## Select the best landing cell to attack `target` from, strictly deterministic:
## 1. Minimal path cost in reach[hex]
## 2. Top-to-bottom row preference (h1.y < h2.y)
## 3. Horizontal bias towards attacker's approach side (side 1: larger x; side 0: smaller x)
static func _best_melee_dest(state: BattleState, actor: BattleStack, target: BattleStack, reach: Dictionary) -> Variant:
	var candidates: Array = []
	for hex: Vector2i in reach:
		if state.dest_adjacent(actor, hex, target):
			candidates.append(hex)
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(h1: Vector2i, h2: Vector2i) -> bool:
		if not actor.flying:
			var c1: int = reach[h1]
			var c2: int = reach[h2]
			if c1 != c2:
				return c1 < c2
		if h1.y != h2.y:
			return h1.y < h2.y
		if actor.side == 1:
			return h1.x > h2.x
		return h1.x < h2.x
	)
	return candidates[0]

## Shooters with shots first, then every other stack, each tier most
## valuable first (heroes.exe 0x9147c: count x V, the creature table's first
## field). Equal stacks keep the army-slot order BattleSetup builds (top to
## bottom). `by_strength` false keeps slot order within each tier, for the
## siege tower.
static func _native_target_order(enemies: Array, by_strength := true) -> Array:
	var shooters: Array = []
	var others: Array = []
	for enemy: BattleStack in enemies:
		if enemy.is_shooter() and enemy.shots > 0:
			shooters.append(enemy)
		else:
			others.append(enemy)
	if by_strength:
		shooters = _by_value(shooters)
		others = _by_value(others)
	shooters.append_array(others)
	return shooters

## heroes.exe 0xafd44 picks the highest count x V, the first slot on a tie;
## a Ghost's AI uses 0xafded instead, the lowest. Stable, unlike sort_custom.
static func _by_value(stacks: Array, lowest_first := false) -> Array:
	var keyed: Array = []
	for i in stacks.size():
		keyed.append([stacks[i], i, BattleAISpell.stack_value(stacks[i])])
	keyed.sort_custom(func(a: Array, b: Array) -> bool:
		if a[2] != b[2]:
			return a[2] < b[2] if lowest_first else a[2] > b[2]
		return int(a[1]) < int(b[1]))
	return keyed.map(func(k: Array) -> BattleStack: return k[0])

## heroes.exe 0xafe96: the stack whose cell centre is closest to the actor's,
## measured as the larger axis gap plus half the smaller (0x87794), first slot
## on a tie. Null for an empty tier. The exe starts from 640 pixels, which
## every pair of cells on the 7x5 field is inside, so no cap is kept.
static func _nearest(actor: BattleStack, stacks: Array) -> BattleStack:
	var from := Hex.to_pixel(actor.hex.x, actor.hex.y,
			Hex.ORIGIN, Hex.STEP)
	var best: BattleStack = null
	var best_d := 0
	for s: BattleStack in stacks:
		var to := Hex.to_pixel(s.hex.x, s.hex.y,
				Hex.ORIGIN, Hex.STEP)
		var dx := absi(int(to.x - from.x))
		var dy := absi(int(to.y - from.y))
		var d := maxi(dx, dy) + mini(dx, dy) / 2
		if best == null or d < best_d:
			best = s
			best_d = d
	return best

## Forced action for a berserked stack, heroes.exe 0x9166f (the battle loop
## calls it at 0xbe75f instead of the stack AI). Friend or foe alike:
## - a stack beside it: strike the one on a random neighbour cell;
## - none, flyer: random field cells until one holds a stack it can reach,
##   then fly to it and strike (a wide stack has two cells, so twice the odds);
## - none, walker (shooters too): one step in a random direction, no strike;
##   a blocked step loses the turn.
## Returns the same action-dict shapes as choose().
static func berserk_action(state: BattleState, actor: BattleStack) -> Dictionary:
	var rng := state.rng
	var beside := _cells_holding_others(state, actor, _neighbour_cells(actor))
	if not beside.is_empty():
		return {"action": "melee", "target": state.stack_at(beside[rng.randi() % beside.size()])}
	var reach: Dictionary = state.reachable_for(actor)
	if actor.is_flying():
		var all_cells: Array = []
		for s: BattleStack in state.stacks:
			all_cells.append_array(s.cells())
		var targets: Array = []
		for c: Vector2i in _cells_holding_others(state, actor, all_cells):
			if _best_melee_dest(state, actor, state.stack_at(c), reach) != null:
				targets.append(c)
		if targets.is_empty():
			return {"action": "pass"}
		var target := state.stack_at(targets[rng.randi() % targets.size()])
		return {"action": "move_melee", "target": target,
				"dest": _best_melee_dest(state, actor, target, reach)}
	var dest := Hex.strike_step(actor.hex, rng.randi() % 6)
	if reach.has(dest):
		return {"action": "move", "dest": dest}
	return {"action": "pass"}

## Cells around every cell of `actor`, its own cells left out.
# shortcut: a wide actor scans both cells' neighbours; 0xad98c's wide handling is not decoded.
static func _neighbour_cells(actor: BattleStack) -> Array:
	var out: Array = []
	for c: Vector2i in actor.cells():
		for n: Vector2i in Hex.neighbors(c.x, c.y):
			if not out.has(n) and not actor.cells().has(n):
				out.append(n)
	return out

static func _cells_holding_others(state: BattleState, actor: BattleStack,
		cells: Array) -> Array:
	return cells.filter(func(c: Vector2i) -> bool:
		var s := state.stack_at(c)
		return s != null and s != actor)
