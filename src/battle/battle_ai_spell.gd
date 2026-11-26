class_name BattleAISpell
extends RefCounted

## The computer hero's combat spell choice, as heroes.exe makes it (KB
## auto-combat-ai.md section 7; tables in data/spells/ai_spell_choice.json).
## Every combat spell with charges is scored against every legal target with
## integer arithmetic, and the single highest score above 0 is cast. A tie
## goes to the spell learned first. choose() returns {} or {spell_id, target};
## the caller resolves it through SpellCast.cast.

const TABLE_PATH := "res://data/spells/ai_spell_choice.json"

static var _table: Dictionary = {}

static func _data() -> Dictionary:
	if _table.is_empty():
		_table = JsonFile.read_dict(TABLE_PATH)
		if _table.is_empty():
			_table = {"_missing": true}
	return _table

## Best castable spell this turn, or {}.
static func choose(state: BattleState, side: int) -> Dictionary:
	var hero = state.heroes[side]
	if hero == null or not hero.has_spellbook or state.cast_used[side]:
		return {}
	var sp: int = maxi(int(hero.effective_spell_power()), 1)
	var best := {}
	var best_score := 0
	for id: String in hero.spellbook.spells:
		if SpellData.get_spell(id).get("context", "") != "battle" \
				or hero.spellbook.charges(id) <= 0:
			continue
		var sc := score_spell(state, side, id, sp)
		if int(sc.score) > best_score:
			best_score = int(sc.score)
			best = {"spell_id": id, "target": sc.target}
	return best

## Score one spell at its best target: {"score": int, "target": Variant}.
## A score of 0 or less means the AI would not cast it.
static func score_spell(state: BattleState, side: int, spell_id: String, sp: int) -> Dictionary:
	var spell := SpellData.get_spell(spell_id)
	if spell.is_empty() or String(spell.get("context", "")) != "battle":
		return _result(0, null)
	match String(spell.get("kind", "")):
		"damage":
			return _score_damage(state, side, spell, sp)
		"buff":
			return _score_status(state, side, spell_id, sp, true)
		"debuff":
			return _score_status(state, side, spell_id, sp, false)
		"cure":
			return _result(_cure_value(state, side), null)
		"dispel":
			return _result(_dispel_value(state, side), null)
		"resurrect":
			return _score_resurrect(state, side, sp)
		"kill_undead":
			return _score_kill_undead(state, side)
	return _result(0, null)   # Teleport: the exe scores it 0

## A stack's worth: count x the creature's value.
static func stack_value(s: BattleStack) -> int:
	return s.count * int(_data().get("creature_value", {}).get(s.unit, 0))

## E(stack, spell), the signed worth of a duration effect on this stack to its
## owner (heroes.exe 0xca23a). Products truncate toward zero, as the exe does.
static func effect_value(s: BattleStack, spell_id: String) -> int:
	var weights: Dictionary = _data().get("effect_weight", {})
	if not weights.has(spell_id):
		return 0
	# The exe's weights are 32-bit floats; truncation must see the same value.
	var w: float = PackedFloat32Array([float(weights[spell_id])])[0]
	var base := float(stack_value(s))
	var v := 0
	match spell_id:
		"slow":
			if s.is_shooter():
				v = 0
			elif s.flying:
				v = int(base * w * float(_data().get("slow_flyer_factor", 3.0)))
			else:
				v = int(float(s.speed - 1) * base * w)
		"haste":
			if s.flying or s.is_shooter() or s.speed >= 3:
				v = 0
			elif s.speed < 2:
				v = int(base * w)
			else:
				v = int(base * w * float(_data().get("haste_medium_factor", 0.5)))
		_:
			v = int(base * w)
	if s.magic_immune or s.has_effect("anti_magic"):
		return 0
	if v < 0 and s.magic_resist > 0.0:
		v = int(float(v) * (1.0 - s.magic_resist))
	return v

static func _result(score: int, target: Variant) -> Dictionary:
	return {"score": score, "target": target}

static func _shift(sp: int) -> int:
	return int(_data().get("spell_power_shift", {}).get(str(sp), 0))

static func _alive(state: BattleState, side: int) -> Array:
	return state.stacks.filter(func(s): return s.is_alive() and s.side == side)

static func _current_effect(s: BattleStack) -> String:
	return String(s.active_effect.get("id", ""))

## Legal targets only. The exe checks no immunity beyond Dragons and
## Anti-Magic, which effect_value and _damage_score already price at 0.
static func _castable(state: BattleState, side: int, spell_id: String, target: Variant) -> bool:
	return SpellCast.target_is_valid(state, side, spell_id, target)

## Buffs on own stacks, debuffs on enemy stacks. Either way the new effect
## replaces the stack's current one, whose worth is given back.
static func _score_status(state: BattleState, side: int, spell_id: String, sp: int,
		buff: bool) -> Dictionary:
	if spell_id == "anti_magic" and state.heroes[1 - side] == null:
		return _result(0, null)
	var shift := _shift(sp)
	var best := _result(0, null)
	for s: BattleStack in _alive(state, side if buff else 1 - side):
		if not _castable(state, side, spell_id, s):
			continue
		var v := 0
		var current := _current_effect(s)
		if buff:
			v = (effect_value(s, spell_id) >> shift) - effect_value(s, current)
		else:
			v = -(effect_value(s, spell_id) >> shift) + effect_value(s, current)
		if v > int(best.score):
			best = _result(v, s)
	return best

