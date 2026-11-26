extends RefCounted
## Neutral stack: offers to join if joinable and hero army is > 1.75x stronger;
## otherwise launches a battle with its army while unbeaten.

func visit(obj: MapObject, ctx: VisitContext) -> VisitResult:
	var stack := obj as NeutralStack
	var r := VisitResult.new()
	if stack == null or not stack.is_armed():
		return r
	var hero_army: ArmyData = ctx.hero_model.army if ctx != null and ctx.hero_model != null else null
	if stack.can_offer_join(hero_army):
		r.join_offer_stack = stack
		return r
	r.start_battle = stack.army
	return r
