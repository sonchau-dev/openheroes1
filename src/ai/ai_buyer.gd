# src/ai/ai_buyer.gd
class_name AIBuyer
extends RefCounted

## A computer player's purchases, decoded from heroes.exe 0x6739c (constants
## and their sources in data/ai/buy_choice.json). Each round every town offers
## its best building, best creature stack and best tavern hero, scored as
## benefit per gold-equivalent cost; the best score over all towns is bought
## and the round repeats until the best falls below `stop_below` or the winner
## cannot be paid for, so the computer saves up for it.
##
## The economy snapshot (player weights, resource worth, army value) is taken
## once per AI turn, as the original does, and reused by every buy that turn.

const RULES_PATH := "res://data/ai/buy_choice.json"

## Building ids by the town flag bit the original scores them under; bit 5 is
## unused and bits 7..12 are the dwellings by tier.
const COMMON_BITS := {"mage_guild": 0, "thieves_guild": 1, "tavern": 2,
		"shipyard": 3, "well": 4, "castle": 6}
const DWELLING_BIT := 7
const KIND_BUILDING := 0
const KIND_HERO := 1
const KIND_CREATURE := 2
const RESOURCES := ["wood", "mercury", "ore", "sulfur", "crystal", "gems", "gold"]

## What a buy needs from the adventure map. Callables keep the scoring free of
## scene nodes so tests can drive it.
class Context:
	var econ: Dictionary = {}
	## roll.call(lo, hi) -> int, inclusive.
	var roll: Callable
	## hero_at.call(town_index) -> HeroModel standing in that town, or null.
	var hero_at: Callable
	## gate_taken.call(town_index) -> bool: any hero on the town's gate.
	var gate_taken: Callable
	## tavern.call() -> Array of the two HeroModels on offer.
	var tavern: Callable
	## hire.call(town_index, hero) -> bool.
	var hire: Callable
	var hired_today := false
	var players_left := 4
	## buy_boat.call(town_index) -> bool: buy a boat beside that town.
	var buy_boat: Callable
	## rebalance.call(town_index): the castle rebalance (0x746d8, act mode) for
	## the hero standing in that town, run before and after the rounds.
	var rebalance: Callable
	## When set, KB.LOG-style lines are appended here.
	var log: Array = []
	var logging := false

static var _rules: Dictionary = {}

static func rules() -> Dictionary:
	if _rules.is_empty():
		_rules = JsonFile.read_dict(RULES_PATH)
	return _rules

static func _f32(x: float) -> float:
	return PackedFloat32Array([x])[0]

## Turn-start snapshot. `income` is the kingdom's daily income by resource
## (gold included), the second number of the original's `RES -` log lines.
static func economy(ai: PlayerState, income: Dictionary, day: int) -> Dictionary:
	var w: Dictionary = rules().get("player_weights", {})
	var factor := 1.0
	for row: Dictionary in w.get("day_factor", []):
		if day < int(row.get("before", 0)):
			factor = float(row.get("factor", 1.0))
			break
	var ad := _f32(float(w.get("ad", 0.0)))
	var b1 := _f32(float(w.get("b1", 0.0)))
	var b5 := _f32(_f32(float(w.get("b5", 0.0))) * _f32(factor))
	var rating := 0.0
	var weights := {}
	for hero: HeroModel in ai.heroes:
		rating += ArmyStrength.of(hero.army)
		weights[hero.visit_id()] = AITileValue.hero_weight_of(hero)
	for town: TownModel in ai.towns:
		rating += ArmyStrength.of(town.army)
	var offset := float((rules().get("army_value", {}) as Dictionary).get("rating_offset", 1000))
	var gold_income := int(income.get("gold", 0))
	var f9 := _f32(_f32(float(ai.gold() + gold_income) / (rating + offset)) + b1)
	# Player +0xf1 (the obelisk's worth) is set here too (0x696a7), from the
	# pieces revealed at the start of the turn.
	return {"ad": ad, "b1": b1, "b5": b5, "f9": f9, "day": day, "hero_weights": weights,
			"obelisks_seen": ai.puzzle_pieces.size(),
			"income": income.duplicate(), "worth": resource_worth(_stock(ai), income)}

