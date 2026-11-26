class_name BattleState
extends RefCounted

## Owns the battle: stacks, seeded RNG, round/turn order, occupancy, win/lose.

const BattleAbilitiesScript := preload("res://src/battle/battle_abilities.gd")
const CreatureCatalogScript := preload("res://src/battle/creature_catalog.gd")

var stacks: Array = []
var rng: RandomNumberGenerator
var heroes: Array = [null, null]     # HeroModel per side; null = no caster
var army_morale: Array = [0, 0]      # battle-start composition modifier per side
var cast_used: Array = [false, false]
var static_blocked: Dictionary = {}  # terrain obstacles and intact siege walls
var siege_defender_side: int = -1
var siege_defender_has_tavern: bool = false
var wall_hp: Array = []              # [int] length 5; rows 0..4
var catapult_pending: bool = false
var catapult_shots: int = 0
var catapult_round_shots: int = 0
var tower_actor: BattleStack = null
var tower_pending: bool = false
var tower_k: int = 5
var tower_mage_guild_level: int = 0
var _first_turn_pending := true
var _morale_extra: Dictionary = {}
var _acted: Dictionary = {}
var _current: BattleStack = null
var _last_action_side := 1           # defender sentinel => attacker opens battle
var _forced_winner := -1             # retreat/surrender ends with live stacks

func setup(p_stacks: Array, p_seed: int = 0, p_static_blocked: Dictionary = {},
		p_siege_defender_side: int = -1, p_siege_defender_has_tavern: bool = false,
		p_siege_tower_k: int = 5, p_siege_mage_guild_level: int = 0) -> void:
	stacks = p_stacks
	static_blocked = p_static_blocked.duplicate()
	siege_defender_side = p_siege_defender_side if p_siege_defender_side in [0, 1] else -1
	siege_defender_has_tavern = p_siege_defender_has_tavern and siege_defender_side >= 0
	tower_k = maxi(5, p_siege_tower_k)
	tower_mage_guild_level = maxi(0, p_siege_mage_guild_level)
	wall_hp = [2, 2, 2, 2, 2] if siege_defender_side >= 0 else []
	catapult_pending = siege_defender_side >= 0
	catapult_shots = 0
	catapult_round_shots = 0
	tower_pending = siege_defender_side >= 0
	if siege_defender_side >= 0:
		_setup_siege_tower()
	_forced_winner = -1
	if siege_defender_side >= 0:
		for row in Hex.ROWS:
			static_blocked[Vector2i(wall_col(), row)] = true
	rng = RandomNumberGenerator.new()
	rng.seed = p_seed
	_first_turn_pending = true
	# The opposing side is preferred first. This remains side 0 in ordinary
	# battles and right-side sieges, but mirrors correctly for an AI assault on
	# the human castle where battle side 1 is the attacker. When highest speed ties,
	# the single-stack defender exception gives preference to the defender.
	var default_pref := 1 - siege_defender_side if siege_defender_side >= 0 else 0
	var init_pref := TurnQueue.initial_preferred_side(stacks, default_pref)
	_last_action_side = 1 - init_pref
	army_morale = [
		army_morale_modifier(stacks, 0),
		army_morale_modifier(stacks, 1),
	]
	_start_round()

func _start_round() -> void:
	for s: BattleStack in stacks:
		s.has_retaliated = false
		s.turn_spent = false
		s.regenerate_top()
	cast_used = [false, false]
	_morale_extra.clear()
	_tick_effects()
	_acted.clear()
	_current = null
	catapult_pending = siege_defender_side >= 0
	catapult_round_shots = 0
	tower_pending = siege_defender_side >= 0

func wall_col() -> int:
	return Hex.wall_col(siege_defender_side)

func siege_attacker_side() -> int:
	return 1 - siege_defender_side if siege_defender_side >= 0 else -1

