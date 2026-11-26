class_name TownModel
extends RefCounted

## Town recruitment, construction, and faction identity.

const RECRUIT_PATH := "res://data/creatures/%s_recruit.json"

var _gold: int = 0
## Owning PlayerState, assigned at runtime. Gold is kingdom-wide in HOMM1, so
## every town owned by the same side reads/writes the same treasury.
var kingdom: RefCounted = null
var gold: int:
	get:
		return int(kingdom.treasury_gold) if kingdom != null else _gold
	set(value):
		if kingdom != null:
			kingdom.treasury_gold = value
		else:
			_gold = value
## Stable MapObject.id of the town gate represented by this model.
var object_id: int = -1
## Map-assigned name (TownNames); empty falls back to the faction's default.
var town_name: String = ""
var available: Dictionary = {}   # unit -> int still recruitable
var army: ArmyData
var town_type: int = 0
var faction: String:
	get:
		return BuildingCatalog.faction_for_type(town_type)

## Constructed buildings: building id (see data/towns/*_buildings.json) -> true.
## Mage Guild is NOT stored here — mage_guild_level is authoritative for it.
var built: Dictionary = {}
var built_today: bool = false     # HOMM1: one construction per castle per day
var sea_access: bool = false      # set by the map (shipyard gate); see object_layer.gd
var ship_launch_tile: Vector2i = Vector2i(-1, -1)

const BOAT_COST := {"gold": 1000, "wood": 10}
const CASTLE_DAILY_INCOME := 1000
const TOWN_DAILY_INCOME := 250

## Back-compat: castle presence now lives in `built`.
var has_castle: bool:
	get:
		return built.has("castle")
	set(v):
		if v:
			built["castle"] = true
		else:
			built.erase("castle")

## Base daily gold income (KB castles.md: castle +1000 g/day, unwalled town +250 g/day).
var daily_income: int:
	get:
		return CASTLE_DAILY_INCOME if has_castle else TOWN_DAILY_INCOME

var mage_guild_level: int = 0

## Number of built monster dwellings (m in siege tower formula, KB battle.md §12.3.1).
func count_built_dwellings() -> int:
	var count := 0
	for b_id in built:
		var ent: Dictionary = BuildingCatalog.entry(String(b_id), faction)
		if ent.has("tier") or ent.has("unit"):
			count += 1
	return count

## Number of built non-dwelling, non-castle buildings (n in siege tower formula).
## The Mage Guild counts as one building if built (level >= 1).
func count_built_other_buildings() -> int:
	var count := 0
	for b_id in built:
		if String(b_id) == "castle":
			continue
		var ent: Dictionary = BuildingCatalog.entry(String(b_id), faction)
		if not ent.has("tier") and not ent.has("unit"):
			count += 1
	if mage_guild_level >= 1:
		count += 1
	return count

## Scaling coefficient k = 5 + 4*m + n for the castle shooting tower (KB battle.md §12.3.1).
func siege_tower_k() -> int:
	return 5 + 4 * count_built_dwellings() + count_built_other_buildings()

var guild_spells: Array = []     # [Array[String] x4], rolled once at game start

const GUILD_SLOTS := [3, 2, 2, 2]
const GUILD_COSTS := [
	{"gold": 2000, "wood": 5, "ore": 5},
	{"gold": 1000, "wood": 5, "ore": 5, "crystal": 4, "gems": 4, "mercury": 4, "sulfur": 4},
	{"gold": 1000, "wood": 5, "ore": 5, "crystal": 6, "gems": 6, "mercury": 6, "sulfur": 6},
	{"gold": 1000, "wood": 5, "ore": 5, "crystal": 10, "gems": 10, "mercury": 10, "sulfur": 10},
]
const SPELLBOOK_COST := 500

const AI_GROWTH_PATH := "res://data/towns/ai_growth.json"
static func ai_growth_multiplier(ai_level: int) -> float:
	return float(JsonFile.read_dict(AI_GROWTH_PATH).get(str(ai_level), 1.0))

static func _recruit_data(p_faction := "knight") -> Dictionary:
	return JsonFile.read_dict(RECRUIT_PATH % p_faction)

func setup(start_gold: int, p_available: Dictionary, p_army: ArmyData,
		p_town_type: int = 0) -> void:
	gold = start_gold
	available = p_available
	army = p_army
	town_type = clampi(p_town_type, 0, BuildingCatalog.FACTIONS.size() - 1)
	built["castle"] = true
	for u: String in available.keys():
		var d := BuildingCatalog.dwelling_for_unit(u, faction)
		if d != "":
			built[d] = true

