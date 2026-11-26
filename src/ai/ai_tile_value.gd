# src/ai/ai_tile_value.gd
class_name AITileValue
extends RefCounted

## What a map object is worth to a computer hero, in gold equivalents:
## heroes.exe 0x71938, the AI's tile value function, with its battle estimate
## 0x6e950. Constants live in data/ai/tile_values.json; the decode is in
## data/knowledge_base/research/ai-planner-decodes.md. A resource counts at its worth (AIBuyer's
## resource_worth), an army at its rating times the player's army value f9.

const RULES_PATH := "res://data/ai/tile_values.json"

## One evaluation's inputs: the hero, the turn's economy snapshot
## (AIBuyer.economy) and the world it looks at.
class Ctx:
	var ai: PlayerState
	var hero: HeroModel
	var hero_id := 0
	var econ: Dictionary = {}
	var state: GameState
	var map: MapData
	## Hero float +0xb2.
	var hero_weight := 0.4
	var human_mult := 1.0
	var computer_mult := 1.0
	var players := 4
	var average_artifact := 0
	## The support factor (data 0x31eac/0x31eb0), set once per hero turn by
	## AIPlanner.support_factor; 1 leaves every value as it is.
	var support := 1.0
	## The strong-hero factor (data 0x31eb4/0x31eb8), set with it by
	## AIPlanner.strong_factor.
	var strong := 1.0

static var _rules: Dictionary = {}

static func rules() -> Dictionary:
	if _rules.is_empty():
		_rules = JsonFile.read_dict(RULES_PATH)
	return _rules

static func context(ai: PlayerState, hero: HeroModel, map: MapData, state: GameState,
		econ: Dictionary) -> Ctx:
	var c := Ctx.new()
	c.ai = ai
	c.hero = hero
	c.hero_id = hero.visit_id() if hero != null else 0
	c.econ = econ
	c.state = state
	if c.state == null:
		var g := AIController._game()
		c.state = g.state if g != null else null
	c.map = map
	# Hero +0xb2 is set for every hero before the buy (0x697a9, the buy at
	# 0x69c3c) and kept all turn; a hero hired since keeps his record's 0
	# until his side's next turn (Barok and Carlawn in the 2026-11-01 saves).
	var weights: Dictionary = econ.get("hero_weights", {})
	c.hero_weight = float(weights.get(c.hero_id, 0.0 if econ.has("hero_weights") else hero_weight_of(hero)))
	var mults := owner_multipliers(ai.ai_level)
	c.human_mult = mults[0]
	c.computer_mult = mults[1]
	c.players = c.state.players.size() if c.state != null else 4
	c.average_artifact = average_artifact_value()
	return c

## Hero +0xb2: plain army rating x per_rating + base.
static func hero_weight_of(hero: HeroModel) -> float:
	var w: Dictionary = rules().get("hero_weight", {})
	return ArmyStrength.of(hero.army if hero != null else null) \
			* float(w.get("per_rating", 0.00004)) + float(w.get("base", 0.4))

## Player float +0xfd: the mean AI value of the ordinary artifacts (native ids
## 4..36, the ones a random artifact can be).
static func average_artifact_value() -> int:
	var values: Dictionary = AIBuyer.rules().get("artifact_values", {})
	var total := 0
	var count := 0
	for id: String in values:
		if id.begins_with("_"):
			continue
		var native := int(ArtifactCatalog.shared().get_artifact(id).get("frame", -1))
		if native >= 4 and native <= 36:
			total += int(values[id])
			count += 1
	return total / maxi(1, count)

## [human, computer] owner multipliers for this computer's level.
static func owner_multipliers(level: int) -> Array:
	var o: Dictionary = rules().get("owner_multiplier", {})
	if level == 1:
		return [float(o.level_1.human), float(o.level_1.computer)]
	if level == 2:
		return [float(o.level_2.human), float(o.level_2.computer)]
	return [1.0 + float(o.get("human_per_level", 0.07)) * level,
			float(o.get("computer_base", 1.1)) - float(o.get("computer_per_level", 0.12)) * level]

static func _worth(ctx: Ctx, res: String) -> float:
	return float((ctx.econ.get("worth", {}) as Dictionary).get(res, 1.0))

static func artifact_value(id: String) -> int:
	return int((AIBuyer.rules().get("artifact_values", {}) as Dictionary).get(id, 0))

