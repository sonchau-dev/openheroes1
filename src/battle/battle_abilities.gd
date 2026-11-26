class_name BattleAbilities
extends RefCounted

## Native probability-based and on-kill creature effects. All rolls use the
## BattleState RNG so seeded battles and replays remain deterministic.

static func strike(attacker: BattleStack, defender: BattleStack,
		ordinary_damage: int, rng: RandomNumberGenerator,
		allow_paralyze := true) -> Dictionary:
	var damage := ordinary_damage
	var ability := ""

	# Genie halving replaces the ordinary hit only when it would be stronger.
	var halving_damage := int((defender.count + 1) / 2) * defender.hp_max
	if attacker.halve_chance > 0.0 and halving_damage > ordinary_damage \
			and rng.randf() < attacker.halve_chance:
		damage = halving_damage
		ability = "genie_halving"

	var report := BattleRules.apply_attack(attacker, defender, damage)
	report["attacker_count"] = attacker.count

	# Every creature killed by Ghosts joins the attacking stack.
	var raised := int(report.killed) if attacker.raise_killed else 0
	if raised > 0:
		attacker.count += raised
		report["raised"] = raised
		ability = "ghost_growth"

	var status_roll := {"rolled": false, "applied": false}
	if defender.is_alive():
		if attacker.blind_chance > 0.0:
			status_roll = _try_status(defender, "blind", attacker.blind_chance, rng,
					attacker.strike_effect_rounds)
		elif allow_paralyze and attacker.paralyze_chance > 0.0:
			status_roll = _try_status(defender, "paralyze", attacker.paralyze_chance, rng,
					attacker.strike_effect_rounds)
		if status_roll.applied:
			ability = String(status_roll.status)

	report["ability"] = ability
	report["status_rolled"] = bool(status_roll.rolled)
	return report

static func _try_status(target: BattleStack, status: String, chance: float,
		rng: RandomNumberGenerator, rounds: int = 3) -> Dictionary:
	if rng.randf() >= chance:
		return {"rolled": false, "applied": false, "status": status}
	var out := {"rolled": true, "applied": false, "status": status}
	if target.magic_immune or target.mind_immune or target.has_effect("anti_magic"):
		return out

	# Dwarves resist the creature ability separately from hostile magic.
	if target.unit == "dwarf":
		var special_resist := 0.25 if status == "blind" else 0.20
		if rng.randf() < special_resist:
			return out
		# Cyclops paralysis also passes through the Dwarf's 20% hostile
		# paralyze resistance. Blind has no second resistance roll.
		if status == "paralyze" and rng.randf() < 0.20:
			return out

	target.apply_spell_effect(status, maxi(rounds, 1))
	if status == "paralyze":
		target.eternal_curse = true
	out.applied = true
	return out
