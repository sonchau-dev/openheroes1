# src/ai/ai_controller.gd
class_name AIController
extends RefCounted

## Adventure AI target choice. Stateless: every call re-scores the world, so
## map changes never leave stale plans. On land the original's move decision
## picks (AIPlanner, heroes.exe 0x693d4); at sea each target is worth its
## tile value (AITileValue, 0x71938) / (1 + path_len/15), ~15 tiles being a
## day's march. Buying is AIBuyer's.

const RULES_PATH := "res://data/ai/adventure_ai.json"

const DAY_TILES := 15.0   # roughly one day's march, the distance discount's scale
const TOWNLESS_VALUE := 10000.0  # a castle-less kingdom's castle target outranks everything

static var _rules: Dictionary = {}

static func rules() -> Dictionary:
	if _rules.is_empty():
		_rules = JsonFile.read_dict(RULES_PATH)
	return _rules

## Day-1 treasury of a computer player, as the DOS saves record it.
static func starting_resources() -> Dictionary:
	var out: Dictionary = {}
	var table: Dictionary = rules().get("starting_resources", {})
	for k: String in table:
		if not k.begins_with("_"):
			out[k] = int(table[k])
	return out

## heroes.exe 0x746d8: a computer hero in a castle of its own rebalances its
## army with the garrison (constants and rules in data/ai/adventure_ai.json
## "castle_swap"). Moves stacks in place and returns the strength that moved,
## positive toward the hero, negative toward the garrison.
##
## `gate` stands in for a register the routine never sets before its leave
## check (0x74cf7: a leaving hero stops when esi <= 1). The buy passes its town
## loop index (0x675b6, 0x68b7a), so a hero never leaves troops in a player's
## first two towns at buy time; the town arrival (0x75b1b) passes a pointer, so
## it always may. After each stack esi holds the garrison slot the stack merged
## into, or 5 when it matched none, so a merge into slot 0 or 1 ends the leave.
static func castle_swap(hero_army: ArmyData, attack: int, defense: int,
		garrison: ArmyData, has_castle: bool, gate := 2) -> int:
	if hero_army == null or garrison == null:
		return 0
	var r: Dictionary = rules().get("castle_swap", {})
	var hero_str := int(ArmyStrength.of(hero_army))
	var town_str := int(ArmyStrength.of(garrison))
	var total := hero_str + town_str
	if total <= 0:
		return 0
	var share := float(town_str) / float(total)
	var k := mini(attack + defense, int(r.get("skill_cap", 10)))
	var target := float(r.get("castle_base", 0.0)) - float(r.get("castle_per_skill", 0.0)) * k \
			if has_castle else float(r.get("town_base", 0.0)) - float(r.get("town_per_skill", 0.0)) * k
	var gap := absf(share - target)
	if gap < float(r.get("tolerance", 0.0)) * target:
		return 0
	var take := target < share
	if take:
		gap += float(r.get("take_bonus", 0.0))
	var left := int(float(total) * gap)
	var source := garrison if take else hero_army
	var dest := hero_army if take else garrison
	var source_str := town_str if take else hero_str
	var moved_str := 0
	while true:
		if not take and gate <= 1:
			break
		var i := _swap_pick(source, dest, take)
		if i < 0:
			break
		var unit := String(source.slots[i].unit)
		var count := int(source.slots[i].count)
		gate = 5
		for j in dest.slots.size():
			if String(dest.slots[j].unit) == unit:
				gate = int(dest.slots[j].get("col", j))
				break
		if not dest.can_add(unit):
			break
		var rating := ArmyStrength.unit_power(unit)
		var n := int(float(left) / rating + float(r.get("round_bias", 0.5)))
		if n <= 0:
			break
		if count < n:
			n = count
		elif n >= count * float(r.get("whole_stack_share", 1.0)) or n >= count - 1:
			if float(source_str - left) * float(r.get("remnant_factor", 0.0)) > (count - n) * rating:
				n = count
		var more := true
		if not take and n >= hero_army.total():
			n = hero_army.total() - 1
			more = false
		var stack_str := int(n * rating)
		if left >= stack_str * float(r.get("overshoot", 1.0)):
			left -= stack_str
		else:
			more = false
		if n > 0:
			dest.add(unit, n)
			source.slots[i].count = count - n
			if count - n <= 0:
				source.slots.remove_at(i)
			moved_str += stack_str
		if not more:
			break
	return moved_str if take else -moved_str

