class_name HeroFactory
extends RefCounted

const CATALOG_PATH := "res://data/heroes/catalog.json"

static var _catalog: Array = []

static func class_for_faction(faction: int) -> String:
	var row := _class_row(faction)
	return String(row.get("id", "knight"))

static func create_for_faction(faction: int, rng: RandomNumberGenerator,
		taken: Array = []) -> HeroModel:
	var row := _class_row(faction)
	var names: Array = row.get("heroes", [])
	var available: Array = []
	for i in names.size():
		var candidate := String(names[i])
		var used := false
		for h in taken:
			if h is HeroModel and h.hero_name == candidate:
				used = true
				break
		if not used:
			available.append(i)
	if available.is_empty():
		available = range(names.size())
	var local_idx := int(available[rng.randi_range(0, available.size() - 1)])
	var h := HeroModel.new()
	h.hero_name = String(names[local_idx])
	h.portrait_idx = clampi(faction, 0, 3) * 9 + local_idx
	h.hero_class = String(row.get("id", "knight"))
	h.attack = int(row.get("attack", 0))
	h.defense = int(row.get("defense", 0))
	h.spell_power = int(row.get("spell_power", 0))
	h.knowledge = int(row.get("knowledge", 0))
	var xp: Array = row.get("experience", [40, 90])
	h.experience = rng.randi_range(int(xp[0]), int(xp[1]))
	h.has_spellbook = bool(row.get("spellbook", false))
	h.morale = int(row.get("morale", 0))
	h.sight_bonus = int(row.get("sight_bonus", 0))
	h.crest_idx = clampi(faction, 0, 3)
	h.army = starting_army_for_class(h.hero_class, rng)
	return h

static func starting_army_for_class(class_id: String,
		rng: RandomNumberGenerator) -> ArmyData:
	var army := ArmyData.new()
	for stack: Array in _roll(_class_row(_faction_of(class_id)), rng, false):
		army.add(String(stack[0]), int(stack[1]))
	return army

## A hire re-rolls the army (heroes.exe 0x6891d and 0x75288 call 0x83210
## with the hire flag): the rolled stacks overwrite the first slots and any
## slot past them keeps what the hero brought, a surrendered army included.
static func reroll_for_hire(h: HeroModel, rng: RandomNumberGenerator) -> void:
	var rolled := _roll(_class_row(_faction_of(h.hero_class)), rng, true)
	var cols := h.army.resolved_columns()
	for k in rolled.size():
		var slot: Dictionary = {}
		for i in h.army.slots.size():
			if int(cols[i]) == k:
				slot = h.army.slots[i]
		if slot.is_empty():
			slot = {"col": k}
			h.army.slots.append(slot)
		slot["unit"] = String(rolled[k][0])
		slot["count"] = int(rolled[k][1])

## heroes.exe 0x83210 over the class rows (data 0x1e544): the first stack
## always; the second when rand(0..99) < 50 or a second rand(0..99) >= 25
## (80 and 65 on a hire); the table's third stack is never rolled. A count
## is rand(min x 10, max x 10 + 9) / 10, its low end raised to the middle of
## that span on a hire. Rows are [unit, min, max] or [unit, 0, min, max].
static func _roll(row: Dictionary, rng: RandomNumberGenerator, hired: bool) -> Array:
	var rows: Array = row.get("army", [])
	var take := [true, false]
	take[1] = rng.randi_range(0, 99) < (80 if hired else 50)
	if rng.randi_range(0, 99) >= (65 if hired else 25):
		take[1] = true
	var out: Array = []
	for i in mini(rows.size(), 2):
		if not take[i]:
			continue
		var r: Array = rows[i]
		var hi := int(r[-1]) * 10 + 9
		var lo := int(r[-2]) * 10
		if hired:
			lo = (lo + hi) / 2
		out.append([String(r[0]), rng.randi_range(lo, hi) / 10])
	return out

static func _faction_of(class_id: String) -> int:
	for i in 4:
		if String(_class_row(i).get("id", "")) == class_id:
			return i
	return 0

static func _class_row(faction: int) -> Dictionary:
	if _catalog.is_empty():
		var parsed := JsonFile.read_dict(CATALOG_PATH)
		_catalog = parsed.get("classes", [])
	if _catalog.is_empty():
		return {}
	return _catalog[clampi(faction, 0, _catalog.size() - 1)]