## heroes.exe 0x73ade: what one unit of each resource is worth in gold terms.
static func resource_worth(stock: Dictionary, income: Dictionary) -> Dictionary:
	var r: Dictionary = rules().get("resource_worth", {})
	var base: Dictionary = r.get("base", {})
	var days := float(r.get("income_days", 5)) * float(r.get("income_weight", 0.7))
	var held: Dictionary = {}
	var total := 0
	for res: String in RESOURCES:
		var b := float(base.get(res, 1))
		held[res] = int((float(stock.get(res, 0)) + days * float(income.get(res, 0))) * b)
		total += int(held[res])
	var mean := maxi(1, total / RESOURCES.size())
	var out: Dictionary = {}
	for res: String in RESOURCES:
		out[res] = _f32(float(base.get(res, 1)) / (float(r.get("ratio_weight", 0.5))
				* float(held[res]) / float(mean) + float(r.get("ratio_offset", 0.5))))
	return out

## heroes.exe 0x712b0: a cost bag in gold equivalents.
static func cost_eq(cost: Dictionary, worth: Dictionary) -> int:
	var sum := 0.0
	for res: String in cost:
		sum += float(cost[res]) * float(worth.get(res, 1.0))
	return int(sum)

## heroes.exe 0x73c74: 1 - 0.15 per day of waiting for the scarcest resource.
static func affordability(cost: Dictionary, stock: Dictionary, income: Dictionary) -> float:
	var a: Dictionary = rules().get("affordability", {})
	var days := 0
	for res: String in cost:
		var need := int(cost[res])
		var have := int(stock.get(res, 0))
		if need <= have:
			continue
		var per_day := int(income.get(res, 0))
		var wait := (need - have) / per_day + 1 if per_day > 0 else int(a.get("no_income_days", 99))
		days = maxi(days, wait)
	return maxf(0.0, _f32(1.0 - _f32(float(a.get("per_day", 0.15))) * days))

static func _stock(ai: PlayerState) -> Dictionary:
	var out := ai.resources.duplicate()
	out["gold"] = ai.gold()
	return out

static func _late() -> float:
	return _f32(float((rules().get("late_term", {}) as Dictionary).get("value", 0.09)))

## One town's building options, in flag-bit order, each
## {id, bit, raw}. Only what 0xd0190 would allow; gold shortfalls stay in.
static func building_options(ai: PlayerState, town_index: int, econ: Dictionary) -> Array:
	var town: TownModel = ai.towns[town_index]
	var b: Dictionary = rules().get("buildings", {})
	var f: Dictionary = rules().get("building_factors", {})
	var ad := float(econ.get("ad", 0.0))
	var b1 := float(econ.get("b1", 0.0))
	var dwellings := BuildingCatalog.dwelling_ids(town.faction)
	var n := 0
	var top := -1
	for tier in dwellings.size():
		if town.is_built(String(dwellings[tier])):
			n += 1
			top = tier
	var ids: Array = []
	for id: String in COMMON_BITS:
		ids.append(id)
	ids.append_array(dwellings)
	var out: Array = []
	for id: String in ids:
		# The original keys the guild on its level byte (town +0x18), which
		# counts built levels from 0: our level less one, 0 with no guild.
		var guild_byte := maxi(0, town.mage_guild_level - 1)
		if id == "mage_guild" and (guild_byte >= int(b.get("guild_max_byte", 3))
				or town.mage_guild_level >= TownModel.GUILD_COSTS.size()):
			continue
		if not (town.can_build(id, ai) in ["buildable", "no_resources"]):
			continue
		var tier := dwellings.find(id)
		var value := 0.0
		if id == "mage_guild":
			var levels: Array = b.get("mage_guild", [])
			value = float(levels[guild_byte])
			if guild_byte > 0:
				value -= float(levels[guild_byte - 1])
			value *= (2.0 * ad + float(f.get("two_ad_offset", 0.33))) \
					* (float(f.get("guild_base", 1.33)) - float(f.get("guild_per_town", 0.33)) * _guilds_at_level_zero(ai))
		elif tier >= 0:
			value = float(((b.get("dwellings", {}) as Dictionary).get(town.faction, []) as Array)[tier])
			value = _dwelling_factor(ai, town, tier, value, n, top, econ)
		else:
			value = float(b.get(id, 0))
			match id:
				"tavern":
					value *= ArmyStrength.of(town.army) / float(f.get("tavern_rating", 3000))
				"shipyard":
					value = 0.0
				"well":
					value *= (ad + float(f.get("ad_offset", 0.66))) * (2.0 * b1 + float(f.get("b1_offset", 0.33))) \
							* (float(f.get("well_base", 0.66)) + float(f.get("well_per_dwelling", 0.33)) * n)
				"castle":
					value *= (2.0 * ad + float(f.get("two_ad_offset", 0.33))) \
							* (float(f.get("castle_base", 1.6)) - float(f.get("castle_per_dwelling", 0.2)) * n)
		var late: Dictionary = rules().get("late_term", {})
		value = maxf(0.0, value * (1.0 - _late() * float(late.get("building_count", 3))))
		# The guild's cost is read at the same byte (0xd00a0), so a second
		# level is scored at the first level's price.
		var cost: Dictionary = TownModel.GUILD_COSTS[guild_byte] if id == "mage_guild" else town.build_cost(id)
		value *= affordability(cost, _stock(ai), econ.get("income", {}))
		var eq := cost_eq(cost, econ.get("worth", {}))
		out.append({"id": id, "bit": DWELLING_BIT + tier if tier >= 0 else int(COMMON_BITS[id]),
				"raw": value / float(eq) if eq > 0 else 0.0})
	return out

