# src/game/player_state.gd
class_name PlayerState
extends RefCounted

## One side's kingdom: economy + towns + heroes. In hot-seat games multiple
## entries are human; GameState.active_player_side identifies the seated one.

var side: int = 0
var team: int = 0
var is_ai: bool = false
var ai_level: int = 0             # 0=None, 1=Dumb, 2=Average, 3=Smart, 4=Genius
var crest_idx: int = 0            # smcrest id = color*4 + class (0 = blue knight)
var _custom_daily_income: int = -1

## Base daily income generated from owned castles (1000g each) and towns (250g each).
## Returns 0 if no towns are owned. If an explicit income override was set (e.g. in test isolation),
## that override is used instead.
var daily_income: int:
	get:
		if _custom_daily_income >= 0:
			return _custom_daily_income
		if not owns_town or towns.is_empty():
			return 0
		var total := 0
		for t: TownModel in towns:
			total += t.daily_income
		return total
	set(v):
		_custom_daily_income = v
## The six non-gold resources. Gold lives in town.gold (see gold()).
var resources: Dictionary = {"wood": 0, "ore": 0, "mercury": 0, "sulfur": 0, "crystal": 0, "gems": 0}
var treasury_gold: int = 0
var towns: Array[TownModel] = []
var active_town: int = 0
## Back-compatible active-town delegate. Town screens keep using `town`, while
## kingdom/economy code can iterate `towns`.
var town: TownModel:
	get:
		return null if towns.is_empty() else towns[clampi(active_town, 0, towns.size() - 1)]
	set(value):
		if value == null:
			towns.clear()
			active_town = 0
		elif towns.is_empty():
			towns.append(value)
			active_town = 0
		else:
			towns[clampi(active_town, 0, towns.size() - 1)] = value
		_bind_towns()
var hero_model: HeroModel = null  # null = this side has no hero (dead / never hired)
var heroes: Array[HeroModel] = []
var returning_heroes: Array[HeroModel] = [] # retreated/surrendered; tavern priority
var active_hero: int = 0
var owns_town: bool = true        # flips false when the side's town is captured
var townless_days_left: int = -1   # 7-day countdown when losing last town; -1 when inactive
var identify_hero_active: bool = false # Level 3 Adventure Spell "Identify Hero"
var alive: bool = true
# Computer naval requests (heroes.exe 0x31e94 / 0x31e98 / 0x31e9c + side): the
# object id of the town to build a shipyard in and of the town to buy a boat
# at (-1 when none), and the day the planner last asked (0x6b207).
var naval_shipyard_town: int = -1
var naval_boat_town: int = -1
var naval_request_day: int = 0
# The computer's dig guess (heroes.exe player +0x52..+0x54), refreshed on each
# obelisk visit (0x76fd0): a confidence and the tile it believes holds the
# Ultimate Artifact.
var dig_confidence: int = 0
var dig_tile: Vector2i = Vector2i(-1, -1)
# Computer-player hires, counted for ai_hire_day only (read through
# ai_hires_on()): the buy allows one hire a turn (heroes.exe 0x27c08).
var ai_hire_day: int = 0
var ai_hires_today: int = 0

func color_name() -> String:
	const COLOR_NAMES := ["Blue", "Green", "Red", "Yellow"]
	var idx := clampi(crest_idx / 4, 0, 3) if crest_idx >= 0 else clampi(side, 0, 3)
	return COLOR_NAMES[idx]

# --- fog of war ---
var explored: PackedByteArray = PackedByteArray()
var explored_w: int = 0
var explored_h: int = 0

## --- puzzle map (Obelisk, per-player progress) ---
## Distinct obelisk MapObject.ids this player's side has visited (note:
## data/knowledge_base/adventure-object-catalog.md's Obelisk row). Kingdom-wide
## like `explored` above, not per-hero, and persisted by to_dict()/from_dict().
var puzzle_pieces: Array = []

## True once this player has visited every obelisk on the map (total_obelisks,
## counted by the caller from MapData.objects). 0 obelisks never counts as solved.
func puzzle_solved(total_obelisks: int) -> bool:
	return total_obelisks > 0 and puzzle_pieces.size() >= total_obelisks

func explored_init(w: int, h: int) -> void:
	if w == explored_w and h == explored_h and not explored.is_empty():
		return   # scene reload: keep what the player has seen
	explored_w = w
	explored_h = h
	explored = PackedByteArray()
	explored.resize(w * h)

func explore(x: int, y: int) -> void:
	if x < 0 or y < 0 or x >= explored_w or y >= explored_h:
		return
	explored[y * explored_w + x] = 1

func is_explored_at(x: int, y: int) -> bool:
	if explored.is_empty():
		return true   # fog not initialized = fog disabled (legacy tests, menus)
	if x < 0 or y < 0 or x >= explored_w or y >= explored_h:
		return false
	return explored[y * explored_w + x] == 1