## heroes.exe 0x73d34: an army's rating as the computer judges a fight.
## Each stack counts count x rating x (1 + its size bracket); a hero adds its
## attack and defense, morale, luck and combat spells; a besieged town adds
## its tower. Plain count x rating is ArmyStrength.of().
static func army_rating(army: ArmyData, hero: HeroModel = null, siege_town: TownModel = null) -> int:
	var r: Dictionary = rules().get("rating", {})
	var a := 0
	if army != null:
		for s: Dictionary in army.slots:
			var unit := String(s.unit)
			var count := int(s.count)
			var bonus := 0.0
			for row: Dictionary in r.get("brackets", []):
				if count > int(row.get("above", 0)):
					bonus = _f32(float(row.get("bonus", 0.0)))
					break
			if int(CreatureCatalog.stats(unit).get("shots", 0)) > 0 \
					or unit in (r.get("shooter_units", []) as Array):
				bonus = _f32(bonus * float(r.get("shooter", 0.7)))
			elif unit in (r.get("griffin_units", []) as Array):
				bonus = _f32(bonus * float(r.get("griffin", 1.2)))
			a += int(count * ArmyStrength.unit_power(unit) * (1.0 + bonus))
	var tower := siege_town.siege_tower_k() * int(r.get("tower_per_k", 120)) if siege_town != null else 0
	var spells := 0
	if hero != null:
		var skill: Array = r.get("skill", [])
		# The hero record's skills include the artifacts' bonuses.
		var multiplier := _f32(float(skill[clampi(hero.effective_attack() + hero.effective_defense() + 20, 0, skill.size() - 1)]))
		a = int(a * multiplier)
		tower = int(tower * multiplier)
		var morale := clampi(hero.effective_morale() + hero.army_morale_modifier(), -3, 3)
		if morale > 0:
			a = a * (morale + int(r.get("morale_up", 48))) / int(r.get("morale_up", 48))
		elif morale < 0:
			a = a * (morale + int(r.get("morale_down", 24))) / int(r.get("morale_down", 24))
		var luck := hero.effective_luck()
		if luck != 0:
			a = a * (luck + int(r.get("luck", 16))) / int(r.get("luck", 16))
		spells = _spell_rating(hero, a, r)
	if 2 * a < tower:
		tower = int(a * float(r.get("tower_high", 1.5)))
	elif tower > a * 1.5:
		tower = int(a * float(r.get("tower_mid", 1.25)))
	elif tower > a:
		tower = int(a * float(r.get("tower_low", 0.9)))
	return a + spells + tower

static func _spell_rating(hero: HeroModel, a: int, r: Dictionary) -> int:
	if not hero.has_spellbook or hero.spellbook == null:
		return 0
	var values: Dictionary = r.get("spell_values", {})
	var power: Array = r.get("power", [])
	var charges_curve: Array = r.get("charges", [])
	var total := 0
	var best := 0
	for id: Variant in hero.spellbook.spells:
		var spell := String(id)
		if not values.has(spell):
			continue
		var factor := 1.0
		if spell in (r.get("power_scaled", []) as Array):
			factor = float(power[hero.spell_power]) if hero.spell_power < power.size() \
					else float(r.get("power_above", 5.0))
		else:
			factor = float((r.get("low_power", {}) as Dictionary).get(str(hero.spell_power), 1.0))
		var v := int(float(values[spell]) * _f32(factor))
		var charges := mini(hero.spellbook.charges(spell), charges_curve.size() - 1)
		total = int(v * _f32(float(charges_curve[maxi(0, charges)])) + total)
		best = maxi(best, v)
	if total > best * float(r.get("cap_share", 3.5)):
		total = int(best * float(r.get("cap_share", 3.5)))
	if 2 * a < total:
		return int(a * float(r.get("spell_high", 1.25)))
	if total > a * 1.5:
		return a
	if total > a:
		return int(a * float(r.get("spell_low", 0.75)))
	return total

static func _f32(x: float) -> float:
	return PackedFloat32Array([x])[0]

## heroes.exe 0x6e950. `defender_side` -1 means neutral. Am and Dm are the
## computer's ratings (army_rating), A0 and D0 plain count x rating. A town's
## defender rates its garrison with the hero and the tower, then the hero's
## own army (`defender_extra`). Returns {p, own_loss, enemy_loss, value}.
static func battle(ctx: Ctx, attacker: ArmyData, defender: ArmyData,
		defender_hero: HeroModel = null, siege := false, defender_side := -1,
		with_hero := true, siege_town: TownModel = null,
		defender_extra: ArmyData = null) -> Dictionary:
	var est: Dictionary = AIController.rules().get("battle_estimate", {})
	var b: Dictionary = rules().get("battle", {})
	var a0 := ArmyStrength.of(attacker)
	var d0 := ArmyStrength.of(defender) + ArmyStrength.of(defender_extra)
	var am := float(army_rating(attacker, ctx.hero if with_hero else null))
	var dm := float(army_rating(defender, defender_hero, siege_town)) \
			+ (float(army_rating(defender_extra)) if defender_extra != null else 0.0)
	if siege:
		dm *= float(b.get("siege", 1.11))
	var defender_player: PlayerState = ctx.state.player_of(defender_side) \
			if ctx.state != null and defender_side >= 0 else null
	if defender_side < 0:
		am *= float(est.get("neutral_base", 0.7)) + float(est.get("neutral_per_level", 0.15)) * ctx.ai.ai_level
	elif defender_player != null and not defender_player.is_ai:
		dm *= float(b.get("human_defender", 1.14))
		if ctx.ai.ai_level == 1:
			am *= float(b.get("dumb_attacker", 1.5))
	var p := AIController.win_chance(am, dm)
	var out1 := int((1.0 - p) * a0)
	var out2 := int(p * d0)
	var own := int(a0 * (1.0 - p) + out1 * p)
	var enemy := int(d0 * p + out2 * (1.0 - p))
	var g := float(ctx.econ.get("b1", 0.3))
	var value := int(-own * pow(float(est.get("loss_base", 1.33)) - g, 2.0))
	var mult := 1.0
	if defender_player != null:
		mult = ctx.computer_mult if defender_player.is_ai else ctx.human_mult
		value = int(enemy * mult * pow(g + float(b.get("gain_offset", 0.66)), 2.0) + value)
	value = int(value * float(ctx.econ.get("f9", 1.0)))
	if with_hero and ctx.hero != null:
		var risk := _artifacts(ctx.hero) + int(b.get("attacker_risk", 1400))
		value = int(value - risk * (1.0 - p))
		var xp := _hit_points(defender) + (int(b.get("hero_xp", 500)) if defender_hero != null else 0)
		value = int(value + xp * float(b.get("xp_share", 0.8)) * p * ctx.hero_weight)
	if defender_hero != null:
		var prize := _artifacts(defender_hero) + int(b.get("defender_prize", 1250))
		value = int(value + prize * mult * p)
	return {"p": p, "own_loss": own, "enemy_loss": enemy, "value": value}

