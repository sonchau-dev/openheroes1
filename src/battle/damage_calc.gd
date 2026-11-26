class_name DamageCalc
extends RefCounted

## Native HOMM1 damage formula (KB damage.md):
##   Damage = D * cnt * Hi
##   i = attack - defense
## Hi is looked up in the authentic heroes.exe modifier table (clamped between 0.2 and 5.0).
## The 32,000 per-target cap is deliberately finalized after melee, luck, and
## special-ability modifiers rather than here.

const MAX_DAMAGE := 32000
const TABLE_PATH := "res://data/creatures/damage_modifiers.json"

static var _table: Dictionary = {}
static var _min_clamp := 0.2
static var _max_clamp := 5.0

static func _ensure_table() -> void:
	if not _table.is_empty():
		return
	var json := JsonFile.read_dict(TABLE_PATH)
	if not json.is_empty():
		_min_clamp = float(json.get("min_clamp", 0.2))
		_max_clamp = float(json.get("max_clamp", 5.0))
		var mods = json.get("modifiers", {})
		if mods is Dictionary:
			for k in mods:
				_table[int(k)] = float(mods[k])

static func modifier(attack: int, defense: int) -> float:
	_ensure_table()
	var difference := attack - defense
	if difference <= -16:
		return _min_clamp
	if difference >= 17:
		return _max_clamp
	if _table.has(difference):
		return _table[difference]
	var step := 1.1 if difference > 0 else 0.9
	return clampf(pow(step, absi(difference)), _min_clamp, _max_clamp)

## `base_damage` is the sum of the independently rolled damage values for all
## creatures in the attacking stack.
static func compute_base(base_damage: int, attack: int, defense: int) -> int:
	return maxi(1, int(round(float(base_damage) * modifier(attack, defense))))

## Apply the native final per-stack/per-target bounds after every other damage
## modifier and replacement ability has resolved.
static func finalize(damage: int) -> int:
	return clampi(damage, 1, MAX_DAMAGE)
