class_name NeutralStack
extends MapObject

## A guarding army on the map. Visiting (while unbeaten) launches a battle;
## the adventure map marks it consumed on victory.

var army: ArmyData = null
var random_stack_id: int = -1
# A native stack whose count the map leaves at 0 names its creature only; the
# count and the joinable flag are rolled at game start like a random class.
var random_unit: String = ""
var joinable: bool = false
var fought_before: bool = false
var authored_fixed: bool = false
# `consumed` is the base MapObject field; base save_state()/
# apply_state() already persist it, so no override is needed here anymore.

# Native mons32 placeholders are MON (B8=191), followed by MON 1..5
# (B8=195..199).  The numbered markers are ascending strength classes; the
# fifth class combines native creature levels 5 and 6.  A previous HOMM2-style
# four-band table treated 195 as unrestricted, which let Claw's weakest guards
# roll Dragons and other end-game creatures.
const RANDOM_ANY := 191
const RANDOM_LEVEL_FIRST := 195
const RANDOM_LEVEL_LAST := 199
const CREATURES_BY_LEVEL := {
	195: ["peasant", "goblin", "sprite", "centaur", "rogue"],
	196: ["archer", "orc", "dwarf", "gargoyle"],
	197: ["pikeman", "wolf", "elf", "griffin", "nomad"],
	198: ["swordsman", "ogre", "druid", "minotaur", "ghost"],
	199: ["cavalry", "troll", "unicorn", "hydra", "paladin", "cyclops",
		"phoenix", "dragon", "genie"],
}
const ALL_CREATURES := [
	"peasant", "goblin", "sprite", "centaur", "rogue",
	"archer", "orc", "dwarf", "gargoyle",
	"pikeman", "wolf", "elf", "griffin", "nomad",
	"swordsman", "ogre", "druid", "minotaur", "ghost",
	"cavalry", "troll", "unicorn", "hydra", "paladin", "cyclops",
	"phoenix", "dragon", "genie",
]
# Native wandering-stack ranges (data/knowledge_base/diplomacy.md).  Counts
# depend on the selected creature, not merely on its strength class.
const COUNT_RANGES := {
	"peasant": [30, 80], "goblin": [25, 40], "sprite": [20, 40],
	"centaur": [20, 50], "rogue": [20, 40],
	"archer": [20, 30], "orc": [15, 30], "dwarf": [10, 25],
	"gargoyle": [15, 30],
	"pikeman": [20, 30], "wolf": [20, 35], "elf": [15, 30],
	"griffin": [10, 25], "nomad": [12, 25],
	"swordsman": [12, 25], "ogre": [10, 20], "druid": [10, 25],
	"minotaur": [10, 16], "ghost": [10, 20],
	"cavalry": [8, 16], "troll": [7, 10], "unicorn": [8, 15],
	"hydra": [6, 8], "paladin": [6, 12], "cyclops": [5, 7],
	"phoenix": [7, 12], "dragon": [3, 7], "genie": [4, 9],
}

func is_armed() -> bool:
	return not consumed and army != null and not army.is_empty()

func resolve_random(rng: RandomNumberGenerator) -> void:
	if is_armed():
		return
	var unit := random_unit
	if unit == "" or not COUNT_RANGES.has(unit):
		if random_stack_id != RANDOM_ANY \
				and (random_stack_id < RANDOM_LEVEL_FIRST or random_stack_id > RANDOM_LEVEL_LAST):
			return
		var units: Array = ALL_CREATURES if random_stack_id == RANDOM_ANY \
			else CREATURES_BY_LEVEL[random_stack_id]
		unit = String(units[rng.randi_range(0, units.size() - 1)])
	var amount: Array = COUNT_RANGES[unit]
	army = ArmyData.new()
	army.add(unit, rng.randi_range(int(amount[0]), int(amount[1])))
	# KB diplomacy.md: on save generation, wandering stacks without an authored
	# count are assigned joinable or non-joinable (except ghosts, which never
	# join). A DOS save keeps the flag as bit 0x80 of the cell's count byte.
	if unit != "ghost":
		joinable = (rng.randi_range(0, 1) == 1)

## KB diplomacy.md: A neutral stack offers to join if:
## - It has not already fought (fought_before == false)
## - It was not authored with a fixed/custom count (authored_fixed == false)
## - It rolled joinable == true
## - It is not a Ghost stack (ghosts never join)
## - The visiting army has a free slot or already has the same creature
## - The visiting army's total power exceeds the stack's power by more than 1.75x
func can_offer_join(visiting_army: ArmyData) -> bool:
	if not is_armed() or not joinable or fought_before or authored_fixed:
		return false
	if army == null or army.slots.is_empty():
		return false
	var unit := String(army.slots[0].unit)
	if unit == "ghost":
		return false
	if visiting_army == null or not visiting_army.can_add(unit):
		return false
	var hero_power := ArmyStrength.of(visiting_army)
	var stack_power := ArmyStrength.of(army)
	if stack_power <= 0.0:
		return false
	return (hero_power / stack_power) > 1.75

func save_state() -> Dictionary:
	var d := super.save_state()
	if army != null and not army.is_empty():
		d["army"] = army.to_dict()
	if joinable:
		d["joinable"] = joinable
	if fought_before:
		d["fought_before"] = fought_before
	if authored_fixed:
		d["authored_fixed"] = authored_fixed
	return d

func apply_state(s: Dictionary) -> void:
	super.apply_state(s)
	if s.get("army", null) is Dictionary:
		army = ArmyData.from_dict(s["army"])
	joinable = bool(s.get("joinable", false))
	fought_before = bool(s.get("fought_before", false))
	authored_fixed = bool(s.get("authored_fixed", false))

func to_spec() -> Dictionary:
	var d := super.to_spec()
	d["army"] = MapObject.army_rows(army) if army != null else []
	if random_stack_id >= 0:
		d["random_stack_id"] = random_stack_id
	if random_unit != "":
		d["unit"] = random_unit
	if joinable:
		d["joinable"] = joinable
	if fought_before:
		d["fought_before"] = fought_before
	if authored_fixed:
		d["authored_fixed"] = authored_fixed
	return d