static func _artifacts(hero: HeroModel) -> int:
	var total := 0
	for art: Variant in hero.artifacts:
		total += artifact_value(String(art))
	return total

## heroes.exe 0x83ba8: experience for beating `army` and `hero`, the army's
## total hit points and hero_xp more for a hero.
static func experience(army: ArmyData, hero: HeroModel = null) -> int:
	return _hit_points(army) + (int((rules().get("battle", {}) as Dictionary).get("hero_xp", 500)) \
			if hero != null else 0)

## The army's total hit points.
static func _hit_points(army: ArmyData) -> int:
	var total := 0
	if army != null:
		for s: Dictionary in army.slots:
			total += int(s.count) * int(CreatureCatalog.stats(String(s.unit)).get("hp", 0))
	return total

## The tile value of `o` for ctx.hero. 0 for anything it would not visit.
## `raw` is the original's modes 1 and 2: a fight keeps its negative value
## (mode 0, the potential's, floors it at 0 as the case exit does).
static func value(o: MapObject, ctx: Ctx, raw := false) -> float:
	var v := _value(o, ctx, raw)
	if ctx != null and ctx.support < 1.0 and _supported(o, ctx, v):
		v = supported(v, ctx)
	if ctx != null and ctx.strong < 1.0 and not (o is TownObject
			and (o as TownObject).owner >= 0 and (o as TownObject).owner != ctx.ai.side):
		v = float(int(v * ctx.strong))
	# 0x7338b: mode 0 (the potential's) floors a negative value at 0; only a
	# hero's (the planner's hero case, not this function) stays negative.
	if not raw and v < 0.0:
		v = 0.0
	return v

## `v` times the support factor, truncated as the case exit 0x732ce does.
## The strong-hero factor never applies to a hero (0x71f1e clears 0x3208c).
static func supported(v: float, ctx: Ctx) -> float:
	return float(int(v * ctx.support)) if ctx.support < 1.0 else v

## Whether the support factor scales `o`'s value: every tile case but those
## that clear data 0x32088, which are an own town, a stack worth fighting
## less than nothing, and the paid dwellings other than the goblins' straw
## hut (0x72cbc keeps the flag).
static func _supported(o: MapObject, ctx: Ctx, v: float) -> bool:
	if o == null:
		return false
	if o is TownObject:
		return (o as TownObject).owner != ctx.ai.side
	if o is NeutralStack:
		return v >= 0.0
	if o is Dwelling:
		return (o as Dwelling).unit in (rules().get("supported_dwellings", []) as Array)
	return true