## 0x76cb8 counts the player's guilds whose level byte is 0: a guild of one
## level, since the byte counts built levels from 0.
static func _guilds_at_level_zero(ai: PlayerState) -> int:
	var count := 0
	for t: TownModel in ai.towns:
		if t.mage_guild_level == 1:
			count += 1
	return count

static func _dwelling_factor(ai: PlayerState, town: TownModel, tier: int, value: float,
		n: int, top: int, econ: Dictionary) -> float:
	var f: Dictionary = rules().get("building_factors", {})
	var units := BuildingCatalog.units(town.faction)
	var unit := String(units[tier]) if tier < units.size() else ""
	# Quirk: with all five garrison slots taken by other creatures the base
	# value goes through unmodified.
	if town.army != null and town.army.slots.size() >= ArmyData.MAX_SLOTS \
			and town.army.count_of(unit) <= 0:
		return value
	var ad := float(econ.get("ad", 0.0))
	var b1 := float(econ.get("b1", 0.0))
	value *= (ad + float(f.get("ad_offset", 0.66))) * (2.0 * b1 + float(f.get("b1_offset", 0.33)))
	var id := String(BuildingCatalog.dwelling_ids(town.faction)[tier])
	var same := 0
	for t: TownModel in ai.towns:
		if t.faction == town.faction and t.is_built(id):
			same += 1
	value *= 1.0 - float(f.get("dwelling_per_town", 0.05)) * same
	if tier < top:
		value *= float(f.get("lower_tier_base", 1.66)) - float(f.get("lower_tier_per_dwelling", 0.33)) * n
	if town.is_built("well"):
		value *= float(f.get("well_bonus", 1.1))
	var ranks: Dictionary = rules().get("creature_rank", {})
	var mine := float(ranks.get(unit, 0))
	var dwellings := BuildingCatalog.dwelling_ids(town.faction)
	for other in dwellings.size():
		var other_unit := String(units[other]) if other < units.size() else ""
		if not town.is_built(String(dwellings[other])) or int(town.available.get(other_unit, 0)) <= 0:
			continue
		if float(ranks.get(other_unit, 0)) * float(f.get("rank_margin", 1.2)) > mine:
			return 0.0
	return value