## Fire the attacker's one catapult shot for this round. The first two shots
## target wall sections 2 and 4; later shots choose among surviving sections.
## A section usually loses one of its two hit points, with the handbook's
## 30/151 (human defender) or 45/151 (computer defender) chance to be destroyed outright.
func catapult_action(computer_controlled := false) -> Dictionary:
	if not catapult_pending or siege_defender_side < 0:
		return {}
	var intact: Array[int] = []
	for row in wall_hp.size():
		if int(wall_hp[row]) > 0:
			intact.append(row)
	if intact.is_empty():
		catapult_pending = false
		return {}
	var target_row := -1
	if catapult_shots == 0 and 1 in intact:
		target_row = 1
	elif catapult_shots <= 1 and 3 in intact:
		target_row = 3
	else:
		target_row = intact[int(rng.randi() % intact.size())]
	catapult_shots += 1
	catapult_round_shots += 1
	var attacker: HeroModel = heroes[siege_attacker_side()] as HeroModel \
			if siege_attacker_side() >= 0 else null
	var round_limit := 2 if attacker != null and attacker.has_ballista() else 1
	catapult_pending = catapult_round_shots < round_limit
	var before := int(wall_hp[target_row])
	var threshold := 45 if computer_controlled else 30
	var damage := before if int(rng.randi() % 151) < threshold else 1
	wall_hp[target_row] = maxi(0, before - damage)
	if int(wall_hp[target_row]) == 0:
		static_blocked.erase(Vector2i(wall_col(), target_row))
	return {
		"row": target_row,
		"damage": before - int(wall_hp[target_row]),
		"hp": int(wall_hp[target_row]),
		"destroyed": int(wall_hp[target_row]) == 0,
	}

func _setup_siege_tower() -> void:
	tower_actor = BattleStack.new()
	tower_actor.unit = "arrow_tower"
	tower_actor.count = 1
	tower_actor.count_initial = 1
	tower_actor.side = siege_defender_side
	var tower_col := Hex.COLS if siege_defender_side == 1 else -1
	tower_actor.hex = Vector2i(tower_col, 0)
	tower_actor.defense = 0
	tower_actor.damage_min = 2 * tower_k
	tower_actor.damage_max = 3 * tower_k
	tower_actor.shots = 999
	tower_actor.shots_max = 999
	tower_actor.hp_current = 9999
	tower_actor.hp_max = 9999
	tower_actor.attack = tower_attack()
	tower_pending = true

## Tower attack = base 2 + defending hero attack + Mage Guild level (KB battle.md §12.3.1).
func tower_attack() -> int:
	var def_hero: HeroModel = heroes[siege_defender_side] as HeroModel \
			if siege_defender_side >= 0 and siege_defender_side < heroes.size() and heroes[siege_defender_side] != null else null
	var hero_atk: int = def_hero.effective_attack() if def_hero != null else 0
	return 2 + hero_atk + tower_mage_guild_level

## True if the defensive shooting tower can fire this round.
## If all defending stacks are immobilized (e.g. Paralyze/Blind), there is no shot.
func can_tower_fire() -> bool:
	if not tower_pending or siege_defender_side < 0 or tower_actor == null:
		return false
	var defenders: Array = stacks.filter(func(s: BattleStack):
		return s.is_alive() and s.side == siege_defender_side)
	if defenders.is_empty():
		return false
	var any_can_act := false
	for s: BattleStack in defenders:
		if s.can_act():
			any_can_act = true
			break
	return any_can_act

## Choose primary enemy target by native shooter priority (shooters first, then others).
func tower_target() -> BattleStack:
	var enemies: Array = stacks.filter(func(s: BattleStack):
		return s.is_alive() and s.side == siege_attacker_side())
	if enemies.is_empty():
		return null
	var targets: Array = BattleAI._native_target_order(enemies, false)
	return targets[0] as BattleStack

