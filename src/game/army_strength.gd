class_name ArmyStrength
extends RefCounted

## Authentic unit power weights X (data/knowledge_base/diplomacy.md)
## used for joining negotiations, whirlpool stack selection, and relative army comparisons.
## sum of count * unit power X across all stacks in the army.

const JOIN_POWER_PATH := "res://data/creatures/join_power.json"
static var _join_power_cache: Dictionary = {}

static func all_join_power() -> Dictionary:
	if _join_power_cache.is_empty():
		_join_power_cache = JsonFile.read_dict(JOIN_POWER_PATH)
	return _join_power_cache

static func unit_power(unit: String) -> float:
	return float(all_join_power().get(unit, 0.0))

static func of(army: ArmyData) -> float:
	if army == null:
		return 0.0
	var t := 0.0
	for s: Dictionary in army.slots:
		t += float(s.count) * unit_power(String(s.unit))
	return t