static func _value(o: MapObject, ctx: Ctx, raw: bool) -> float:
	if o == null or ctx.hero == null:
		return 0.0
	if o is TownObject:
		var town := _town_tile(o as TownObject, ctx)
		return town if raw else maxf(0.0, town)
	var gold := _worth(ctx, "gold")
	if o is ResourcePile:
		var pile := o as ResourcePile
		return 0.0 if pile.consumed else float(pile.amount) * _worth(ctx, pile.res)
	if o is ArtifactPickup:
		return _artifact_tile(o as ArtifactPickup, ctx)
	if o is Mine:
		return _mine(o as Mine, ctx)
	if o is DragonCity:
		return _dragon_city(o as DragonCity, ctx)
	if o is Dwelling:
		return maxf(0.0, recruit_value(o as Dwelling, ctx))
	if o is NeutralStack:
		return _monster(o as NeutralStack, ctx, raw)
	if o is GuardedPickup:
		return _guarded_site(o as GuardedPickup, ctx)
	if o is WeeklyPickup:
		return _mill(o as WeeklyPickup, ctx)
	if o is Shrine:
		return shrine_value(o as Shrine, ctx)
	if o.consumed:
		return 0.0
	var boosters: Dictionary = rules().get("boosters", {})
	if boosters.has(o.type):
		return 0.0 if o.was_visited_by(ctx.hero_id) else ctx.hero_weight * float(boosters[o.type])
	match o.type:
		"chest":
			return gold * float(rules().get("chest_gold", 1500))
		"campfire":
			var c: Dictionary = rules().get("campfire", {})
			var rare := 0.0
			for res: String in ["wood", "mercury", "ore", "sulfur", "crystal", "gems"]:
				rare += _worth(ctx, res)
			return rare / 6.0 * float(c.get("resources", 5)) + gold * float(c.get("gold", 500))
		"skeleton":
			# 0x72c4b: only a skeleton the map start gave a find (byte 9 = 2).
			if not o.visited_by.is_empty() or (o.artifact_assignment_resolved and not o.has_find):
				return 0.0
			return ctx.average_artifact * float(rules().get("skeleton_share", 0.1))
		"lighthouse":
			return 0.0 if o.owner == ctx.ai.side else float(rules().get("lighthouse", 1000))
		"obelisk":
			return obelisk_value(o, ctx)
	return 0.0

static func _artifact_tile(a: ArtifactPickup, ctx: Ctx) -> float:
	if not a.resolved or a.consumed or a.artifact_id == "" \
			or not ctx.hero.can_add_artifact(a.artifact_id):
		return 0.0
	var r: Dictionary = rules().get("artifact", {})
	var value := float(artifact_value(a.artifact_id))
	var guard := ArmyData.new()
	for i in int(r.get("guard_stacks", 5)):
		guard.add(String(r.get("guard_unit", "rogue")), int(r.get("guard_count", 10)), false)
	var fight := battle(ctx, ctx.hero.army, guard)
	var guarded := int(value * float(fight.p) + int(fight.value))
	var paid := maxi(0, int(value - float(r.get("price", 2000)) * _worth(ctx, "gold")))
	# 0x719e1..0x71aff: the encounter counts only once someone has visited the
	# cell (data 0x2f5d4); until then the computer expects the roll's mix.
	var mode := a.encounter_mode if not a.visited_by.is_empty() else ""
	match mode:
		"free":
			return value
		"guarded":
			return float(guarded)
		"paid":
			return float(paid)
	return float(int(value * float(r.get("free_share", 0.6))
			+ guarded * float(r.get("guarded_share", 0.2)) + paid * float(r.get("paid_share", 0.2))))

## Days of a site's income the computer expects to keep: fewer near other
## players' heroes (data 0x30a14, rebuilt each AI turn).
static func income_days(tile: Vector2i, ctx: Ctx) -> int:
	var m: Dictionary = rules().get("mine", {})
	var days := int(m.get("days", 7))
	if ctx.state == null:
		return days
	var box := int(m.get("box", 10))
	for p: PlayerState in ctx.state.players:
		if p.side == ctx.ai.side or not p.alive:
			continue
		for h: HeroModel in p.heroes:
			var d := h.tile - tile
			if absi(d.x) > box or absi(d.y) > box:
				continue
			days = mini(days, absi(absi(d.x) + absi(d.y) - int(m.get("offset", 4))) / int(m.get("divisor", 4)))
	return days

## 0x71c55: the owner multipliers of the computer's level (data 0x1e430/4,
## set each AI turn at 0x69a8d; 2.0 and 0.8 are only their initial values).
static func _owned_scale(owner: int, ctx: Ctx) -> float:
	var p: PlayerState = ctx.state.player_of(owner) if ctx.state != null and owner >= 0 else null
	if p == null:
		return 1.0
	return ctx.computer_mult if p.is_ai else ctx.human_mult

static func _hostile_owner(owner: int, ctx: Ctx) -> bool:
	if owner < 0:
		return true
	if owner == ctx.ai.side:
		return false
	var p: PlayerState = ctx.state.player_of(owner) if ctx.state != null else null
	return p == null or ctx.ai.is_hostile_to(p)

static func _mine(m: Mine, ctx: Ctx) -> float:
	if not _hostile_owner(m.owner, ctx):
		return 0.0
	var income := 0.0
	var yield_bag := m.daily_yield()
	for res: String in yield_bag:
		income += float(yield_bag[res]) * _worth(ctx, res)
	var value := income * income_days(m.action_tile, ctx) * _owned_scale(m.owner, ctx)
	# Ours: a mine carrying its own guard (hand-authored maps) is fought for.
	if m.is_armed():
		var fight := battle(ctx, ctx.hero.army, m.guard)
		value = value * float(fight.p) + float(fight.value)
	return maxf(0.0, value)

