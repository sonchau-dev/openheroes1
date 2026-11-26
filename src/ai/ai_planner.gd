# src/ai/ai_planner.gd
class_name AIPlanner
extends RefCounted

## Where a computer hero goes next: heroes.exe 0x693d4's move decision. Every
## tile the hero can reach in about two days is a candidate (grid points,
## interactive tiles, the dig guess, and towns and heroes further out); each
## scores a route value
##   RV = trunc(V / (f + 0.2)) + trunc(2 x P / (f + 1))
## where V is what the tile and the way there are worth, P the location
## potential (what lies around the tile, 0x73410) and f the days of travel.
## Constants live in data/ai/planner.json; tile values come from
## AITileValue. Decode: data/knowledge_base/research/ai-planner-decodes.md.

const RULES_PATH := "res://data/ai/planner.json"

static var _rules: Dictionary = {}

static func rules() -> Dictionary:
	if _rules.is_empty():
		_rules = JsonFile.read_dict(RULES_PATH)
	return _rules

## One decision's world: what stands where, and the caches.
class Plan:
	var ai: PlayerState
	var hero: HeroModel
	var tv: AITileValue.Ctx
	var map: MapData
	var grid: PassabilityGrid
	## grid.guard_zones() read once: guard state holds for the whole plan.
	var zones: Dictionary = {}
	var state: GameState
	var max_move := 60
	## action tile -> live MapObject
	var objects_at: Dictionary = {}
	## tile -> [HeroModel, side] for every hero on the map but the planner's own
	var heroes_at: Dictionary = {}
	## tile -> BoatState for every free boat (cell class 190 at run time)
	var boats_at: Dictionary = {}
	## the hero sails (hero +0xae bit 0x80)
	var at_sea := false
	var values: Dictionary = {}
	var potentials: Dictionary = {}
	## Mode-1 potentials (the night stop's), by tile.
	var camps: Dictionary = {}
	var object_cells: Dictionary = {}
	## The hero's movement left (hero +0x27), for the night stop; -1 for none.
	var move_left := -1
	var roll: Callable
	var field: Dictionary = {}
	## data 0x1e454: liths count 0 while a lith is being valued.
	var lith_busy := false
	var lith_values: Dictionary = {}
	## The nearest coastal castle, recorded as own towns are valued
	## (0x31e8c..0x31e8f): its distance from the hero, whether any was found
	## and whether the recorded one has a shipyard.
	var coast_town: TownObject = null
	var coast_dist := 0
	var coast_found := false
	var coast_shipyard := false
	## A free boat was valued (0x31e90).
	var boat_seen := false

static func _level(ai: PlayerState) -> int:
	return clampi(ai.ai_level if ai.ai_level > 0 else 2, 1, 4)

## Steps a hero walks before it plans again.
static func step_count(ai: PlayerState, hero: HeroModel) -> int:
	var s: Dictionary = rules().get("steps", {})
	var base := int(s.get("sea", 15)) if hero.travel_mode == &"sea" else int(s.get("land", 5))
	return maxi(1, int(base * (float(s.get("base", 1.7)) - float(s.get("per_level", 0.1)) * _level(ai))))

## [budget B, grid step g] for the hero standing on `from`.
static func budget(ai: PlayerState, map: MapData, from: Vector2i, max_move: int) -> Array:
	var b: Dictionary = rules().get("budget", {})
	var g: Dictionary = rules().get("grid", {})
	var value := int((max_move + int(b.get("offset", 42)))
			* ((_level(ai) - 1) * float(b.get("per_level", 0.06)) + float(b.get("base", 0.8))))
	var step := max_move / int(g.get("divisor", 6))
	var terrain := map.terrain_at(from) if map != null else ""
	if terrain in (b.get("rough_terrain", []) as Array):
		value = int(value * float(b.get("rough", 1.25)))
		step -= 1
	elif terrain in (b.get("desert_terrain", []) as Array):
		value = int(value * float(b.get("desert", 1.5)))
		step -= 2
	return [value, maxi(int(g.get("minimum", 3)), step)]

static func make(ai: PlayerState, map: MapData, grid: PassabilityGrid, ctx: Dictionary) -> Plan:
	var p := Plan.new()
	p.ai = ai
	p.hero = ai.active()
	p.map = map
	p.grid = grid
	p.zones = grid.guard_zones()
	p.state = ctx.get("game_state") as GameState
	var econ: Dictionary = ctx.get("economy", {})
	if econ.is_empty():
		econ = AIController.economy_of(ai, map, p.state)
	p.tv = AITileValue.context(ai, p.hero, map, p.state, econ)
	if p.state == null:
		p.state = p.tv.state
	# Hero +0x25 is set when the turn starts: a recruit or an artifact during the
	# turn changes it only the next day (the 2026-11-02 KB.LOG).
	p.max_move = int(ctx["max_move"]) if ctx.has("max_move") \
			else Hero.calculate_model_max_move(p.hero, map.objects, ai.side, ai.ai_level)
	p.roll = ctx.get("roll", func(lo: int, hi: int) -> int: return randi_range(lo, hi))
	p.at_sea = p.hero.travel_mode == &"sea"
	p.move_left = int(ctx.get("move_left", -1))
	for o: MapObject in map.objects:
		if o.consumed:
			continue
		for t: Vector2i in o.interaction_tiles():
			p.objects_at[t] = o
	_collect_heroes(p)
	p.tv.support = float(ctx["support"]) if ctx.has("support") else support_factor(p, p.hero.tile)
	p.tv.strong = float(ctx["strong"]) if ctx.has("strong") else strong_factor(p)
	# The tile value (data 0x2cd0c) and potential (0x2a48c) caches last the
	# hero's whole turn (see turn_factors and forget_near).
	p.values = ctx.get("tile_cache", p.values)
	p.potentials = ctx.get("pot_cache", p.potentials)
	return p

