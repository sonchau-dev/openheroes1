class_name AIArrival
extends RefCounted

## Resolves the AI hero arriving on its destination target: encounters (guards,
## dwellings, guarded pickups, general objects), town sieges, enemy/human hero
## engagements, ultimate artifact digging, and launching battles.

var _root: Node2D
var _map: MapData
var _astar: PassabilityGrid
var _world: AdventureWorldRenderer
var _roster: AIHeroRoster
var _castle_turn: AICastleTurn
var _prepare_for_battle_fn: Callable
var _turn_economy: Dictionary = {}
var shown_to_human: bool = false

func setup(root: Node2D, map: MapData, astar: PassabilityGrid,
		world: AdventureWorldRenderer, roster: AIHeroRoster,
		castle_turn: AICastleTurn, prepare_for_battle_fn: Callable,
		turn_economy: Dictionary) -> void:
	_root = root
	_map = map
	_astar = astar
	_world = world
	_roster = roster
	_castle_turn = castle_turn
	_prepare_for_battle_fn = prepare_for_battle_fn
	_turn_economy = turn_economy

func resolve_arrival(ai: PlayerState, target: Dictionary) -> bool:
	match String(target.get("kind", "")):
		# A stack taken as a target is stepped onto like a guard: it joins when
		# it offers to and the army has room, and is fought otherwise
		# (diplomacy.md). Only offering the join left a full army beside a
		# joinable stack re-taking it all day, every day.
		"guard", "stack":
			return await fight_guard(ai, target.object as NeutralStack)
		"own_town":
			if _castle_turn != null:
				var town_obj := target.get("object") as TownObject
				var town_model: TownModel = null
				if town_obj != null:
					town_model = ai.town_by_object_id(town_obj.id)
				if town_model == null:
					town_model = _castle_turn.home_town(ai)
				_castle_turn.visit_own_castle(ai, town_model)
			return false
		"player_hero":
			var human_side := Game.state.active_player_side if Game.state != null else 0
			return attack_human_hero(ai, Game.state.player_of(human_side) if Game.state != null else null,
					int(target.get("hero_index", -1)))
		"player_town":
			var town_obj := _target_town(target)
			# A hero in the gate defends the town and is fought first.
			var gate_keeper := gate_defender(ai, town_obj)
			if not gate_keeper.is_empty():
				return await resolve_arrival(ai, gate_keeper)
			var human := Game.state.human() if Game.state != null else null
			var town_model := human.town_by_object_id(town_obj.id) if human != null and town_obj != null else (human.town if human != null else null)
			var garrison: ArmyData = town_model.army if town_model != null else (town_obj.garrison if town_obj != null else null)
			if garrison == null or garrison.is_empty():
				if town_obj != null:
					if _castle_turn != null:
						await _castle_turn.capture_town(town_obj, ai.side)
						_castle_turn.visit_own_castle(ai, ai.town_by_object_id(town_obj.id))
				return true
			launch_ai_battle(ai, garrison, Game.state.active_player_side if Game.state != null else 0, false, town_obj, false)
			return true
		"enemy_hero":
			var defender := Game.state.player_of(int(target.get("side", -1))) if Game.state != null else null
			var defender_index := int(target.get("hero_index", 0))
			if defender == null or defender_index < 0 or defender_index >= defender.heroes.size() or not ai.is_hostile_to(defender):
				return false
			var defender_hero: HeroModel = defender.heroes[defender_index]
			if not defender.is_ai:
				return attack_human_hero(ai, defender, defender_index)
			# heroes.exe 0xb6981: the hero first, then a town he held (0xb69cf).
			var held := _map.own_town_gate_at(defender_hero.tile, defender.side) if _map != null else null
			var fight := quick_fight(ai, defender_hero.army, defender_hero, defender.side)
			if fight.defender_dead and _roster != null:
				_roster.remove_ai_hero_at(defender, defender.heroes.find(defender_hero), shown_to_human)
			if fight.attacker_won and not fight.attacker_dead and held != null:
				var held_model := defender.town_by_object_id(held.id)
				var held_army: ArmyData = held_model.army if held_model != null else held.garrison
				if held_army == null or held_army.is_empty():
					if _castle_turn != null:
						await _castle_turn.capture_town(held, ai.side)
						_castle_turn.visit_own_castle(ai, ai.town_by_object_id(held.id))
				else:
					fight = quick_fight(ai, held_army, null, -1, true, held_model)
					if fight.attacker_won and not fight.attacker_dead and _castle_turn != null:
						await _castle_turn.capture_town(held, ai.side)
						_castle_turn.visit_own_castle(ai, ai.town_by_object_id(held.id))
			if (fight.attacker_dead or not fight.attacker_won) and _roster != null:
				_roster.handle_ai_hero_death(ai, shown_to_human)
			return true
		"enemy_town":
			var town_object := target.get("object") as TownObject
			if town_object == null:
				return false
			var gate_keeper := gate_defender(ai, town_object)
			if not gate_keeper.is_empty():
				return await resolve_arrival(ai, gate_keeper)
			var current_owner := Game.state.player_of(town_object.owner) if (Game.state != null and town_object.owner >= 0) else null
			if current_owner != null and not ai.is_hostile_to(current_owner):
				return false
			var defender := Game.state.player_of(int(target.get("side", -1))) if Game.state != null else null
			var town_model := defender.town_by_object_id(town_object.id) if defender != null and town_object != null else null
			if town_object == null:
				return false
			if defender != null and not defender.is_ai \
					and town_model != null and town_model.army != null \
					and not town_model.army.is_empty():
				if _prepare_for_battle_fn.is_valid():
					_prepare_for_battle_fn.call()
				defender.select_town(town_object.id)
				if not Game.activate_local_player(defender.side):
					return false
				Game.hotseat_handoff_pending = true
				launch_ai_battle(ai, town_model.army, defender.side, true, town_object)
				return true
			var garrison: ArmyData = town_model.army if town_model != null else town_object.garrison
			if garrison == null or garrison.is_empty():
				if _castle_turn != null:
					await _castle_turn.capture_town(town_object, ai.side)
					_castle_turn.visit_own_castle(ai, ai.town_by_object_id(town_object.id))
			else:
				# heroes.exe 0x75a2d: a neutral or computer town's garrison.
				var fight := quick_fight(ai, garrison, null, -1, true, town_model)
				if fight.attacker_won and not fight.attacker_dead:
					if _castle_turn != null:
						await _castle_turn.capture_town(town_object, ai.side)
						_castle_turn.visit_own_castle(ai, ai.town_by_object_id(town_object.id))
				elif _roster != null:
					_roster.handle_ai_hero_death(ai, shown_to_human)
			return true
		"dig_ultimate":
			var dig_node := _roster.hero_for_side(ai.side) if _roster != null else null
			var res := Dig.perform_dig(dig_node, ai.active(), ai, _map, _root)
			return bool(res.get("waiting", false)) or (bool(res.get("ok", false)) and String(res.get("artifact", "")) != "")
		_:
			var obj: MapObject = target.get("object") as MapObject
			if obj == null and _map != null and target.has("tile"):
				obj = _map.object_at_action(target.tile)
			if obj == null:
				return false
			return visit_object(ai, obj)
	return false