## One town's creature options in tier order, each {unit, tier, n, raw}.
static func creature_options(ai: PlayerState, town_index: int, econ: Dictionary,
		hero: HeroModel) -> Array:
	var town: TownModel = ai.towns[town_index]
	var c: Dictionary = rules().get("creatures", {})
	var units := BuildingCatalog.units(town.faction)
	var dwellings := BuildingCatalog.dwelling_ids(town.faction)
	var heavy: Array = c.get("heavy_units", [])
	var out: Array = []
	for tier in mini(units.size(), dwellings.size()):
		var unit := String(units[tier])
		var stock := int(town.available.get(unit, 0))
		if not town.is_built(String(dwellings[tier])) or stock <= 0:
			continue
		if town.army == null or not town.army.can_add(unit):
			continue
		var n := buy_count(town, unit, ai.gold(), stock)
		if n <= 0:
			continue
		var b := int(n * ArmyStrength.unit_power(unit) * float(econ.get("f9", 0.0)))
		if hero != null:
			b = int(b * float(c.get("hero_bonus", 1.1)))
			if _creature_faction(unit) == hero.hero_class:
				b = int(b * _f32(float(c.get("class_bonus", 1.1))))
			if unit in heavy:
				b = int(b * _heavy_factor(hero.army, heavy, c))
			b = int(b * (float(econ.get("b1", 0.0)) + float(c.get("b1_offset", 0.66))))
		if unit in heavy:
			b = int(b * _heavy_factor(town.army, heavy, c))
		var late: Dictionary = rules().get("late_term", {})
		b = int(b * pow(_late() + float(late.get("creature_base", 0.96)), float(late.get("creature_power", 3))))
		var unit_cost := _unit_cost(town, unit)
		var value := int(b * affordability(unit_cost, _stock(ai), econ.get("income", {})))
		var eq := n * cost_eq(unit_cost, econ.get("worth", {}))
		out.append({"unit": unit, "tier": tier, "n": n,
				"raw": float(value) / float(eq) if eq > 0 else 0.0})
	return out

## heroes.exe 0x70860: half of what the gold buys (only gold counts), capped
## at the stock; 0 below min_count.
static func buy_count(town: TownModel, unit: String, gold: int, stock: int) -> int:
	var price := town.cost_of(unit)
	if price <= 0:
		return 0
	var q := gold / price
	if q > 1:
		q /= 2
	q = mini(q, stock)
	return q if q >= int((rules().get("creatures", {}) as Dictionary).get("min_count", 2)) else 0

static func _unit_cost(town: TownModel, unit: String) -> Dictionary:
	var cost := town.rare_cost_of(unit).duplicate()
	cost["gold"] = town.cost_of(unit)
	return cost

static func _heavy_factor(army: ArmyData, heavy: Array, c: Dictionary) -> float:
	var count := 0
	if army != null:
		for s: Dictionary in army.slots:
			if String(s.unit) in heavy:
				count += 1
	return float(c.get("heavy_base", 1.18)) - float(c.get("heavy_per_stack", 0.06)) * count

## Faction of a town creature by its native id (six per faction, in the hero
## class order Knight, Barbarian, Sorceress, Warlock).
static func _creature_faction(unit: String) -> String:
	var id := CreatureCatalog.native_id(unit)
	if id < 0 or id >= 24:
		return ""
	return String(BuildingCatalog.FACTIONS[id / 6])

## A tavern hero's Raw BC for this town.
static func hero_raw(ai: PlayerState, town: TownModel, hero: HeroModel, econ: Dictionary) -> float:
	var h: Dictionary = rules().get("heroes", {})
	var arts: Dictionary = rules().get("artifact_values", {})
	var value := int(h.get("base", 2000)) + hero.experience + hero.experience / 2
	for art: Variant in hero.artifacts:
		value += int(arts.get(String(art), 0))
	value = int(value * (1.0 + float(econ.get("b5", 0.0)) - float(econ.get("b1", 0.0))))
	if String((h.get("class_bonus_town", {}) as Dictionary).get(hero.hero_class, "")) == town.faction:
		value = int(value * _f32(float(h.get("class_bonus", 1.1))))
	# 0x73410 at (0, 0): on Day 1 for side 1, the BSS cache is uninitialized (0);
	# for sides 2 and 3 on Day 1, starting heroes have target (-1, -1) giving
	# a crowding penalty of -1215. On Day 2+, all heroes are on the map (d >= 9), so potential is 0.
	var pot: int = 0
	if int(econ.get("day", 1)) == 1 and ai != null and ai.side > 1:
		pot = int(h.get("initial_hero_penalty", -1215))
	value += pot - int(h.get("potential_offset", 200))
	var cost := {"gold": HeroPool.COST}
	value = int(value * affordability(cost, _stock(ai), econ.get("income", {})))
	var eq := cost_eq(cost, econ.get("worth", {}))
	return float(value) / float(eq) if eq > 0 else 0.0