## After a visit, heroes.exe (0x6bbf7 -> 0x66f88) forgets the cached tile
## value at the hero's planned target and the potentials within Manhattan
## distance 10 of it; everything else, a cell grabbed on the way included,
## keeps its value until the next hero is picked.
static func forget_near(factors: Dictionary, target: Vector2i) -> void:
	if target == Vector2i(-1, -1):
		return
	(factors.get("tile_cache", {}) as Dictionary).erase(target)
	var pots: Dictionary = factors.get("pot_cache", {})
	for t: Vector2i in pots.keys():
		if absi(t.x - target.x) + absi(t.y - target.y) < 10:
			pots.erase(t)

## {"support", "strong"} for the active hero. heroes.exe sets both once, when
## it picks the hero to move (0x69fcd..0x6a44c); every plan of that hero's
## turn reuses them (the re-plan jumps back to 0x6a5e6), so recruits and
## fights later in the turn do not change them. Merge into the plans' ctx.
static func turn_factors(ai: PlayerState, map: MapData, grid: PassabilityGrid,
		ctx: Dictionary) -> Dictionary:
	var p := make(ai, map, grid, ctx)
	# 0x6a4cd clears both caches when the hero is picked.
	return {"support": p.tv.support, "strong": p.tv.strong, "tile_cache": {}, "pot_cache": {}}

static func _collect_heroes(p: Plan) -> void:
	if p.state != null:
		for other: PlayerState in p.state.players:
			if not other.alive:
				continue
			for h: HeroModel in other.heroes:
				if h != p.hero and h.tile != Vector2i(-1, -1):
					p.heroes_at[h.tile] = [h, other.side]
		for boat: BoatState in p.state.boats:
			p.boats_at[boat.tile] = boat

## 0x69fcd..0x6a2c6, when the hero is picked: tile values shrink when it has
## both strong own towns and strong enemies within reach, so a weak hero by a
## well-garrisoned castle stays near it. A sums the own towns whose garrison
## beats twice the hero's army, B the other towns and heroes that beat half
## of it, each weighed by how soon the hero gets there; with both above 1 the
## factor is 3 / (A + 2 + B), else 1. A hero's cell is a hero's (class 0xbd)
## even in a town. Constants: planner.json "support".
static func support_factor(p: Plan, from: Vector2i) -> float:
	if p.hero == null or p.hero.army == null or not p.grid.is_in_boundsv(from):
		return 1.0
	var r: Dictionary = rules().get("support", {})
	var s := maxf(float(r.get("minimum", 100)), ArmyStrength.of(p.hero.army))
	var own_bar := s * float(r.get("own_ratio", 2.0))
	var enemy_bar := s * float(r.get("enemy_ratio", 0.5))
	var own_offset := int(r.get("own_offset", 10))
	var enemy_offset := int(r.get("enemy_offset", 30))
	var reach := p.max_move * int(r.get("reach", 4))
	var field := Pathfinder.build_sea_field(p.grid, from, p.hero.hero_class, reach,
			p.boats_at, p.heroes_at) if p.at_sea else Pathfinder.build_land_field(p.grid, from, p.hero.hero_class,
			-1, -1, null, reach, p.boats_at)
	var w := p.map.width
	var a := 0.0
	var b := 0.0
	for flat: int in field.get("costs", {}):
		var t := Vector2i(flat % w, flat / w)
		if t == from:
			continue
		var cost := int(field.costs[flat])
		var there: Array = p.heroes_at.get(t, [])
		if not there.is_empty():
			if int(there[1]) != p.ai.side:
				var rating := ArmyStrength.of((there[0] as HeroModel).army)
				if rating > enemy_bar:
					b += (rating / enemy_bar - 1.0) * (p.max_move + enemy_offset) / (cost + enemy_offset)
			continue
		var town := p.objects_at.get(t) as TownObject
		if town == null:
			continue
		var g := ArmyStrength.of(_garrison(p, town))
		if town.owner == p.ai.side:
			if g > own_bar:
				a += (g / own_bar - 1.0) * (p.max_move + own_offset) / (cost + own_offset)
		elif g > enemy_bar:
			b += (g / enemy_bar - 1.0) * (p.max_move + enemy_offset) / (cost + enemy_offset)
	if a <= 1.0 or b <= 1.0:
		return 1.0
	return float(r.get("numerator", 3.0)) / (a + float(r.get("offset", 2.0)) + b)

