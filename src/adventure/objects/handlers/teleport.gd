extends RefCounted
## Stone Liths / Menhir. data/knowledge_base/adventure-object-catalog.md's
## "Stone Liths / Menhir" row documents the real HOMM1 mechanic as a single
## many-to-many random-teleport POOL, not fixed A<->B gate pairs: "Randomly
## teleports the hero to another Stone Liths/Menhir on
## the map. If the destination menhir is currently 'occupied' by any hero
## (including the visiting player's own), the teleport is blocked."
##
## Every stone_liths object on ctx.map forms one pool. Visiting one rolls a
## random OTHER lith (Game.rng — the seeded live RNG, same pattern chest/
## campfire/shrine use, never bare randi()); a destination whose action_tile
## currently holds any hero is excluded from candidates. No free candidate ->
## no teleport and no message, object stays fully repeatable (never consumed). Landing is the destination's action_tile; the resolver applies
## `teleport_to` via its teleport_fn Callable (root's teleport_hero, which
## explicitly does NOT auto-visit the landing tile — see adventure_map.gd:438-442
## and its doc comment — so arriving on another lith by teleport can never
## re-trigger a chain teleport).

const MIN_DISTANCE := 3

func visit(obj: MapObject, ctx: VisitContext) -> VisitResult:
	var r := VisitResult.new()
	if ctx.map == null:
		# Bare/test contexts (no map wired): nothing to scan for partners.
		return r
	# heroes.exe 0xb38a4 counts every lith cell more than 3 tiles (Manhattan)
	# from the hero and picks one at random, so a nearby lith is never a
	# destination and a wider lith is likelier.
	var occupied: Array = ctx.occupied_tiles
	var candidates: Array[Vector2i] = []
	for o: MapObject in ctx.map.objects:
		if o == obj or o.type != "stone_liths":
			continue
		for cell: Vector2i in o.interaction_tiles():
			var d := absi(cell.x - obj.action_tile.x) + absi(cell.y - obj.action_tile.y)
			if d > MIN_DISTANCE and not occupied.has(cell):
				candidates.append(cell)
	if candidates.is_empty():
		# heroes.exe does nothing at all when no lith qualifies.
		return r
	r.teleport_to = candidates[Game.rng.randi_range(0, candidates.size() - 1)]
	# No message/dialog on a successful teleport: HOMM1's Stone Liths just moves
	# the hero silently (matches the spell-cast "teleport" case in
	# spell_controller.gd's cast(), which also fires _teleport_fn with no dialog).
	return r