static func _dragon_city(dc: DragonCity, ctx: Ctx) -> float:
	if not _hostile_owner(dc.owner, ctx):
		return 0.0
	var r: Dictionary = rules().get("dragon_city", {})
	var income := income_days(dc.action_tile, ctx) * _worth(ctx, "gold") \
			* float(r.get("gold", 1000)) * float(r.get("factor", 1.5))
	if not dc.is_armed():
		return income
	var fight := battle(ctx, ctx.hero.army, dc.guard)
	return maxf(0.0, float(int(income * float(fight.p) + int(fight.value))))

## heroes.exe 0x74228: n creatures x rating x f9, less the price of paid ones
## at resource worth, less the weakest other stack when the army is full.
static func recruit_value(dw: Dwelling, ctx: Ctx) -> float:
	if dw.consumed or dw.available <= 0 or ctx.hero.army == null:
		return 0.0
	var paid := dw.cost > 0 or not dw.cost_resources.is_empty()
	# 0x74228 caps a paid dwelling at what the treasury affords; a full army
	# gives up its weakest stack below rather than zeroing the value.
	var n := dw.available
	if paid:
		var price := dw.cost_resources.duplicate()
		price["gold"] = dw.cost
		for r: String in price:
			if int(price[r]) > 0:
				var have := ctx.ai.gold() if r == "gold" else int(ctx.ai.resources.get(r, 0))
				n = mini(n, have / int(price[r]))
	if n <= 0:
		return 0.0
	var value := n * ArmyStrength.unit_power(dw.unit) * float(ctx.econ.get("f9", 1.0))
	if paid:
		var price := dw.cost_resources.duplicate()
		price["gold"] = dw.cost
		value -= n * AIBuyer.cost_eq(price, ctx.econ.get("worth", {}))
	if not ctx.hero.army.can_add(dw.unit):
		value -= _weakest_stack(ctx.hero.army)
	return value

static func _weakest_stack(army: ArmyData) -> float:
	var weakest := INF
	for s: Dictionary in army.slots:
		weakest = minf(weakest, float(s.count) * ArmyStrength.unit_power(String(s.unit)))
	return 0.0 if weakest == INF else weakest

## 0x71cc9: a stack that offers to join is worth 0.6 x the troops (when the
## army has room) + 0.4 x the fight; otherwise the fight alone.
static func _monster(stack: NeutralStack, ctx: Ctx, raw := false) -> float:
	if not stack.is_armed():
		return 0.0
	var fight := battle(ctx, ctx.hero.army, split_five(stack.army))
	var value := float(fight.value)
	if will_join(stack, ctx):
		var j: Dictionary = rules().get("monster_join", {})
		var unit := String(stack.army.slots[0].unit)
		var join := 0.0
		if ctx.hero.army.can_add(unit):
			join = stack.army.total() * ArmyStrength.unit_power(unit) * float(ctx.econ.get("f9", 1.0))
		value = float(int(join * float(j.get("join_share", 0.6)) + value * float(j.get("battle_share", 0.4))))
	return value if raw else maxf(0.0, value)

## 0x71cc9: a wandering stack fights as five, N / 5 each and the remainder
## one apiece from the first.
static func split_five(army: ArmyData) -> ArmyData:
	var out := ArmyData.new()
	if army == null or army.slots.is_empty():
		return out
	var unit := String(army.slots[0].unit)
	var total := army.total()
	for i in 5:
		var n := total / 5 + (1 if i < total % 5 else 0)
		if n > 0:
			out.add(unit, n, false)
	return out

## How sure the value is, 0..100: a fight's chance (P x 100, or P x 60 + 40
## for a stack that will join), 100 for anything else.
static func confidence(o: MapObject, ctx: Ctx) -> int:
	if o is NeutralStack and (o as NeutralStack).is_armed():
		var stack := o as NeutralStack
		var p := float(battle(ctx, ctx.hero.army, split_five(stack.army)).p)
		return int(p * 60.0 + 40.0) if will_join(stack, ctx) else int(p * 100.0)
	if o is TownObject:
		# The town case's confidence is the siege's P x 100 (1 when undefended).
		var fight := {}
		_town_tile(o as TownObject, ctx, fight)
		return int(float(fight.get("p", 1.0)) * 100.0)
	return 100

## 0x71cc9: the computer counts on a stack joining when it offers to (cell
## byte 9 bit 0x80) and the hero army's plain rating beats join_ratio x the
## stack's plain rating. Room in the army only decides
## whether the join is worth anything.
static func will_join(stack: NeutralStack, ctx: Ctx) -> bool:
	if not stack.joinable or stack.fought_before or stack.authored_fixed \
			or stack.army == null or stack.army.slots.is_empty() \
			or String(stack.army.slots[0].unit) == "ghost":
		return false
	var ratio := float((rules().get("monster_join", {}) as Dictionary).get("join_ratio", 1.75))
	# 0x71e65 rates the hero's army with 0x73d34 at ecx = 0: plain count x
	# rating, no size brackets and no hero skills (0x73eb9, 0x73f5c).
	return ArmyStrength.of(ctx.hero.army) > ArmyStrength.of(stack.army) * ratio

