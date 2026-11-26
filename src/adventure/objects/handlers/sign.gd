extends RefCounted
## Sign (HOMM1 Signpost, KB objects.md:128): shows the name of the nearest
## castle/town on the map. `params.text`, when authored non-empty, is a
## scenario-tool override (our own extension beyond the real HOMM1 object,
## kept for mapmaker flavor text — see homm1-object-catalog.md's Signpost row).
## Never consumed, no state.

func visit(obj: MapObject, ctx: VisitContext) -> VisitResult:
	var r := VisitResult.new()
	var text := String(obj.params.get("text", ""))
	if text == "":
		text = _nearest_castle_message(obj, ctx)
	r.message = text
	r.show_dialog = text != ""   # never pop an empty dialog when no castle is found/named
	return r

## Nearest town by Manhattan distance (tile-step count matches adventure-map
## movement cost more closely than Euclidean for this purpose). Ties keep the
## first town encountered in map.objects order.
func _nearest_castle_message(obj: MapObject, ctx: VisitContext) -> String:
	if ctx == null or ctx.map == null:
		return ""
	var best_name := ""
	var best_dist := -1
	for o: MapObject in ctx.map.objects:
		if o.type != "town":
			continue
		var name := String(o.params.get("name", ""))
		if name == "":
			continue
		var d: int = absi(o.tile.x - obj.tile.x) + absi(o.tile.y - obj.tile.y)
		if best_dist < 0 or d < best_dist:
			best_dist = d
			best_name = name
	if best_name == "":
		return ""
	return "Signpost\n\nA signpost reads:\n\n%s is near." % best_name