## Fire the defensive shooting tower ahead of the first defending stack's turn.
## Base damage is (2-3) * k, modified by attacker's defense via DamageCalc.
func tower_action() -> Dictionary:
	if not can_tower_fire():
		tower_pending = false
		return {}
	tower_pending = false
	var target := tower_target()
	if target == null:
		return {}
	tower_actor.attack = tower_attack()
	tower_actor.damage_min = 2 * tower_k
	tower_actor.damage_max = 3 * tower_k
	var roll := 0
	for _i in tower_k:
		roll += rng.randi_range(2, 3)
	var atk := tower_actor.attack
	var def := defense_for(target)
	var raw_damage := DamageCalc.compute_base(roll, atk, def)
	var dmg := DamageCalc.finalize(raw_damage)
	var p := target.has_effect("paralyze")
	var b := target.has_effect("blind")
	var killed: int = target.apply_damage(dmg)
	_wake(target, p, b)
	return {
		"target": target,
		"damage": dmg,
		"killed": killed,
		"roll": roll,
		"attack": atk,
		"defense": def,
	}

## Decrement each stack's active duration effect; on expiry, clear it and —
## for curse/blind specifically — lift eternal_curse too (KB spells.md 5.4).
func _tick_effects() -> void:
	for s: BattleStack in stacks:
		if s.active_effect.is_empty():
			continue
		s.active_effect["rounds"] = int(s.active_effect["rounds"]) - 1
		if int(s.active_effect["rounds"]) <= 0:
			var id: String = s.active_effect["id"]
			s.clear_effect()
			if id == "curse" or id == "blind":
				s.eternal_curse = false

func active() -> BattleStack:
	if _forced_winner >= 0:
		return null
	if _current != null and _current.is_alive() and not _acted.has(_current):
		return _current
	while true:
		var preferred_side := 1 - _last_action_side
		var candidate := TurnQueue.next(stacks, _acted, preferred_side)
		if candidate == null:
			if winner() != -1:
				return null
			_start_round()
			continue
		# Blind/paralyzed stacks have standing speed in the native selector.
		# Mark them spent without changing the preferred side.
		if not candidate.can_act():
			_acted[candidate] = true
			continue
		_current = candidate
		return _current
	return null

func morale_for(stack: BattleStack) -> int:
	# Ghosts are unaffected by both good and bad morale.
	if stack.undead:
		return 0
	var hero = heroes[stack.side] \
			if stack.side >= 0 and stack.side < heroes.size() else null
	var hero_morale := int(hero.effective_morale()) if hero != null else 0
	var composition := int(army_morale[stack.side]) \
			if stack.side >= 0 and stack.side < army_morale.size() else 0
	var tavern_bonus := 1 if (siege_defender_has_tavern and stack.side == siege_defender_side) else 0
	return clampi(hero_morale + composition + tavern_bonus, -3, 3)

## Native army morale is based on distinct troop factions, not the number of
## creature stacks: one faction +1, two 0, then -1 per additional faction
## (KB heroes.md 4.1, castles.md).
static func army_morale_modifier(side_stacks: Array, side: int) -> int:
	var units: Array[String] = []
	for stack: BattleStack in side_stacks:
		if stack.side == side and stack.is_alive():
			units.append(stack.unit)
	return HeroModel.composition_morale(units)

func hero_attack_bonus(stack: BattleStack) -> int:
	var hero = heroes[stack.side] \
			if stack.side >= 0 and stack.side < heroes.size() else null
	return int(hero.effective_attack()) if hero != null else 0

func hero_defense_bonus(stack: BattleStack) -> int:
	var hero = heroes[stack.side] \
			if stack.side >= 0 and stack.side < heroes.size() else null
	return int(hero.effective_defense()) if hero != null else 0

func attack_for(stack: BattleStack) -> int:
	return stack.attack + hero_attack_bonus(stack)

func defense_for(stack: BattleStack) -> int:
	return stack.defense + hero_defense_bonus(stack) \
			+ (3 if stack.has_effect("shield") else 0)

func defense_for_attack(attacker: BattleStack, defender: BattleStack,
		melee_attack := false) -> int:
	return defense_for(defender) + siege_defense_bonus(attacker, defender, melee_attack)