## 0x6a2cc..0x6a44c: a hero rated at least `rating` (army with his skills,
## 0x73d34) that no other player's town (siege-rated garrison) or hero (army
## x hero_weight) outrates scales tile values by best of them x share /
## his rating, so he stops collecting and goes for them. Neutral towns do not
## count. 1 when the hero is weaker, any enemy stronger, or none exists.
## Constants: planner.json "strong".
static func strong_factor(p: Plan) -> float:
	if p.hero == null or p.hero.army == null:
		return 1.0
	var r: Dictionary = rules().get("strong", {})
	var s := maxf(float(r.get("minimum", 100)), float(AITileValue.army_rating(p.hero.army, p.hero)))
	if s < float(r.get("rating", 30000)):
		return 1.0
	var best := 0.0
	for o: MapObject in p.map.objects:
		var town := o as TownObject
		if town == null or town.owner < 0 or town.owner == p.ai.side or p.heroes_at.has(town.action_tile):
			continue
		var model := _town_model(p, town)
		var g := float(AITileValue.army_rating(_garrison(p, town), null, model))
		if g > s:
			return 1.0
		best = maxf(best, g)
	for t: Vector2i in p.heroes_at:
		var there: Array = p.heroes_at[t]
		if int(there[1]) == p.ai.side:
			continue
		var gate := p.map.own_town_gate_at(t, int(there[1]))
		var h := float(AITileValue.army_rating((there[0] as HeroModel).army, null,
				_town_model(p, gate) if gate != null else null)) * float(r.get("hero_weight", 2.0))
		if h > s:
			return 1.0
		best = maxf(best, h)
	if best <= 0.0:
		return 1.0
	return best * float(r.get("share", 0.75)) / s

static func _town_model(p: Plan, town: TownObject) -> TownModel:
	var owner: PlayerState = p.state.player_of(town.owner) if p.state != null and town.owner >= 0 else null
	return owner.town_by_object_id(town.id) if owner != null else null

static func _garrison(p: Plan, town: TownObject) -> ArmyData:
	var model := _town_model(p, town)
	return model.army if model != null else town.garrison

## The decision: the best candidate as a pick_target target, {} for none.
static func plan(ai: PlayerState, map: MapData, grid: PassabilityGrid, from: Vector2i,
		ctx: Dictionary, planner: Plan = null) -> Dictionary:
	if ai.active() == null:
		return {}
	var p: Plan = planner if planner != null else make(ai, map, grid, ctx)
	var best := {}
	for c: Dictionary in score_all(p, from):
		if best.is_empty() or ranks_before(c, best, from):
			best = c
	var naval := naval_fallback(p, int(best.rv) if not best.is_empty() else -1)
	if naval.has("tile"):
		best = naval
	# The hero walks to the best whatever it scores (0x6b13d onward), so with
	# nothing worth a step it heads for the -100 fallback cell.
	if best.is_empty():
		return {}
	p.hero.planned_dest = best.tile
	var target := _target(p, best)
	if naval.has("buy"):
		target["naval_buy"] = true
	if best.has("path"):
		if best.get("guard") != null:
			var guard := best.guard as NeutralStack
			var guard_route := Pathfinder.guarded_path(p.field, guard.action_tile)
			if not guard_route.is_empty() and guard_route.has("path"):
				target["path"] = guard_route.path
		else:
			target["path"] = best.path
	return target

## Whether candidate `a` beats `b` (0x6afaa..0x6b06c): the scan runs x-major
## and only a higher RV replaces the best, except that on RV 0 the tile
## farther from the hero (|dx| + |dy|) wins.
static func ranks_before(a: Dictionary, b: Dictionary, from: Vector2i) -> bool:
	if int(a.rv) != int(b.rv):
		return int(a.rv) > int(b.rv)
	var at: Vector2i = a.tile
	var bt: Vector2i = b.tile
	if int(a.rv) == 0:
		var da := absi(at.x - from.x) + absi(at.y - from.y)
		var db := absi(bt.x - from.x) + absi(bt.y - from.y)
		if da != db:
			return da > db
	return at.x < bt.x or (at.x == bt.x and at.y < bt.y)

## 0x6b13d..0x6b26c: a hero with nothing worth 75 heads for the coastal
## castle the valuation recorded and asks for a shipyard and a boat there.
## Returns the candidate to use instead ({} for none), with "buy" set when
## the original runs a buy at this point.
static func naval_fallback(p: Plan, best_rv: int) -> Dictionary:
	var r: Dictionary = rules().get("naval_fallback", {})
	var day := p.state.day if p.state != null else 1
	if best_rv >= int(r.get("below", 75)) or p.coast_town == null \
			or not (p.coast_found or p.coast_shipyard) or p.boat_seen \
			or day <= int(r.get("after_day", 3)):
		return {}
	var town := p.coast_town
	if not p.coast_shipyard and p.ai.naval_shipyard_town >= 0 \
			and p.ai.naval_shipyard_town != town.id:
		return {"buy": true}
	var income: Dictionary = p.tv.econ.get("income", {}) if p.tv != null else {}
	var wood := int(p.ai.resources.get("wood", 0)) \
			+ int(r.get("wood_days", 6)) * int(income.get("wood", 0))
	if wood < int(r.get("wood_shipyard", 10) if p.coast_shipyard else r.get("wood_coast", 30)):
		return {"buy": true}
	if not p.coast_shipyard:
		p.ai.naval_shipyard_town = town.id
	p.ai.naval_boat_town = town.id
	p.ai.naval_request_day = day
	return {"tile": town.action_tile, "rv": int(r.get("rv", 123)), "guard": null, "buy": true}

