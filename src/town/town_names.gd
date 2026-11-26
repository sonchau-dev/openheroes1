class_name TownNames
extends RefCounted

## The original's 36 random town names (homm1-native-data.md 3.6). Each town
## record stores one index into this flat table, and DOS saves of one scenario
## give the same name to different factions across runs, so a name does not
## depend on the town's type.
const NAMES := [
	"Blackridge", "Pinehurst", "Woodhaven", "Hillstone", "Whiteshield", "Bloodreign",
	"Dragontooth", "Greywind", "Blackwind", "Portsmith", "Middle Gate", "Tundara",
	"Vulcania", "Sansobar", "Atlantium", "Baywatch", "Wildabar", "Fountainhead",
	"Vertigo", "Winterkill", "Nightshadow", "Sandcaster", "Lakeside", "Olympus",
	"Necropolis", "Burlock", "Xabran", "Dragadune", "Alamar", "Kalindra",
	"Blackfang", "Basenji", "Algary", "Sorpigal", "Dusk", "Erliquin",
]

## Give every unnamed town a name no other town on the map shares, drawn at random
## from all 36. Idempotent: named towns keep their name.
static func assign(objects: Array, rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var free: Array = NAMES.duplicate()
	for o: Variant in objects:
		if o is TownObject:
			free.erase(String(o.params.get("name", "")))
	for o: Variant in objects:
		if not (o is TownObject) or String(o.params.get("name", "")) != "":
			continue
		if free.is_empty():
			free = NAMES.duplicate()
		o.params["name"] = free.pop_at(rng.randi_range(0, free.size() - 1))