## Intact walls grant defenders +4 Defense against outside shooters. A
## destroyed section opens the row beside it and the handbook's specified
## diagonal lines through the breach.
func siege_defense_bonus(attacker: BattleStack, defender: BattleStack,
		melee_attack := false) -> int:
	if siege_defender_side < 0 or melee_attack \
			or attacker.side != siege_attacker_side() \
			or defender.side != siege_defender_side:
		return 0
	var col := wall_col()
	var attacker_outside := attacker.hex.x < col if siege_defender_side == 1 \
			else attacker.hex.x > col
	var defender_right_col := defender.hex.x if siege_defender_side == 1 \
			else (defender.hex.x + (1 if defender.wide else 0))
	var defender_inside := defender_right_col > col if siege_defender_side == 1 \
			else defender_right_col < col
	if not attacker_outside or not defender_inside:
		return 0
	var ar := attacker.hex.y
	var dr := defender.hex.y
	if _wall_open(ar) and absi(dr - ar) <= 1:
		return 0
	if _wall_open(ar - 1) and dr in [ar - 2, ar - 3]:
		return 0
	if _wall_open(ar + 1) and dr in [ar + 2, ar + 3]:
		return 0
	if _wall_open(2) and ((ar == 0 and dr == 4) or (ar == 4 and dr == 0)):
		return 0
	return 4

func _wall_open(row: int) -> bool:
	return row >= 0 and row < wall_hp.size() and int(wall_hp[row]) == 0

func luck_for(stack: BattleStack) -> int:
	var hero = heroes[stack.side] \
			if stack.side >= 0 and stack.side < heroes.size() else null
	return clampi(int(hero.effective_luck()), -3, 3) if hero != null else 0

static func negative_morale_triggers(morale: int, roll_12: int) -> bool:
	return morale < 0 and roll_12 < -morale

static func positive_morale_triggers(morale: int, roll_24: int) -> bool:
	return morale > 0 and roll_24 < morale

## Good morale is rolled by any action that spends the stack's turn. The
## original's sunbird roll (heroes.exe 0x8ab26, `Random(1, 24)` at 0x8abf0) is
## reached from exactly two places in the combat action switch: the
## move-and-strike case (0xc26df, action code 2) and the melee case (0xc2771,
## action code 6). The plain move is that same code 2 path — 0x9184a walks the
## acting stack toward the target cell and strikes only when it reaches one,
## and the switch rolls morale on the way out either way. The wait case
## (action code 3, set by the Space key at 0xbf8fe, handled at 0xc2824) and the
## hero's spell cast (action code 1, handled at 0xc261b) mark the stack as
## having acted without ever rolling.
static func action_grants_morale(action: String) -> bool:
	return (action == "move" or action == "shoot" or action == "melee"
			or action == "move_melee")

static func luck_outcome(luck: int, roll_12: int) -> int:
	if luck > 0 and roll_12 < luck:
		return 1
	if luck <= -2 and roll_12 < -(luck + 1):
		return -1
	return 0

## Negative morale is checked immediately before the scheduled action. The
## battle's first stack is immune; computer defenders get the native extra 25%
## chance to shake off a failed check.
func fails_morale(stack: BattleStack, computer_controlled := false) -> bool:
	if _first_turn_pending:
		_first_turn_pending = false
		return false
	var morale := morale_for(stack)
	if not negative_morale_triggers(morale, int(rng.randi() % 12)):
		return false
	if computer_controlled and rng.randi() % 4 == 0:
		return false
	return true

## End the acting stack's turn after `action`. Moving or attacking rolls for
## good morale (see `action_grants_morale`); waiting does not.
func finish_action(stack: BattleStack, action: String) -> bool:
	return finish_turn(stack, action_grants_morale(action))

## Returns true when good morale grants one immediate extra action. The extra
## action cannot generate another morale action in the same round.
func finish_turn(stack: BattleStack, allow_morale := true) -> bool:
	if _morale_extra.has(stack):
		end_turn()
		return false
	var morale := morale_for(stack)
	if allow_morale and stack.is_alive() and winner() == -1 and morale > 0 \
			and positive_morale_triggers(morale, int(rng.randi() % 24)):
		_last_action_side = stack.side
		_morale_extra[stack] = true
		return true
	end_turn()
	return false

