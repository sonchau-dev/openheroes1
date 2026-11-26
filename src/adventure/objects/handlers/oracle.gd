extends RefCounted
## Oracle map object, presented as "Shrine" by the original event window. It is
## repeatable and opens the complete four-level Thieves' Guild ranking table.

const INTRO := "Within the ornate shrine sits a blind seer. After explaining the intent of your journey, the seer activates his crystal ball, allowing you to see the strengths and weaknesses of your opponents."

func visit(_obj: MapObject, _ctx: VisitContext) -> VisitResult:
	var r := VisitResult.new()
	r.open_oracle = true
	r.message = INTRO
	return r
