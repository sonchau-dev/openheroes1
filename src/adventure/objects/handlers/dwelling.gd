extends RefCounted
## Dwelling: joins all available troops to the hero, then empties the stock.

func visit(obj: MapObject, ctx: VisitContext = null) -> VisitResult:
	var dw := obj as Dwelling
	var r := VisitResult.new()
	if dw == null:
		return r
	var paid := dw.cost > 0 or not dw.cost_resources.is_empty() or dw.unit in ["rogue", "nomad", "genie"]
	# heroes.exe (0xb53db) tells of an empty free dwelling before it looks at
	# the hero's army, so an empty hut never reports full ranks.
	if not paid and dw.available <= 0:
		r.message = empty_message(dw)
		r.show_dialog = true
		return r
	if ctx != null and ctx.hero_model != null and ctx.hero_model.army != null:
		if not ctx.hero_model.army.can_add(dw.unit):
			r.message = "You are unable to recruit at this time, your ranks are full."
			r.show_dialog = true
			return r
	if paid:
		r.recruit_dwelling = dw
		return r
	r.free_dwelling = dw
	r.join_unit = dw.unit
	r.join_count = dw.available
	r.show_dialog = false
	r.message = ""
	dw.available = 0
	return r

## The visit-message title heroes.exe gives a free dwelling (messages 0x17..0x25,
## three per dwelling). These differ from the object names the quick info shows
## (House, Straw Hut, Cabin, Log Cabin).
static func visit_title(dw: Dwelling) -> String:
	match dw.unit:
		"goblin": return "Hut"
		"peasant": return "Thatched Hut"
		"archer", "dwarf": return "Cottage"
	return dw.title

static func empty_message(dw: Dwelling) -> String:
	match dw.unit:
		"goblin":
			return "Hut\n\nAs you approach the goblin dwelling, you notice that there is no one here."
		"peasant":
			# The fifth dwelling (a peasant Log Cabin, object 145) has its own
			# copy of the text, without the comma.
			if dw.title == "Log Cabin":
				return "Thatched Hut\n\nAs you approach the peasant dwelling you notice that there is no one here."
			return "Thatched Hut\n\nAs you approach the peasant dwelling, you notice that there is no one here."
		"archer":
			return "Cottage\n\nAs you approach the archer dwelling, you notice that there is no one here."
		"dwarf":
			return "Cottage\n\nAs you approach the dwarves' dwelling, you notice that there is no one here."
	return "As you approach the %s dwelling, you notice that there is no one here." % dw.unit