func explore_all() -> void:
	explored.fill(1)

func setup(p_side: int, p_is_ai: bool, p_crest: int, start_gold: int, available: Dictionary, p_income: int = -1) -> void:
	side = p_side
	team = p_side
	is_ai = p_is_ai
	crest_idx = p_crest
	_custom_daily_income = p_income
	treasury_gold = start_gold
	var first_town := TownModel.new()
	towns = [first_town]
	_bind_towns()
	first_town.setup(start_gold, available.duplicate(), ArmyData.new())

func gold() -> int:
	return treasury_gold

## Thieves' Guilds this kingdom owns. One guild reveals the creature types in
## an enemy town or castle garrison, two reveal their approximate quantity
## (KB castles.md, "Thieves' Guild information levels").
func thieves_guild_count() -> int:
	var count := 0
	for model: TownModel in towns:
		if model.is_built("thieves_guild"):
			count += 1
	return count

func _bind_towns() -> void:
	for model: TownModel in towns:
		model.kingdom = self

func town_by_object_id(object_id: int) -> TownModel:
	for model: TownModel in towns:
		if model.object_id == object_id:
			return model
	return null

func town_for_object(object_id: int) -> TownModel:
	return town_by_object_id(object_id)

func select_town(object_id: int) -> TownModel:
	for i in towns.size():
		if towns[i].object_id == object_id:
			active_town = i
			return towns[i]
	return null

func add_town(model: TownModel) -> void:
	if model == null or town_by_object_id(model.object_id) != null:
		return
	model.kingdom = self
	towns.append(model)
	owns_town = true
	townless_days_left = -1

func remove_town(object_id: int) -> TownModel:
	var model := town_by_object_id(object_id)
	if model == null:
		return null
	towns.erase(model)
	model.kingdom = null
	model._gold = treasury_gold
	active_town = clampi(active_town, 0, max(0, towns.size() - 1))
	owns_town = not towns.is_empty()
	return model

## Add a {resource: amount} bag. "gold" routes to the town; the rest to resources.
func add_resources(bag: Dictionary) -> void:
	for k: String in bag.keys():
		var amt := int(bag[k])
		if k == "gold":
			treasury_gold += amt
		else:
			resources[k] = int(resources.get(k, 0)) + amt

func active() -> HeroModel:
	if heroes.is_empty():
		return hero_model   # legacy/test states created before the heroes array existed
	var idx := clampi(active_hero, 0, heroes.size() - 1)
	return heroes[idx]

## heroes.exe 0x80e49 (KB research/day-order.md step 25): a human turn opens on
## the first hero in roster order that can still move, not the last one picked.
## Returns that index, or -1 when no hero can move (selection left as is).
func select_turn_start_hero() -> int:
	for i in heroes.size():
		if heroes[i].move_points != 0:   # -1 = not yet set, i.e. full movement
			active_hero = i
			return i
	return -1

func add_hero(h: HeroModel) -> bool:
	if heroes.size() >= 8:
		return false
	heroes.append(h)
	hero_model = heroes[0]
	return true

func remove_hero(h: HeroModel) -> void:
	heroes.erase(h)
	if heroes.is_empty():
		active_hero = 0
		hero_model = null
	else:
		active_hero = clampi(active_hero, 0, heroes.size() - 1)
		hero_model = heroes[0]

func dismiss_hero(h: HeroModel, rng: RandomNumberGenerator = null, pool: HeroPool = null) -> bool:
	if h == null or not heroes.has(h):
		return false
	remove_hero(h)
	returning_heroes.erase(h)
	_return_boat(h)
	var p: HeroPool = pool if pool != null else _get_hero_pool()
	if p != null:
		p.release_hero(h, rng)
	return true

func defeat_hero(h: HeroModel, rng: RandomNumberGenerator = null, pool: HeroPool = null) -> bool:
	return dismiss_hero(h, rng, pool)

func return_to_tavern(h: HeroModel, preserve_army: bool,
		rng: RandomNumberGenerator, pool: HeroPool = null) -> bool:
	if h == null or not heroes.has(h):
		return false
	remove_hero(h)
	_return_boat(h)
	if not preserve_army:
		h.army = HeroFactory.starting_army_for_class(h.hero_class, rng)
	h.tile = Vector2i(-1, -1)
	h.planned_dest = Vector2i(-1, -1)
	h.move_points = -1
	h.carried_boat_id = -1
	h.travel_mode = &"land"
	h.cowardice = -1
	h.kept_surrender_army = preserve_army
	if not returning_heroes.has(h):
		returning_heroes.append(h)
	var p: HeroPool = pool if pool != null else _get_hero_pool()
	if p != null:
		p.return_to_tavern(h, side, preserve_army, rng)
	return true

