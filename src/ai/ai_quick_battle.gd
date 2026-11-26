class_name AIQuickBattle
extends RefCounted

## heroes.exe 0x74424: how the original settles a computer hero's fight with
## neutrals, another computer hero or a town no human holds. Nothing is shown;
## one random draw against the battle estimate's win chance (0x6e950) picks the
## winner, the margin sets how much the winner loses, and a roll per creature
## (0xbe4bb) applies it. Fights with a human go to the battle screen instead.
## Rules and constants: data/ai/adventure_ai.json "quick_battle".

## Outcome of `fight`: whether the attacker won, the fractions each side lost,
## and the experience the winner was given.
class Result:
	var attacker_won := false
	var p := 0.0
	var attacker_loss := 0.0
	var defender_loss := 0.0
	var xp := 0
	var attacker_dead := false
	var defender_dead := false

static func rules() -> Dictionary:
	return AIController.rules().get("quick_battle", {})

## The fight's numbers alone (0x744a3..0x745ee): P from the estimate and the
## draw `r` in 0..100. Returns [attacker won, attacker loss, defender loss].
static func outcome(p: float, r: int) -> Array:
	var q := rules()
	var draw := r * float(q.get("draw_scale", 0.01))
	var won := draw < p
	var w := p if won else 1.0 - p
	var margin := absf(draw - p)
	var spread := margin
	if won and p > float(q.get("strong_above", 0.6)):
		spread = (p + float(q.get("strong_bonus", 0.65))) * margin
	var loss := pow(spread - 1.0, 2.0)
	if w > float(q.get("sure_above", 0.8)) and loss > float(q.get("sure_loss_above", 0.2)):
		loss *= loss
	if w > float(q.get("cap_above", 0.96)):
		loss = minf(loss, (1.0 - w) * float(q.get("cap_share", 0.5)))
	if won:
		return [true, loss, 1.0]
	return [false, 1.0, loss * spread]

## Fight `defender_army` (and `defender_hero`, who may be null) with the
## hero in `ctx`; `siege` for a town, rated with `siege_town` when known. Both armies lose their
## casualties in place; the winning hero gains experience and the loser's
## artifacts. The caller removes a dead hero (Result.attacker_dead /
## defender_dead) and captures the town.
static func fight(ctx: AITileValue.Ctx, defender_army: ArmyData,
		defender_hero: HeroModel = null, defender_side := -1, siege := false,
		siege_town: TownModel = null, rng: RandomNumberGenerator = null) -> Result:
	var q := rules()
	var res := Result.new()
	var attacker := ctx.hero
	# 0x7443a computes the attacker army's experience and drops it; the
	# defender's (0x7444d) is what either winner is given.
	res.xp = AITileValue.experience(defender_army, defender_hero)
	var est := AITileValue.battle(ctx, attacker.army, defender_army, defender_hero,
			siege, defender_side, true, siege_town)
	res.p = float(est.p)
	var o := outcome(res.p, _roll(rng, 0, 100))
	res.attacker_won = bool(o[0])
	res.attacker_loss = float(o[1])
	res.defender_loss = float(o[2])
	var dead_at := float(q.get("dead_at", 0.99))
	if res.attacker_won:
		attacker.grant_experience(res.xp, rng)
	else:
		attacker.move_points = 0
		if defender_hero != null:
			defender_hero.grant_experience(res.xp, rng)
	var game := AIController._game()
	if game != null:
		game.clear_hero_battle_modifiers(attacker)
		game.clear_hero_battle_modifiers(defender_hero)
	if res.attacker_loss > dead_at:
		HeroModel.capture_artifacts(defender_hero, attacker, true)
	elif res.defender_loss > dead_at:
		HeroModel.capture_artifacts(attacker, defender_hero, true)
	res.attacker_dead = res.attacker_loss >= dead_at
	res.defender_dead = defender_hero != null and res.defender_loss >= dead_at
	if not res.attacker_dead:
		apply_losses(attacker.army, res.attacker_loss, rng)
	if not res.defender_dead:
		apply_losses(defender_army, res.defender_loss, rng)
	attacker.discard_pending_level_up_events()
	if defender_hero != null:
		defender_hero.discard_pending_level_up_events()
	return res

## 0xbe4bb: each creature dies when random(0..100) < trunc(fraction x 100).
## The first occupied stack keeps one unless the fraction is all but total;
## at 1.0 every stack goes.
static func apply_losses(army: ArmyData, fraction: float, rng: RandomNumberGenerator = null) -> void:
	if army == null:
		return
	var q := rules()
	var k := int(fraction * 100.0)
	var first := true
	var i := 0
	while i < army.slots.size():
		var count := int(army.slots[i].count)
		var lost := 0
		for _n in count:
			if _roll(rng, 0, 100) < k:
				lost += 1
		if first and lost == count and fraction < float(q.get("keep_one_below", 0.999)):
			lost -= 1
		first = false
		count -= lost
		if count <= 0 or fraction >= 1.0:
			army.slots.remove_at(i)
			continue
		army.slots[i].count = count
		i += 1

## A wandering stack fights as five (0x75574) and keeps the five's total.
static func fight_stack(ctx: AITileValue.Ctx, stack_army: ArmyData,
		rng: RandomNumberGenerator = null) -> Result:
	var five := AITileValue.split_five(stack_army)
	var res := fight(ctx, five, null, -1, false, null, rng)
	var unit := String(stack_army.slots[0].unit) if not stack_army.slots.is_empty() else ""
	stack_army.slots.clear()
	if unit != "" and five.total() > 0:
		stack_army.add(unit, five.total())
	return res

static func _roll(rng: RandomNumberGenerator, lo: int, hi: int) -> int:
	return rng.randi_range(lo, hi) if rng != null else randi_range(lo, hi)
