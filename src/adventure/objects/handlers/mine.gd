extends RefCounted
## Mine: captures for the visiting side, or launches a battle if still guarded.

func visit(obj: MapObject, ctx: VisitContext) -> VisitResult:
	var mine := obj as Mine
	var r := VisitResult.new()
	if mine == null:
		return r
	if mine.owner == ctx.player_side:
		return r
	if mine.owner >= 0 and Game.state != null and ctx.player_state != null:
		var mine_owner := Game.state.player_of(mine.owner)
		if mine_owner != null and not ctx.player_state.is_hostile_to(mine_owner):
			return r
	if mine.is_armed():
		r.start_battle = mine.guard
		return r
	mine.owner = ctx.player_side
	r.message = "%s mine captured" % mine.res
	return r
