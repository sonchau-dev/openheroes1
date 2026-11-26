class_name Movement
extends RefCounted

## BFS reachable hexes from `start` within `steps`, blocked = occupied {Vector2i: true}.
## Returns { hex: distance } excluding the start.
static func reachable(start: Vector2i, steps: int, blocked: Dictionary) -> Dictionary:
	var dist := {start: 0}
	var frontier: Array = [start]
	var head := 0
	while head < frontier.size():
		var cur: Vector2i = frontier[head]
		head += 1
		if dist[cur] >= steps:
			continue
		var nbrs := Hex.neighbors(cur.x, cur.y)
		for n: Vector2i in nbrs:
			if blocked.has(n) or dist.has(n):
				continue
			dist[n] = dist[cur] + 1
			frontier.append(n)
	dist.erase(start)
	return dist

## Flying stacks may land anywhere on the battlefield, regardless of speed, and
## ignore intervening creatures and obstacles. Destination occupancy is filtered
## by BattleState.
static func flying_reachable(start: Vector2i) -> Dictionary:
	var out := {}
	for row in Hex.ROWS:
		for col in Hex.COLS:
			var h := Vector2i(col, row)
			var distance := Hex.distance(start.x, start.y, col, row)
			if distance > 0:
				out[h] = distance
	return out

## Shortest hex path from `start` to `goal` (BFS, parent backtrace).
## Returns the waypoints AFTER start, ending at goal; empty if unreachable.
static func path(start: Vector2i, goal: Vector2i, blocked: Dictionary) -> Array:
	if start == goal:
		return []
	var prev := {start: start}
	var frontier: Array = [start]
	var head := 0
	while head < frontier.size():
		var cur: Vector2i = frontier[head]
		head += 1
		if cur == goal:
			break
		for n: Vector2i in Hex.neighbors(cur.x, cur.y):
			if prev.has(n) or (blocked.has(n) and n != goal):
				continue
			prev[n] = cur
			frontier.append(n)
	if not prev.has(goal):
		return []
	var out: Array = []
	var c := goal
	while c != start:
		out.push_front(c)
		c = prev[c]
	return out
