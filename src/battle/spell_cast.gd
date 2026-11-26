class_name SpellCast

## Battle-spell resolver. All rules transcribed from data/knowledge_base/spells.md.
## SP = caster's spell_power; charges live in the hero's Spellbook (Knowledge).

const MIND_SPELLS := ["blind", "paralyze", "berserk"]
const DEBUFFS := ["slow", "curse", "blind", "paralyze", "berserk"]

static func cast(state: BattleState, side: int, spell_id: String, target) -> Dictionary:
	var out := {"ok": false, "reason": "", "hits": [], "resisted": []}
	var hero = state.heroes[side]
	if hero == null:
		out.reason = "no_hero"; return out
	if not hero.has_spellbook:
		out.reason = "no_book"; return out
	if state.cast_used[side]:
		out.reason = "already_cast"; return out
	if hero.spellbook.charges(spell_id) <= 0:
		out.reason = "no_charges"; return out
	var spell := SpellData.get_spell(spell_id)
	if spell.is_empty() or spell.context != "battle":
		out.reason = "bad_target"; return out
	var sp: int = max(int(hero.effective_spell_power()), 1)

	match String(spell.kind):
		"damage":
			var targets := _damage_targets(state, spell, side, target)
			if targets.is_empty():
				out.reason = "bad_target"; return out
			for s in targets:
				if _blocked(s, spell, state.rng):
					out.resisted.append(s)
					continue
				var dmg := int(spell.dmg_per_sp) * sp
				if s.has_effect("paralyze"):
					if not s.infinite_retaliation:
						s.has_retaliated = true
					s.turn_spent = true
					state._acted[s] = true
				elif s.has_effect("blind"):
					s.turn_spent = true
					state._acted[s] = true
				out.hits.append({"stack": s, "damage": dmg, "killed": s.apply_damage(dmg)})
			out.ok = true
			# An area spell can kill both armies. winner() reads -1 with no one
			# alive, which spins the turn loop forever, so the caster loses.
			if state.stacks.all(func(st): return not st.is_alive()):
				state.force_winner(1 - side)
		"buff", "debuff":
			if not (target is BattleStack) or not target.is_alive() or not _side_ok(spell, side, target):
				out.reason = "bad_target"; return out
			out.ok = true
			if _blocked(target, spell, state.rng):
				out.resisted.append(target)
			else:
				var rounds: int = sp
				target.apply_spell_effect(spell_id, rounds)
				if spell_id == "bless":
					target.eternal_curse = false     # KB 5.4
				elif spell_id == "paralyze":
					target.eternal_curse = true      # KB 5.4 hidden property
				out.hits.append({"stack": target, "damage": 0, "killed": 0})
		"dispel":
			for s in state.stacks:
				if s.is_alive() and not s.active_effect.is_empty() \
						and not s.has_effect("anti_magic"):
					s.clear_effect()  # eternal_curse survives (KB 5.4)
					out.hits.append({"stack": s, "damage": 0, "killed": 0})
			out.ok = true
		"cure":
			for s in state.stacks:
				if s.is_alive() and s.side == side \
						and String(s.active_effect.get("id", "")) in DEBUFFS:
					s.clear_effect()
					out.hits.append({"stack": s, "damage": 0, "killed": 0})
			out.ok = true
		"resurrect":
			if not (target is BattleStack) or target.side != side or not target.is_alive():
				out.reason = "bad_target"; return out
			if _blocked(target, spell, state.rng):
				out.resisted.append(target)
			else:
				var before: int = target.count
				var raise_count := int((int(spell.dmg_per_sp) * sp) / target.hp_max)
				# A Ghost stack can stand above its start count; never shrink it.
				target.count = mini(maxi(target.count_initial, target.count),
						target.count + raise_count)
				out.hits.append({"stack": target, "damage": 0, "killed": 0,
						"raised": target.count - before})
			out.ok = true
		"teleport":
			if not (target is Dictionary) or not (target.get("stack") is BattleStack) \
					or not (target.get("dest") is Vector2i):
				out.reason = "bad_target"; return out
			var st: BattleStack = target.stack
			var dest: Vector2i = target.dest
			if st.side != side or not _cells_free(state, st, dest):
				out.reason = "bad_target"; return out
			var from_hex: Vector2i = st.hex
			st.hex = dest
			out.hits.append({
				"stack": st,
				"from_hex": from_hex,
				"dest_hex": dest,
				"damage": 0,
				"killed": 0,
			})
			out.ok = true
		"kill_undead":
			if not (target is BattleStack) or not target.is_alive() or target.side == side:
				out.reason = "bad_target"; return out
			if not target.undead:
				out.reason = "no_effect"; return out
			if _blocked(target, spell, state.rng):
				out.resisted.append(target)
				out.ok = true
			else:
				var dmg: int = target.total_hp()
				out.hits.append({"stack": target, "damage": dmg, "killed": target.apply_damage(dmg)})
				out.ok = true
		_:
			out.reason = "bad_target"; return out

	if out.ok:
		hero.spellbook.cast(spell_id)
		state.cast_used[side] = true
	return out

