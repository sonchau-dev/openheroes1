class_name GameState
extends RefCounted

## Persistent run state: day counter + per-side kingdoms. In a standard game
## active_player_side stays zero. Hot-seat rotates it between local humans, so
## the long-standing human() delegates remain useful to every gameplay screen.

const DAYS_PER_WEEK := 7
const DAYS_PER_MONTH := 28
const ORDINARY_WEEK_NAMES := [
	"Squirrel", "Rabbit", "Gopher", "Badger", "Rat", "Eagle", "Weasel",
	"Raven", "Mongoose", "Dog", "Aardvark", "Lizard", "Tortoise",
	"Hedgehog", "Condor",
]
const CREATURE_WEEK_UNITS := [
	"peasant", "archer", "pikeman", "swordsman", "cavalry", "paladin",
	"goblin", "orc", "wolf", "ogre", "troll", "cyclops",
	"sprite", "dwarf", "elf", "druid", "unicorn", "phoenix",
	"centaur", "gargoyle", "griffin", "minotaur", "hydra", "dragon",
]
const ORDINARY_MONTH_NAMES := [
	"Grasshopper", "Ant", "Dragonfly", "Spider", "Butterfly",
	"Bumblebee", "Locust", "Earthworm", "Hornet", "Beetle",
]
const CREATURE_MONTH_UNITS := [
	"peasant", "goblin", "dwarf", "elf", "ogre", "druid",
	"orc", "wolf", "centaur", "gargoyle", "unicorn", "griffin",
]


var day: int = 1
## The run's Ultimate Artifact, {"tile": [x, y], "artifact": id}; {} once dug
## or when there is none. Set at new game, so every map load restores it.
var ultimate_artifact: Dictionary = {}
var ultimate_set := false
## Tiles dug this run. A dig leaves a hole sprite in the cell (heroes.exe
## 0x98b0e), so a tile can be dug only once and the computer never guesses it.
var dug_tiles: Array[Vector2i] = []
var players: Array = []   # Array[PlayerState], ordered by runtime turn order
var active_player_side: int = 0
var boats: Array[BoatState] = []
var next_boat_id: int = 1
var last_week_event: Dictionary = {}
var last_spawned_neutrals: Array[NeutralStack] = []
var spawned_neutral_stacks: Array[Dictionary] = []
var hero_pool: HeroPool = null
var king_of_the_hill: bool = false

## --- players[0] delegates (back-compat for town screen / HUD / overview) ---
var town: TownModel:
	get:
		return null if players.is_empty() else human().town
var resources: Dictionary:
	get:
		return {} if players.is_empty() else human().resources
var daily_income: int:
	get:
		return 0 if players.is_empty() else human().daily_income
	set(v):
		if not players.is_empty():
			human().daily_income = v

func setup(start_gold: int, available: Dictionary, p_daily_income: int = -1, rng: RandomNumberGenerator = null) -> void:
	players.clear()
	active_player_side = 0
	var p := PlayerState.new()
	p.setup(0, false, 0, start_gold, available, p_daily_income)
	players.append(p)
	if hero_pool == null:
		hero_pool = HeroPool.new()
		hero_pool.setup(rng, 0)

func human() -> PlayerState:
	var active := player_of(active_player_side)
	if active != null and not active.is_ai:
		return active
	for p: PlayerState in players:
		if not p.is_ai:
			active_player_side = p.side
			return p
	return players[0] if not players.is_empty() else null

## The player of `side`, or null. (Sides are assigned in append order, but look
## up by field rather than index so eliminations can't shift identities.)
func player_of(side: int) -> PlayerState:
	for p: PlayerState in players:
		if p.side == side:
			return p
	return null

func add_player(is_ai: bool, crest: int, start_gold: int, available: Dictionary,
		income: int = -1) -> PlayerState:
	var p := PlayerState.new()
	p.setup(players.size(), is_ai, crest, start_gold, available, income)
	players.append(p)
	return p

func human_players(alive_only: bool = true) -> Array:
	var out: Array = []
	for p: PlayerState in players:
		if not p.is_ai and (p.alive or not alive_only):
			out.append(p)
	return out

## The next local player later in today's humans-first turn order.
func next_human_after(side: int) -> PlayerState:
	for p: PlayerState in players:
		if not p.is_ai and p.alive and p.side > side:
			return p
	return null