func note_ai_hire(day: int) -> void:
	_roll_ai_hire_day(day)
	ai_hires_today += 1

func ai_hires_on(day: int) -> int:
	return ai_hires_today if ai_hire_day == day else 0

func _roll_ai_hire_day(day: int) -> void:
	if ai_hire_day != day:
		ai_hire_day = day
		ai_hires_today = 0

func _get_hero_pool() -> HeroPool:
	var state := _get_game_state()
	return state.hero_pool if state != null else null

func _get_game_state() -> GameState:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var game_node = tree.root.get_node_or_null("Game")
		if game_node != null:
			return game_node.state
	return null

## A hero that leaves the map while sailing leaves its boat, unowned, where it was.
func _return_boat(h: HeroModel) -> void:
	if h.travel_mode != &"sea" or h.carried_boat_id < 0 or h.tile == Vector2i(-1, -1):
		return
	var state := _get_game_state()
	if state != null:
		state.place_boat(h.carried_boat_id, h.tile, -1, h.facing)

func abandon_heroes(rng: RandomNumberGenerator = null, pool: HeroPool = null) -> Array[HeroModel]:
	var abandoned: Array[HeroModel] = []
	for h: HeroModel in heroes.duplicate():
		abandoned.append(h)
		dismiss_hero(h, rng, pool)
	return abandoned

## End of this kingdom's own turn (heroes.exe 0x7fa3d): a running townless
## countdown loses a day. The turn-start warning shows the stored value first,
## so the day after the last town falls reads "7 days left" (DOS capture
## 2026-10-12). A townless kingdom with heroes and no countdown starts one, as
## the end-of-turn condition check does (0xd290d).
func end_turn_townless() -> void:
	if owns_town or heroes.is_empty():
		return
	if townless_days_left > 0:
		townless_days_left -= 1
	elif townless_days_left == -1:
		townless_days_left = 7

## A running townless countdown is the turn controller's to expire (banishment).
func is_eliminated() -> bool:
	return heroes.is_empty() and not owns_town

func is_hostile_to(other: PlayerState) -> bool:
	return other != null and side != other.side and team != other.team

func buy_spellbook(hero: HeroModel) -> bool:
	if hero == null or not hero.can_add_artifact("spell_book") \
			or town == null or town.gold < town.SPELLBOOK_COST:
		return false
	town.gold -= town.SPELLBOOK_COST
	hero.add_artifact("spell_book")
	town.teach_visiting_hero(hero)
	return true

## {resource: cost} where "gold" checks/deducts town.gold, everything else
## checks/deducts the resources dict (see add_resources() above).
func can_afford(cost: Dictionary) -> bool:
	for k: String in cost:
		var have: int = treasury_gold if k == "gold" else int(resources.get(k, 0))
		if have < int(cost[k]):
			return false
	return true

func pay(cost: Dictionary) -> void:
	for k: String in cost:
		var amt := int(cost[k])
		if k == "gold":
			treasury_gold -= amt
		else:
			resources[k] = int(resources.get(k, 0)) - amt

func can_hire() -> bool:
	return heroes.size() < 8 and town != null and town.gold >= HeroPool.COST

func hire(h: HeroModel, at: Vector2i, pool: HeroPool = null, rng: RandomNumberGenerator = null) -> bool:
	if not can_hire():
		return false
	town.gold -= HeroPool.COST
	h.tile = at
	h.facing = Direction.E   # a pool hero keeps the facing of its last map life
	h.move_points = -1
	if not add_hero(h):
		return false
	if rng == null:
		rng = RandomNumberGenerator.new()
	if not h.kept_surrender_army:
		HeroFactory.reroll_for_hire(h, rng)
	h.kept_surrender_army = false
	# heroes.exe 0x75288 / 0x6891d seat the hire in the town and run 0xc91a2,
	# which teaches the Mage Guild to a visiting hero with a spell book.
	town.teach_visiting_hero(h)
	returning_heroes.erase(h)
	# Town exit and the adventure-map camera both follow active_hero. Selecting
	# the new roster entry here makes the recruited hero the immediate focus.
	active_hero = heroes.size() - 1
	var p: HeroPool = pool if pool != null else _get_hero_pool()
	if p != null:
		p.on_hero_hired(h, side, rng)
	return true

## --- save/load ---
## hero_model is NOT serialized: from_dict rebuilds it as heroes[0], the same
## invariant add_hero()/remove_hero() maintain.

