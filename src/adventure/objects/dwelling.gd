class_name Dwelling
extends MapObject

## Adventure-map troop dwelling. Most dwellings give their stock away; paid
## dwellings (Wagons/Tents/Lamps) open the native recruit flow instead.

var unit: String = "peasant"
var weekly: int = 0
var weekly_min: int = 0
var weekly_max: int = 0
var available: int = 0
var cost: int = 0
var cost_resources: Dictionary = {}
var disappears_when_empty: bool = false
var title: String = ""
var offer_text: String = ""
var empty_text: String = ""

func weekly_grow(rng: RandomNumberGenerator = null) -> int:
	var growth := weekly
	if weekly_max > 0:
		var low := mini(weekly_min if weekly_min > 0 else weekly_max, weekly_max)
		var high := maxi(weekly_min, weekly_max)
		growth = rng.randi_range(low, high) if rng != null else randi_range(low, high)
	available += growth
	return growth

func total_cost_for(count: int) -> Dictionary:
	var res_cost := cost_resources if not cost_resources.is_empty() else ({"gold": cost} if cost > 0 else {})
	var total: Dictionary = {}
	for r: String in res_cost:
		total[r] = int(res_cost[r]) * count
	return total

func max_recruitable(player: PlayerState, army: ArmyData) -> int:
	if player == null or army == null or not army.can_add(unit):
		return 0
	var res_cost := cost_resources if not cost_resources.is_empty() else ({"gold": cost} if cost > 0 else {})
	if res_cost.is_empty():
		return available
	var max_affordable := available
	for r: String in res_cost:
		var per_unit := int(res_cost[r])
		if per_unit > 0:
			var player_has := player.gold() if r == "gold" else (int(player.resources.get(r, 0)) if player.resources != null else 0)
			max_affordable = mini(max_affordable, player_has / per_unit)
	return max_affordable

func recruit(count: int, player: PlayerState, army: ArmyData) -> bool:
	if count <= 0 or count > max_recruitable(player, army):
		return false
	if not army.add(unit, count):
		return false
	var total := total_cost_for(count)
	player.pay(total)
	available -= count
	if disappears_when_empty and available <= 0:
		consumed = true
	return true

func save_state() -> Dictionary:
	var d := super.save_state()
	d["available"] = available
	return d

func apply_state(s: Dictionary) -> void:
	super.apply_state(s)
	available = int(s.get("available", available))
	if disappears_when_empty and available <= 0:
		consumed = true

func to_spec() -> Dictionary:
	var d := super.to_spec()
	d["unit"] = unit
	d["weekly"] = weekly
	d["available"] = available
	if weekly_min > 0:
		d["weekly_min"] = weekly_min
	if weekly_max > 0:
		d["weekly_max"] = weekly_max
	if cost > 0:
		d["cost"] = cost
	if not cost_resources.is_empty():
		var cr: Dictionary = {}
		for rk: String in cost_resources:
			cr[rk] = int(cost_resources[rk])
		d["cost_resources"] = cr
	if disappears_when_empty:
		d["disappears_when_empty"] = disappears_when_empty
	if title != "":
		d["title"] = title
	if offer_text != "":
		d["offer_text"] = offer_text
	if empty_text != "":
		d["empty_text"] = empty_text
	return d
