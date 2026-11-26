extends RefCounted

func visit(obj: MapObject, ctx: VisitContext) -> VisitResult:
	var result := VisitResult.new()
	if obj is not Lighthouse:
		return result
	# heroes.exe 0xb29eb: the owner's own visit does nothing.
	if obj.owner == ctx.player_side:
		return result
	obj.owner = ctx.player_side
	result.message = "The lighthouse is now under your control, and all of your ships will now move further each turn."
	result.show_dialog = true
	return result
