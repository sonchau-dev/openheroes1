class_name SpellData

## Static loader for data/spells/spells.json — the hand-built HOMM1 spell table
## (transcribed from data/knowledge_base/spells.md; no extracted-asset data).

const PATH := "res://data/spells/spells.json"

static var _by_id: Dictionary = {}
static var _order: Array = []

static func _load() -> void:
	if not _by_id.is_empty():
		return
	var parsed: Array = JsonFile.read_array(PATH)
	if parsed.is_empty():
		push_error("SpellData: bad JSON in " + PATH)
		return
	for e in parsed:
		_by_id[e.id] = e
		_order.append(e)
		if e.id == "dimension_door":
			_by_id["town_portal"] = e

static func get_spell(id: String) -> Dictionary:
	_load()
	return _by_id.get(id, {})

static func all() -> Array:
	_load()
	return _order

static func of_level(level: int) -> Array:
	_load()
	return _order.filter(func(e): return int(e.level) == level)

## Weighted pick without replacement, per KB spells.md 5.3 (weights 12.5,
## except Bless / Town Portal / Town Gate at 25).
static func roll_guild_spells(level: int, count: int, rng: RandomNumberGenerator) -> Array:
	var pool := of_level(level).duplicate()
	var picked: Array = []
	while picked.size() < count and not pool.is_empty():
		var total := 0.0
		for e in pool:
			total += float(e.get("guild_weight", 12.5))
		var r := rng.randf() * total
		for i in pool.size():
			r -= float(pool[i].get("guild_weight", 12.5))
			if r <= 0.0:
				picked.append(String(pool[i].id))
				pool.remove_at(i)
				break
	return picked