## Every candidate with its route value, [{tile, rv, guard, cost}], in the
## route field's order.
static func score_all(p: Plan, from: Vector2i) -> Array:
	var bg := budget(p.ai, p.map, from, p.max_move)
	var b := int(bg[0])
	var step := int(bg[1])
	var br: Dictionary = rules().get("budget", {})
	var armed: Dictionary = {}
	for o: MapObject in p.map.objects:
		if o is NeutralStack and (o as NeutralStack).is_armed():
			armed[o] = true
	var field := Pathfinder.build_sea_field(p.grid, from, p.hero.hero_class,
			b * int(br.get("search", 3)), p.boats_at, p.heroes_at) if p.at_sea \
			else Pathfinder.build_guarded_field(p.grid, from, p.hero.hero_class,
			func(stack: NeutralStack) -> bool: return armed.has(stack),
			b * int(br.get("search", 3)), p.boats_at, p.move_left, p.heroes_at, route_ends)
	p.field = field
	var out: Array = []
	if field.is_empty():
		return out
	var w := p.map.width
	var n := int(field.tiles)
	var seen: Dictionary = {}
	# Every reached cell that is no candidate scores -100 (0x6af40); with the
	# x-major scan only the first of them can win.
	var fallback := Vector2i(-1, -1)
	var fallback_cost := 0
	for state: int in field.costs:
		var flat := state % n
		if seen.has(flat):
			continue
		seen[flat] = true
		var tile := Vector2i(flat % w, flat / w)
		if tile == from:
			continue
		# The route that passes no monster wins whenever there is one (0x877e8).
		var direct := int(field.costs.get(flat, -1))
		var cost := direct if direct >= 0 else int(field.costs.get(n + flat, -1))
		if not _candidate(p, tile, cost, b, step):
			# shortcut: the planned destination's -150 is never the best, so it is skipped here.
			if tile != p.hero.planned_dest and (fallback.x < 0 or tile.x < fallback.x
					or (tile.x == fallback.x and tile.y < fallback.y)):
				fallback = tile
				fallback_cost = cost
			continue
		var route := Pathfinder.guarded_path(field, tile)
		if route.is_empty():
			continue
		var guard := route.guard as NeutralStack
		out.append({"tile": tile, "guard": guard, "cost": cost,
				"night": route.get("night", Vector2i(-1, -1)),
				"rv": route_value(p, from, tile, cost, guard, route.get("night", Vector2i(-1, -1))),
				"path": route.path})
	if fallback.x >= 0:
		var back := Pathfinder.guarded_path(field, fallback)
		if not back.is_empty():
			out.append({"tile": fallback, "guard": back.guard, "cost": fallback_cost,
					"night": back.get("night", Vector2i(-1, -1)), "rv": int(rules().get("unsuitable", -100)),
					"path": back.path, "fallback": true})
	return out

## 0x86ed0: the object classes that end a planning route (resources, towns,
## chests, campfires, the genie lamp, artifacts, signs, buoys, skeletons,
## fountains, obelisks, statues); a route walks on through the others.
static func route_ends(o: MapObject) -> bool:
	if o is Dwelling and (o as Dwelling).unit == "genie":
		return true
	return o.type in (rules().get("route_ends", []) as Array)

## Whether `tile` holds something the planner values (cell B8 bit 0x80): an
## object, a hero, or a free boat.
static func _interactive(p: Plan, tile: Vector2i) -> bool:
	return p.objects_at.has(tile) or p.heroes_at.has(tile) or p.boats_at.has(tile)

## 0x6a82c, 0x6b0b5..: which reached tiles are scored. At sea every landing
## cell within the budget counts too (the coast class, B8 & 0x1f == 0x1f).
static func _candidate(p: Plan, tile: Vector2i, cost: int, b: int, step: int) -> bool:
	if cost <= b:
		if _interactive(p, tile) or tile == p.ai.dig_tile:
			return true
		if p.at_sea and p.map.is_land(tile):
			return true
		if tile.x % step == 0 and tile.y % step == 0:
			return p.map.is_water(tile) == p.at_sea
		return false
	if cost <= b * int((rules().get("budget", {}) as Dictionary).get("far", 2)):
		return p.heroes_at.has(tile) or p.objects_at.get(tile) is TownObject \
				or (not p.at_sea and p.boats_at.has(tile))
	return false