## The settlement a "player_town" target names. The castle-less fallback target
## carries only the gate tile, so the town is read off that tile: the fight is
## then fought at the settlement the hero actually reached, never at another
## of the human's towns.
func _target_town(target: Dictionary) -> TownObject:
	if target.get("object") is TownObject:
		return target.get("object") as TownObject
	if _map != null:
		var tile: Vector2i = target.get("tile", Vector2i(-1, -1))
		if tile != Vector2i(-1, -1):
			var at_tile := _map.town_at(tile) as TownObject
			if at_tile != null:
				return at_tile
	if _map != null and Game.state != null:
		return _map.town_of_side(Game.state.active_player_side)
	return null

func gate_defender(ai: PlayerState, town: TownObject) -> Dictionary:
	if town == null or Game.state == null:
		return {}
	if _roster != null:
		_roster.persist_heroes()
	for player: PlayerState in Game.state.players:
		if player.side == ai.side or not player.alive or not ai.is_hostile_to(player):
			continue
		for i in player.heroes.size():
			if player.heroes[i].tile == town.action_tile:
				var kind := "player_hero" if player.side == Game.state.active_player_side \
						else "enemy_hero"
				return {"tile": town.action_tile, "kind": kind, "object": null,
						"side": player.side, "hero_index": i}
	return {}