func _roll_luck(stack: BattleStack) -> int:
	var luck := luck_for(stack)
	if luck == 0 or luck == -1:
		return 0
	return luck_outcome(luck, int(rng.randi() % 12))

func stack_at(hex: Vector2i) -> BattleStack:
	for s: BattleStack in stacks:
		if s.is_alive() and s.occupies(hex):
			return s
	return null

func occupancy(exclude: BattleStack = null) -> Dictionary:
	var o := static_blocked.duplicate()
	for s: BattleStack in stacks:
		if s.is_alive() and s != exclude:
			for c: Vector2i in s.cells():
				o[c] = true
	return o

## Convert occupied board cells into invalid anchor cells for this stack. A wide
## walker must keep both its anchor and body cell clear at every waypoint, not
## only at its final destination. `occupied` leaves the stack's own cells out,
## so its rear cell may step onto the cell its front already covers and the
## whole body shifts one cell forward (KB battlefield.md 2.2).
func _movement_blockers(stack: BattleStack, occupied: Dictionary) -> Dictionary:
	if not stack.wide:
		return occupied
	var blocked := {}
	for row in Hex.ROWS:
		for col in Hex.COLS:
			var anchor := Vector2i(col, row)
			for cell: Vector2i in stack.cells_at(anchor):
				if not Hex.in_bounds(cell.x, cell.y) or occupied.has(cell):
					blocked[anchor] = true
					break
	return blocked

## Reachable anchor cells. For wide units both occupied cells must remain free
## throughout the route.
func reachable_for(stack: BattleStack) -> Dictionary:
	var occ := occupancy(stack)
	var r := Movement.flying_reachable(stack.hex) \
			if stack.is_flying() else Movement.reachable(stack.hex, stack.effective_speed(),
					_movement_blockers(stack, occ))
	var out := {}
	for h: Vector2i in r:
		var valid := true
		for cell: Vector2i in stack.cells_at(h):
			if not Hex.in_bounds(cell.x, cell.y) or occ.has(cell):
				valid = false
				break
		if valid:
			out[h] = r[h]
	return out

## Animation path for the already-validated destination. Flyers glide directly
## to the target in a straight line; walkers route around blockers via hex BFS.
func movement_path(stack: BattleStack, dest: Vector2i) -> Array:
	if stack.is_flying():
		return [dest] if dest != stack.hex else []
	var blocked := _movement_blockers(stack, occupancy(stack))
	return Movement.path(stack.hex, dest, blocked)

func is_blocked(stack: BattleStack) -> bool:
	for s: BattleStack in stacks:
		if s.is_alive() and s.side != stack.side and adjacent(stack, s):
			return true
	return false

func can_attack(attacker: BattleStack, defender: BattleStack) -> bool:
	if defender == null or not defender.is_alive() or defender == attacker:
		return false
	if attacker.has_effect("berserk"):
		return adjacent(attacker, defender)
	if attacker.side == defender.side:
		return false
	if attacker.is_ranged() and attacker.shots > 0 and not is_blocked(attacker):
		return true
	return adjacent(attacker, defender)

## Min hex distance between any cell of `a` and any cell of `b`.
static func cell_distance(a_cells: Array, b_cells: Array) -> int:
	var m := 1 << 30
	for ac: Vector2i in a_cells:
		for bc: Vector2i in b_cells:
			m = mini(m, Hex.distance(ac.x, ac.y, bc.x, bc.y))
	return m

## True if the two stacks occupy mutually adjacent cells (melee range).
func adjacent(a: BattleStack, b: BattleStack) -> bool:
	return cell_distance(a.cells(), b.cells()) == 1

## True if placing `stack`'s anchor at `dest` would put it in melee range of `target`.
func dest_adjacent(stack: BattleStack, dest: Vector2i, target: BattleStack) -> bool:
	return cell_distance(stack.cells_at(dest), target.cells()) == 1

func move(stack: BattleStack, dest: Vector2i) -> bool:
	if not reachable_for(stack).has(dest):
		return false
	stack.hex = dest
	return true