## A town tile: an own castle is a trip home, any other the siege.
static func _town_tile(town: TownObject, ctx: Ctx, fight_out: Variant = null) -> float:
	if town.owner == ctx.ai.side:
		# 0x723d8: an own town with a hero inside (town +0x15) is worth nothing.
		if ctx.hero.tile == town.action_tile:
			return 0.0
		for h: HeroModel in ctx.ai.heroes:
			if h.tile == town.action_tile:
				return 0.0
		return home_value(ctx.ai.town_by_object_id(town.id), ctx)
	if not _hostile_owner(town.owner, ctx):
		return 0.0
	var owner: PlayerState = ctx.state.player_of(town.owner) if ctx.state != null and town.owner >= 0 else null
	var model: TownModel = owner.town_by_object_id(town.id) if owner != null else null
	var defender: HeroModel = null
	if owner != null:
		for h: HeroModel in owner.heroes:
			if h.tile == town.action_tile:
				defender = h
	return town_value(town, model.army if model != null else town.garrison, defender, ctx, fight_out)

static func _guarded_site(gp: GuardedPickup, ctx: Ctx) -> float:
	if gp.looted:
		return 0.0
	if gp.type == "demon_cave":
		var d: Dictionary = rules().get("demon_cave", {})
		# 0x72751: the ransom outcome is worth -100 (0 in mode 0, after the
		# common exit) while the kingdom holds less gold than the demon asks.
		if gp.rolled_band >= 0 and gp.rolled_band < gp.outcomes.size():
			var ransom := int((gp.outcomes[gp.rolled_band] as Dictionary).get("ransom", 0))
			if ransom > 0 and ctx.ai.gold() < ransom:
				return float(d.get("broke", -100))
		return float(d.get("hero_weight", 700)) * ctx.hero_weight + ctx.average_artifact \
				+ float(d.get("gold", 1750)) * _worth(ctx, "gold")
	if gp.outcomes.is_empty():
		return 0.0
	var bands: Array = [gp.rolled_band] if gp.rolled_band >= 0 else range(gp.outcomes.size())
	var total := 0.0
	var weight := 0.0
	for band: int in bands:
		var outcome: Dictionary = gp.outcomes[band]
		var reward: Dictionary = outcome.get("reward", {})
		var prize := float(reward.get("gold", 0)) * _worth(ctx, "gold") \
				+ (ctx.average_artifact if reward.has("artifact") else 0)
		var fight := battle(ctx, ctx.hero.army, gp.guard_army_for(band))
		var w := 1.0 if bands.size() == 1 else float(outcome.get("p", 1.0))
		total += w * float(int(int(prize) * float(fight.p) + int(fight.value)))
		weight += w
	return maxf(0.0, total / maxf(weight, 0.0001))

static func _mill(wp: WeeklyPickup, ctx: Ctx) -> float:
	if ctx.state != null and wp.last_collected_week == (ctx.state.day - 1) / GameState.DAYS_PER_WEEK:
		return 0.0
	if wp.params.has("gold"):
		# The original counts the mill's gold in units of watermill_gold.
		var due := int(wp.params.get("gold", 1000))
		if wp.last_collected_week < 0 and ctx.state != null \
				and (ctx.state.day - 1) / GameState.DAYS_PER_WEEK == 0:
			due = int(wp.params.get("first_week_gold", due))
		var unit := int(rules().get("watermill_gold", 500))
		return float(due / unit * unit) * _worth(ctx, "gold")
	var pool: Array = wp.params.get("pool", [])
	if pool.is_empty():
		return 0.0
	# 0x72bad: 2 x the worth of this week's resource (cell byte 9).
	if wp.week_resource != "":
		return float(rules().get("windmill_amount", 2)) * _worth(ctx, wp.week_resource)
	var mean := 0.0
	for res: Variant in pool:
		mean += _worth(ctx, String(res))
	return float(rules().get("windmill_amount", 2)) * mean / pool.size()

## 0x728d7: what a shrine's spell adds, the spell's value (data 0x1f17c) x
## (charge curve at the hero's knowledge - at the charges he holds), and for
## spells that scale with power x the skill table at his knowledge. Nothing
## without a spell book or knowledge.
static func shrine_value(sh: Shrine, ctx: Ctx) -> float:
	var hero := ctx.hero
	var k := hero.effective_knowledge()
	if k <= 0 or not hero.has_spellbook or hero.spellbook == null or sh.spell_id == "":
		return 0.0
	var r: Dictionary = rules().get("rating", {})
	var extra: Dictionary = (rules().get("shrine", {}) as Dictionary).get("extra_values", {})
	var v := float((r.get("spell_values", {}) as Dictionary).get(sh.spell_id, extra.get(sh.spell_id, 0)))
	var curve: Array = r.get("charges", [])
	var held := hero.spellbook.charges(sh.spell_id) if hero.spellbook.spells.has(sh.spell_id) else 0
	var top := curve.size() - 1
	var value := int(v * (_f32(float(curve[mini(k, top)])) - _f32(float(curve[clampi(held, 0, top)]))))
	if sh.spell_id in (r.get("power_scaled", []) as Array):
		var skill: Array = r.get("skill", [])
		value = int(value * _f32(float(skill[mini(k, skill.size() - 1)])))
	return float(maxi(0, value))

