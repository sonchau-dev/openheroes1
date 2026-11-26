class_name HeroPool
extends RefCounted

## Shared recruitment pool of all 36 named HOMM1 heroes (9 per class).
## Tracks experience, ownership, and per-player tavern residency.
## Dismissed and defeated heroes return to the pool with experience intact (KB heroes.md 4.3).
## Weekly rollover replaces both tavern slots per player (KB bugs.md §3).

const COST := 2500

const HEROES_BY_CLASS := {
	"knight": [
		"Lord Kilburn", "Lord Haart", "Sir Gallant", "Arturius", "Tyro",
		"Maximus", "Ector", "Dimitri", "Ambrose"
	],
	"barbarian": [
		"Thundax", "Ergon", "Kelzen", "Tsabu", "Crag Hack",
		"Jojosh", "Atlas", "Yog", "Antoine"
	],
	"sorceress": [
		"Ariel", "Vatawna", "Carlawn", "Rebecca", "Luna",
		"Astra", "Natasha", "Gem", "Troyan"
	],
	"warlock": [
		"Agar", "Crodo", "Falagar", "Barok", "Arie",
		"Kastore", "Sandro", "Wrathmont", "Vesper"
	],
}

var all_heroes: Array[HeroModel] = []
var free_queue: Array[HeroModel] = []
var tavern_slots: Dictionary = {} # side (int) -> Array[HeroModel] (size 2: [left, right])

func setup(rng: RandomNumberGenerator = null, num_players: int = 4) -> void:
	if rng == null:
		rng = RandomNumberGenerator.new()
	all_heroes.clear()
	free_queue.clear()
	tavern_slots.clear()

	for class_idx in 4:
		var class_name_str: String = ["knight", "barbarian", "sorceress", "warlock"][class_idx]
		var names: Array = HEROES_BY_CLASS[class_name_str]
		for i in names.size():
			var h_name: String = names[i]
			var h := HeroModel.new()
			h.hero_name = h_name
			h.hero_class = class_name_str
			h.crest_idx = class_idx
			h.portrait_idx = class_idx * 9 + i
			_apply_base_stats(h, class_name_str)
			all_heroes.append(h)
			free_queue.append(h)

	for side in num_players:
		_fill_tavern_slots(side, rng)

static func _apply_base_stats(h: HeroModel, class_name_str: String) -> void:
	match class_name_str:
		"knight":
			h.attack = 1; h.defense = 2; h.spell_power = 1; h.knowledge = 1
			h.morale = 1; h.sight_bonus = 0; h.has_spellbook = false
		"barbarian":
			h.attack = 2; h.defense = 1; h.spell_power = 1; h.knowledge = 1
			h.morale = 0; h.sight_bonus = 0; h.has_spellbook = false
		"sorceress":
			h.attack = 0; h.defense = 0; h.spell_power = 2; h.knowledge = 3
			h.morale = 0; h.sight_bonus = 0; h.has_spellbook = true
			h.artifacts = []
		"warlock":
			h.attack = 0; h.defense = 0; h.spell_power = 3; h.knowledge = 2
			h.morale = 0; h.sight_bonus = 2; h.has_spellbook = true
			h.artifacts = []
	h.experience = -1
	h.army = ArmyData.new()
	h.tile = Vector2i(-1, -1)
	h.move_points = -1
	h.planned_dest = Vector2i(-1, -1)

static func _ensure_hero_stats(h: HeroModel, rng: RandomNumberGenerator) -> void:
	if h == null:
		return
	if h.experience < 0:
		h.experience = rng.randi_range(40, 90)
	if h.army == null or h.army.is_empty():
		h.army = HeroFactory.starting_army_for_class(h.hero_class, rng)
		h.kept_surrender_army = false

static func _class_index(class_str: String) -> int:
	match class_str:
		"knight": return 0
		"barbarian": return 1
		"sorceress": return 2
		"warlock": return 3
		_: return -1