## The route value of `tile`, reached at `cost`, past `guard` (or null),
## stopping for the night on `night` (none when -1).
## `parts`, when given, receives the terms before noise (the KB.LOG replay
## compares them with the original's per-candidate log).
static func route_value(p: Plan, from: Vector2i, tile: Vector2i, cost: int,
		guard: NeutralStack, night := Vector2i(-1, -1), parts: Variant = null) -> int:
	var r: Dictionary = rules().get("route_value", {})
	var hero_there: Array = p.heroes_at.get(tile, [])
	# heroes.exe 0x6a902..0x6a96f: if another living teammate hero already targets
	# this tile, it scores teammate (-2000), unless the cell is a town's (class
	# 0xa8) or holds a hero (0xbd), a teammate standing on his target included.
	var obj_here: MapObject = p.objects_at.get(tile)
	if not (obj_here is TownObject) and hero_there.is_empty():
		if p.ai != null:
			for other: HeroModel in p.ai.heroes:
				if other != p.hero and other.tile != Vector2i(-1, -1) and other.planned_dest != Vector2i(-1, -1):
					if other.planned_dest == tile or (obj_here != null and (other.planned_dest == obj_here.tile or obj_here.interaction_tiles().has(other.planned_dest))):
						return int(r.get("teammate", -2000))
	# V: the stack fought on the way, and a stack whose cell this is.
	var v := 0
	var conf_way := 100
	if guard != null:
		v = int(AITileValue.value(guard, p.tv, true))
		conf_way = AITileValue.confidence(guard, p.tv)
	# Where the hero spends the night (0x6ab0a): the heroes around it count
	# when they make it a bad place, and doubt about them lowers T and P.
	var conf_night := 100
	if night.x >= 0:
		var camp := potential(p, night, true)
		if int(camp[0]) < 0:
			v += int(camp[0])
		conf_night = int(camp[1])
	# A monster guarding the cell, unless the cell holds a walk-on object;
	# 0x6ab68 asks 0x84138 with no exclusion, so the stack passed on the way
	# counts again when it guards the cell too.
	var here: MapObject = p.objects_at.get(tile)
	var near: NeutralStack = p.zones.get(tile)
	if near != null and here != near \
			and not (here != null and here.type in (r.get("zone_skip_types", []) as Array)):
		var nv := int(AITileValue.value(near, p.tv, true))
		if nv < 0:
			v += nv
		var nc := AITileValue.confidence(near, p.tv)
		conf_way = nc if conf_way == 100 else conf_way * nc / 100
	# T: the tile itself, when it holds something or was the last destination.
	var t := 0
	var conf_tile := 100
	if _interactive(p, tile) or tile == p.ai.dig_tile:
		var tv := _tile_value(p, tile, true)
		t = int(tv[0])
		conf_tile = int(tv[1])
	var pot := potential(p, tile)
	var pv := int(pot[0])
	var conf_pot := int(pot[1])
	if conf_tile < 100:
		pv = pv * conf_tile / 100
	if conf_pot < 100:
		t = t * conf_pot / 100
		pv = pv * conf_pot / 100
	if conf_night < 100:
		t = t * conf_night / 100
		pv = pv * conf_night / 100
	var v_way := v
	if conf_way < 100:
		if v > 0:
			v = (v + t + pv) * conf_way / 100
		else:
			v += (pv + t) * conf_way / 100
	else:
		v += t
	var f := travel_days(float(cost) / float(maxi(1, p.max_move)), p.at_sea)
	var p_term := int(float(r.get("p_weight", 2)) * pv / (f + float(r.get("p_offset", 1))))
	var rv := int(v / (f + float(r.get("v_offset", 0.2)))) + p_term
	if p.at_sea and p.map.is_water(tile):
		rv += int(r.get("sea_bonus", 40))
	if parts != null:
		(parts as Dictionary).merge({"v_way": v_way, "v": v, "t": t, "p": pv, "conf_way": conf_way,
				"conf_tile": conf_tile, "conf_pot": conf_pot, "conf_night": conf_night,
				"f": f, "p_term": p_term, "pre": rv}, true)
	rv = rv * (int(r.get("noise_base", 75)) + int(p.roll.call(int(r.get("noise_lo", 1)),
			int(r.get("noise_hi", 50))))) / 100
	if tile == p.hero.planned_dest:
		rv = int(rv * float(r.get("dest_factor", 1.5)))
		if absi(tile.x - from.x) + absi(tile.y - from.y) > int(r.get("dest_near", 3)):
			rv += 1
	return rv

## f: days of travel, stretched as the trip grows (0x6ad72..0x6aea4).
static func travel_days(d: float, at_sea: bool) -> float:
	var r: Dictionary = rules().get("route_value", {})
	if at_sea:
		return float(r.get("sea_base", 0.5)) + float(r.get("sea_per_day", 0.5)) * d
	for row: Dictionary in r.get("brackets", []):
		if d > float(row.get("above", 0.0)):
			return d * float(row.get("factor", 1.0))
	return d

## [value, confidence] of whatever stands on `tile` (object or hero).
static func _tile_value(p: Plan, tile: Vector2i, raw: bool) -> Array:
	var tv := _tile_case(p, tile, raw)
	# 0x733a9: mode 0 (the potential's) keeps a value within +-32000 before
	# caching it; modes 1 and 2 leave the case's value as it is.
	if not raw:
		var cap := float(AITileValue.rules().get("mode0_cap", 32000))
		tv[0] = clampf(float(tv[0]), -cap, cap)
	return tv

static func _tile_case(p: Plan, tile: Vector2i, raw: bool) -> Array:
	# A hero's cell is class 0xbd, even a town's gate he stands in: the hero
	# case values him and the town he holds.
	if p.heroes_at.has(tile):
		return _hero_tile(p, tile, raw)
	var o: MapObject = p.objects_at.get(tile)
	if o != null and o.type in (rules().get("liths", {}) as Dictionary).get("types", []):
		var lv := lith_value(p, o, tile)
		return [lv if raw else maxf(0.0, lv), 100]
	if o == null and p.boats_at.has(tile):
		p.boat_seen = true
		var bv := float(AITileValue.rules().get("boat", 100))
		if not raw and p.zones.has(tile):
			bv = 0.0
		return [bv, 100]
	if o is TownObject and (o as TownObject).owner == p.ai.side:
		_note_coast(p, o as TownObject)
	if o != null:
		var v := AITileValue.value(o, p.tv, raw)
		# Mode 0 (the potential's) counts nothing a monster guards: data
		# 0x41160 bit 0x80 marks those cells; the monster itself still counts.
		# Its builders (0x78827, 0x7c92e) exempt a sprite cell only below the
		# monster, the same rule as 0x84138, so protecting_stack_at reads it.
		if not raw and v > 0.0 and not (o is NeutralStack) and p.zones.has(tile):
			v = 0.0
		return [v, AITileValue.confidence(o, p.tv)]
	# 0x73259: the cell the computer believes holds the Ultimate Artifact.
	var dig: Dictionary = rules().get("dig", {})
	if tile == p.ai.dig_tile and p.ai.dig_confidence > int(dig.get("above", 15)):
		return [float((p.ai.dig_confidence - int(dig.get("above", 15))) * int(dig.get("value", 16200)) / 100), 100]
	return [0.0, 100]

