class_name WeeklyPickup
extends MapObject

## Windmill + Watermill (data/knowledge_base/adventure-object-catalog.md
## Windmill/Watermill rows). Generic
## once-per-game-week visit gate — distinct from GuardedPickup's one-shot
## `looted` flag and Mine/DragonCity's continuous daily tick: this site is
## inert only until the NEXT game week starts, then yields again forever.
## Params (catalog default_params, see catalog.json's _comment_weekly):
##   windmill:  {stat: "resource_random", amount: 2, pool: [...]}
##   watermill: {gold: 1000, first_week_gold: 500}
## The handler (handlers/weekly_pickup.gd) reads params; this class only
## carries the persisted collection-gate state.

## Game-week index ((Game.state.day - 1) / GameState.DAYS_PER_WEEK) of the last
## effective collection. -1 = never collected (also distinguishes "first-ever
## collection" for the Watermill's game-week-1 discount from an ordinary
## same-week revisit).
var last_collected_week: int = -1
## A windmill's resource this week, rolled at map start and each new week
## (heroes.exe 0x7b295, 0x7feea: cell byte 9 = random(1, 5)); "" = not rolled.
var week_resource: String = ""

## Rolls a windmill's resource from its pool; other weekly sites keep none.
func roll_week_resource(rng: RandomNumberGenerator) -> void:
	var pool: Array = params.get("pool", [])
	if String(params.get("stat", "")) == "resource_random" and not pool.is_empty():
		week_resource = String(pool[rng.randi_range(0, pool.size() - 1)])

func save_state() -> Dictionary:
	var d := super.save_state()
	d["last_collected_week"] = last_collected_week
	if week_resource != "":
		d["week_resource"] = week_resource
	return d

func apply_state(s: Dictionary) -> void:
	super.apply_state(s)
	last_collected_week = int(s.get("last_collected_week", last_collected_week))  # JSON ints load as floats
	week_resource = String(s.get("week_resource", week_resource))
