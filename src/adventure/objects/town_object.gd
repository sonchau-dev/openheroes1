class_name TownObject
extends MapObject

## A town entrance. Visiting opens the town screen. (Ownership/capture deferred.)

var town_type: int = 0
## Immutable source owner used when setup remaps authored seats to runtime sides.
var authored_owner: int = -2
var garrison: ArmyData = null
## The buildings a neutral town holds from the start, rolled with its
## garrison. The siege estimate counts them in the tower (heroes.exe 0x73d34
## reads the town record's built flags) and a capture keeps them.
var neutral_built: Array = []

const FACTION_LEVEL_UNITS := [
	["peasant", "archer", "pikeman", "swordsman"],   # 0: Knight
	["goblin", "orc", "wolf", "ogre"],              # 1: Barbarian
	["sprite", "dwarf", "elf", "druid"],            # 2: Sorceress
	["centaur", "gargoyle", "griffin", "minotaur"],  # 3: Warlock
]

static func roll_creature_level(rng: RandomNumberGenerator) -> int:
	if rng == null:
		rng = RandomNumberGenerator.new()
	var r := rng.randi_range(0, 14)
	if r < 5:
		return 1
	elif r < 10:
		return 2
	elif r < 13:
		return 3
	else:
		return 4

static func roll_growth_count(level: int, rng: RandomNumberGenerator) -> int:
	if rng == null:
		rng = RandomNumberGenerator.new()
	match level:
		1: return rng.randi_range(8, 15)
		2: return rng.randi_range(5, 7)
		3: return rng.randi_range(3, 5)
		4: return rng.randi_range(1, 3)
		_: return 1

## KB week.md §9.2: Initial neutral garrison has 4 stacks of level 1-4 creatures of that town type.
static func roll_initial_neutral_garrison(faction: int, rng: RandomNumberGenerator) -> ArmyData:
	if rng == null:
		rng = RandomNumberGenerator.new()
	var army := ArmyData.new()
	var f_idx := clampi(faction, 0, 3)
	var units: Array = FACTION_LEVEL_UNITS[f_idx]
	for i in 4:
		var lvl := roll_creature_level(rng)
		var unit_name: String = units[lvl - 1]
		var count := roll_growth_count(lvl, rng)
		army.add(unit_name, count, true)
	return army

## KB week.md §9.2: Weekly replenishment is 1 stack of level 1-4 creatures of that town type.
static func replenish_neutral_garrison(tw: TownObject, rng: RandomNumberGenerator) -> void:
	if tw == null or tw.owner >= 0:
		return
	if rng == null:
		rng = RandomNumberGenerator.new()
	if tw.garrison == null:
		tw.garrison = roll_initial_neutral_garrison(tw.town_type, rng)
		tw.params["army"] = tw.garrison
		return
	var f_idx := clampi(tw.town_type, 0, 3)
	var units: Array = FACTION_LEVEL_UNITS[f_idx]
	var lvl := roll_creature_level(rng)
	var unit_name: String = units[lvl - 1]
	var count := roll_growth_count(lvl, rng)
	tw.garrison.add(unit_name, count, true)
	tw.params["army"] = tw.garrison

## A town model with the neutral town's buildings, for the siege estimate.
func neutral_model() -> TownModel:
	var model := TownModel.new()
	model.object_id = id
	model.setup(0, {}, ArmyData.new(), town_type)
	model.set_start_dwellings(neutral_built)
	model.has_castle = bool(params.get("has_castle", true))
	return model

func save_state() -> Dictionary:
	var d := super.save_state()
	d["owner"] = owner
	d["town_type"] = town_type
	if String(params.get("name", "")) != "":
		d["name"] = params["name"]
	if garrison != null and not garrison.is_empty():
		d["garrison"] = garrison.to_dict()
	if owner < 0 and not neutral_built.is_empty():
		d["neutral_built"] = neutral_built
	return d

func apply_state(s: Dictionary) -> void:
	super.apply_state(s)
	owner = int(s.get("owner", owner))
	town_type = int(s.get("town_type", town_type))
	if String(s.get("name", "")) != "":
		params["name"] = String(s["name"])
	if s.has("garrison") and s["garrison"] is Dictionary:
		garrison = ArmyData.from_dict(s["garrison"])
		params["army"] = garrison
	elif owner >= 0:
		garrison = null
		params.erase("army")
	if s.has("neutral_built") and s["neutral_built"] is Array:
		neutral_built = (s["neutral_built"] as Array).duplicate()

func to_spec() -> Dictionary:
	var d := super.to_spec()
	d["town_type"] = town_type
	d["owner"] = owner
	if garrison != null and not garrison.is_empty():
		d["army"] = MapObject.army_rows(garrison)
	return d

static func _get_game_state() -> GameState:
	var loop := Engine.get_main_loop() as SceneTree
	if loop != null and loop.root != null:
		var g: Node = loop.root.get_node_or_null("Game")
		if g != null and "state" in g:
			return g.get("state") as GameState
	return null

func is_armed(state: GameState = null) -> bool:
	if garrison != null and not garrison.is_empty():
		return true
	if state == null:
		state = _get_game_state()
	if owner >= 0 and state != null:
		var p := state.player_of(owner)
		if p != null:
			var t := p.town_by_object_id(id)
			if t == null and p.towns.size() == 1 and id == 0:
				t = p.towns[0]
			if t != null and t.army != null and not t.army.is_empty():
				return true
	return false

func is_guarded_against(side: int, _map: MapData = null, state: GameState = null) -> bool:
	if owner == side:
		return false
	if state == null:
		state = _get_game_state()
	if is_armed(state):
		return true
	if state != null:
		var visitor := state.player_of(side)
		for p: PlayerState in state.players:
			if p.side != side and (visitor == null or p.is_hostile_to(visitor)):
				for h: HeroModel in p.heroes:
					if h.tile == action_tile and h.army != null and not h.army.is_empty():
						return true
	return false

func uses_attack_cursor(state: GameState = null) -> bool:
	if state == null:
		state = _get_game_state()
	var local_side := state.active_player_side if state != null else 0
	return is_guarded_against(local_side, null, state)