func first_human() -> PlayerState:
	for p: PlayerState in players:
		if not p.is_ai and p.alive:
			return p
	return null

func first_ai_side() -> int:
	for p: PlayerState in players:
		if p.is_ai and p.alive:
			return p.side
	return players.size()

## Alive AI sides, in side order.
func ai_players() -> Array:
	var out: Array = []
	for p: PlayerState in players:
		if p.is_ai and p.alive:
			out.append(p)
	return out

func gold() -> int:
	return human().gold()

func add_resources(bag: Dictionary) -> void:
	human().add_resources(bag)

func boat_at(tile: Vector2i) -> BoatState:
	for boat: BoatState in boats:
		if boat.tile == tile:
			return boat
	return null

## The hero standing or sailing on `tile`. A sailing hero carries its boat,
## so boat_at() misses it.
func hero_at(tile: Vector2i) -> HeroModel:
	for p: PlayerState in players:
		if not p.alive:
			continue
		for h: HeroModel in p.heroes:
			if h.tile == tile:
				return h
	return null

## Every tile a hero stands or sails on, as a set.
func hero_tiles() -> Dictionary:
	var out := {}
	for p: PlayerState in players:
		if not p.alive:
			continue
		for h: HeroModel in p.heroes:
			out[h.tile] = true
	return out

func boat_by_id(id: int) -> BoatState:
	for boat: BoatState in boats:
		if boat.id == id:
			return boat
	return null

func create_boat(tile: Vector2i, owner: int, direction: int = Direction.E) -> BoatState:
	if boat_at(tile) != null:
		return null
	var boat := BoatState.create(next_boat_id, tile, owner, direction)
	next_boat_id += 1
	boats.append(boat)
	return boat

func take_boat(id: int) -> BoatState:
	var boat := boat_by_id(id)
	if boat != null:
		boats.erase(boat)
	return boat

func place_boat(id: int, tile: Vector2i, owner: int, direction: int) -> BoatState:
	if boat_at(tile) != null:
		return null
	var actual_id := id if id >= 0 else next_boat_id
	var boat := BoatState.create(actual_id, tile, owner, direction)
	boats.append(boat)
	next_boat_id = maxi(next_boat_id, actual_id + 1)
	return boat

func is_first_day_of_week() -> bool:
	return (day - 1) % DAYS_PER_WEEK == 0

func is_first_day_of_month() -> bool:
	return (day - 1) % DAYS_PER_MONTH == 0 and day > 1