## Stack one cell behind `defender` on the attack line. Cyclops, Phoenix, and
## Dragon strikes damage this second stack even when it is friendly. A strike
## has one direction (heroes.exe 0x8f5c6), and the second hit lands on the cell
## past the struck cell in that direction (0x8fa75..0x8faee). There is none
## when that cell holds the struck stack (a frontal strike on a wide body) or
## when a wide attacker strikes the cell above or below its middle (6 and 7).
func line_secondary(attacker: BattleStack, defender: BattleStack) -> BattleStack:
	return _line_victim(attacker, _strike_dir(attacker, defender))

## The cell `stack` strikes from and the cell it lands on in strike direction
## `dir` (Hex.strike_step). A wide stack strikes rightward from its right cell
## and leftward from its left cell (0x8f6fc); 6 and 7 land above and below the
## middle of its body (0xadeab).
func _strike_cells(stack: BattleStack, dir: int) -> Array:
	var left := Vector2i(mini(stack.cells()[0].x, stack.cells()[-1].x), stack.hex.y)
	var right := left + Vector2i(1, 0) if stack.wide else left
	if dir >= 6:
		return [right, Hex.strike_step(right, 5 if dir == 6 else 3)]
	var origin := right if dir <= 2 else left
	return [origin, Hex.strike_step(origin, dir)]

## The direction `attacker` strikes `defender` in, -1 when they do not touch.
## Every direction is tried and the last one that lands on the defender wins,
## as in the computer player's choice (0x91a84).
func _strike_dir(attacker: BattleStack, defender: BattleStack) -> int:
	var dir := -1
	for d: int in (8 if attacker.wide else 6):
		if defender.occupies(_strike_cells(attacker, d)[1]):
			dir = d
	return dir

## The retaliation strikes back along the reversed direction (0xae39e), and a
## wide retaliator whose attacker stands above or below its middle uses 6 or 7
## (0x902b6).
func _retaliation_line(attacker: BattleStack, defender: BattleStack) -> BattleStack:
	var dir := _strike_dir(attacker, defender)
	if dir < 0:
		return null
	dir = (dir + 3) % 6 if dir < 6 else 13 - dir
	if defender.wide:
		if attacker.hex == _strike_cells(defender, 6)[1]:
			dir = 6
		elif attacker.hex == _strike_cells(defender, 7)[1]:
			dir = 7
	return _line_victim(defender, dir)

func _line_victim(striker: BattleStack, dir: int) -> BattleStack:
	if dir < 0 or dir >= 6:
		return null
	var cells := _strike_cells(striker, dir)
	var candidate := stack_at(Hex.behind(cells[0], cells[1]))
	return candidate if candidate != stack_at(cells[1]) else null

func _strike(attacker: BattleStack, defender: BattleStack,
		minimum_damage := false, allow_paralyze := true,
		melee_attack := false, allow_luck := true,
		blind_retaliation := false) -> Dictionary:
	var base_damage := attacker.count * attacker.damage_min if minimum_damage \
			else BattleRules.roll_base_damage(attacker, rng)
	var effective_attack := attack_for(attacker)
	var wall_bonus := siege_defense_bonus(attacker, defender, melee_attack)
	var effective_defense := defense_for(defender) + wall_bonus
	var ordinary_damage := DamageCalc.compute_base(
			base_damage, effective_attack, effective_defense)
	if melee_attack and attacker.is_shooter():
		ordinary_damage = maxi(1, int(ordinary_damage / 2))
	if blind_retaliation:
		ordinary_damage = maxi(1, int(ordinary_damage / 2))
	var luck := _roll_luck(attacker) if allow_luck else 0
	if luck > 0:
		ordinary_damage *= 2
	elif luck < 0:
		ordinary_damage = maxi(1, int(ordinary_damage / 2))
	var report := BattleAbilitiesScript.strike(
			attacker, defender, ordinary_damage, rng, allow_paralyze)
	report["luck"] = luck
	report["melee_penalty"] = melee_attack and attacker.is_shooter()
	report["blind_retaliation"] = blind_retaliation
	report["effective_attack"] = effective_attack
	report["effective_defense"] = effective_defense
	report["hero_attack_bonus"] = hero_attack_bonus(attacker)
	report["hero_defense_bonus"] = hero_defense_bonus(defender)
	report["siege_defense_bonus"] = wall_bonus
	report["base_damage"] = base_damage
	return report