func to_dict() -> Dictionary:
	var hs: Array = []
	for h: HeroModel in heroes:
		hs.append(h.to_dict())
	var returned: Array = []
	for h: HeroModel in returning_heroes:
		returned.append(h.to_dict())
	var res := {}
	for k in resources:
		res[String(k)] = int(resources[k])
	return {
		"side": side,
		"team": team,
		"is_ai": is_ai,
		"ai_level": ai_level,
		"crest_idx": crest_idx,
		"daily_income": daily_income,
		"custom_daily_income": _custom_daily_income,
		"resources": res,
		"treasury_gold": treasury_gold,
		"towns": towns.map(func(model: TownModel): return model.to_dict()),
		"active_town": active_town,
		"heroes": hs,
		"returning_heroes": returned,
		"active_hero": active_hero,
		"owns_town": owns_town,
		"townless_days_left": townless_days_left,
		"identify_hero_active": identify_hero_active,
		"alive": alive,
		"naval_shipyard_town": naval_shipyard_town,
		"naval_boat_town": naval_boat_town,
		"naval_request_day": naval_request_day,
		"dig_confidence": dig_confidence,
		"dig_tile": [dig_tile.x, dig_tile.y],
		"ai_hire_log": [ai_hire_day, ai_hires_today],
		"explored": Marshalls.raw_to_base64(explored) if not explored.is_empty() else "",
		"explored_w": explored_w,
		"explored_h": explored_h,
		"puzzle_pieces": puzzle_pieces.duplicate(),
	}

static func from_dict(d: Dictionary) -> PlayerState:
	var p := PlayerState.new()
	p.side = int(d.get("side", 0))
	p.team = int(d.get("team", p.side))
	p.is_ai = bool(d.get("is_ai", false))
	p.ai_level = clampi(int(d.get("ai_level", 2 if p.is_ai else 0)), 0, 4)
	p.crest_idx = int(d.get("crest_idx", 0))
	if d.has("custom_daily_income"):
		p._custom_daily_income = int(d["custom_daily_income"])
	elif d.has("daily_income") and not d.has("towns") and not d.has("town"):
		p._custom_daily_income = int(d["daily_income"])
	else:
		p._custom_daily_income = -1
	var res: Dictionary = d.get("resources", {})
	for k in res:
		p.resources[String(k)] = int(res[k])
	var saved_towns: Variant = d.get("towns", null)
	if saved_towns is Array:
		for town_data in saved_towns:
			if town_data is Dictionary and not (town_data as Dictionary).is_empty():
				p.towns.append(TownModel.from_dict(town_data))
	elif d.has("town") and d["town"] is Dictionary and not (d["town"] as Dictionary).is_empty():
		p.towns.append(TownModel.from_dict(d["town"]))
	p.treasury_gold = int(d.get("treasury_gold", p.towns[0]._gold if not p.towns.is_empty() else 0))
	p.active_town = clampi(int(d.get("active_town", 0)), 0, max(0, p.towns.size() - 1))
	p._bind_towns()
	for hd in d.get("heroes", []):
		if hd is Dictionary:
			p.heroes.append(HeroModel.from_dict(hd))
	for hd in d.get("returning_heroes", []):
		if hd is Dictionary:
			p.returning_heroes.append(HeroModel.from_dict(hd))
	p.hero_model = null if p.heroes.is_empty() else p.heroes[0]
	p.active_hero = clampi(int(d.get("active_hero", 0)), 0, max(0, p.heroes.size() - 1))
	p.owns_town = bool(d.get("owns_town", not p.towns.is_empty()))
	p.townless_days_left = int(d.get("townless_days_left", -1))
	p.identify_hero_active = bool(d.get("identify_hero_active", false))
	p.alive = bool(d.get("alive", true))
	p.naval_shipyard_town = int(d.get("naval_shipyard_town", -1))
	p.naval_boat_town = int(d.get("naval_boat_town", -1))
	p.naval_request_day = int(d.get("naval_request_day", d.get("naval_build_day", 0)))
	if bool(d.get("naval_build_needed", false)):
		# Older saves kept one flag for the kingdom: the first coastal town
		# without a shipyard is the one it meant.
		for town: TownModel in p.towns:
			if town.sea_access and not town.is_built("shipyard"):
				p.naval_shipyard_town = town.object_id
				break
	p.dig_confidence = int(d.get("dig_confidence", 0))
	var dig: Array = d.get("dig_tile", [-1, -1])
	p.dig_tile = Vector2i(int(dig[0]), int(dig[1])) if dig.size() >= 2 else Vector2i(-1, -1)
	var hire_log: Array = d.get("ai_hire_log", [0, 0])
	if hire_log.size() >= 2:
		p.ai_hire_day = int(hire_log[0])
		p.ai_hires_today = int(hire_log[1])
	var b64 := String(d.get("explored", ""))
	p.explored = Marshalls.base64_to_raw(b64) if b64 != "" else PackedByteArray()
	p.explored_w = int(d.get("explored_w", 0))
	p.explored_h = int(d.get("explored_h", 0))
	p.puzzle_pieces = []
	for pid in d.get("puzzle_pieces", []):
		p.puzzle_pieces.append(int(pid))
	return p