## Player int +0xf1: what one more obelisk is worth, 0 once visited.
static func obelisk_value(o: MapObject, ctx: Ctx) -> float:
	if ctx.ai.puzzle_pieces.has(o.id) or ctx.map == null or ctx.map.ultimate_artifact.is_empty():
		return 0.0
	var r: Dictionary = rules().get("obelisk", {})
	var obelisks := Dig.count_obelisks(ctx.map)
	var pieces := int(r.get("pieces", 48))
	var seen := int(ctx.econ.get("obelisks_seen", ctx.ai.puzzle_pieces.size()))
	var revealed := seen * pieces / maxi(1, obelisks)
	var ultimate := artifact_value(String(ctx.map.ultimate_artifact.get("artifact", "")))
	var v := int(ultimate / int(r.get("divisor", 110)) * pieces / maxi(1, obelisks))
	v = int(v * (float(r.get("base", 1.5)) - absf(float(int(r.get("center", 32)) - revealed)) / pieces))
	return float(int(v * (float(ctx.econ.get("b5", 0.3)) + float(r.get("b5_offset", 0.66)))))

## A town the hero's player does not own: its worth x P + the siege.
## `fight`, when given, receives the battle's win chance as "p" (the tile
## case's confidence is P x 100).
static func town_value(town: TownObject, garrison: ArmyData, defender_hero: HeroModel,
		ctx: Ctx, fight_out: Variant = null) -> float:
	var worth := town_worth(town, ctx)
	var hero_army: ArmyData = defender_hero.army if defender_hero != null else null
	if (garrison == null or garrison.is_empty()) and (hero_army == null or hero_army.is_empty()):
		return worth
	var owner: PlayerState = ctx.state.player_of(town.owner) if ctx.state != null and town.owner >= 0 else null
	var model: TownModel = owner.town_by_object_id(town.id) if owner != null else null
	if model == null and town.owner < 0:
		model = town.neutral_model()
	var fight := battle(ctx, ctx.hero.army, garrison if garrison != null else ArmyData.new(),
			defender_hero, true, town.owner, true, model, hero_army)
	if fight_out != null:
		(fight_out as Dictionary)["p"] = float(fight.p)
	return float(int(worth * float(fight.p) + int(fight.value)))

## A town's worth to a conqueror: its buildings, a week and a half of gold,
## more when a player owns it.
static func town_worth(town: TownObject, ctx: Ctx) -> float:
	var t: Dictionary = rules().get("town", {})
	var worth := _base_worth(town, ctx)
	var owner: PlayerState = ctx.state.player_of(town.owner) if ctx.state != null and town.owner >= 0 else null
	if owner != null and owner.town_by_object_id(town.id) != null:
		var mult := ctx.computer_mult if owner.is_ai else ctx.human_mult
		worth *= mult * (float(t.get("owned_base", 0.9)) + float(t.get("owned_per_missing", 0.25))
				* (int(t.get("players_max", 5)) - ctx.players))
	return worth

## The town's buildings and a week and a half of gold, before any owner's
## multiplier (0x723a3 and 0x71fe1 both start from it).
static func _base_worth(town: TownObject, ctx: Ctx) -> float:
	var t: Dictionary = rules().get("town", {})
	var worth := float(t.get("gold", 1875)) * _worth(ctx, "gold") + float(t.get("extra", 750))
	var owner: PlayerState = ctx.state.player_of(town.owner) if ctx.state != null and town.owner >= 0 else null
	var model: TownModel = owner.town_by_object_id(town.id) if owner != null else null
	if model == null and town.owner < 0:
		model = town.neutral_model()
	if model != null:
		worth += _building_worth(model)
	return worth

static func _building_worth(model: TownModel) -> float:
	var b: Dictionary = AIBuyer.rules().get("buildings", {})
	var total := 0.0
	for id: String in model.built:
		var tier := BuildingCatalog.dwelling_ids(model.faction).find(id)
		if tier >= 0:
			total += float(((b.get("dwellings", {}) as Dictionary).get(model.faction, []) as Array)[tier])
		elif b.has(id) and not (b[id] is Array):
			total += float(b[id])
	var levels: Array = b.get("mage_guild", [])
	if model.mage_guild_level > 0 and model.mage_guild_level <= levels.size():
		total += float(levels[model.mage_guild_level - 1])
	return total