static func hero_cap(players_left: int) -> int:
	var h: Dictionary = rules().get("heroes", {})
	return int(h.get("cap_two_players", 4)) if players_left == 2 else int(h.get("cap", 3))

## Garrison share terms per town: [a, b] with b = rating + 400.
static func _share_terms(ai: PlayerState) -> Array:
	var c: Dictionary = rules().get("creatures", {})
	var offset := int(c.get("garrison_offset", 400))
	var b_sum := 0
	var w_sum := 0
	var bs: Array = []
	var ws: Array = []
	for town: TownModel in ai.towns:
		var b := int(ArmyStrength.of(town.army)) + offset
		var w := int(c.get("garrison_weight_castle", 10)) if town.has_castle \
				else int(c.get("garrison_weight_town", 7))
		bs.append(b)
		ws.append(w)
		b_sum += b
		w_sum += w
	var m := b_sum / maxi(1, w_sum)
	var out: Array = []
	for i in bs.size():
		out.append([int(ws[i]) * m + offset, int(bs[i])])
	return out

## One round: every town's three candidates, the best of all. Returns the
## winner {kind, town, ...} or {} when the best scores below stop_below.
static func choose(ai: PlayerState, ctx: Context) -> Dictionary:
	var noise: Dictionary = rules().get("noise", {})
	var empty := float(noise.get("empty", -99.0))
	var shares := _share_terms(ai)
	var best := {"score": empty}
	for town_index in ai.towns.size():
		var town: TownModel = ai.towns[town_index]
		# Buildings.
		var pick := {"kind": KIND_BUILDING, "town": town_index, "id": "", "index": -1, "raw": empty}
		var pick_rand := empty
		for opt: Dictionary in building_options(ai, town_index, ctx.econ):
			var rand := float(opt.raw) * (int((noise.building as Dictionary).base)
					+ int(ctx.roll.call(int(noise.building.lo), int(noise.building.hi)))) * 0.01
			_log(ctx, "Town: %d  Building: %s Raw BC = %.2f, RandBC = %.2f." % [town_index, opt.id, opt.raw, rand])
			if rand > pick_rand:
				pick_rand = rand
				pick = {"kind": KIND_BUILDING, "town": town_index, "id": opt.id, "index": opt.bit, "raw": opt.raw}
		pick["score"] = float(pick.raw) * _candidate_noise(ctx)
		if float(pick.score) > float(best.score):
			best = pick
		# Creatures.
		var hero_in: HeroModel = ctx.hero_at.call(town_index) if ctx.hero_at.is_valid() else null
		pick = {"kind": KIND_CREATURE, "town": town_index, "id": "", "index": -1, "n": 0, "raw": empty}
		pick_rand = empty
		for opt: Dictionary in creature_options(ai, town_index, ctx.econ, hero_in):
			var rand := float(opt.raw) * (int((noise.creature as Dictionary).base)
					+ int(ctx.roll.call(int(noise.creature.lo), int(noise.creature.hi)))) * 0.01
			_log(ctx, "Town: %d  Creature: %s Raw BC = %.2f, RandBC = %.2f." % [town_index, opt.unit, opt.raw, rand])
			if rand > pick_rand:
				pick_rand = rand
				pick = {"kind": KIND_CREATURE, "town": town_index, "id": opt.unit, "index": opt.tier,
						"n": opt.n, "raw": opt.raw}
		var c: Dictionary = rules().get("creatures", {})
		var share: Array = shares[town_index]
		var share_factor := float(share[0]) / float(share[1]) * _f32(1.0 / float(c.get("share_divisor", 3))) \
				+ float(c.get("share_offset", 0.66))
		pick["score"] = float(pick.raw) * share_factor * _candidate_noise(ctx)
		if float(pick.score) > float(best.score):
			best = pick
		# Tavern heroes.
		if ai.heroes.size() >= hero_cap(ctx.players_left) or not town.has_castle:
			continue
		var offered: Array = ctx.tavern.call() if ctx.tavern.is_valid() else []
		if offered.is_empty():
			continue
		pick = {"kind": KIND_HERO, "town": town_index, "id": "", "index": -1, "raw": empty}
		pick_rand = empty
		for slot in offered.size():
			var candidate := offered[slot] as HeroModel
			var raw := hero_raw(ai, town, candidate, ctx.econ)
			var rand := raw * (int((noise.hero as Dictionary).base)
					+ int(ctx.roll.call(int(noise.hero.lo), int(noise.hero.hi)))) * 0.01
			_log(ctx, "Town: %d  Hero    : %d Raw BC = %.2f, RandBC = %.2f." % [town_index, slot, raw, rand])
			if rand > pick_rand:
				pick_rand = rand
				pick = {"kind": KIND_HERO, "town": town_index, "id": candidate.hero_name, "index": slot,
						"hero": candidate, "raw": raw}
		pick["score"] = _hero_score(ai, ctx, town_index, float(pick.raw))
		if float(pick.score) > float(best.score):
			best = pick
	_log(ctx, "BestBHC : %d %d %d 0 0" % [int(best.get("kind", -1)),
			int(float(best.score) * 100.0), int(best.get("index", -1))])
	if float(best.score) < float(rules().get("stop_below", 0.02)):
		return {}
	return best

