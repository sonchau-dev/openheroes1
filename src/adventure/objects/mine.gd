class_name Mine
extends MapObject

## Ownable resource generator. Yields `daily` of `res` per day once owned.
## If `guard` is non-empty, the first visit launches a battle; capture happens
## on victory (handled by the adventure map's post-battle hook).

var res: String = "ore"
var daily: int = 0
var guard: ArmyData = null

func _init() -> void:
	type = "mine"

func is_armed() -> bool:
	return owner == -1 and guard != null and not guard.is_empty()

## Resources added per end-of-day while owned.
func daily_yield() -> Dictionary:
	return {res: daily}

func save_state() -> Dictionary:
	var d := super.save_state()
	d["owner"] = owner
	return d

func apply_state(s: Dictionary) -> void:
	super.apply_state(s)
	owner = int(s.get("owner", -1))

func to_spec() -> Dictionary:
	var d := super.to_spec()
	d["res"] = res
	d["daily"] = daily
	if guard != null and not guard.is_empty():
		d["guard"] = MapObject.army_rows(guard)
	return d
