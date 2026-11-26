extends RefCounted
## Weekly visit-gate (Windmill + Watermill,
## data/knowledge_base/adventure-object-catalog.md rows). Data-driven: the
## catalog's params decide WHAT is granted; this handler only enforces WHEN
## (once per game-week) and the Watermill's authentic first-week discount.
##
## params shapes (catalog.json):
##   {"stat": "resource_random", "amount": N, "pool": [res, ...]}  -- Windmill:
##     +N of ONE resource rolled from `pool` via Game.rng (the note: "never
##     gold or wood" -- enforced by the catalog's pool simply excluding both,
##     not by this handler).
##   {"gold": N, "first_week_gold": M}  -- Watermill: N gold/week, EXCEPT the
##     very FIRST-EVER collection (obj.last_collected_week still -1 when this
##     visit starts) yields only M gold if it lands in game week 1 (week index
##     0, i.e. Game.state.day 1-7).

## The visit texts as heroes.exe stores them (data 0x20e44), without the
## title line the window adds itself.
const MSG_RESOURCE_GRANTED := "The keeper of the mill announces: \"Milord, I have been working very hard to provide you with these resources, come back next week for more.\""
const MSG_RESOURCE_EMPTY := "The keeper of the mill announces: \"Milord, I am sorry, there are no resources currently available. Please try again next week.\""
const MSG_GOLD_GRANTED := "The keeper of the mill announces: \"Milord, I have been working very hard to provide you with this gold, come back next week for more.\""
const MSG_GOLD_EMPTY := "The keeper of the mill announces: \"Milord, I am sorry, there is no gold currently available. Please try again next week.\""

func visit(obj: MapObject, _ctx: VisitContext) -> VisitResult:
	var wp := obj as WeeklyPickup
	var r := VisitResult.new()
	if wp == null or Game.state == null:
		return r
	var is_gold := wp.params.has("gold")
	var current_week := (Game.state.day - 1) / GameState.DAYS_PER_WEEK
	if current_week <= wp.last_collected_week:
		r.message = MSG_GOLD_EMPTY if is_gold else MSG_RESOURCE_EMPTY
		r.show_dialog = true
		return r
	var p: Dictionary = wp.params
	var granted := _roll_grant(p, wp, current_week)
	if granted.is_empty():
		return r   # malformed/empty params: no yield, gate NOT consumed (nothing to collect)
	wp.last_collected_week = current_week
	r.granted = granted
	r.message = MSG_GOLD_GRANTED if is_gold else MSG_RESOURCE_GRANTED
	r.show_dialog = true
	return r

func _roll_grant(p: Dictionary, wp: WeeklyPickup, current_week: int) -> Dictionary:
	if String(p.get("stat", "")) == "resource_random":
		var pool: Array = p.get("pool", [])
		if pool.is_empty():
			return {}
		var res := wp.week_resource
		if res == "":
			res = String(pool[Game.rng.randi_range(0, pool.size() - 1)])
		return {res: int(p.get("amount", 0))}
	if p.has("gold"):
		var gold := int(p["gold"])
		# Watermill's note caveat: the FIRST-EVER collection (never collected
		# before this visit) that lands in game week 1 (week index 0) yields
		# only first_week_gold instead of the full weekly gold.
		if wp.last_collected_week == -1 and current_week == 0 and p.has("first_week_gold"):
			gold = int(p["first_week_gold"])
		return {"gold": gold}
	return {}