static func _candidate_noise(ctx: Context) -> float:
	var noise: Dictionary = rules().get("noise", {})
	return float(100 - int(ctx.roll.call(0, int(noise.get("candidate_max", 10))))) * 0.01

static func _hero_score(ai: PlayerState, ctx: Context, town_index: int, raw: float) -> float:
	var h: Dictionary = rules().get("heroes", {})
	var score := raw
	if ctx.gate_taken.is_valid() and bool(ctx.gate_taken.call(town_index)):
		score -= float(h.get("gate_penalty", 200))
	score *= _candidate_noise(ctx)
	var count := ai.heroes.size()
	var cap := hero_cap(ctx.players_left)
	var gold_income := int((ctx.econ.get("income", {}) as Dictionary).get("gold", 0))
	if not ctx.hired_today and int(ctx.econ.get("day", 0)) > int(h.get("bonus_after_day", 5)) and score > 0.0:
		if gold_income >= int(h.get("income_add", 1250)) and count < cap - 2:
			score += float(h.get("add", 500))
		elif gold_income >= int(h.get("income_scale", 1500)) and count < cap - 1:
			score *= float(h.get("scale", 1.3))
	elif count == 0:
		score += float(h.get("add", 500))
	return score

static func _log(ctx: Context, line: String) -> void:
	if ctx.logging:
		ctx.log.append(line)

## The whole buy: naval holdback, rounds until the stop rule, holdback
## returned. Returns the purchases in order, each the winning candidate.
static func run(ai: PlayerState, ctx: Context) -> Array:
	var bought: Array = []
	if ai == null or ai.towns.is_empty() or ai.gold() < int(rules().get("min_gold", 200)):
		return bought
	var held := _naval_request(ai, ctx)
	_rebalance(ai, ctx)
	for _round in 64:
		var pick := choose(ai, ctx)
		if pick.is_empty() or not _buy(ai, ctx, pick):
			break
		bought.append(pick)
	ai.add_resources(held)
	_rebalance(ai, ctx)
	return bought

## heroes.exe 0x675af and 0x68b73: every town of the player, in list order.
static func _rebalance(ai: PlayerState, ctx: Context) -> void:
	if ctx.rebalance.is_valid():
		for i in ai.towns.size():
			ctx.rebalance.call(i)

## heroes.exe 0x6971c, once at the start of each computer turn: both naval
## requests lapse when more than 8 days have passed since the planner last
## made one. The original keeps that day as a signed byte (0x31e9c), so from
## day 128 a request lapses at the next turn start.
static func expire_naval_request(ai: PlayerState, day: int) -> void:
	if ai.naval_shipyard_town < 0 and ai.naval_boat_town < 0:
		return
	var stamp := ai.naval_request_day & 0xff
	if stamp >= 128:
		stamp -= 256
	if day - stamp > 8:
		ai.naval_shipyard_town = -1
		ai.naval_boat_town = -1

