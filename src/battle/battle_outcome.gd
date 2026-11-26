class_name BattleOutcome
extends RefCounted

## Shared battle-end rules that need the live survivor counts. HOMM1 surrender
## costs half the gold value of every creature still alive at the moment the
## offer is made (KB basic-concepts.md 3.3.3; monsters.md cost table).

## Creatures no town recruits; every other cost comes from the faction recruit
## tables. Ghosts cannot be hired, but each contributes 125 gold to ransom:
## their implied creature value is therefore 250 before the final halving.
const NEUTRAL_GOLD_COSTS := {"rogue": 50, "nomad": 200, "ghost": 250, "genie": 650}
static var _gold_costs: Dictionary = {}

static func unit_gold_cost(unit: String) -> int:
	if _gold_costs.is_empty():
		_gold_costs = NEUTRAL_GOLD_COSTS.duplicate()
		for faction: String in BuildingCatalog.FACTIONS:
			var table := JsonFile.read_dict(TownModel.RECRUIT_PATH % faction)
			for u: String in table:
				_gold_costs[u] = int(table[u].get("cost", 0))
	return int(_gold_costs.get(unit, 0))

static func surrender_cost(stacks: Array, side: int) -> int:
	var value := 0
	for stack: BattleStack in stacks:
		if stack.side == side and stack.is_alive():
			value += stack.count * unit_gold_cost(stack.unit)
	return value / 2

## Rebuild an ArmyData with every survivor in the column it started in: a dead
## stack leaves a gap, the others never shift over. Stacks that did not come
## from an army slot (raised in battle, split neutrals) merge into a slot of
## their unit or take the first free column.
static func surviving_army(stacks: Array, side: int) -> ArmyData:
	var army := ArmyData.new()
	var used := {}
	var loose: Array = []
	for stack: BattleStack in stacks:
		if stack.side != side or not stack.is_alive():
			continue
		if stack.slot_col >= 0 and not used.has(stack.slot_col):
			used[stack.slot_col] = true
			army.slots.append({"unit": stack.unit, "count": stack.count, "col": stack.slot_col})
		else:
			loose.append(stack)
	# Merging keeps a split neutral stack (BattleSetup._place_neutral) one count
	# on the map, as its save format holds (KB map-format.md).
	for stack: BattleStack in loose:
		army.add(stack.unit, stack.count)
	army.slots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.col) < int(b.col))
	return army

## Mutate the original ArmyData rather than replacing it: HeroModel, Game, and
## town garrisons may all hold the same reference.
static func write_survivors(stacks: Array, side: int, target: ArmyData) -> void:
	if target == null:
		return
	var survivors := surviving_army(stacks, side)
	target.slots = survivors.slots.duplicate(true)
