extends RefCounted
## Town: entering opens the town screen.

func visit(_obj: MapObject, _ctx: VisitContext) -> VisitResult:
	var r := VisitResult.new()
	r.enter_town = true
	return r