func get_hero(hero_name: String) -> HeroModel:
	for h in all_heroes:
		if h.hero_name == hero_name:
			return h
	return null

func take_hero_for_faction(faction: int, rng: RandomNumberGenerator = null) -> HeroModel:
	if rng == null:
		rng = RandomNumberGenerator.new()
	var class_str: String = ["knight", "barbarian", "sorceress", "warlock"][clampi(faction, 0, 3)]
	var matching_indices: Array[int] = []
	for i in free_queue.size():
		if free_queue[i].hero_class == class_str:
			matching_indices.append(i)
	var h: HeroModel = null
	if not matching_indices.is_empty():
		var chosen_idx: int = matching_indices[rng.randi_range(0, matching_indices.size() - 1)]
		h = free_queue.pop_at(chosen_idx)
	elif not free_queue.is_empty():
		var any_pick := rng.randi_range(0, free_queue.size() - 1)
		h = free_queue.pop_at(any_pick)
	_ensure_hero_stats(h, rng)
	return h

func _pick_free_hero(rng: RandomNumberGenerator, exclude_class_idx: int = -1) -> HeroModel:
	var classes := [0, 1, 2, 3]
	if exclude_class_idx >= 0 and classes.has(exclude_class_idx):
		classes.erase(exclude_class_idx)

	var pick_idx := rng.randi_range(0, classes.size() - 1)
	var chosen_class: int = classes[pick_idx]
	var class_str: String = ["knight", "barbarian", "sorceress", "warlock"][chosen_class]

	var matching_indices: Array[int] = []
	for i in free_queue.size():
		if free_queue[i].hero_class == class_str:
			matching_indices.append(i)
	var h: HeroModel = null
	if not matching_indices.is_empty():
		var chosen_idx: int = matching_indices[rng.randi_range(0, matching_indices.size() - 1)]
		h = free_queue.pop_at(chosen_idx)
	else:
		var allowed_indices: Array[int] = []
		for i in free_queue.size():
			var c_idx := _class_index(free_queue[i].hero_class)
			if classes.has(c_idx):
				allowed_indices.append(i)
		if not allowed_indices.is_empty():
			var chosen_idx: int = allowed_indices[rng.randi_range(0, allowed_indices.size() - 1)]
			h = free_queue.pop_at(chosen_idx)
		elif not free_queue.is_empty():
			var any_pick := rng.randi_range(0, free_queue.size() - 1)
			h = free_queue.pop_at(any_pick)
	_ensure_hero_stats(h, rng)
	return h

