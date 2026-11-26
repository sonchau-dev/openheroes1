class_name BattleInput
extends RefCounted

## Turns a clicked hex into an action for the active stack, using engine rules.
## Returns the same action shapes as BattleAI so the controller executes them identically.


const CUR_INVALID := 0
const CUR_MOVE := 1
const CUR_SHOOT := 3
const CUR_GENERAL := 4
const CUR_VIEW := 5
const CUR_SPELL_BASE := 1000

## [screen-angle°, sword sprite id] — 0°=E, 90°=S, 180°=W, -90°=N.
## Sword sprite tips: 8 E, 9 SE, 14 S, 10 SW, 11 W, 12 NW, 13 N, 7 NE.
const _SWORD_DIRS := [
	[0.0, 8],
	[45.0, 9],
	[90.0, 14],
	[135.0, 10],
	[180.0, 11],
	[-135.0, 12],
	[-90.0, 13],
	[-45.0, 7],
]

## Directional attack-sword sprite pointing from the attack hex toward the target.
static func sword_for(from_hex: Vector2i, target_hex: Vector2i, origin: Vector2 = Hex.ORIGIN, step: Vector2 = Hex.STEP) -> int:
	var a := Hex.to_pixel(from_hex.x, from_hex.y, origin, step)
	var b := Hex.to_pixel(target_hex.x, target_hex.y, origin, step)
	var ang := rad_to_deg((b - a).angle())
	var best_id := 8
	var best_d := 999.0
	for e: Array in _SWORD_DIRS:
		var d: float = absf(wrapf(ang - e[0], -180.0, 180.0))
		if d < best_d:
			best_d = d
			best_id = e[1]
	return best_id

## Finds the best destination hex adjacent to target for actor to attack from.
## When mouse_pos is provided, chooses the candidate closest to the mouse angle relative to the target cell.
## Otherwise picks the candidate with lowest movement cost.
static func best_attack_dest(state: BattleState, actor: BattleStack, target: BattleStack,
		mouse_pos: Vector2 = Vector2.INF, origin: Vector2 = Hex.ORIGIN, step: Vector2 = Hex.STEP) -> Vector2i:
	if target == null or not target.is_alive() or target.side == actor.side:
		return Vector2i(-1, -1)
	var reach := state.reachable_for(actor)
	var candidates: Array[Vector2i] = []
	if state.adjacent(actor, target):
		candidates.append(actor.hex)
	for h: Vector2i in reach:
		if state.dest_adjacent(actor, h, target):
			candidates.append(h)

	if candidates.is_empty():
		return Vector2i(-1, -1)
	if candidates.size() == 1 or not mouse_pos.is_finite():
		var best := candidates[0]
		for h in candidates:
			if reach.get(h, 0) < reach.get(best, 0):
				best = h
		return best

	var half_y := step.y * 0.5
	var best_dest := candidates[0]
	var best_angle_diff := INF
	var best_cost: int = reach.get(best_dest, 0)
	var best_dist_sq := INF

	for h in candidates:
		var best_ac := h
		var best_tc := target.hex
		var min_touch_dist_sq := INF
		for ac: Vector2i in actor.cells_at(h):
			for tc: Vector2i in target.cells():
				if Hex.distance(ac.x, ac.y, tc.x, tc.y) == 1:
					var p_ac := Hex.to_pixel(ac.x, ac.y, origin, step) - Vector2(0.0, half_y)
					var d := mouse_pos.distance_squared_to(p_ac)
					if d < min_touch_dist_sq:
						min_touch_dist_sq = d
						best_ac = ac
						best_tc = tc

		var tc_center := Hex.to_pixel(best_tc.x, best_tc.y, origin, step) - Vector2(0.0, half_y)
		var ac_center := Hex.to_pixel(best_ac.x, best_ac.y, origin, step) - Vector2(0.0, half_y)

		var candidate_dir := ac_center - tc_center
		var mouse_dir := mouse_pos - tc_center

		var angle_diff := 0.0
		if mouse_dir.length_squared() >= 4.0:
			angle_diff = absf(wrapf(mouse_dir.angle() - candidate_dir.angle(), -PI, PI))

		var cost: int = reach.get(h, 0)
		var dist_sq := mouse_pos.distance_squared_to(ac_center)

		if angle_diff < best_angle_diff - 0.05:
			best_angle_diff = angle_diff
			best_dest = h
			best_cost = cost
			best_dist_sq = dist_sq
		elif absf(angle_diff - best_angle_diff) <= 0.05:
			if cost < best_cost or (cost == best_cost and dist_sq < best_dist_sq):
				best_angle_diff = angle_diff
				best_dest = h
				best_cost = cost
				best_dist_sq = dist_sq

	return best_dest