## 0x74707..0x7486c (the castle routine's evaluate mode): note the nearest
## own town with a shipyard, else the nearest castle whose launch cell, one
## left of and below the gate, is water. The distance is kept in a signed
## byte, as the original does.
static func _note_coast(p: Plan, town: TownObject) -> void:
	var model := p.ai.town_by_object_id(town.id)
	if model == null:
		return
	var d := absi(town.action_tile.x - p.hero.tile.x) + absi(town.action_tile.y - p.hero.tile.y)
	if model.is_built("shipyard") and town != p.coast_town:
		if not (p.coast_shipyard and p.coast_dist <= d):
			p.coast_dist = d - 256 if d >= 128 else d
			p.coast_town = town
		p.coast_found = true
		p.coast_shipyard = true
		return
	if not model.has_castle or p.coast_shipyard or town == p.coast_town \
			or not p.map.is_water(town.action_tile + Vector2i(-1, 1)):
		return
	if not (p.coast_found and p.coast_dist <= d):
		p.coast_dist = d - 256 if d >= 128 else d
		p.coast_town = town
	p.coast_found = true

static func _hero_tile(p: Plan, tile: Vector2i, raw: bool) -> Array:
	var there: Array = p.heroes_at[tile]
	var h := there[0] as HeroModel
	var side := int(there[1])
	if side == p.ai.side:
		# 0x71f34..0x71f68: a teammate is worth nothing in mode 0; in the
		# planner's modes -5000 unless the support factor is in force, and
		# never a sure thing (confidence 0).
		if not raw:
			return [0.0, 100]
		return [0.0 if p.tv.support < 1.0 else float(rules().get("teammate_cell", -5000)), 0]
	if p.state != null and not p.ai.is_hostile_to(p.state.player_of(side)):
		return [0.0, 100]
	var town := p.map.own_town_gate_at(tile, side)
	var fight := {}
	var hv := AITileValue.hero_value(h, side, town, p.tv, raw, fight)
	# 0x71f1e clears data 0x32088 only for a hero worth less than nothing;
	# its confidence is the battle's P x 100.
	return [AITileValue.supported(hv, p.tv) if hv >= 0.0 else hv, int(float(fight.get("p", 1.0)) * 100.0)]

## 0x730d5: a stone lith is worth the best other lith of its kind more than
## `far` tiles away, at `share` of its potential, less the potential where
## the hero stands and `cost`; -cost when that is no gain. While one is being
## valued every lith counts 0 (data 0x1e454).
static func lith_value(p: Plan, lith: MapObject, tile: Vector2i) -> float:
	if p.lith_busy:
		return 0.0
	if p.lith_values.has(tile):
		return p.lith_values[tile]
	var r: Dictionary = rules().get("liths", {})
	p.lith_busy = true
	var best := int(r.get("none", -9999))
	for other: MapObject in p.map.objects:
		if other.type != lith.type or other.consumed:
			continue
		var t: Vector2i = other.action_tile
		if absi(t.x - tile.x) + absi(t.y - tile.y) <= int(r.get("far", 4)):
			continue
		best = maxi(best, int(int(potential(p, t)[0]) * float(r.get("share", 0.85))))
	var here := int(potential(p, p.hero.tile)[0])
	p.lith_busy = false
	var cost := int(r.get("cost", 200))
	var value := float(best - here - cost) if here + cost < best else float(-cost)
	p.lith_values[tile] = value
	return value

## 0x73410: what surrounds `tile`, [P, confidence], cached per plan. A hero
## at sea searches the water, except from a landing cell, where the search
## is a land one (0x734c7: the at-sea flag is cleared on the coast class).
## `heroes_only` is mode 1, the night stop's: a longer reach, and only the
## heroes count, not the objects.
## `terms`, when given, collects each term as [kind, tile, value, cost, total]
## (kind "obj", "own" or "mate"; a mate's cost is its distance).
static func potential(p: Plan, tile: Vector2i, heroes_only := false, terms = null) -> Array:
	var cache: Dictionary = p.camps if heroes_only else p.potentials
	if cache.has(tile) and terms == null:
		return cache[tile]
	var r: Dictionary = rules().get("potential", {})
	var reach := int(r.get("night_reach", 60)) if heroes_only else int(r.get("reach", 36))
	var field := Pathfinder.build_sea_field(p.grid, tile, p.hero.hero_class, reach,
			p.boats_at, p.heroes_at) \
			if p.at_sea and p.map.is_water(tile) \
			else Pathfinder.build_land_field(p.grid, tile, p.hero.hero_class, -1, -1, null, reach, p.boats_at,
					Vector2i(-1, -1), _object_cells(p), true)
	var w := p.map.width
	var total := 0
	var conf := 100
	var offset := int(r.get("cost_offset", 2))
	var near_cost := int(r.get("near_cost", 32))
	var penalty := int(r.get("penalty", 1250))
	# A hero's cell is an object cell to the original (class 0xbd), a route's
	# end; our grid makes teammates solid, so price the step onto each one.
	var costs: Dictionary = field.get("costs", {})
	if not costs.is_empty():
		for t: Vector2i in p.heroes_at:
			var hf := t.y * w + t.x
			if t != tile and not costs.has(hf) and p.grid.is_point_solid(t):
				var onto := _cost_onto(p, costs, t)
				if onto >= 0 and onto <= reach:
					costs[hf] = onto
	for flat: int in costs:
		var t := Vector2i(flat % w, flat / w)
		if t == tile:
			continue
		var cost := int(field.costs[flat])
		if not heroes_only and (p.objects_at.has(t) or p.boats_at.has(t)):
			if not p.values.has(t):
				p.values[t] = _tile_value(p, t, false)
			total = int(float((p.values[t] as Array)[0]) / (cost + offset) + total)
			if terms != null:
				terms.append(["obj", t, int((p.values[t] as Array)[0]), cost, total])
		var there: Array = p.heroes_at.get(t, [])
		if there.is_empty():
			continue
		if int(there[1]) == p.ai.side:
			if cost < near_cost:
				total -= (near_cost - cost) * penalty / near_cost
				if terms != null:
					terms.append(["own", t, 0, cost, total])
			continue
		if not p.values.has(t):
			p.values[t] = _tile_value(p, t, false)
		total = int(float((p.values[t] as Array)[0]) / (cost + offset) + total)
		if terms != null:
			terms.append(["obj", t, int((p.values[t] as Array)[0]), cost, total])
		conf = conf * (100 - _caution(p, there[0] as HeroModel, int(there[1]), cost)) / 100
	var near_tiles := int(r.get("near_tiles", 9))
	var land := not p.map.is_water(tile)
	for h: HeroModel in p.ai.heroes:
		if h == p.hero or h.tile == Vector2i(-1, -1):
			continue
		# heroes.exe 0x738d6..0x739c4: distance to the other hero's target
		# (hero +0x20/+0x21, kept after he arrives); one without a target
		# (0xff) is never near.
		var target: Vector2i = h.planned_dest
		if target == Vector2i(-1, -1):
			continue
		var d := absi(target.x - tile.x) + absi(target.y - tile.y)
		var target_is_water := p.map.is_water(target) if (p.map != null and target.x >= 0 and target.x < p.map.width and target.y >= 0 and target.y < p.map.height) else false
		if d < near_tiles and (not target_is_water) == land:
			total -= (near_tiles - d) * penalty / near_tiles
			if terms != null:
				terms.append(["mate", target, 0, d, total])
	total = mini(int(total * float(r.get("scale", 1.25))), int(r.get("cap", 32000)))
	cache[tile] = [total, conf]
	return cache[tile]

