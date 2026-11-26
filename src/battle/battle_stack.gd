class_name BattleStack
extends RefCounted

## One army stack in battle. Loads its combat stats from the complete catalog.

const CreatureCatalogScript := preload("res://src/battle/creature_catalog.gd")

var unit: String = ""
var side: int = 0           # 0 = attacker, 1 = defender
var hex: Vector2i = Vector2i.ZERO
var count: int = 0
var slot_col: int = -1      # army column this stack came from; -1 for stacks raised in battle

var attack: int = 0
var defense: int = 0
var damage_min: int = 0
var damage_max: int = 0
var hp_max: int = 0
var hp_current: int = 0     # HP of the current (top) creature in the stack
var speed: int = 0
var shots: int = 0
var shots_max: int = 0
var attack_effect: StringName = &"physical"
var wide: bool = false      # occupies two horizontal cells (Cavalry, Dragons, ...)
var flying: bool = false
var double_attack: bool = false
var regeneration: bool = false
var no_retaliation: bool = false
var infinite_retaliation: bool = false
var attack_all_adjacent: bool = false
var two_cell_attack: bool = false
var blind_chance: float = 0.0
var paralyze_chance: float = 0.0
## Rounds a blinding or paralysing strike holds its target. heroes.exe 0xc6515
## sets 3 for any creature strike, where a hero's spell uses spell power.
var strike_effect_rounds: int = 0
var halve_chance: float = 0.0
var raise_killed: bool = false
var has_retaliated: bool = false
var turn_spent: bool = false

var count_initial: int = 0
var active_effect: Dictionary = {}   # {} or {"id": String, "rounds": int} — single
                                      # slot: HOMM1 allows one duration spell per stack
var eternal_curse: bool = false      # Paralyze side effect (KB spells.md 5.4)
var undead: bool = false
var magic_immune: bool = false
var mind_immune: bool = false
var magic_resist: float = 0.0

func setup(p_unit: String, p_count: int, p_side: int, p_hex: Vector2i) -> bool:
	var s := CreatureCatalogScript.stats(p_unit)
	if s.is_empty():
		push_error("BattleStack: unknown unit %s" % p_unit)
		return false
	unit = p_unit
	count = p_count
	count_initial = p_count
	side = p_side
	hex = p_hex
	attack = int(s.get("attack", 0))
	defense = int(s.get("defense", 0))
	damage_min = int(s.get("damage_min", 0))
	damage_max = int(s.get("damage_max", 0))
	hp_max = int(s.get("hp", 1))
	hp_current = hp_max
	speed = int(s.get("speed", 0))
	shots = int(s.get("shots", 0))
	shots_max = shots
	attack_effect = StringName(s.get("attack_effect", "physical"))
	wide = bool(s.get("wide", false))
	flying = bool(s.get("flying", false))
	double_attack = bool(s.get("double_attack", false))
	regeneration = bool(s.get("regeneration", false))
	no_retaliation = bool(s.get("no_retaliation", false))
	infinite_retaliation = bool(s.get("infinite_retaliation", false))
	attack_all_adjacent = bool(s.get("attack_all_adjacent", false))
	two_cell_attack = bool(s.get("two_cell_attack", false))
	blind_chance = float(s.get("blind_chance", 0.0))
	paralyze_chance = float(s.get("paralyze_chance", 0.0))
	strike_effect_rounds = int(s.get("strike_effect_rounds", 0))
	halve_chance = float(s.get("halve_chance", 0.0))
	raise_killed = bool(s.get("raise_killed", false))
	undead = bool(s.get("undead", false))
	magic_immune = bool(s.get("magic_immune", false))
	mind_immune = bool(s.get("mind_immune", false))
	magic_resist = float(s.get("magic_resist", 0.0))
	return true

func is_alive() -> bool:
	return count > 0

## Probability of resisting a spell (KB monsters.md 10.3).
## Dwarves resist area damage at 25%, single-target debuffs/lightning at 20%,
## blind at 0%, and friendly buffs at 0%.
func spell_resist_chance(spell_id: String) -> float:
	if unit == "dwarf":
		if spell_id == "blind":
			return 0.0
		if spell_id in ["fireball", "meteor_shower", "starfall", "armageddon"]:
			return 0.25
		if spell_id in ["lightning_bolt", "slow", "curse", "berserk", "paralyze"]:
			return 0.20
		return 0.0
	return magic_resist

## A wide unit's body extends one cell toward the enemy: east for side 0
## (attacker, faces right), west for side 1 (defender, faces left). `hex` is the
## anchor (feet) cell; the body sprite already spans this extra cell visually.
func body_dx() -> int:
	return 1 if side == 0 else -1

## The grid cells this stack occupies (one, or two for wide units), with `hex`
## first. Use for occupancy, adjacency, and reachability — never raw `hex`.
func cells() -> Array:
	if not wide:
		return [hex]
	return [hex, hex + Vector2i(body_dx(), 0)]

## Cells the stack would occupy if its anchor were at `h` (for move planning).
func cells_at(h: Vector2i) -> Array:
	if not wide:
		return [h]
	return [h, h + Vector2i(body_dx(), 0)]

func occupies(c: Vector2i) -> bool:
	return c in cells()

func is_ranged() -> bool:
	return shots > 0

func is_flying() -> bool:
	return flying and not has_effect("slow")

func is_shooter() -> bool:
	return shots_max > 0

func has_effect(id: String) -> bool:
	return active_effect.get("id", "") == id

func apply_spell_effect(id: String, rounds: int) -> void:
	active_effect = {"id": id, "rounds": rounds}

func clear_effect() -> void:
	active_effect = {}

## haste/slow override the stack's base speed for turn order and movement.
func effective_speed() -> int:
	if has_effect("haste"):
		return 4
	if has_effect("slow"):
		return 1
	return speed

## False while blind, paralyzed, or turn was spent (skips the stack's turn entirely).
func can_act() -> bool:
	return not (has_effect("blind") or has_effect("paralyze") or turn_spent)

## False if already retaliated this round, or paralyzed (blind may still retaliate).
func can_retaliate() -> bool:
	return (infinite_retaliation or not has_retaliated) and not has_effect("paralyze")

## Troll regeneration restores the surviving top creature, never a dead one.
func regenerate_top() -> void:
	if regeneration and is_alive():
		hp_current = hp_max

func total_hp() -> int:
	if count <= 0:
		return 0
	return (count - 1) * hp_max + hp_current

## Apply `dmg` to the stack's HP pool; returns the number of creatures killed.
func apply_damage(dmg: int) -> int:
	var old := count
	var pool := total_hp() - dmg
	if pool <= 0:
		count = 0
		hp_current = 0
		return old
	var new_count := int(ceil(float(pool) / float(hp_max)))
	hp_current = pool - (new_count - 1) * hp_max
	count = new_count
	if dmg > 0 and (has_effect("blind") or has_effect("paralyze")):
		clear_effect()  # eternal_curse intentionally survives (KB spells.md 5.4)
	return old - new_count