## heroes.exe 0x74875..0x74a12, the rebalance routine's act mode before the
## swap: in a castle with a Mage Guild, a hero with knowledge and no spell
## book buys one for 500 gold, and a hero with a book learns the guild's
## spells. False when the treasury cannot pay for the book; the original
## then ends the hero's movement for the day (0x748d7).
static func castle_guild(hero: HeroModel, town: TownModel) -> bool:
	if hero == null or town == null or town.mage_guild_level <= 0:
		return true
	if hero.effective_knowledge() > 0 and not hero.has_spellbook \
			and hero.can_add_artifact("spell_book"):
		if town.gold < town.SPELLBOOK_COST:
			return false
		town.gold -= town.SPELLBOOK_COST
		hero.add_artifact("spell_book")
	town.teach_visiting_hero(hero)
	return true

## The next stack to move: the first whose creature is already on the other
## side; otherwise the slowest (leaving) or fastest (taking), the stronger on
## a tie. -1 when the source is empty.
static func _swap_pick(source: ArmyData, dest: ArmyData, take: bool) -> int:
	for i in source.slots.size():
		if dest.count_of(String(source.slots[i].unit)) > 0:
			return i
	var pick := -1
	var best_speed := 1 if take else 3
	var best_str := -9999.0
	for i in source.slots.size():
		var unit := String(source.slots[i].unit)
		var speed := _speed(unit)
		var stack_str := float(source.slots[i].count) * ArmyStrength.unit_power(unit)
		if (take and speed > best_speed) or (not take and speed < best_speed) \
				or (speed == best_speed and stack_str > best_str):
			pick = i
			best_speed = speed
			best_str = stack_str
	return pick

static func pick_target(ai: PlayerState, map: MapData, astar: PassabilityGrid, from: Vector2i, ctx: Dictionary, planner: AIPlanner.Plan = null) -> Dictionary:
	var hero := ai.active()
	var naval_state: GameState = ctx.get("game_state") as GameState
	var travel_mode: StringName = hero.travel_mode if hero != null else &"land"
	var carried_boat := hero.carried_boat_id if hero != null else -1
	var hero_class := hero.hero_class if hero != null else ""
	if ai.towns.is_empty():
		# Only the townless search walks routes, so only it pays for the field.
		var land_field := Pathfinder.build_land_field(astar, from, hero_class) \
				if travel_mode == &"land" else {}
		var castle := _townless_target(map, astar, from, ctx, naval_state,
				travel_mode, carried_boat, hero_class, land_field)
		if not castle.is_empty():
			return castle
	if hero == null:
		return {}
	# The original's move decision chooses (AIPlanner), on land and at sea;
	# the dig guess is one of its candidates.
	return AIPlanner.plan(ai, map, astar, from, ctx, planner)

## The turn's economy snapshot when the caller has none (tests, tools).
static func economy_of(ai: PlayerState, map: MapData, state: GameState) -> Dictionary:
	var day := state.day if state != null else 1
	return AIBuyer.economy(ai, AIBuyer.income_of(ai, map.objects if map != null else [], day), day)