## The anchor a tap on an empty cell sends `actor` to, or (-1, -1) when the
## cell is out of reach.
##
## A wide stack covers two cells, and the player points at a cell rather than
## at an anchor: the stack walks toward the tapped cell and stops when the
## nearest part of it arrives. The tapped cell can therefore end up under the
## stack's front cell or under its rear cell. Of the two placements that cover
## it, the cheaper one wins and the front placement breaks a tie, so tapping
## the empty cell in front of a stack walks it forward one hex, and tapping
## the cell behind it walks it back one hex.
static func tap_dest(state: BattleState, actor: BattleStack, clicked: Vector2i) -> Vector2i:
	var reach := state.reachable_for(actor)
	if not actor.wide:
		return clicked if reach.has(clicked) else Vector2i(-1, -1)
	var candidates: Array[Vector2i] = [
		clicked - Vector2i(actor.body_dx(), 0),   # the tapped cell becomes the front cell
		clicked,                                  # the tapped cell becomes the rear cell
	]
	var best := Vector2i(-1, -1)
	var best_cost := 1 << 30
	for cand: Vector2i in candidates:
		if not reach.has(cand):
			continue
		var cost := int(reach[cand])
		if cost < best_cost:
			best_cost = cost
			best = cand
	return best

static func resolve(state: BattleState, actor: BattleStack, clicked: Vector2i, mouse_pos: Vector2 = Vector2.INF) -> Dictionary:
	var occ := state.stack_at(clicked)
	if occ != null and occ.side != actor.side:
		# enemy clicked
		if state.can_attack(actor, occ):
			if actor.is_ranged() and actor.shots > 0 and not state.is_blocked(actor):
				return {"action": "shoot", "target": occ}
		var best := best_attack_dest(state, actor, occ, mouse_pos)
		if best != Vector2i(-1, -1):
			if best == actor.hex:
				return {"action": "melee", "target": occ}
			return {"action": "move_melee", "dest": best, "target": occ}
		return {"action": "invalid"}
	# A tap on an empty cell is a move; a tap on one of the actor's own cells
	# only ever inspects it, front half or rear half alike.
	if occ == null:
		var dest := tap_dest(state, actor, clicked)
		if dest != Vector2i(-1, -1):
			return {"action": "move", "dest": dest}
	return {"action": "invalid"}

## Directional sword sprite pointing from the attack dest toward the target.
static func sword_for_attack_dest(actor: BattleStack, dest: Vector2i, target: BattleStack,
		mouse_pos: Vector2 = Vector2.INF, origin: Vector2 = Hex.ORIGIN, step: Vector2 = Hex.STEP) -> int:
	var half_y := step.y * 0.5
	var best_ac := dest
	var best_tc := target.hex
	var min_touch_dist_sq := INF
	for ac: Vector2i in actor.cells_at(dest):
		for tc: Vector2i in target.cells():
			if Hex.distance(ac.x, ac.y, tc.x, tc.y) == 1:
				if not mouse_pos.is_finite():
					return sword_for(ac, tc, origin, step)
				var p_ac := Hex.to_pixel(ac.x, ac.y, origin, step) - Vector2(0.0, half_y)
				var d := mouse_pos.distance_squared_to(p_ac)
				if d < min_touch_dist_sq:
					min_touch_dist_sq = d
					best_ac = ac
					best_tc = tc
	return sword_for(best_ac, best_tc, origin, step)

## Cursor id for the action the active stack would take against `hex`.
static func cursor_for(state: BattleState, actor: BattleStack, hex: Vector2i,
		mouse_pos: Vector2 = Vector2.INF, origin: Vector2 = Hex.ORIGIN, step: Vector2 = Hex.STEP) -> int:
	var occ := state.stack_at(hex)
	if occ != null and occ.side != actor.side:
		if state.can_attack(actor, occ):
			if actor.is_ranged() and actor.shots > 0 and not state.is_blocked(actor):
				return CUR_SHOOT
		var best := best_attack_dest(state, actor, occ, mouse_pos, origin, step)
		if best != Vector2i(-1, -1):
			return sword_for_attack_dest(actor, best, occ, mouse_pos, origin, step)
		return CUR_INVALID
	if occ != null:
		# The actor's own cells only ever inspect the stack, front half and
		# rear half alike.
		return CUR_VIEW
	if tap_dest(state, actor, hex) != Vector2i(-1, -1):
		return CUR_MOVE
	return CUR_INVALID

## Hex cell closest to the world coordinate.
static func hex_at(world: Vector2, origin: Vector2 = Hex.ORIGIN, step: Vector2 = Hex.STEP) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := INF
	var half_y := step.y * 0.5
	for r in Hex.ROWS:
		for c in Hex.COLS:
			var center := Hex.to_pixel(c, r, origin, step) - Vector2(0.0, half_y)
			var d := world.distance_squared_to(center)
			if d < bd:
				bd = d
				best = Vector2i(c, r)
	return best