func _secondary_attacks(attacker: BattleStack, primary: BattleStack,
		line_target: BattleStack = null, allow_paralyze := true) -> Array:
	var hits: Array = []
	if attacker.attack_all_adjacent:
		for target: BattleStack in stacks:
			if target != primary and target.is_alive() and target.side != attacker.side \
					and adjacent(attacker, target):
				var p := target.has_effect("paralyze")
				var b := target.has_effect("blind")
				hits.append({"target": target,
					"attack": _strike(attacker, target, false, true, true, false)})
				_wake(target, p, b)
	elif attacker.two_cell_attack and line_target != null and line_target.is_alive():
		var p := line_target.has_effect("paralyze")
		var b := line_target.has_effect("blind")
		hits.append({"target": line_target,
				"attack": _strike(
						attacker, line_target, false, allow_paralyze, true, false)})
		_wake(line_target, p, b)
	return hits

## A whole melee exchange: the strike, the retaliation, then a Wolf's or a
## Paladin's second strike. The animated battle runs the three steps itself so
## each strike lands on the board before the next one is rolled, as heroes.exe
## does; this resolves them back to back for simulations and tests. The
## random draws come in the same order either way.
func melee(attacker: BattleStack, defender: BattleStack) -> Dictionary:
	var r := melee_strike(attacker, defender)
	r.merge(melee_retaliation(attacker, defender, r))
	r["second_attack"] = melee_second_strike(attacker, defender)
	if attacker.has_effect("berserk"):
		attacker.clear_effect()
	return r

## The attacker's first strike (heroes.exe 0x8f5c6 with no retaliation flag).
## Pass the result to `melee_retaliation`.
func melee_strike(attacker: BattleStack, defender: BattleStack) -> Dictionary:
	var attack_line := line_secondary(attacker, defender) if attacker.two_cell_attack else null
	var defender_was_paralyzed := defender.has_effect("paralyze")
	var defender_was_blind := defender.has_effect("blind")
	var atk := _strike(attacker, defender, false, true, true)
	var attack_splashes := _secondary_attacks(
			attacker, defender, attack_line, not bool(atk.status_rolled))
	_wake(defender, defender_was_paralyzed, defender_was_blind)
	return {
		"attack": atk,
		"attack_splashes": attack_splashes,
		"defender_was_paralyzed": defender_was_paralyzed,
		"defender_was_blind": defender_was_blind,
	}

## The defender's answer to `strike`, a `melee_strike` result. Empty when it
## cannot retaliate.
func melee_retaliation(attacker: BattleStack, defender: BattleStack,
		strike: Dictionary) -> Dictionary:
	var retal := {}
	var retaliation_splashes: Array = []
	var atk: Dictionary = strike.attack
	var defender_was_blind := bool(strike.defender_was_blind)
	var status_inflicted := String(atk.get("ability", "")) in ["paralyze", "blind"]
	var can_counter := defender.is_alive() and not attacker.no_retaliation \
			and not bool(strike.defender_was_paralyzed) and not status_inflicted \
			and defender.can_retaliate()
	if can_counter:
		var retaliation_line := _retaliation_line(attacker, defender) \
				if defender.two_cell_attack else null
		defender.has_retaliated = true
		retal = _strike(defender, attacker, false, true, true, true, defender_was_blind)
		retaliation_splashes = _secondary_attacks(
				defender, attacker, retaliation_line, not bool(retal.status_rolled))
	return {"retaliation": retal, "retaliation_splashes": retaliation_splashes}

