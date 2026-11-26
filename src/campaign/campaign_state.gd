class_name CampaignState
extends RefCounted

var ruler: int = 0
var route: Array[int] = []
var route_index: int = 0
var total_days: int = 1
var mission_start_day: int = 1
var mission_seed: int = 0
var completed: bool = false

static func create(p_ruler: int) -> CampaignState:
	var c := CampaignState.new()
	c.ruler = clampi(p_ruler, 0, 3)
	c.route = CampaignCatalog.route_for(c.ruler)
	c.mission_seed = c._seed_for_current()
	return c

func mission_id() -> int:
	return route[route_index] if route_index >= 0 and route_index < route.size() else -1

func mission() -> CampaignMission:
	return CampaignCatalog.mission(mission_id())

func advance(completed_on_day: int) -> bool:
	total_days = maxi(total_days, completed_on_day)
	route_index += 1
	if route_index >= route.size():
		completed = true
		return false
	mission_start_day = total_days + 1
	mission_seed = _seed_for_current()
	return true

## A fresh roll each time a mission is reached, so a new campaign does not
## replay the last one's artifacts and monsters. Restart reuses the stored
## seed, which keeps a restarted mission identical.
func _seed_for_current() -> int:
	return randi()

func to_dict() -> Dictionary:
	return {"ruler": ruler, "route": route.duplicate(), "route_index": route_index,
		"total_days": total_days, "mission_start_day": mission_start_day,
		"mission_seed": mission_seed, "completed": completed}

static func from_dict(d: Dictionary) -> CampaignState:
	var c := CampaignState.new()
	c.ruler = clampi(int(d.get("ruler", 0)), 0, 3)
	for id in d.get("route", CampaignCatalog.route_for(c.ruler)):
		c.route.append(int(id))
	c.route_index = clampi(int(d.get("route_index", 0)), 0, c.route.size())
	c.total_days = maxi(1, int(d.get("total_days", 1)))
	c.mission_start_day = maxi(1, int(d.get("mission_start_day", c.total_days)))
	c.mission_seed = int(d.get("mission_seed", c._seed_for_current()))
	c.completed = bool(d.get("completed", c.route_index >= c.route.size()))
	return c
