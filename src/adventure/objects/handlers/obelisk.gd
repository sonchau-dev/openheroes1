extends RefCounted
## Obelisk (data/knowledge_base/adventure-object-catalog.md
## Obelisk row): "Reveals the entire map if there is exactly one obelisk
## on the map, or one piece of the treasure/puzzle map if there are multiple.
## ... Yes (per-obelisk, once visited it just repeats 'already visited')." Max 48
## obelisks/map (note; not enforced here — placement-time concern only).
##
## puzzle_pieces lives on PlayerState (per SIDE — see player_state.gd), not per
## hero: the puzzle map is kingdom-wide knowledge, matching HOMM1's real
## single per-player puzzle screen and this project's existing `explored`
## fog-of-war bitset precedent (also per-side). Different players (sides) each
## track their OWN progress independently, including toward the SAME physical
## obelisk (side 0 and side 1 visiting the same obelisk id both record it, on
## their own PlayerState — HOMM1's puzzle map is not a shared/racing resource).
##
## Never consumed: the obelisk sprite always stays on the map (matches the
## note's "per-obelisk, once visited it just repeats 'already visited'" — an
## inert repeat message, not removal).

const INTRO := "You come upon an obelisk made from a type of stone you have never seen before.  Staring at it intensely, the smooth surface suddenly changes to an inscription.  The inscription is a piece of a lost ancient map.  Quickly you copy down the piece and the inscription vanishes as abruptly as it had appeared."
const REVISIT := "You have already been to this obelisk."

func visit(obj: MapObject, ctx: VisitContext) -> VisitResult:
	var r := VisitResult.new()
	var player: PlayerState = Game.state.player_of(ctx.player_side) if Game.state != null else null
	if player == null:
		return r   # no matching PlayerState (unknown side / no live game state): safe no-op
	if player.puzzle_pieces.has(obj.id):
		r.message = REVISIT
		r.show_dialog = true
		r.already_visited = true
		return r
	player.puzzle_pieces.append(obj.id)
	if player.is_ai and ctx.map != null and Game.state != null:
		AIPlanner.refresh_dig_guess(player, ctx.map, Game.rng, Game.state.dug_tiles)
	var total := Dig.count_obelisks(ctx.map) if ctx.map != null else 0
	if total <= 1:
		r.reveal_map = true
	r.message = INTRO
	r.show_dialog = true
	return r