func attack_human_hero(ai: PlayerState, defender: PlayerState, index: int) -> bool:
	if defender == null or defender.heroes.is_empty():
		return false
	if index < 0 or index >= defender.heroes.size():
		index = clampi(defender.active_hero, 0, defender.heroes.size() - 1)
	var defender_hero: HeroModel = defender.heroes[index]
	var seated := defender.side == (Game.state.active_player_side if Game.state != null else 0)
	if _prepare_for_battle_fn.is_valid():
		_prepare_for_battle_fn.call()
	defender.active_hero = index
	if not Game.activate_local_player(defender.side):
		return false
	if not seated:
		Game.hotseat_handoff_pending = true
	var held_gate := _map.own_town_gate_at(defender_hero.tile, defender.side) if _map != null else null
	# The attacking hero has already turned to face the defender. That turn is
	# a single frame of sprite swap, so the map is held for a beat before the
	# battle screen takes over: the player should see the two heroes square
	# off before the fight starts.
	launch_ai_battle(ai, defender_hero.army, -1, true, held_gate, held_gate != null,
			Hero.ENGAGE_FACE_DELAY)
	return true

func recruit_at_dwelling(ai: PlayerState, dw: Dwelling) -> void:
	var army := ai.active().army if ai.active() != null else null
	if army == null or dw.available <= 0:
		return
	var paid := dw.cost > 0 or not dw.cost_resources.is_empty()
	if paid:
		if not dw.recruit(dw.max_recruitable(ai, army), ai, army):
			return
	else:
		if not army.add(dw.unit, dw.available):
			return
		dw.available = 0
	Game.record_object_state(dw)
	if dw.consumed and _world != null:
		_world.refresh_object(dw.id)

func fight_guard(ai: PlayerState, stack: NeutralStack) -> bool:
	if stack == null or not stack.is_armed() or ai.active() == null:
		return false
	accept_joiners(ai, stack)
	if stack.consumed:
		return false
	stack.fought_before = true
	var hero_node := _roster.hero_for_side(ai.side) if _roster != null else null
	if shown_to_human and _world != null and hero_node != null:
		await _world.play_attack_flourish(stack, hero_node.tile)
	var fight := AIQuickBattle.fight_stack(quick_ctx(ai), stack.army, Game.rng)
	if fight.attacker_won:
		stack.consumed = true
		finish_consumed_pickup(stack)
	else:
		Game.record_object_state(stack)
		if shown_to_human and _world != null:
			_world.resume_stack_idle(stack)
	if (fight.attacker_dead or not fight.attacker_won) and _roster != null:
		_roster.handle_ai_hero_death(ai, shown_to_human)
		return true
	return false

func quick_ctx(ai: PlayerState) -> AITileValue.Ctx:
	var econ: Dictionary = _turn_economy.get(ai.side, {})
	if econ.is_empty():
		econ = AIController.economy_of(ai, _map, Game.state)
	return AITileValue.context(ai, ai.active(), _map, Game.state, econ)

func quick_fight(ai: PlayerState, army: ArmyData, defender_hero: HeroModel = null,
		defender_side := -1, siege := false, town: TownModel = null) -> AIQuickBattle.Result:
	if defender_hero == null and not siege and army != null and army.slots.size() == 1:
		return AIQuickBattle.fight_stack(quick_ctx(ai), army, Game.rng)
	return AIQuickBattle.fight(quick_ctx(ai), army, defender_hero, defender_side,
			siege, town, Game.rng)