## bugs.md 25.2 item 1: a kingdom without a castle goes for one whatever the
## odds, the weakest within castle_reach_days or else the nearest, taking an
## ownerless resource pile within detour_tiles first. {} when no castle is
## reachable, so the ordinary scoring runs instead.
static func _townless_target(map: MapData, astar: PassabilityGrid, from: Vector2i,
		ctx: Dictionary, state: GameState, mode: StringName, carried: int,
		hero_class: String, land_field: Dictionary) -> Dictionary:
	var townless: Dictionary = rules().get("townless", {})
	var detour := int(townless.get("detour_tiles", 0))
	var pile := {}
	for o: MapObject in map.objects:
		if o is ResourcePile and not o.consumed:
			var steps := _path_to(astar, map, from, o.action_tile, state, mode,
					carried, hero_class, land_field).size() - 1
			if steps >= 1 and steps <= detour and steps < int(pile.get("steps", 1 << 30)):
				pile = {"tile": o.action_tile, "kind": "resource", "object": o,
						"score": TOWNLESS_VALUE, "steps": steps}
	if not pile.is_empty():
		return pile
	var castles: Array = []
	for hostile: Dictionary in ctx.get("hostile_towns", []):
		castles.append({"tile": hostile.tile, "kind": String(hostile.get("kind", "enemy_town")),
				"object": hostile.object, "side": int(hostile.side),
				"strength": float(hostile.get("strength", 0.0))})
	var reach := float(townless.get("castle_reach_days", 0)) * DAY_TILES
	var nearest := {}
	var weakest_in_reach := {}
	for c: Dictionary in castles:
		var steps := _path_to(astar, map, from, c.tile, state, mode, carried,
				hero_class, land_field).size() - 1
		if steps < 1:
			continue
		c["steps"] = steps
		if nearest.is_empty() or steps < int(nearest.steps):
			nearest = c
		if float(steps) <= reach and (weakest_in_reach.is_empty() \
				or float(c.strength) < float(weakest_in_reach.strength) \
				or (is_equal_approx(float(c.strength), float(weakest_in_reach.strength)) \
					and steps < int(weakest_in_reach.steps))):
			weakest_in_reach = c
	var pick := weakest_in_reach if not weakest_in_reach.is_empty() else nearest
	if pick.is_empty():
		return {}
	var target := {"tile": pick.tile, "kind": pick.kind, "object": pick.object,
			"score": TOWNLESS_VALUE}
	if pick.has("side"):
		target["side"] = pick.side
	return target

## heroes.exe 0x6e950 against a neutral stack: the attacker's win chance P
## and its expected loss in plain rating (count x rating). The original's
## count brackets and hero skill terms (0x73d34) are not ported.
static func battle_estimate(attacker: ArmyData, defender: ArmyData, ai_level: int) -> Dictionary:
	var b: Dictionary = rules().get("battle_estimate", {})
	var a0 := ArmyStrength.of(attacker)
	var d0 := ArmyStrength.of(defender)
	var am := maxf(1.0, a0 * (float(b.get("neutral_base", 0.7)) + float(b.get("neutral_per_level", 0.15)) * ai_level))
	var dm := maxf(1.0, d0)
	var p := win_chance(am, dm)
	var out1 := int((1.0 - p) * a0)
	return {"p": p, "own_loss": int(a0 * (1.0 - p) + out1 * p)}

## 0x6e950's P from the modified ratings: Am^e / (Am^e + Dm^e), then the
## pessimism rows.
static func win_chance(am: float, dm: float) -> float:
	var b: Dictionary = rules().get("battle_estimate", {})
	am = maxf(1.0, am)
	dm = maxf(1.0, dm)
	var large := float(b.get("large", 1000000.0))
	var e := float(b.get("exponent_large", 2.0)) if am > large or dm > large else float(b.get("exponent", 2.75))
	var p := pow(am, e) / (pow(am, e) + pow(dm, e))
	for row: Dictionary in b.get("pessimism", []):
		if p < float(row.get("below", 0.0)):
			return float(row.set) if row.has("set") else p + float(row.get("add", 0.0))
	return p

## Route from `from` to `tile` over land, or by sea when the hero can sail
## there; [] when unreachable.
static func _path_to(astar: PassabilityGrid, map: MapData, from: Vector2i,
		tile: Vector2i, state: GameState, mode: StringName, carried: int,
		hero_class: String, land_field: Dictionary) -> Array:
	var path := Pathfinder.path_from_field(land_field, tile) \
			if not land_field.is_empty() else Pathfinder.find(
					astar, from, tile, map, hero_class)
	if path.size() < 2 and state != null \
			and (mode == &"sea" or carried >= 0 or not state.boats.is_empty()):
		var plan := NavalPlanner.find(astar, map, state, from, tile, mode,
				carried, hero_class)
		if plan.size() >= 2:
			path = plan
	return path

static func _speed(unit: String) -> int:
	return int(CreatureCatalog.stats(unit).get("speed", 0))

static func _game() -> Node:
	var ml := Engine.get_main_loop() as SceneTree
	return ml.root.get_node_or_null("Game") if ml != null and ml.root != null else null