## heroes.exe 0x673d9..0x675af, before the rounds: the shipyard request
## builds its shipyard when it can, else holds shipyard_hold back; the boat
## request buys a boat when the town has a shipyard and boat_hold is there,
## and is then done, else holds boat_hold back. Both lapse when the town has
## changed hands. Returns what was held, to give back after the rounds.
static func _naval_request(ai: PlayerState, ctx: Context = null) -> Dictionary:
	if ai.naval_shipyard_town < 0 and ai.naval_boat_town < 0:
		return {}
	var town_id := ai.naval_shipyard_town if ai.naval_shipyard_town >= 0 else ai.naval_boat_town
	var index := -1
	for i in ai.towns.size():
		if (ai.towns[i] as TownModel).object_id == town_id:
			index = i
	if index < 0:
		ai.naval_shipyard_town = -1
		ai.naval_boat_town = -1
		return {}
	var town: TownModel = ai.towns[index]
	var naval: Dictionary = rules().get("naval", {})
	var held: Dictionary = {}
	if ai.naval_shipyard_town >= 0:
		ai.active_town = index
		if town.can_build("shipyard", ai) == "buildable" and town.build("shipyard", ai):
			ai.naval_shipyard_town = -1
		else:
			_hold(ai, naval.get("shipyard_hold", {}), held)
	if ai.naval_boat_town >= 0:
		var hold: Dictionary = naval.get("boat_hold", {})
		if town.is_built("shipyard") and ai.gold() >= int(hold.get("gold", 1000)) \
				and int(ai.resources.get("wood", 0)) >= int(hold.get("wood", 10)):
			if ctx != null and ctx.buy_boat.is_valid():
				ctx.buy_boat.call(index)
			ai.naval_boat_town = -1
		else:
			_hold(ai, hold, held)
	return held

## Take `hold` out of the treasury (as much as there is) and add it to `held`.
static func _hold(ai: PlayerState, hold: Dictionary, held: Dictionary) -> void:
	var taken: Dictionary = {}
	for res: String in hold:
		var have := ai.gold() if res == "gold" else int(ai.resources.get(res, 0))
		taken[res] = mini(have, int(hold[res]))
		held[res] = int(held.get(res, 0)) + int(taken[res])
	ai.pay(taken)

## Pre-check and buy. False ends the whole buy (the original's saving rule).
static func _buy(ai: PlayerState, ctx: Context, pick: Dictionary) -> bool:
	var town_index := int(pick.town)
	var town: TownModel = ai.towns[town_index]
	ai.active_town = town_index
	match int(pick.kind):
		KIND_BUILDING:
			# The computer's build (0x75190) pays the guild's price at the level
			# byte, as the scoring reads it: level 2 at level 1's price, level 3
			# at level 2's, level 4 at level 3's. Whether it may build is asked
			# at the listed price, so a level 2 can leave the gold below zero.
			if String(pick.id) == "mage_guild":
				return town.build("mage_guild", ai, TownModel.GUILD_COSTS[maxi(0, town.mage_guild_level - 1)])
			return String(pick.id) != "" and town.build(String(pick.id), ai)
		KIND_CREATURE:
			return town.recruit(String(pick.id), int(pick.n), ai)
		KIND_HERO:
			if ctx.hired_today or ai.gold() < HeroPool.COST:
				return false
			if ctx.gate_taken.is_valid() and bool(ctx.gate_taken.call(town_index)):
				return false
			if not ctx.hire.is_valid() or not bool(ctx.hire.call(town_index, pick.hero)):
				return false
			ctx.hired_today = true
			return true
	return false

## Daily income by resource: towns, hero artifacts, owned mines and dragon cities.
## heroes.exe day-1 quirk: on day 1, the original's income array read 500 gold
## (RES - Gold 10000 500), then 1000 gold/day from day 2 onwards.
static func income_of(ai: PlayerState, objects: Array, day: int = 2) -> Dictionary:
	var base_gold := mini(500, ai.daily_income) if day <= 1 else ai.daily_income
	var out := {"gold": base_gold}
	for hero: HeroModel in ai.heroes:
		out["gold"] = int(out["gold"]) + hero.daily_gold_bonus()
	for o: Variant in objects:
		var yield_bag: Dictionary = {}
		if o is Mine and (o as Mine).owner == ai.side:
			yield_bag = (o as Mine).daily_yield()
		elif o is DragonCity and (o as DragonCity).owner == ai.side:
			yield_bag = (o as DragonCity).daily_yield()
		for res: String in yield_bag:
			out[res] = int(out.get(res, 0)) + int(yield_bag[res])
	return out