func cost_of(unit: String) -> int:
	return int(_recruit_data(faction).get(unit, {}).get("cost", 0))

func rare_cost_of(unit: String) -> Dictionary:
	var e: Dictionary = _recruit_data(faction).get(unit, {})
	var resource := String(e.get("resource", ""))
	var cost := int(e.get("resource_cost", 0))
	return {} if resource == "" or cost <= 0 else {resource: cost}

func max_recruitable(unit: String, player: PlayerState = null) -> int:
	if army == null or not army.can_add(unit):
		return 0
	var c := cost_of(unit)
	if c <= 0:
		return 0
	var current_gold := player.gold() if player != null else gold
	var maximum: int = min(int(available.get(unit, 0)), current_gold / c)
	var rare: Dictionary = rare_cost_of(unit)
	if not rare.is_empty():
		if player == null:
			return 0
		var resource: String = rare.keys()[0]
		maximum = min(maximum,
				int(player.resources.get(resource, 0)) / int(rare[resource]))
	return maximum

func recruit(unit: String, n: int, player: PlayerState = null) -> bool:
	if n <= 0 or n > max_recruitable(unit, player):
		return false
	if army == null or not army.add(unit, n):
		return false
	if player != null:
		player.treasury_gold -= n * cost_of(unit)
		if kingdom == null:
			_gold = player.treasury_gold
	else:
		gold -= n * cost_of(unit)
	var rare: Dictionary = rare_cost_of(unit)
	if player != null and not rare.is_empty():
		var resource: String = rare.keys()[0]
		player.resources[resource] = int(player.resources.get(resource, 0)) \
				- n * int(rare[resource])
	available[unit] = int(available.get(unit, 0)) - n
	return true


## Building already constructed? (mage_guild = any level built)
func is_built(id: String) -> bool:
	if id == "mage_guild":
		return mage_guild_level >= 1
	return built.has(id)

## Cost bag for `id`. Mage guild: the NEXT level's cost ({} once maxed).
func build_cost(id: String) -> Dictionary:
	if id == "mage_guild":
		return {} if mage_guild_level >= GUILD_COSTS.size() else GUILD_COSTS[mage_guild_level]
	return BuildingCatalog.entry(id, faction).get("cost", {})

## Castle Options cell status. Check order matters: built > castle gate >
## one-per-day > prereqs > sea > affordability.
func can_build(id: String, player: PlayerState) -> String:
	var e := BuildingCatalog.entry(id, faction)
	if e.is_empty():
		return "no_prereq"
	if id == "mage_guild":
		if mage_guild_level >= GUILD_COSTS.size():
			return "built"
	elif built.has(id):
		return "built"
	if id != "castle" and not has_castle:
		return "no_castle"
	if built_today:
		return "done_today"
	for pre: String in e.get("prereq", []):
		if not is_built(pre):
			return "no_prereq"
	if bool(e.get("needs_sea", false)) and not sea_access:
		return "no_sea"
	if not player.can_afford(build_cost(id)):
		return "no_resources"
	return "buildable"

## Construct `id`: pay, flag, count the day. Dwellings come stocked with one
## week's growth (HOMM1). The mage guild is a level, not a flag.
## `price`, when given, is what is paid instead of the listed cost (the
## computer's guild price). Only the listed cost is checked, as in the
## original, so the treasury can go below zero.
func build(id: String, player: PlayerState, price: Variant = null) -> bool:
	if can_build(id, player) != "buildable":
		return false
	player.pay(build_cost(id) if price == null else price)
	if id == "mage_guild":
		mage_guild_level += 1
	else:
		built[id] = true
	built_today = true
	var unit := String(BuildingCatalog.entry(id, faction).get("unit", ""))
	if unit != "":
		var growth := int((_recruit_data(faction).get(unit, {}) as Dictionary).get("growth", 0))
		available[unit] = int(available.get(unit, 0)) + growth
	return true

## Boat buying has its own daily flag: construction may happen first and a
## boat can still be bought afterward, but buying first closes construction.
func can_buy_boat(player: PlayerState, state: GameState = null) -> String:
	if not is_built("shipyard"):
		return "no_shipyard"
	if not sea_access or ship_launch_tile == Vector2i(-1, -1):
		return "no_sea"
	if state != null and state.boat_at(ship_launch_tile) != null:
		return "occupied"
	if not player.can_afford(BOAT_COST):
		return "no_resources"
	return "buyable"

func buy_boat(player: PlayerState, state: GameState) -> BoatState:
	if state == null or can_buy_boat(player, state) != "buyable":
		return null
	player.pay(BOAT_COST)
	var boat := state.create_boat(ship_launch_tile, player.side, Direction.E)
	if boat == null:
		return null
	return boat