## Another player's hero: the fight, plus the town he holds (0x71f1e). `raw`
## is the planner's modes 1 and 2: a human's hero worth over 200 counts 1.5
## times, and the long-odds penalties are mode 0's (the potential's) only.
static func hero_value(target: HeroModel, side: int, in_town: TownObject, ctx: Ctx,
		raw := false, fight_out: Variant = null) -> float:
	var owner_model: PlayerState = ctx.state.player_of(side) if ctx.state != null and side >= 0 else null
	var held: TownModel = owner_model.town_by_object_id(in_town.id) if owner_model != null and in_town != null else null
	var fight := battle(ctx, ctx.hero.army, target.army, target, in_town != null, side, true, held)
	if fight_out != null:
		(fight_out as Dictionary)["p"] = float(fight.p)
	var value := float(fight.value)
	if in_town != null:
		var t: Dictionary = rules().get("town", {})
		var owner: PlayerState = ctx.state.player_of(side) if ctx.state != null else null
		var mult := ctx.computer_mult if owner != null and owner.is_ai else ctx.human_mult
		var worth := _base_worth(in_town, ctx)
		if owner != null:
			worth = float(int(worth * (1.0 + float(t.get("owned_per_missing", 0.25))
					* (int(t.get("players_max", 5)) - ctx.players) * mult)))
		value = float(int(worth * float(fight.p) + value))
	var p := float(fight.p)
	var odds: Dictionary = rules().get("hero_odds", {})
	if raw:
		var owner_state: PlayerState = ctx.state.player_of(side) if ctx.state != null and side >= 0 else null
		if owner_state != null and not owner_state.is_ai and value > float(odds.get("human_above", 200)):
			value = float(int(value * float(odds.get("human_factor", 1.5))))
		return value
	# Long odds are made worse still, so a weak hero keeps away.
	if p < float(odds.get("worse_below", 0.4)):
		value *= 3.0 - 2.0 * p
		if p < float(rules().get("hero_odds", {}).get("worst_below", 0.2)):
			value *= 2.0 - 2.0 * p
	return value

## heroes.exe 0x746d8 in evaluate mode: a trip to an own castle, worth what
## the rebalance would hand the hero.
static func home_value(town: TownModel, ctx: Ctx) -> float:
	if town == null or town.army == null or ctx.hero.army == null:
		return 0.0
	return float(guild_value(town, ctx.hero)) + _swap_value(town, ctx)

## 0x748dd..0x74a0d, the rebalance routine's evaluate mode: every spell the
## hero would learn in the town's Mage Guild, a spell book or not, worth its
## value (data 0x1f17c) x (charge curve at his knowledge - at the charges he
## holds), x his knowledge for spells that scale with power. Summed with a
## truncation after each spell, as the original accumulates into an int.
static func guild_value(town: TownModel, hero: HeroModel) -> int:
	if town.mage_guild_level <= 0 or town.guild_spells.is_empty():
		return 0
	var r: Dictionary = rules().get("rating", {})
	var values: Dictionary = r.get("spell_values", {})
	var scaled: Array = r.get("power_scaled", [])
	var curve: Array = r.get("charges", [])
	var top := curve.size() - 1
	var k := hero.effective_knowledge()
	var total := 0
	for lvl in mini(town.mage_guild_level, town.guild_spells.size()):
		for id: String in town.guild_spells[lvl]:
			var held := 0
			if hero.spellbook != null and hero.spellbook.spells.has(id):
				held = hero.spellbook.charges(id)
			if held >= k:
				continue
			var gain := _f32(float(curve[mini(k, top)])) - _f32(float(curve[clampi(held, 0, top)]))
			total = int(total + gain * float(values.get(id, 0)) * (k if id in scaled else 1))
	return total

## The troop swap's share of a trip home (0x74b21..0x74c2f).
static func _swap_value(town: TownModel, ctx: Ctx) -> float:
	var r: Dictionary = AIController.rules().get("castle_swap", {})
	var h: Dictionary = rules().get("home", {})
	var hero_str := ArmyStrength.of(ctx.hero.army)
	var town_str := ArmyStrength.of(town.army)
	var total := hero_str + town_str
	if total <= 0.0:
		return 0.0
	var share := town_str / total
	var k := mini(ctx.hero.effective_attack() + ctx.hero.effective_defense(), int(r.get("skill_cap", 10)))
	var target := float(r.get("castle_base", 0.54)) - float(r.get("castle_per_skill", 0.02)) * k \
			if town.has_castle else float(r.get("town_base", 0.33)) - float(r.get("town_per_skill", 0.01)) * k
	# Evaluate mode uses the plain gap; only an actual take adds take_bonus.
	var gap := absf(share - target)
	if gap < float(r.get("tolerance", 0.15)) * target:
		return 0.0
	var scale := float(h.get("weaker", 0.25)) if hero_str < town_str else float(h.get("stronger", 0.13))
	return maxf(0.0, float(int((pow(1.0 + gap + float(h.get("offset", -0.22)), 2.0) - 1.0)
			* float(ctx.econ.get("f9", 1.0)) * total * scale)))