func accept_joiners(ai: PlayerState, stack: NeutralStack) -> void:
	var army := ai.active().army if ai.active() != null else null
	if army == null or not stack.can_offer_join(army):
		return
	var slot: Dictionary = stack.army.slots[0]
	if not army.add(String(slot.unit), int(slot.count)):
		return
	stack.consumed = true
	if _astar != null:
		_astar.invalidate_guard_zones()
	Game.record_object_state(stack)
	if _world != null:
		_world.refresh_object(stack.id)

func resolve_guarded(ai: PlayerState, gp: GuardedPickup) -> bool:
	if gp == null or gp.looted:
		return false
	if gp.rolled_band < 0:
		gp.rolled_band = GuardedPickup.roll_band(gp.outcomes, Game.rng)
	var ransom := int(gp.outcomes[gp.rolled_band].get("ransom", 0)) \
			if gp.rolled_band < gp.outcomes.size() else 0
	if ransom > 0:
		# Daemon Cave capture: the computer pays like a human who says Yes
		# (KB adventure-ai.md, the cave is worth visiting only with the ransom in
		# hand); the cave stays armed either way, as heroes.exe 0xb410a leaves it.
		if ai.gold() >= ransom:
			ai.add_resources({"gold": -ransom})
		Game.record_object_state(gp)
		return false
	var guard := gp.guard_army()
	if not guard.is_empty():
		var fight := quick_fight(ai, guard)
		if fight.attacker_dead or not fight.attacker_won:
			if _roster != null:
				_roster.handle_ai_hero_death(ai, shown_to_human)
			return true
	GuardedPickup.apply_reward(gp, gp.rolled_band, ai, ai.active(), Game.rng)
	if ai.active() != null:
		ai.active().discard_pending_level_up_events()
	Game.record_object_state(gp)
	return false

func visit_object(ai: PlayerState, obj: MapObject) -> bool:
	if obj == null:
		return false
	if obj is Dwelling:
		recruit_at_dwelling(ai, obj as Dwelling)
		return false
	if obj is GuardedPickup:
		return resolve_guarded(ai, obj as GuardedPickup)

	var ctx := VisitContext.of(ai.side, ai.active())
	ctx.player_state = ai
	ctx.map = _map
	ctx.occupied_tiles = []
	var map_heroes: Array[Hero] = []
	if _roster != null:
		map_heroes = _roster.all_map_heroes()
	for occupied: Hero in map_heroes:
		if occupied.tile != Vector2i(-1, -1) and not ctx.occupied_tiles.has(occupied.tile):
			ctx.occupied_tiles.append(occupied.tile)

	var prev_owner := obj.owner
	var vr := obj.on_visit(ctx)
	var handled_paid_choice := false
	if not vr.choice.is_empty():
		var choice_type := String(vr.choice.get("type", ""))
		InteractionResolver.apply_choice(vr, 0, ctx)
		if choice_type == "artifact_paid":
			handled_paid_choice = true
		if vr.continue_visit and vr.source_object != null:
			vr = (vr.source_object as MapObject).on_visit(ctx)

	if vr.start_battle != null:
		var fight := quick_fight(ai, vr.start_battle)
		if fight.attacker_won:
			if obj is Mine:
				(obj as Mine).guard = null
				obj.owner = ai.side
			elif obj is DragonCity:
				obj.owner = ai.side
				handle_dragon_city_captured(prev_owner, ai.side)
			elif obj is ArtifactPickup:
				var ap := obj as ArtifactPickup
				if ai.active() != null:
					ai.active().add_artifact(ap.artifact_id)
				ap.consumed = true
				finish_consumed_pickup(ap)
			Game.record_object_state(obj)
			if _world != null:
				_world.refresh_object(obj.id)
		else:
			Game.record_object_state(obj)
		if fight.attacker_dead or not fight.attacker_won:
			if _roster != null:
				_roster.handle_ai_hero_death(ai, shown_to_human)
			return true
		return false

	if not vr.granted.is_empty():
		ai.add_resources(vr.granted)
	if vr.grant_artifact != "" and not handled_paid_choice and ai.active() != null:
		ai.active().add_artifact(vr.grant_artifact)
	if vr.grant_exp > 0 and ai.active() != null:
		ai.active().grant_experience(vr.grant_exp, Game.rng)
	if vr.teleport_to != Vector2i(-1, -1) and ai.active() != null:
		var node := _roster.hero_for_side(ai.side) if _roster != null else null
		if node != null:
			node.tile = vr.teleport_to
			node.position = Vector2(vr.teleport_to.x * (_map.tile_size if _map != null else 32), vr.teleport_to.y * (_map.tile_size if _map != null else 32))
		ai.active().tile = vr.teleport_to

	if obj is DragonCity:
		if obj.owner != prev_owner:
			handle_dragon_city_captured(prev_owner, obj.owner)
		Game.record_object_state(obj)
		if _world != null:
			_world.refresh_object(obj.id)
	elif obj is Mine:
		Game.record_object_state(obj)
		if _world != null:
			_world.refresh_object(obj.id)
	elif vr.consumed:
		finish_consumed_pickup(obj)
	else:
		Game.record_object_state(obj)
		if _world != null:
			_world.refresh_object(obj.id)

	if ai.active() != null:
		ai.active().discard_pending_level_up_events()
	return false