## A Wolf's or a Paladin's second strike, empty when there is none. heroes.exe
## 0x903bc runs the whole strike routine again after the retaliation, with
## its own luck roll and no retaliation of its own.
func melee_second_strike(attacker: BattleStack, defender: BattleStack) -> Dictionary:
	if not (attacker.is_alive() and defender.is_alive() and attacker.double_attack \
			and attacker.unit != "elf" and not attacker.has_effect("paralyze")):
		return {}
	# Blind inflicted by a Unicorn retaliation still permits the second hit,
	# but pins it to minimum damage. Paralyze cancels it entirely.
	return _strike(attacker, defender, attacker.has_effect("blind"), true, true)

## Waking a paralyzed or blind defender consumes its turn for the round;
## paralyzed units also lose their retaliation (KB spells.md 5.4).
func _wake(defender: BattleStack, was_paralyzed: bool, was_blind: bool) -> void:
	if was_paralyzed:
		if not defender.infinite_retaliation:
			defender.has_retaliated = true
		defender.turn_spent = true
		_acted[defender] = true
	elif was_blind:
		defender.turn_spent = true
		_acted[defender] = true

## Both of an Elf volley's arrows resolved back to back; see `melee`.
func shoot(attacker: BattleStack, defender: BattleStack) -> Dictionary:
	var first := shoot_once(attacker, defender)
	var second := shoot_once(attacker, defender) \
			if shoots_again(attacker, defender) else {}
	return {"attack": first, "second_attack": second}

## One arrow (heroes.exe 0x8e241): a shot spent, luck, damage.
func shoot_once(attacker: BattleStack, defender: BattleStack) -> Dictionary:
	attacker.shots = maxi(attacker.shots - 1, 0)
	var defender_was_paralyzed := defender.has_effect("paralyze")
	var defender_was_blind := defender.has_effect("blind")
	var report := _strike(attacker, defender)
	_wake(defender, defender_was_paralyzed, defender_was_blind)
	return report

## Whether an Elf's first arrow is followed by a second. 0x8e241 calls itself
## once more for an Elf (creature 0xe) while the target lives, even when the
## first arrow spent the last shot.
func shoots_again(attacker: BattleStack, defender: BattleStack) -> bool:
	return attacker.double_attack and attacker.unit == "elf" and defender.is_alive()

## Complete the selected stack. Only a full action changes the preferred side;
## negative morale and disabled-stack skips pass `performed_action = false`.
func end_turn(performed_action := true) -> void:
	if _current != null:
		_acted[_current] = true
		_current.turn_spent = true
		if performed_action:
			_last_action_side = _current.side
	_current = null

func winner() -> int:
	if _forced_winner >= 0:
		return _forced_winner
	var a := false
	var d := false
	for s: BattleStack in stacks:
		if s.is_alive():
			if s.side == 0:
				a = true
			else:
				d = true
	if a and not d:
		return 0
	if d and not a:
		return 1
	return -1

func force_winner(side: int) -> void:
	_forced_winner = clampi(side, 0, 1)
	_current = null

## Victory XP for `side` (KB experience.md §14.1, battle.md):
## - 1 XP per 1 HP of killed hostile creatures.
## - Exceptions: Trolls grant 1.25x HP (50 XP each), Cyclopes grant 0.75x HP (60 XP each).
## - Partial damage to a stack's surviving top creature does not count.
## - Defeating an enemy hero awards +500 XP.
## - Capturing a town/castle (defeating siege defender) awards +500 XP.
func xp_for(side: int, enemy_withdrew: bool = false) -> int:
	var xp := 0
	for s: BattleStack in stacks:
		if s.side != side:
			var mult: float = 1.25 if s.unit == "troll" else (0.75 if s.unit == "cyclops" else 1.0)
			var dead_count: int = clampi(s.count_initial - s.count, 0, s.count_initial)
			xp += int(round(float(dead_count * s.hp_max) * mult))
	var opp_side := 1 - side
	if not enemy_withdrew and opp_side >= 0 and opp_side < heroes.size() and heroes[opp_side] != null:
		xp += 500
	if siege_defender_side == opp_side:
		xp += 500
	return xp