## Stacks a stack-target spell may legally hit — used by battle UI highlight.
static func valid_targets(state: BattleState, side: int, spell_id: String) -> Array:
	var spell := SpellData.get_spell(spell_id)
	var alive := state.stacks.filter(func(s): return s.is_alive())
	if String(spell.get("kind", "")) == "kill_undead":
		return alive.filter(func(s): return s.side != side and s.undead)
	match String(spell.get("target", "")):
		"own_stack":
			return alive.filter(func(s): return s.side == side)
		"enemy_stack":
			return alive.filter(func(s): return s.side != side)
		"any_stack":
			return alive
	return []

## Whether the battle UI may commit `target` for this spell. This deliberately
## excludes resistance/immunity (a legal cast may still be resisted), while
## rejecting picks the resolver would bounce as bad_target/no_effect.
static func target_is_valid(state: BattleState, side: int, spell_id: String, target) -> bool:
	var spell := SpellData.get_spell(spell_id)
	if spell.is_empty() or String(spell.get("context", "")) != "battle":
		return false
	match String(spell.get("kind", "")):
		"damage":
			return not _damage_targets(state, spell, side, target).is_empty()
		"buff", "debuff":
			return target is BattleStack and target.is_alive() and _side_ok(spell, side, target)
		"dispel", "cure":
			return target == null
		"resurrect":
			return target is BattleStack and target.side == side and target.is_alive()
		"teleport":
			if not (target is Dictionary) or not (target.get("stack") is BattleStack) \
					or not (target.get("dest") is Vector2i):
				return false
			var stack: BattleStack = target.stack
			return stack.is_alive() and stack.side == side \
					and _cells_free(state, stack, target.dest)
		"kill_undead":
			return target is BattleStack and target.is_alive() \
					and target.side != side and target.undead
	return false

static func _side_ok(spell: Dictionary, side: int, s: BattleStack) -> bool:
	match String(spell.target):
		"own_stack": return s.side == side
		"enemy_stack": return s.side != side
	return true

## Immunity/resistance (monsters.md 10.3, spells-fog-objects.md): full magic immunity,
## mind-spell immunity, percent resist roll per spell, anti-magic effect.
static func _blocked(s: BattleStack, spell: Dictionary, rng: RandomNumberGenerator) -> bool:
	if s.magic_immune:
		return true
	if s.has_effect("anti_magic") and String(spell.get("id", "")) != "anti_magic":
		return true
	if s.mind_immune and String(spell.id) in MIND_SPELLS:
		return true
	var resist := s.spell_resist_chance(String(spell.get("id", "")))
	if resist > 0.0 and rng.randf() < resist:
		return true
	return false

static func _damage_targets(state: BattleState, spell: Dictionary, side: int, target) -> Array:
	var alive := state.stacks.filter(func(s): return s.is_alive())
	match String(spell.target):
		"enemy_stack":
			if target is BattleStack and target.side != side and target.is_alive():
				return [target]
			return []
		"all_stacks":
			return alive
		"cell_area":
			if not (target is Vector2i):
				return []
			var hexes := [target] + Hex.neighbors(target.x, target.y)
			var seen := {}
			var found: Array = []
			for s in alive:
				for c in s.cells():
					if c in hexes and not seen.has(s):
						seen[s] = true
						found.append(s)
			return found
	return []

static func _cells_free(state: BattleState, st: BattleStack, dest: Vector2i) -> bool:
	var occ := state.occupancy(st)
	for c in st.cells_at(dest):
		if occ.has(c) or c.x < 0 or c.x >= Hex.COLS or c.y < 0 or c.y >= Hex.ROWS:
			return false
	return true