func _fill_tavern_slots(side: int, rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		rng = RandomNumberGenerator.new()
	var slots: Array = tavern_slots.get(side, [])
	while slots.size() < 2:
		slots.append(null)

	if slots[0] == null:
		slots[0] = _pick_free_hero(rng, -1)

	if slots[1] == null:
		var left_class := _class_index(slots[0].hero_class) if slots[0] != null else -1
		slots[1] = _pick_free_hero(rng, left_class)

	tavern_slots[side] = slots

## Draw the two tavern heroes of every listed side that has none yet. The game
## calls this once all starting heroes are placed: heroes.exe keeps both slots in
## the player block from day 1, so a hero beaten mid-week goes to the free pool
## and only reaches a tavern on a hire or the weekly refresh.
func fill_taverns(sides: Array, rng: RandomNumberGenerator = null) -> void:
	for side in sides:
		_fill_tavern_slots(int(side), rng)

func tavern_candidates(player_side: int, rng: RandomNumberGenerator = null, returning: Array = []) -> Array[HeroModel]:
	if rng == null:
		rng = RandomNumberGenerator.new()
	_fill_tavern_slots(player_side, rng)
	var slots: Array = tavern_slots.get(player_side, [])
	var res: Array[HeroModel] = []
	for h in slots:
		if h is HeroModel:
			res.append(h)
	for r in returning:
		if r is HeroModel and not res.has(r):
			res.push_front(r)
			if res.size() > 2:
				res = res.slice(0, 2)
	return res

func on_hero_hired(hero: HeroModel, side: int, rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		rng = RandomNumberGenerator.new()
	var slots: Array = tavern_slots.get(side, [])
	var idx := slots.find(hero)
	if idx < 0:
		return
	slots[idx] = null
	var other_idx := 1 - idx
	var other_hero: HeroModel = slots[other_idx] if other_idx < slots.size() else null
	var exclude_class := _class_index(other_hero.hero_class) if other_hero != null else -1
	slots[idx] = _pick_free_hero(rng, exclude_class)
	tavern_slots[side] = slots

func release_hero(hero: HeroModel, rng: RandomNumberGenerator = null, to_back: bool = false) -> void:
	if hero == null:
		return
	if rng == null:
		rng = RandomNumberGenerator.new()
	hero.army = HeroFactory.starting_army_for_class(hero.hero_class, rng)
	hero.kept_surrender_army = false
	hero.tile = Vector2i(-1, -1)
	hero.move_points = -1
	hero.planned_dest = Vector2i(-1, -1)
	hero.carried_boat_id = -1
	hero.travel_mode = &"land"
	hero.cowardice = 0
	hero.temporary_morale = 0
	hero.temporary_luck = 0
	hero.temporary_morale_modifiers.clear()
	hero.temporary_luck_modifiers.clear()
	hero.battle_booster_visits.clear()
	hero.artifacts = []

	if not free_queue.has(hero):
		if to_back:
			free_queue.append(hero)
		else:
			free_queue.push_front(hero)

func return_to_tavern(hero: HeroModel, side: int, preserve_army: bool, rng: RandomNumberGenerator = null) -> void:
	if hero == null:
		return
	if rng == null:
		rng = RandomNumberGenerator.new()
	if not preserve_army:
		hero.army = HeroFactory.starting_army_for_class(hero.hero_class, rng)
		hero.kept_surrender_army = false
	hero.tile = Vector2i(-1, -1)
	hero.move_points = -1
	hero.planned_dest = Vector2i(-1, -1)
	hero.carried_boat_id = -1
	hero.travel_mode = &"land"

	free_queue.erase(hero)

	var slots: Array = tavern_slots.get(side, [null, null])
	while slots.size() < 2:
		slots.append(null)
	if slots[0] != hero:
		if slots[1] == hero:
			slots[1] = slots[0]
			slots[0] = hero
		else:
			var displaced: HeroModel = slots[1]
			slots[1] = slots[0]
			slots[0] = hero
			if displaced != null and not free_queue.has(displaced):
				free_queue.push_front(displaced)
	tavern_slots[side] = slots

func weekly_refresh(sides: Array, rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		rng = RandomNumberGenerator.new()
	for side in sides:
		var slots: Array = tavern_slots.get(side, [null, null])
		while slots.size() < 2:
			slots.append(null)

		# heroes.exe 0x7fe41 only unmarks a returning hero (0x52e9f 0x40 -> 0xff):
		# a retreated or surrendered hero rejoins the pool with its artifacts
		# and army. Only the owner's re-hire that week keeps a surrendered army
		# whole; a hire from the pool re-rolls the first slots as heroes.exe does.
		# Left slot leaves first, immediately becoming available
		var departing_left: HeroModel = slots[0]
		if departing_left != null:
			slots[0] = null
			if not free_queue.has(departing_left):
				departing_left.cowardice = 0
				departing_left.kept_surrender_army = false
				free_queue.append(departing_left)

		slots[0] = _pick_free_hero(rng, -1)

		# Right slot leaves, immediately becoming available
		var departing_right: HeroModel = slots[1]
		if departing_right != null:
			slots[1] = null
			if not free_queue.has(departing_right):
				departing_right.cowardice = 0
				departing_right.kept_surrender_army = false
				free_queue.append(departing_right)

		var left_class := _class_index(slots[0].hero_class) if slots[0] != null else -1
		slots[1] = _pick_free_hero(rng, left_class)

		tavern_slots[side] = slots

## Make the kingdoms' hero objects the pool's own: a hero a player holds or
## has returning replaces the pool's copy of that name and leaves the free queue.
func adopt_owned(players: Array) -> void:
	for p: PlayerState in players:
		for h: HeroModel in p.heroes + p.returning_heroes:
			for j in all_heroes.size():
				if all_heroes[j].hero_name == h.hero_name:
					all_heroes[j] = h
					break
			for k in range(free_queue.size() - 1, -1, -1):
				if free_queue[k].hero_name == h.hero_name:
					free_queue.remove_at(k)
			for slots: Array in tavern_slots.values():
				for k in slots.size():
					if slots[k] is HeroModel and slots[k].hero_name == h.hero_name:
						slots[k] = h

func to_dict() -> Dictionary:
	var heroes_data: Array = []
	for h in all_heroes:
		heroes_data.append(h.to_dict())
	var free_names: Array = []
	for h in free_queue:
		free_names.append(h.hero_name)
	var slots_data: Dictionary = {}
	for side in tavern_slots.keys():
		var slot_pair: Array = tavern_slots[side]
		var pair_names: Array = []
		for h in slot_pair:
			pair_names.append(h.hero_name if h != null else "")
		slots_data[str(side)] = pair_names
	return {
		"all_heroes": heroes_data,
		"free_queue": free_names,
		"tavern_slots": slots_data,
	}

static func from_dict(d: Dictionary) -> HeroPool:
	var pool := HeroPool.new()
	var hero_map: Dictionary = {}
	for hd in d.get("all_heroes", []):
		if hd is Dictionary:
			var h := HeroModel.from_dict(hd)
			pool.all_heroes.append(h)
			hero_map[h.hero_name] = h
	for name in d.get("free_queue", []):
		var h: HeroModel = hero_map.get(String(name), null)
		if h != null:
			pool.free_queue.append(h)
	var slots_dict: Dictionary = d.get("tavern_slots", {})
	for side_str in slots_dict.keys():
		var side := int(side_str)
		var pair_names: Array = slots_dict[side_str]
		var pair: Array[HeroModel] = [null, null]
		if pair_names.size() > 0 and hero_map.has(String(pair_names[0])):
			pair[0] = hero_map[String(pair_names[0])]
		if pair_names.size() > 1 and hero_map.has(String(pair_names[1])):
			pair[1] = hero_map[String(pair_names[1])]
		pool.tavern_slots[side] = pair
	return pool

static func candidates(rng: RandomNumberGenerator, taken: Array, _town_faction: int = 0,
		returning: Array = [], player_side: int = -1) -> Array:
	var tree := Engine.get_main_loop() as SceneTree
	var game_node = tree.root.get_node_or_null("Game") if tree != null and tree.root != null else null
	if game_node != null and game_node.state != null and game_node.state.hero_pool != null:
		var side := player_side if player_side >= 0 else 0
		return game_node.state.hero_pool.tavern_candidates(side, rng, returning)

	var result: Array[HeroModel] = []
	var used := taken.duplicate()
	for returned in returning:
		if returned is HeroModel and not used.has(returned):
			result.append(returned)
			used.append(returned)
			if result.size() == 2:
				return result
	var factions := [0, 1, 2, 3]
	for existing: HeroModel in result:
		var existing_faction := ["knight", "barbarian", "sorceress", "warlock"].find(
				existing.hero_class)
		if existing_faction in factions:
			factions.erase(existing_faction)
	while result.size() < 2 and not factions.is_empty():
		var pick := rng.randi_range(0, factions.size() - 1)
		var faction: int = factions.pop_at(pick)
		var h := HeroFactory.create_for_faction(faction, rng, used)
		if h == null:
			break
		result.append(h)
		used.append(h)
	return result