## The potential's search (0x73410 over 0x86b64 in its non-planning mode)
## reaches object and hero cells but goes no further through them.
static func _object_cells(p: Plan) -> Dictionary:
	if p.object_cells.is_empty():
		p.object_cells = p.objects_at.duplicate()
		p.object_cells.merge(p.heroes_at)
	return p.object_cells

## The cheapest step onto `t` from a reached neighbour, priced like the
## route search (the source cell's straight or diagonal price), or -1.
static func _cost_onto(p: Plan, costs: Dictionary, t: Vector2i) -> int:
	var w := p.map.width
	var best := -1
	var barbarian := p.hero.hero_class == "barbarian"
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var nb := t + Vector2i(dx, dy)
			if (dx == 0 and dy == 0) or not p.grid.is_in_boundsv(nb):
				continue
			var nf := nb.y * w + nb.x
			# The step obeys the step check (0x87a98), and the search goes no
			# further through an object or hero cell (0x73410 over 0x86b64).
			if not costs.has(nf) or not p.grid.can_enter(nb, t, true, true) \
					or (int(costs[nf]) > 0 and _object_cells(p).has(nb)):
				continue
			var straight := 4 if barbarian else int(p.grid.terrain_costs[nf])
			var step := (6 if barbarian else straight + (straight >> 1)) if dx != 0 and dy != 0 else straight
			var c := int(costs[nf]) + step
			if best < 0 or c < best:
				best = c
	return best

## How much a reachable enemy hero the computer would rather avoid lowers a
## potential's confidence (0x73831..): its attack desire against him, and how
## soon he could strike.
static func _caution(p: Plan, h: HeroModel, side: int, cost: int) -> int:
	var d: Dictionary = rules().get("desire", {})
	var desire := attack_desire(p, h, side)
	if desire >= 100:
		return 0
	var owner: PlayerState = p.state.player_of(side) if p.state != null else null
	var move := maxi(1, h.max_move_points)
	if owner != null and owner.is_ai:
		var span := move + int(d.get("computer_offset", 20))
		return (100 - desire) * (span - cost) / span
	if cost > move:
		return int((100 - desire) * float(d.get("far_share", 0.2)))
	if cost > int(d.get("near_cost", 14)):
		return (move - cost + int(d.get("near_offset", 10))) * (100 - desire) / move
	return 100 - desire

## 0x2f58c: how keen the computer is to attack hero `h`, 0..100.
static func attack_desire(p: Plan, h: HeroModel, side: int) -> int:
	var d: Dictionary = rules().get("desire", {})
	var fight := AITileValue.battle(p.tv, p.hero.army, h.army, h, false, side)
	var chance := float(fight.p)
	if chance > float(d.get("sure", 0.75)):
		return 100
	var factor := float(d.get("base", 100))
	for row: Dictionary in d.get("rows", []):
		if chance > float(row.get("above", 0.0)):
			factor = float(row.get("factor", 100))
			break
	return mini(100, int(chance * factor))