## HOMM1's week table has a common denominator of 480: each of the fifteen
## ordinary names owns 24 outcomes (75% total), while each castle creature
## owns five outcomes (25% total), as heroes.exe 0x7fc84 rolls them. Its
## "week == 4" test there reads the counter before the increment, so it only
## spares the week that opens a month, which the month proclamation replaces;
## the fourth week of a month rolls like any other. Tests and legacy callers
## without an RNG use Gopher deterministically.
static func roll_week_event(rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		return {"kind": "ordinary", "name": "Gopher", "unit": ""}
	var roll := rng.randi_range(0, 479)
	if roll < 360:
		return {
			"kind": "ordinary",
			"name": String(ORDINARY_WEEK_NAMES[int(roll / 24)]),
			"unit": "",
		}
	var unit := String(CREATURE_WEEK_UNITS[int((roll - 360) / 5)])
	return {"kind": "creature", "name": unit.capitalize(), "unit": unit}

## HOMM1's month table has a common denominator of 300 (KB week.md §9.4):
## - 50% Ordinary Animal Months (10 names, 15 outcomes each = 1/20 each)
## - 40% Creature Months (12 units, 10 outcomes each = 1/30 each)
## - 10% Month of PLAGUE (30 outcomes = 1/10)
static func roll_month_event(rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		return {"cycle": "month", "kind": "ordinary", "name": "Grasshopper", "unit": ""}
	var roll := rng.randi_range(0, 299)
	if roll < 150:
		var name := String(ORDINARY_MONTH_NAMES[int(roll / 15)])
		return {"cycle": "month", "kind": "ordinary", "name": name, "unit": ""}
	if roll < 270:
		var unit := String(CREATURE_MONTH_UNITS[int((roll - 150) / 10)])
		return {"cycle": "month", "kind": "creature", "name": unit.capitalize(), "unit": unit}
	return {"cycle": "month", "kind": "plague", "name": "PLAGUE", "unit": ""}

static func month_message(event: Dictionary) -> String:
	var kind := String(event.get("kind", "ordinary"))
	var name := String(event.get("name", "Grasshopper"))
	if kind == "plague":
		return "Astrologers proclaim month of the PLAGUE!\n\nAll populations are halved."
	if kind == "creature":
		return "Astrologers proclaim month of the %s.\n\n%s population doubles!\n\nAll dwellings increase population." % [name.to_lower(), name.capitalize()]
	return "Astrologers proclaim month of the %s.\n\nAll dwellings increase population." % name

static func week_message(event: Dictionary) -> String:
	if String(event.get("cycle", "week")) == "month":
		return month_message(event)
	var name := String(event.get("name", "Gopher"))
	if String(event.get("kind", "ordinary")) == "creature":
		return "Astrologers proclaim week of the %s.\n\n%s growth +5.\n\nAll dwellings increase population." % [name.to_lower(), name.capitalize()]
	return "Astrologers proclaim week of the %s.\n\nAll dwellings increase population." % name

## Advance one day for EVERY side: income, per-owner mine sweep, and on a new
## week refill every town's availability + grow dwellings. Returns new-week flag.
func advance_day(objects: Array = [], rng: RandomNumberGenerator = null, map: MapData = null) -> bool:
	day += 1
	last_spawned_neutrals.clear()
	for p: PlayerState in players:
		if not p.alive:
			continue
		p.identify_hero_active = false
		for town_model: TownModel in p.towns:
			town_model.built_today = false
		p.treasury_gold += p.daily_income
		# Every living carrier pays artifact income to the owning kingdom.
		# Duplicate income artifacts deliberately stack in HeroModel.
		for hero: HeroModel in p.heroes:
			p.treasury_gold += hero.daily_gold_bonus()
		for o in objects:
			if o is Mine and (o as Mine).owner == p.side:
				p.add_resources((o as Mine).daily_yield())
			elif o is DragonCity and (o as DragonCity).owner == p.side:
				p.add_resources((o as DragonCity).daily_yield())
	var new_week := is_first_day_of_week()
	if new_week:
		var new_month := is_first_day_of_month()
		if new_month:
			last_week_event = roll_month_event(rng)
			var kind := String(last_week_event.get("kind", "ordinary"))
			if kind == "plague":
				for p: PlayerState in players:
					for town_model: TownModel in p.towns:
						for u: String in town_model.available.keys():
							town_model.available[u] = int(town_model.available[u] / 2)
				# Plague halves town dwellings only. heroes.exe grows the map's
				# dwellings every week (0x7fec2) before it rolls the month.
				for o in objects:
					if o is Dwelling and not (o as Dwelling).consumed:
						if not is_dwelling_occupied(o as Dwelling):
							(o as Dwelling).weekly_grow(rng)
			else:
				var bonus_unit := String(last_week_event.get("unit", ""))
				for p: PlayerState in players:
					var p_ai_level := p.ai_level if p.is_ai else 0
					for town_model: TownModel in p.towns:
						_grow(town_model, "", p_ai_level)
						if kind == "creature" and bonus_unit != "" and town_model.available.has(bonus_unit):
							town_model.available[bonus_unit] = int(town_model.available[bonus_unit]) * 2
				for o in objects:
					if o is TownObject and (o as TownObject).owner < 0:
						TownObject.replenish_neutral_garrison(o as TownObject, rng)
					elif o is Dwelling and not (o as Dwelling).consumed:
						if not is_dwelling_occupied(o as Dwelling):
							(o as Dwelling).weekly_grow(rng)
				if kind == "creature" and bonus_unit != "" and map != null:
					spawn_month_creatures(map, bonus_unit, rng)
		else:
			last_week_event = roll_week_event(rng)
			var bonus_unit := String(last_week_event.get("unit", ""))
			for p: PlayerState in players:
				var p_ai_level := p.ai_level if p.is_ai else 0
				for town_model: TownModel in p.towns:
					_grow(town_model, bonus_unit, p_ai_level)
			for o in objects:
				if o is TownObject and (o as TownObject).owner < 0:
					TownObject.replenish_neutral_garrison(o as TownObject, rng)
				elif o is Dwelling and not (o as Dwelling).consumed:
					if not is_dwelling_occupied(o as Dwelling):
						(o as Dwelling).weekly_grow(rng)
		# Each new week re-rolls every windmill's resource (0x7feea).
		for o in objects:
			if o is WeeklyPickup and rng != null:
				(o as WeeklyPickup).roll_week_resource(rng)
		for p: PlayerState in players:
			p.returning_heroes.clear()
		if hero_pool != null:
			var alive_sides: Array = []
			for p: PlayerState in players:
				if p.alive:
					alive_sides.append(p.side)
			hero_pool.weekly_refresh(alive_sides, rng)
	return new_week

## Authentic HOMM1: If a hero occupies a dwelling's tile on Day 7, it does NOT grow on Day 1 (KB objects.md §7.3).
func is_dwelling_occupied(dwelling: Dwelling) -> bool:
	if dwelling == null:
		return false
	var target_action := dwelling.action_tile
	var target_tile := dwelling.tile
	for p: PlayerState in players:
		if not p.alive:
			continue
		for hero: HeroModel in p.heroes:
			if hero.tile != Vector2i(-1, -1):
				if (target_action != Vector2i(-1, -1) and hero.tile == target_action) or hero.tile == target_tile:
					return true
	return false

## Creature month (heroes.exe 0x8026b, KB calendar-economy.md 4.2): every land
## cell whose B8 is 0 (no object or scenery of any kind) rolls random(0, 360) == 10,
## which the 7-bit generator makes 1 in 128. Native maps carry their B8 cells
## as `object_cells`; a taken pickup or beaten stack clears its B8, as in the
## original. Hand-authored maps have no B8, so they fall back to passability.
func spawn_month_creatures(map: MapData, unit: String, rng: RandomNumberGenerator = null) -> Array[NeutralStack]:
	if map == null or unit == "":
		return []
	if rng == null:
		rng = RandomNumberGenerator.new()
	last_spawned_neutrals.clear()
	var occupied: Dictionary = {}
	var freed: Dictionary = {}
	var native := not map.object_cells.is_empty()
	for o in map.objects:
		if o is MapObject and (o as MapObject).consumed:
			freed[(o as MapObject).tile] = true
		elif o is MapObject:
			occupied[(o as MapObject).tile] = true
			occupied[(o as MapObject).action_tile] = true
			for it: Vector2i in (o as MapObject).interaction_tiles():
				occupied[it] = true
	for p: PlayerState in players:
		for h: HeroModel in p.heroes:
			occupied[h.tile] = true
	for b: BoatState in boats:
		occupied[b.tile] = true

	for y in map.height:
		for x in map.width:
			var tile := Vector2i(x, y)
			if not map.is_land(tile):
				continue
			if native:
				if map.object_cells.has(tile) and not freed.has(tile):
					continue
			elif not map.is_passable(x, y):
				continue
			if occupied.has(tile):
				continue
			if rng.randi_range(0, 127) == 10:
				var s := NeutralStack.new()
				s.id = map.objects.size()
				s.type = "stack"
				s.tile = tile
				s.action_tile = tile
				s.authored_interaction_tiles = [tile]
				s.entry_rule = "all"
				s.army = ArmyData.new()
				var amount: Array = NeutralStack.COUNT_RANGES.get(unit, [10, 20])
				var count: int = rng.randi_range(int(amount[0]), int(amount[1]))
				s.army.add(unit, count)
				s.joinable = (rng.randi_range(0, 1) == 1) if unit != "ghost" else false
				s.fought_before = false
				s.authored_fixed = false
				map.add_object(s)
				last_spawned_neutrals.append(s)
				var spec := s.to_spec()
				spec["id"] = s.id
				spawned_neutral_stacks.append(spec)
				occupied[tile] = true
	return last_spawned_neutrals

func restore_spawned_neutral_stacks(map: MapData) -> void:
	if map == null:
		return
	for spec: Dictionary in spawned_neutral_stacks:
		var sid := int(spec.get("id", -1))
		if sid >= 0 and map.object_by_id(sid) != null:
			continue
		var s := NeutralStack.new()
		s.id = sid if sid >= 0 else map.objects.size()
		s.type = "stack"
		var t_arr: Array = spec.get("tile", [0, 0])
		s.tile = Vector2i(int(t_arr[0]), int(t_arr[1]))
		s.action_tile = s.tile
		s.authored_interaction_tiles = [s.tile]
		s.entry_rule = "all"
		if spec.has("army") and spec["army"] is Dictionary:
			s.army = ArmyData.from_dict(spec["army"])
		elif spec.has("army") and spec["army"] is Array:
			s.army = ArmyData.new()
			for row in spec["army"]:
				if row is Array and row.size() >= 2:
					s.army.add(String(row[0]), int(row[1]))
		s.random_stack_id = int(spec.get("random_stack_id", -1))
		s.joinable = bool(spec.get("joinable", false))
		s.fought_before = bool(spec.get("fought_before", false))
		s.authored_fixed = bool(spec.get("authored_fixed", false))
		s.consumed = bool(spec.get("consumed", false))
		map.add_object(s)

## Back-compat name used by the town screen and older tests.
func end_turn(objects: Array = [], _player_side: int = 0) -> bool:
	return advance_day(objects)

## Weekly growth: only BUILT dwellings produce (KB castles.md), +2 each when
## the town has a Well. Keyed on built, not available — a newly built dwelling
## adds its unit key here on its first new week.
func _grow(t: TownModel, bonus_unit: String = "", ai_level: int = 0) -> void:
	var rec := TownModel._recruit_data(t.faction)
	var bonus := 2 if t.built.has("well") else 0
	var mult := TownModel.ai_growth_multiplier(ai_level)
	for id: String in t.built.keys():
		var unit := String(BuildingCatalog.entry(id, t.faction).get("unit", ""))
		if unit == "":
			continue
		var growth := int((rec.get(unit, {}) as Dictionary).get("growth", 0))
		var effective_growth := int(floor(float(growth + bonus) * mult))
		var creature_week_bonus := 5 if unit == bonus_unit else 0
		t.available[unit] = int(t.available.get(unit, 0)) + effective_growth \
				+ creature_week_bonus

## --- save/load ---

func to_dict() -> Dictionary:
	var ps: Array = []
	for p: PlayerState in players:
		ps.append(p.to_dict())
	var saved_boats: Array = []
	for boat: BoatState in boats:
		saved_boats.append(boat.to_dict())
	var out := {"day": day, "players": ps, "active_player_side": active_player_side,
		"boats": saved_boats,
		"last_week_event": last_week_event.duplicate(true),
		"next_boat_id": next_boat_id}
	if not spawned_neutral_stacks.is_empty():
		out["spawned_neutral_stacks"] = spawned_neutral_stacks.duplicate(true)
	if hero_pool != null:
		hero_pool.adopt_owned(players)
		out["hero_pool"] = hero_pool.to_dict()
	out["king_of_the_hill"] = king_of_the_hill
	if ultimate_set:
		out["ultimate_artifact"] = ultimate_artifact.duplicate(true)
	if not dug_tiles.is_empty():
		out["dug_tiles"] = dug_tiles.map(func(t: Vector2i) -> Array: return [t.x, t.y])
	return out

static func from_dict(d: Dictionary) -> GameState:
	var g := GameState.new()
	g.day = int(d.get("day", 1))
	g.king_of_the_hill = bool(d.get("king_of_the_hill", false))
	if d.get("ultimate_artifact", null) is Dictionary:
		g.ultimate_artifact = (d["ultimate_artifact"] as Dictionary).duplicate(true)
		g.ultimate_set = true
	g.last_week_event = (d.get("last_week_event", {}) as Dictionary).duplicate(true)
	for t: Variant in d.get("dug_tiles", []):
		if t is Array and (t as Array).size() >= 2:
			g.dug_tiles.append(Vector2i(int(t[0]), int(t[1])))
	for pd in d.get("players", []):
		if pd is Dictionary:
			var p := PlayerState.from_dict(pd)
			if p != null:
				g.players.append(p)
	g.active_player_side = int(d.get("active_player_side", 0))
	if g.player_of(g.active_player_side) == null:
		g.active_player_side = 0
	for bd in d.get("boats", []):
		if bd is Dictionary:
			var boat := BoatState.from_dict(bd)
			if boat.id >= 0 and g.boat_at(boat.tile) == null:
				g.boats.append(boat)
				g.next_boat_id = maxi(g.next_boat_id, boat.id + 1)
	g.next_boat_id = maxi(g.next_boat_id, int(d.get("next_boat_id", 1)))
	for sd in d.get("spawned_neutral_stacks", []):
		if sd is Dictionary:
			g.spawned_neutral_stacks.append(sd.duplicate(true))
	if d.has("hero_pool"):
		g.hero_pool = HeroPool.from_dict(d["hero_pool"])
		g.hero_pool.adopt_owned(g.players)
	return g