## Cure: the worth of every debuff on our side (heroes.exe 0xca616).
static func _cure_value(state: BattleState, side: int) -> int:
	var v := 0
	for s: BattleStack in _alive(state, side):
		if _current_effect(s) in SpellCast.DEBUFFS:
			v -= effect_value(s, _current_effect(s))
	return v

## Dispel: debuffs lifted off our side and buffs off theirs count for us;
## buffs we lose and debuffs they lose count against.
static func _dispel_value(state: BattleState, side: int) -> int:
	var v := 0
	for s: BattleStack in state.stacks:
		if not s.is_alive() or _current_effect(s) == "":
			continue
		var e := effect_value(s, _current_effect(s))
		v += -e if s.side == side else e
	return v

## Resurrect: creatures restored, spell power x 50 / hp, capped at the stack's
## starting count, times the creature's value (heroes.exe 0xca806).
static func _score_resurrect(state: BattleState, side: int, sp: int) -> Dictionary:
	var heal := int(SpellData.get_spell("resurrect").get("dmg_per_sp", 50)) * sp
	var best := _result(0, null)
	for s: BattleStack in _alive(state, side):
		if s.magic_immune or s.has_effect("anti_magic") or not _castable(state, side, "resurrect", s):
			continue
		var restored := mini(heal / maxi(s.hp_max, 1), s.count_initial - s.count)
		var v := maxi(restored, 0) * int(_data().get("creature_value", {}).get(s.unit, 0))
		if v > int(best.score):
			best = _result(v, s)
	return best

static func _score_kill_undead(state: BattleState, side: int) -> Dictionary:
	var best := _result(0, null)
	for s: BattleStack in _alive(state, 1 - side):
		if not s.undead or s.has_effect("anti_magic") or not _castable(state, side, "kill_undead", s):
			continue
		var v := stack_value(s)
		if v > int(best.score):
			best = _result(v, s)
	return best

## Damage spells (heroes.exe 0xca8fc). Lightning Bolt tries each enemy stack,
## Storm and Armageddon hit every stack, and Fireball and Meteor Shower try
## every cell, scoring only the stacks on its six neighbours: the exe leaves
## the aimed cell's own stack out of the score.
static func _score_damage(state: BattleState, side: int, spell: Dictionary, sp: int) -> Dictionary:
	var spell_id := String(spell.id)
	var dmg := int(spell.get("dmg_per_sp", 0)) * sp
	var best := _result(0, null)
	match String(spell.get("target", "")):
		"enemy_stack":
			for s: BattleStack in _alive(state, 1 - side):
				if not _castable(state, side, spell_id, s):
					continue
				var v := _damage_score(state, side, spell_id, [s], dmg)
				if v > int(best.score):
					best = _result(v, s)
		"all_stacks":
			var all := state.stacks.filter(func(s): return s.is_alive())
			best = _result(_damage_score(state, side, spell_id, all, dmg), null)
		"cell_area":
			for row in Hex.ROWS:
				for col in Hex.COLS:
					var cell := Vector2i(col, row)
					if not _castable(state, side, spell_id, cell):
						continue
					var hit: Array = []
					for n: Vector2i in Hex.neighbors(col, row):
						var s := state.stack_at(n)
						if s != null and s.is_alive() and not s in hit:
							hit.append(s)
					var v := _damage_score(state, side, spell_id, hit, dmg)
					if v > int(best.score):
						best = _result(v, cell)
	return best

static func _damage_score(state: BattleState, side: int, spell_id: String, hit: Array,
		dmg: int) -> int:
	var data := _data()
	var values: Dictionary = data.get("creature_value", {})
	var wound_factor := float(data.get("wound_factor", 0.75))
	var partial := [0, 0]
	var whole := [0, 0]
	var wiped := [0, 0]
	for s: BattleStack in hit:
		if s.magic_immune or s.has_effect("anti_magic"):
			continue
		var d := dmg
		if s.magic_resist > 0.0:
			d = int(float(dmg) * (1.0 - s.magic_resist))
		var hp := maxi(s.hp_max, 1)
		var kills := d / hp
		var rest := d % hp
		var wound := s.hp_max - s.hp_current
		if rest + wound >= hp:
			kills += 1
			rest -= hp - wound
		if s.count <= kills:
			kills = s.count
			rest = 0
			wiped[s.side] += 1
		var value := int(values.get(s.unit, 0))
		partial[s.side] += int((float(kills * hp) + float(rest) * wound_factor) * float(value) / float(hp))
		whole[s.side] += kills * value
	var foe := 1 - side
	if wiped[0] >= _alive(state, 0).size() or wiped[1] >= _alive(state, 1).size():
		if whole[side] <= 0:
			return int(data.get("finishing_blow_base", 100000000)) \
					- int(data.get("finishing_blow_cost", {}).get(spell_id, 0))
		return whole[foe] - whole[side]
	return partial[foe] - partial[side]