## heroes.exe 0x6b71d (logged as GOODADJ): before each step, the best
## neighbour worth taking now. A neighbour qualifies when the hero may step
## there, it holds something, no monster guards it, it is no stone lith or
## whirlpool, and its value (mode 2) beats `floor` at confidence above
## `confidence`. Directions are tried N, NE, E, SE, S, SW, W, NW. {} for none,
## and none while the hero stands on stone liths.
static func adjacent_grab(p: Plan, tile: Vector2i) -> Dictionary:
	var g: Dictionary = rules().get("adjacent", {})
	p.zones = p.grid.guard_zones()
	var here: MapObject = p.objects_at.get(tile)
	if here != null and here.type in (g.get("skip_types", []) as Array):
		return {}
	var best := {}
	var best_value := float(g.get("floor", 100))
	for d: Array in g.get("directions", []):
		var n := tile + Vector2i(int(d[0]), int(d[1]))
		var o: MapObject = p.objects_at.get(n)
		if p.at_sea:
			# 0xa89f2 for a hero at sea: water cells only; the walk-on
			# pickups and buoys never, another hero only when he sails too.
			if not p.map.is_water(n) or not _sea_grab(p, n, o):
				continue
		elif not p.grid.can_enter(tile, n, false):
			continue
		if (o == null and not p.heroes_at.has(n)) or (o != null and o.type in (g.get("skip_types", []) as Array)):
			continue
		var stack: NeutralStack = p.zones.get(n)
		if stack != null and stack != o:
			continue
		var tv := _tile_value(p, n, true)
		if int(tv[1]) <= int(g.get("confidence", 80)) or float(tv[0]) <= best_value:
			continue
		best_value = float(tv[0])
		best = {"tile": n, "rv": int(tv[0]), "guard": null}
	if best.is_empty():
		return {}
	var target := _target(p, best)
	target["path"] = [tile, best.tile]
	return target

## What a sailing hero may take from the next water cell (0xa89f2).
static func _sea_grab(p: Plan, n: Vector2i, o: MapObject) -> bool:
	var there: Array = p.heroes_at.get(n, [])
	if not there.is_empty():
		return (there[0] as HeroModel).travel_mode == &"sea"
	if o == null:
		return false
	return not (o.type in ((rules().get("adjacent", {}) as Dictionary).get("sea_never", []) as Array)) \
			and not o.is_walk_on_pickup()

## A computer player's dig guess (0x76db4, run for the player at each of its
## obelisk visits (0x76fd0) and for every player after each dig (0x98d8e)).
static func refresh_dig_guess(ai: PlayerState, map: MapData, rng: RandomNumberGenerator,
		dug: Array = []) -> void:
	if ai == null or not ai.is_ai or map == null:
		return
	var r: Dictionary = rules().get("dig", {})
	var buried := Dig._buried_tile(map)
	var obelisks := Dig.count_obelisks(map)
	var pieces := int(r.get("pieces", 48))
	var revealed := mini(pieces, ai.puzzle_pieces.size() * pieces / maxi(1, obelisks))
	if revealed < int(r.get("min_pieces", 11)) or buried == Vector2i(-1, -1):
		ai.dig_confidence = 0
		ai.dig_tile = Vector2i(-1, -1)
		return
	var conf := ((revealed - int(r.get("min_pieces", 11))) * int(r.get("per_piece", 4))) & 0xff
	ai.dig_confidence = conf - 256 if conf >= 128 else conf
	if _roll(rng, 1, 100) <= ai.dig_confidence:
		ai.dig_tile = buried
		return
	for _try in int(r.get("tries", 200)):
		var t := buried + Vector2i(_dig_offset(rng), _dig_offset(rng))
		if t.x >= 0 and t.y >= 0 and t.x < map.width and t.y < map.height \
				and not dug.has(t) and Dig.is_clear_ground(map, t):
			ai.dig_tile = t
			return
	ai.dig_tile = buried

## 3 - three draws of 0..2, drawn again while 0 (0x76efb).
static func _dig_offset(rng: RandomNumberGenerator) -> int:
	while true:
		var v := 3 - _roll(rng, 0, 2) - _roll(rng, 0, 2) - _roll(rng, 0, 2)
		if v != 0:
			return v
	return 1

static func _roll(rng: RandomNumberGenerator, lo: int, hi: int) -> int:
	return rng.randi_range(lo, hi) if rng != null else randi_range(lo, hi)

## The pick_target target for the chosen tile.
static func _target(p: Plan, best: Dictionary) -> Dictionary:
	var tile: Vector2i = best.tile
	var rv := float(best.rv)
	var guard := best.get("guard") as NeutralStack
	if guard != null:
		return {"tile": guard.action_tile, "kind": "guard", "object": guard, "score": rv,
				"beyond": tile}
	var there: Array = p.heroes_at.get(tile, [])
	if not there.is_empty():
		var side := int(there[1])
		var owner: PlayerState = p.state.player_of(side) if p.state != null else null
		var kind := "player_hero" if p.state != null and side == p.state.active_player_side else "enemy_hero"
		return {"tile": tile, "kind": kind, "object": null, "score": rv, "side": side,
				"hero_index": owner.heroes.find(there[0]) if owner != null else 0}
	var o: MapObject = p.objects_at.get(tile)
	if o == null and p.boats_at.has(tile):
		return {"tile": tile, "kind": "boat", "object": null, "score": rv}
	if o is TownObject:
		if o.owner == p.ai.side:
			return {"tile": tile, "kind": "own_town", "object": o, "score": rv}
		var player_side := p.state.active_player_side if p.state != null else -1
		var kind := "player_town" if o.owner >= 0 and o.owner == player_side else "enemy_town"
		return {"tile": tile, "kind": kind, "object": o, "score": rv, "side": o.owner}
	if o != null:
		return {"tile": tile, "kind": o.type, "object": o, "score": rv}
	if tile == p.ai.dig_tile:
		return {"tile": tile, "kind": "dig_ultimate", "object": null, "score": rv}
	return {"tile": tile, "kind": "move", "object": null, "score": rv}