## Authentic HOMM1 start (KB castles.md 8.3): castle + level-1 dwelling, plus
## the level-2 dwelling at 30% (human) / 51% (AI). Rebuilds availability from
## the built dwellings (one week's stock each). Call AFTER setup().
func init_start_buildings(rng: RandomNumberGenerator, is_ai: bool) -> void:
	set_start_dwellings(start_dwellings(faction, rng, is_ai))

## KB castles.md: an unconfigured town starts with its level-1 dwelling, and
## its level-2 dwelling 30% of the time for a human player's, 51% otherwise.
static func start_dwellings(faction_id: String, rng: RandomNumberGenerator, is_ai: bool) -> Array:
	var dwellings := BuildingCatalog.dwelling_ids(faction_id)
	if dwellings.is_empty():
		return []
	var out: Array = [dwellings[0]]
	if rng.randf() < (0.51 if is_ai else 0.30):
		if dwellings.size() > 1:
			out.append(dwellings[1])
	return out

func set_start_dwellings(ids: Array) -> void:
	built = {"castle": true}
	for id: Variant in ids:
		built[String(id)] = true
	available = {}
	for id: String in built.keys():
		var unit := String(BuildingCatalog.entry(id, faction).get("unit", ""))
		if unit != "":
			available[unit] = int((_recruit_data(faction).get(unit, {}) as Dictionary).get("growth", 0))

## Roll the guild's spell pool once (per KB spells.md 5.3). Levels are always
## rolled regardless of how many guild levels are actually built; teach only
## reveals up to mage_guild_level.
func roll_guild(rng: RandomNumberGenerator) -> void:
	guild_spells = []
	for lvl in 4:
		guild_spells.append(SpellData.roll_guild_spells(lvl + 1, GUILD_SLOTS[lvl], rng))

## Hero must own a spellbook (KB objects.md/heroes.md). Learning also refreshes
## every book spell to current Knowledge (KB spells.md 5.4 replenish rule).
## Replenishment requires an actually-built guild (mage_guild_level >= 1) —
## guild_spells is rolled at game start regardless of construction, so an
## unbuilt guild must not teach or refresh anything (KB spells.md 5.4).
func teach_visiting_hero(hero: HeroModel) -> void:
	if mage_guild_level <= 0:
		return
	if not hero.has_spellbook or hero.fixed_spellbook or guild_spells.is_empty():
		return
	for lvl in mage_guild_level:
		for id in guild_spells[lvl]:
			hero.spellbook.learn(id, hero.effective_knowledge())
	hero.spellbook.refresh_all(hero.effective_knowledge())

## --- save/load ---
## Mage Guild is level-keyed (mage_guild_level), matching the class comment up top:
## it is intentionally NOT in `built`.

func to_dict() -> Dictionary:
	var av := {}
	for u in available:
		av[String(u)] = int(available[u])
	var b := {}
	for id in built:
		b[String(id)] = true
	return {
		"gold": gold,
		"object_id": object_id,
		"town_name": town_name,
		"town_type": town_type,
		"available": av,
		"army": army.to_dict() if army != null else {},
		"built": b,
		"built_today": built_today,
		"sea_access": sea_access,
		"ship_launch_tile": [ship_launch_tile.x, ship_launch_tile.y],
		"mage_guild_level": mage_guild_level,
		"guild_spells": guild_spells.duplicate(true),
	}

static func from_dict(d: Dictionary) -> TownModel:
	var t := TownModel.new()
	t.gold = int(d.get("gold", 0))
	t.object_id = int(d.get("object_id", -1))
	t.town_name = String(d.get("town_name", ""))
	t.town_type = clampi(int(d.get("town_type", 0)), 0, BuildingCatalog.FACTIONS.size() - 1)
	var av: Dictionary = d.get("available", {})
	for u in av:
		t.available[String(u)] = int(av[u])
	t.army = ArmyData.from_dict(d.get("army", {}))
	for id in d.get("built", {}):
		t.built[String(id)] = true
	t.built_today = bool(d.get("built_today", false))
	t.sea_access = bool(d.get("sea_access", false))
	var launch: Variant = d.get("ship_launch_tile", [-1, -1])
	if launch is Array and launch.size() == 2:
		t.ship_launch_tile = Vector2i(int(launch[0]), int(launch[1]))
	t.mage_guild_level = int(d.get("mage_guild_level", 0))
	t.guild_spells = []
	for lvl in d.get("guild_spells", []):
		var ids: Array = []
		for id in lvl:
			ids.append(String(id))
		t.guild_spells.append(ids)
	return t