func handle_dragon_city_captured(prev_owner: int, new_owner: int) -> void:
	if prev_owner != new_owner and (Game.state == null or new_owner != Game.state.active_player_side):
		if _root != null:
			MapDialogs.info(_root, {"text": "The enemy has captured the dragon city!!"})
		if Game.game_mode == &"campaign" and Game.campaign != null \
				and Game.campaign.mission().objective == &"capture_dragon_city":
			Game.pending_defeat = true
			Game.pending_defeat_message = "The enemy has captured the dragon city!!"

func finish_consumed_pickup(obj: MapObject) -> void:
	if obj is NeutralStack and _astar != null:
		_astar.invalidate_guard_zones()
	Game.record_object_state(obj)
	if _world != null:
		_world.refresh_object(obj.id)

## Launch the AI's battle. `delay` holds the adventure map on screen for that
## long before the battle screen takes over — the hero-vs-hero engage uses it
## so the turn to face the opponent is visible (Hero.ENGAGE_FACE_DELAY).
func launch_ai_battle(ai: PlayerState, human_side_army: ArmyData, town_side: int,
		already_prepared: bool = false, defender_town: TownObject = null,
		hero_defense: bool = false, delay: float = 0.0) -> void:
	Game.pending_ai_battle = true
	Game.pending_ai_side = ai.side
	Game.pending_town_battle_side = town_side
	Game.pending_day_advance = true
	Game.battle_return = "map"
	if _roster != null:
		_roster.persist_heroes()
	if hero_defense and defender_town != null:
		# The defender's own army holds the gate, so no garrison aliasing here.
		# The town's garrison joins him for the fight.
		Game.set_pending_town_battle(defender_town, defender_town.owner, true)
		Game.join_gate_garrison(human_side_army)
	elif town_side == (Game.state.active_player_side if Game.state != null else 0):
		# AI assaulting the human town gate: to_battle() below reassigns
		# Game.player_army to the garrison (aliased with the town's army) —
		# stash the hero's field army so it isn't silently clobbered.
		Game.saved_player_army = Game.player_army
		var human_town := defender_town if defender_town != null \
				else (_map.town_of_side(town_side) if _map != null else null)
		if human_town != null:
			Game.set_pending_town_battle(human_town, town_side)
	if not already_prepared and _prepare_for_battle_fn.is_valid():
		_prepare_for_battle_fn.call()
	Game.battle_terrain = _map.terrain_at(ai.active().tile) if _map != null and ai.active() != null else "grass"
	Game.to_battle(human_side_army, ai.active().army, ai.active(),
			&"hero" if hero_defense or Game.pending_town_battle_side < 0 else &"town",
			false, -1, delay)
