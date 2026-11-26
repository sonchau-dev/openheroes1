class_name BattleRules
extends RefCounted

## Stateless attack resolution. Mutates the defender via apply_damage.

## HOMM1 rolls damage once per living creature, then sums those rolls before
## applying the Attack/Defense coefficient. Bless/Curse pin every individual
## roll and therefore consume no damage RNG values.
static func roll_base_damage(stack: BattleStack, rng: RandomNumberGenerator) -> int:
	if stack.has_effect("bless"):
		return stack.count * stack.damage_max
	if stack.has_effect("curse") or stack.eternal_curse:
		return stack.count * stack.damage_min
	var total := 0
	for _i in stack.count:
		total += rng.randi_range(stack.damage_min, stack.damage_max)
	return total

static func apply_attack(attacker: BattleStack, defender: BattleStack, dmg: int) -> Dictionary:
	var final_damage := DamageCalc.finalize(dmg)
	var killed := defender.apply_damage(final_damage)
	return {
		"damage": final_damage,
		"killed": killed,
		"defender_dead": not defender.is_alive(),
		"damage_capped": dmg > DamageCalc.MAX_DAMAGE,
	}
