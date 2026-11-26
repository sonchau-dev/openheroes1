class_name InteractionResolver
extends RefCounted

signal interaction_resolved(obj: MapObject, result: VisitResult)

## Applies VisitResults when the hero lands on an object's action tile,
## resolves returned-from-battle state, and transfers towns.
##
## Ordering note: the scene root calls resolve_post_battle() EARLY in _ready(),
## before the AStar grid, the hero, and the AITurnRunner node exist (consumed
## objects must not be solid when the grid is built). Late-bound refs (_astar,
## _ai) are therefore passed as CLOSURES so they resolve to null at that point
## (the original null guards are preserved) and to live values once _ready()
## finishes and object visits fire.

var _root: Node2D
var _map: MapData
var _astar_fn: Callable          # func() -> PassabilityGrid (late-bound; null pre-build)
var _world: AdventureWorldRenderer
var _hero_fn: Callable           # func() -> Hero
var _army_fn: Callable           # func() -> ArmyData (root._current_army)
var _fallback_army_fn: Callable  # func() -> ArmyData (root._fallback_army; battle-only fallback)
var _persist_fn: Callable        # func() -> void (root._persist_hero)
var _prepare_for_battle_fn: Callable  # persist + _following=false + input.clear_path()
var _enter_town_fn: Callable     # _following=false + input.clear_path() (no persist)
var _hud_fn: Callable            # func() -> AdventureHud (may be null)
var _update_ui_fn: Callable      # func() -> void
var _check_game_over_fn: Callable  # func() -> void
var _player_hero_death_fn: Callable  # func() -> void
var _first_ai_fn: Callable       # func() -> PlayerState (reads Game.state directly)
var _ai_hero_death_fn: Callable  # func(PlayerState) -> void (routes to _ai or nulls state)
var _teleport_fn: Callable       # func(tile: Vector2i) -> void (root.teleport_hero;
                                  # mirrors spell_controller.gd's _teleport_fn wiring)
var _reveal_fn: Callable         # func() -> void (obelisk's
                                  # single-obelisk-on-the-map special case; mirrors _teleport_fn's
                                  # wiring. adventure_map.gd's closure calls _fog.explore_everything(),
                                  # which fills its bound player's (Game.state.human()) explored bitset
                                  # AND redraws the fog; v1 always reveals the human side (0), same
                                  # simplification as the reveal-all spell.)
var _occupied_tiles_fn: Callable # func() -> Array of Vector2i (root.occupied_hero_tiles:
                                  # ALL live human hero nodes, active and inactive, + the AI
                                  # hero — stone_liths destination-occupancy)
var _open_oracle_fn: Callable    # func() -> void; called after the Shrine intro
                                  # closes to open the full player-ranking panel
var _open_puzzle_fn: Callable    # func() -> void; called after the first-visit
                                  # Obelisk inscription closes

# Deferred stop-before target (resource pile OR armed object): the hero halts
# one tile short; on arrival collect_pending() faces it, charges the final
# step's cost, and visits (pickup or battle launch).
var pending_resource: MapObject = null
var pending_cost: int = 0
var pending_tile: Vector2i = Vector2i(-1, -1)
## The "you have lost your last town" box, while it is up. heroes.exe shows it
## modally (0xd2908), so the enemy turn waits on it.
var town_notice: CanvasLayer = null

func setup(root: Node2D, map: MapData, astar_fn: Callable, world: AdventureWorldRenderer,
		hero_fn: Callable, army_fn: Callable, fallback_army_fn: Callable,
		persist_fn: Callable, prepare_for_battle_fn: Callable, enter_town_fn: Callable,
		hud_fn: Callable, update_ui_fn: Callable, check_game_over_fn: Callable,
		player_hero_death_fn: Callable, first_ai_fn: Callable,
		ai_hero_death_fn: Callable, teleport_fn: Callable,
		occupied_tiles_fn: Callable, reveal_fn: Callable, open_oracle_fn: Callable,
		open_puzzle_fn: Callable) -> void:
	_root = root
	_map = map
	_astar_fn = astar_fn
	_world = world
	_hero_fn = hero_fn
	_army_fn = army_fn
	_fallback_army_fn = fallback_army_fn
	_persist_fn = persist_fn
	_prepare_for_battle_fn = prepare_for_battle_fn
	_enter_town_fn = enter_town_fn
	_hud_fn = hud_fn
	_update_ui_fn = update_ui_fn
	_check_game_over_fn = check_game_over_fn
	_player_hero_death_fn = player_hero_death_fn
	_first_ai_fn = first_ai_fn
	_ai_hero_death_fn = ai_hero_death_fn
	_teleport_fn = teleport_fn
	_occupied_tiles_fn = occupied_tiles_fn
	_reveal_fn = reveal_fn
	_open_oracle_fn = open_oracle_fn
	_open_puzzle_fn = open_puzzle_fn

func set_pending(obj: MapObject, cost: int, tile: Vector2i) -> void:
	pending_resource = obj
	pending_cost = cost
	pending_tile = tile

func clear_pending() -> void:
	pending_resource = null
	pending_cost = 0
	pending_tile = Vector2i(-1, -1)

func collect_pending() -> void:
	if pending_resource == null:
		return
	var res_obj := pending_resource
	var cost := pending_cost
	var res_tile := pending_tile

	clear_pending()

	var hero := _hero_fn.call() as Hero
	hero.face_towards(res_tile)
	hero.move_points = maxi(0, hero.move_points - cost)
	_persist_fn.call()
	visit(res_obj)

## Handle the hero arriving on an object's action tile: apply its VisitResult.
func visit(obj: MapObject) -> void:
	var result_dialog: CanvasLayer = null
	var prev_owner := obj.owner
	var local_side := Game.state.active_player_side if Game.state != null else 0
	var ctx := VisitContext.of(local_side, Game.ensure_player_hero(_army_fn.call()))
	ctx.player_state = Game.state.player_of(local_side) if Game.state != null else null
	ctx.map = _map
	ctx.occupied_tiles = _occupied_tiles_fn.call()
	var vr := obj.on_visit(ctx)
	interaction_resolved.emit(obj, vr)
	if not vr.granted.is_empty() and Game.state != null:
		Game.state.add_resources(vr.granted)
		# Windmill/Watermill and the campfire get their own titled popup (below)
		# instead of the small resource-collect HUD toast meant for resource piles.
		if not (obj is WeeklyPickup or obj.type == "campfire"):
			var hud := _hud_fn.call() as AdventureHud
			if hud != null:
				for res: String in vr.granted.keys():
					hud.show_resource_popup(res, vr.granted[res])
	if vr.free_dwelling != null:
		var free_dw := vr.free_dwelling
		var join_count := vr.join_count
		result_dialog = MapDialogs.free_dwelling(_root, free_dw, func(choice_idx: int):
			if choice_idx == 0:
				var army := _army_fn.call() as ArmyData
				var added := false
				if army != null:
					added = army.add(free_dw.unit, join_count)
				if not added:
					free_dw.available += join_count
				Game.record_object_state(free_dw)
				_persist_fn.call()
				var joined := VisitResult.new()
				joined.join_unit = free_dw.unit
				joined.join_count = join_count if added else 0
				interaction_resolved.emit(free_dw, joined)
				_update_ui_fn.call()
			else:
				free_dw.available += join_count
				Game.record_object_state(free_dw)
				_persist_fn.call()
				_update_ui_fn.call()
		)
	if vr.join_offer_stack != null:
		var offer_stack := vr.join_offer_stack
		var unit := String(offer_stack.army.slots[0].unit)
		var count := int(offer_stack.army.slots[0].count)
		result_dialog = MapDialogs.followers_join(_root, unit, func(choice_idx: int):
			if choice_idx == 0:
				var army := _army_fn.call() as ArmyData
				if army != null:
					army.add(unit, count)
				offer_stack.consumed = true
				if _astar_fn.is_valid():
					var astar := _astar_fn.call() as PassabilityGrid
					if astar != null:
						astar.invalidate_guard_zones()
				Game.record_object_state(offer_stack)
				if _world != null:
					_world.refresh_object(offer_stack.id)
				_persist_fn.call()
				var joined := VisitResult.new()
				joined.join_unit = unit
				joined.join_count = count
				joined.consumed = true
				interaction_resolved.emit(offer_stack, joined)
				_update_ui_fn.call()
				# The monsters joined instead of fighting, so no fight resolves
				# the mine the hero stepped onto (adventure_map.gd queues it
				# behind the fight). Take it now -- the hero stands on its
				# tile -- and drop the queue, or a later battle would capture
				# a mine out of nowhere.
				_take_queued_mine(local_side, ctx.hero_model.tile if ctx.hero_model != null else Vector2i(-1, -1))
			else:
				offer_stack.fought_before = true
				Game.record_object_state(offer_stack)
				_persist_fn.call()
				MapDialogs.followers_refusal(_root, func():
					var hero := _hero_fn.call() as Hero
					if hero != null and _world != null:
						# The battle scene frees the map, so the hold never ends.
						if _root.has_method("_begin_engage_hold"):
							_root.call("_begin_engage_hold")
						await _world.play_attack_flourish(offer_stack, hero.tile)
					Game.pending_object_id = offer_stack.id
					Game.battle_return = "map"
					_prepare_for_battle_fn.call()
					_start_object_battle(offer_stack.army)
				)
		)
	if vr.recruit_dwelling != null:
		var paid_dwelling := vr.recruit_dwelling
		var player := Game.state.player_of(ctx.player_side) if Game.state != null else null
		var army := _army_fn.call() as ArmyData
		MapDialogs.recruit_dwelling(_root, paid_dwelling, player, army, func(quantity: int):
			Game.record_object_state(paid_dwelling)
			_persist_fn.call()
			var recruited := VisitResult.new()
			recruited.join_unit = paid_dwelling.unit
			recruited.join_count = quantity
			if paid_dwelling.disappears_when_empty and paid_dwelling.available <= 0:
				paid_dwelling.consumed = true
				recruited.consumed = true
				_world.refresh_object(paid_dwelling.id)
			interaction_resolved.emit(paid_dwelling, recruited)
			_update_ui_fn.call()
		)
	var artifact_was_granted := false
	if vr.grant_artifact != "" and ctx.hero_model != null:
		artifact_was_granted = ctx.hero_model.add_artifact(vr.grant_artifact)
	if vr.grant_exp > 0 and ctx.hero_model != null:
		ctx.hero_model.grant_experience(vr.grant_exp, Game.rng)
	if obj is WeeklyPickup:
		# Visual bug report + human-supplied reference screenshot: Windmill/
		# Watermill show a titled popup (keeper-of-the-mill flavor text +
		# granted resource icon/amount), not the generic text-only dialog.
		MapDialogs.weekly_pickup(_root, obj.type, vr.message, vr.granted)
	elif obj.type == "campfire" and vr.consumed:
		# DOS campaign recording: a titled window with the gold and resource
		# icons and amounts, not the sidebar resource panel.
		result_dialog = MapDialogs.campfire(_root, vr.message, vr.granted)
	elif obj.type in ["statue", "fountain", "faerie_ring", "gazebo", "oasis", "buoy"] and vr.show_dialog and vr.message != "":
		# Reference-confirmed themed popups: Statue uses the tall icon layout;
		# Fountain/Faerie Ring use the compact single-rainbow grant layout;
		# Gazebo uses the evntwin5 layout with exp star and amount label;
		# Faerie Ring/Fountain/Gazebo text-only revisits are measured from native captures.
		var amount := int(obj.params.get("amount", 1000)) if obj.type == "gazebo" else 0
		result_dialog = MapDialogs.stat_boost(_root, obj.type, vr.message, vr.already_visited, amount)
	elif obj is GuardedPickup and obj.type == "demon_cave" and vr.show_dialog and vr.message != "":
		var cave := obj as GuardedPickup
		result_dialog = MapDialogs.demon_cave_info(_root, vr.message, cave.reward_artifact(cave.rolled_band))
	elif obj is GuardedPickup and (obj as GuardedPickup).looted and vr.show_dialog and vr.message != "":
		# Searching a plundered Graveyard/Shipwreck: heroes.exe shows the
		# bad-morale bird under the text (0xb4294, icon 0xd).
		result_dialog = MapDialogs.weekly_pickup(_root, obj.type, vr.message, {"morale_bad": 0})
	elif obj.type == "obelisk" and vr.show_dialog and vr.message != "":
		MapDialogs.obelisk(_root, vr.message,
				Callable() if vr.already_visited else _open_puzzle_fn,
				vr.already_visited)
	elif obj is ArtifactPickup and artifact_was_granted:
		MapDialogs.artifact(_root, vr.grant_artifact)
	elif obj.type == "skeleton" and artifact_was_granted:
		# heroes.exe 0xb2f35 shows the find with the artifact's icon.
		MapDialogs.artifact(_root, vr.grant_artifact, vr.message)
	elif obj is Shrine and vr.show_dialog:
		var has_book := ctx.hero_model != null and ctx.hero_model.has_spellbook
		result_dialog = MapDialogs.spell_shrine(_root, (obj as Shrine).spell_id, has_book)
	elif vr.free_dwelling != null or vr.recruit_dwelling != null or vr.join_offer_stack != null:
		pass
	elif vr.show_dialog and vr.message != "":
		result_dialog = MapDialogs.info(_root, {"lines": [vr.message]})
	if vr.reveal_map:
		_reveal_fn.call()
	if vr.open_oracle:
		MapDialogs.shrine(_root, vr.message, _open_oracle_fn)
	if not vr.choice.is_empty():
		_show_choice(vr, ctx)
	_present_pending_level_ups(ctx.hero_model, result_dialog)
	# Persist the (possibly mutated) object state so the next scene reload reflects it.
	Game.record_object_state(obj)
	if vr.consumed and _world != null:
		if should_dissolve_pickup(obj, vr):
			_world.dissolve_object(obj)
		else:
			_world.refresh_object(obj.id)
	if vr.start_battle != null:
		if obj is ArtifactPickup and vr.message != "":
			# The Rogues jump out first; the battle starts once that is read.
			MapDialogs.info(_root, {"lines": [vr.message], "on_close": func():
				Game.pending_object_id = obj.id
				Game.battle_return = "map"
				_prepare_for_battle_fn.call()
				_start_object_battle(vr.start_battle)
			})
			return
		if obj is NeutralStack:
			(obj as NeutralStack).fought_before = true
			Game.record_object_state(obj)
			var hero := _hero_fn.call() as Hero
			if hero != null and _world != null:
				# Hold map input through the flourish; the battle scene frees the map.
				if _root.has_method("_begin_engage_hold"):
					_root.call("_begin_engage_hold")
				await _world.play_attack_flourish(obj as NeutralStack, hero.tile)
		Game.pending_object_id = obj.id
		Game.battle_return = "map"
		_prepare_for_battle_fn.call()
		_start_object_battle(vr.start_battle)
		return
	if vr.enter_town:
		var tw := obj as TownObject
		if tw != null and tw.owner != local_side:
			# A hero parked in the gate defends the town (KB armies.md §3.1
			# "Stationed Defender"/"Siege Warfare"): he leads the garrison into
			# the fight and the town only falls with him. The map's own attack
			# route meets that hero before the town is entered; this is the same
			# rule for every other way in, so a town whose gate is held is never
			# taken for free.
			var gate_defender := _gate_defender(tw, local_side)
			if not gate_defender.is_empty():
				_fight_gate_defender(tw, gate_defender)
				return
			var garrison: ArmyData = null
			if tw.owner >= 0:
				var ai := Game.state.player_of(tw.owner) if Game.state != null else null
				var ai_town := ai.town_by_object_id(tw.id) if ai != null else null
				garrison = ai_town.army if ai_town != null else null
			else:
				garrison = tw.garrison
			if garrison != null and not garrison.is_empty():
				Game.pending_ai_side = tw.owner
				Game.set_pending_town_battle(tw, tw.owner)
				Game.pending_day_advance = false
				Game.battle_return = "map"
				_prepare_for_battle_fn.call()
				_start_object_battle(garrison, &"town")
			else:
				capture_town(tw, local_side)
				_check_game_over_fn.call()
				_update_ui_fn.call()
			return
		if tw != null and Game.state != null:
			Game.state.human().select_town(tw.id)
		_enter_town_fn.call()
		Game.to_town(Game.ensure_player_hero(_army_fn.call()))
		return
	if vr.teleport_to != Vector2i(-1, -1):
		# Stone Liths: teleport_hero() itself does NOT auto-visit
		# the landing tile (adventure_map.gd:438-442's documented contract) and
		# already persists + refreshes the HUD, so no further work here.
		_teleport_fn.call(vr.teleport_to)
		return
	if obj is Mine and obj.owner == local_side:
		if prev_owner != local_side:
			_world.refresh_object(obj.id)   # unguarded capture flips ownership immediately
			MapDialogs.mine_captured(_root, (obj as Mine).res)
	if obj is DragonCity and obj.owner == local_side:
		if prev_owner != local_side:
			_world.refresh_object(obj.id)   # walkover capture; the handler's message says so
	if obj is Lighthouse and obj.owner == local_side and prev_owner != local_side:
		_world.refresh_object(obj.id)
	# A mine inside a stack's control zone was queued behind that fight
	# (adventure_map.gd). No fight is running now, so the queue has nobody
	# left to resolve it: take the mine while the hero stands on it, and drop
	# the queue so a later battle cannot capture a mine out of nowhere.
	if vr.join_offer_stack == null and Game.pending_followup_object_id >= 0:
		_take_queued_mine(local_side, ctx.hero_model.tile if ctx.hero_model != null else Vector2i(-1, -1))
	_update_ui_fn.call()

## Take the mine the hero stepped onto while it was inside a neutral stack's
## control zone. That mine is queued behind the guarding stack's fight
## (adventure_map.gd); this resolves the queue outside a fight -- the monsters
## joined, or the stack was already gone -- and always clears it, so a stale
## id can never capture a mine the hero never visited.
func _take_queued_mine(local_side: int, hero_tile: Vector2i) -> CanvasLayer:
	var queued_id := Game.pending_followup_object_id
	Game.pending_followup_object_id = -1
	if queued_id < 0 or _map == null:
		return null
	var mine := _map.object_by_id(queued_id) as Mine
	if mine == null or mine.owner == local_side:
		return null
	# The hero only owns the mine by standing on it; if he has moved on, the
	# mine stays as it was.
	if not mine.interaction_tiles().has(hero_tile):
		return null
	mine.owner = local_side
	Game.record_object_state(mine)
	if _world != null:
		_world.refresh_object(mine.id)
	return MapDialogs.mine_captured(_root, mine.res)

func _present_pending_level_ups(hero: HeroModel, after_dialog: CanvasLayer = null) -> void:
	if hero == null:
		return
	var events := hero.take_pending_level_up_events()
	if events.is_empty():
		return
	if _root != null and _root.has_method("queue_level_up"):
		_root.call("queue_level_up", hero, events, after_dialog)
		return
	var show := func():
		MapDialogs.level_ups(_root, hero, events)
	if after_dialog == null or not is_instance_valid(after_dialog):
		show.call()
	elif after_dialog.has_signal("closed"):
		after_dialog.connect("closed", func(): show.call(), CONNECT_ONE_SHOT)
	elif after_dialog.has_signal("chosen"):
		after_dialog.connect("chosen", func(_idx: int): show.call(), CONNECT_ONE_SHOT)
	else:
		# Unknown modal contract: defer at least one frame so its creation order is
		# stable and the level-up event cannot appear beneath it.
		_root.get_tree().process_frame.connect(func(): show.call(), CONNECT_ONE_SHOT)

## Pops a two-(or-more)-button dialog for VisitResult.choice (e.g. a chest's
## gold-vs-experience pick); applies the chosen option via apply_choice() and
## refreshes the HUD. UI-only — headless tests call apply_choice() directly.
func _show_choice(vr: VisitResult, ctx: VisitContext) -> void:
	var options: Array = vr.choice.get("options", [])
	var labels: Array = []
	for o: Dictionary in options:
		labels.append(String(o.get("label", "")))
	var update_fn := _update_ui_fn
	var death_fn := _player_hero_death_fn
	var root := _root
	MapDialogs.choice(_root, String(vr.choice.get("prompt", "")), labels, vr.choice, func(idx: int):
		var choice_type := String(vr.choice.get("type", ""))
		var previous_artifact := vr.grant_artifact
		apply_choice(vr, idx, ctx)
		if choice_type == "artifact_paid":
			if idx == 1:
				interaction_resolved.emit(vr.source_object, vr)   # the leprechaun vanishes: killfade
				MapDialogs.paid_artifact_refusal(root, func():
					if vr.source_object != null:
						Game.record_object_state(vr.source_object)
						if vr.source_object.consumed:
							_world.refresh_object(vr.source_object.id)
					update_fn.call()
					_present_pending_level_ups(ctx.hero_model)
				)
				return
			else:
				if vr.grant_artifact == "":
					MapDialogs.info(root, {"text": ArtifactPickup.NO_GOLD_MESSAGE})
				if vr.source_object != null:
					Game.record_object_state(vr.source_object)
					if vr.source_object.consumed:
						_world.refresh_object(vr.source_object.id)
				update_fn.call()
				_present_pending_level_ups(ctx.hero_model)
				return
		if previous_artifact == "" and vr.grant_artifact != "":
			interaction_resolved.emit(vr.source_object, vr)
			MapDialogs.artifact(root, vr.grant_artifact)
		if vr.source_object != null:
			Game.record_object_state(vr.source_object)
			if vr.source_object.consumed:
				_world.refresh_object(vr.source_object.id)
		update_fn.call()
		_present_pending_level_ups(ctx.hero_model)
		if vr.continue_visit and vr.source_object != null:
			# Native encounter prompts are a gate, not the encounter itself. The
			# accepted Demon Cave visit immediately re-enters the same object; the
			# transient entry_confirmed flag prevents this from reopening the prompt.
			visit(vr.source_object)
			return
		# Demon Cave ransom refusal. apply_choice stays
		# UI-free and merely flips vr.destroy_hero; the death callback lives here
		# so it reaches the resolver's _player_hero_death_fn (which apply_choice,
		# being static, cannot call). This _show_choice path is human-only (the AI
		# never routes through choice dialogs), so the human hero-death fn is correct.
		if vr.destroy_hero:
			if Game.state != null and Game.state.hero_pool != null and ctx.hero_model != null:
				Game.state.hero_pool.release_hero(ctx.hero_model, Game.rng, true)
			death_fn.call()
	)

## Applies the idx'th option of a VisitResult.choice (granted resources and/or
## experience) directly onto Game.state / ctx.hero_model — no UI, so headless
## tests (and _show_choice's button callback above) can call this identically.
## Side-aware: resources land on ctx.player_side's kingdom so
## the AI turn runner can resolve chest choices for its own side (side 0 keeps
## the previous human()-targeting behavior).
static func apply_choice(vr: VisitResult, idx: int, ctx: VisitContext) -> void:
	var options: Array = vr.choice.get("options", [])
	if idx < 0 or idx >= options.size():
		return
	var opt: Dictionary = options[idx]
	if bool(opt.get("confirm_entry", false)):
		var gated := vr.choice.get("object") as MapObject
		if gated != null and "entry_confirmed" in gated:
			gated.set("entry_confirmed", true)
			vr.source_object = gated
			vr.continue_visit = true
		return
	if bool(opt.get("enter_demon_cave", false)):
		var cave := vr.choice.get("object") as GuardedPickup
		if cave != null:
			cave.entry_confirmed = true
			vr.source_object = cave
			vr.continue_visit = true
		return
	# Paid artifact encounters commit only after the chosen response. Declining
	# consumes the pickup; an unaffordable/stale Buy leaves it untouched.
	if bool(opt.get("decline_artifact", false)):
		var declined := vr.choice.get("object") as ArtifactPickup
		if declined != null:
			declined.consumed = true
			vr.consumed = true
			vr.source_object = declined
		return
	var artifact_id := String(opt.get("artifact", ""))
	if artifact_id != "":
		var artifact_obj := vr.choice.get("object") as ArtifactPickup
		var buyer: PlayerState = Game.state.player_of(ctx.player_side) if Game.state != null else null
		var artifact_price := int(opt.get("pay", 0))
		if artifact_obj == null or buyer == null or ctx.hero_model == null \
				or buyer.gold() < artifact_price or not ctx.hero_model.can_add_artifact(artifact_id):
			return
		buyer.add_resources({"gold": -artifact_price})
		ctx.hero_model.add_artifact(artifact_id)
		vr.grant_artifact = artifact_id
		artifact_obj.consumed = true
		vr.consumed = true
		vr.source_object = artifact_obj
		return
	var granted: Dictionary = opt.get("granted", {})
	if not granted.is_empty() and Game.state != null:
		var p: PlayerState = Game.state.player_of(ctx.player_side)
		if p != null:
			p.add_resources(granted)
	var exp := int(opt.get("exp", 0))
	if exp > 0 and ctx.hero_model != null:
		ctx.hero_model.grant_experience(exp, Game.rng)
	# Demon Cave ransom band. A `pay` option DEDUCTS that
	# gold from the visiting side's kingdom (add_resources routes gold to the town).
	# A `destroy_hero` option flips vr.destroy_hero; the caller (_show_choice) then
	# fires the hero-death fn. Both stay UI-free so headless tests drive them directly.
	var pay := int(opt.get("pay", 0))
	if pay > 0 and Game.state != null:
		var pp: PlayerState = Game.state.player_of(ctx.player_side)
		if pp != null:
			pp.add_resources({"gold": -pay})
	if bool(opt.get("destroy_hero", false)):
		vr.destroy_hero = true

## The hostile hero standing in the town's gate, with the side that owns it:
## `{"player": PlayerState, "hero": HeroModel}`. Empty when the gate is free.
func _gate_defender(tw: TownObject, side: int) -> Dictionary:
	if tw == null or Game.state == null:
		return {}
	var visitor := Game.state.player_of(side)
	for p: PlayerState in Game.state.players:
		if p.side == side or not p.alive:
			continue
		if visitor != null and not p.is_hostile_to(visitor):
			continue
		for h: HeroModel in p.heroes:
			if h.tile == tw.action_tile:
				return {"player": p, "hero": h}
	return {}

## The hero in the gate defends the town: he leads the garrison into the fight
## (heroes.exe 0xb6981 fights the hero first, then the town he held, 0xb69cf)
## and the town changes hands when he falls.
func _fight_gate_defender(tw: TownObject, defender: Dictionary) -> void:
	var p := defender.get("player") as PlayerState
	var hero := defender.get("hero") as HeroModel
	if p == null or hero == null:
		return
	var idx := p.heroes.find(hero)
	if idx >= 0:
		p.active_hero = idx
	Game.pending_ai_side = p.side
	Game.set_pending_town_battle(tw, tw.owner, true)
	var hero_army := hero.army if hero.army != null else ArmyData.new()
	if hero.army == null:
		hero.army = hero_army
	if tw.owner < 0:
		# A neutral town's garrison lives on the map object.
		if tw.garrison != null and not tw.garrison.is_empty():
			hero_army.absorb(tw.garrison)
	else:
		# The owner's town garrison joins the hero holding its gate.
		Game.join_gate_garrison(hero_army)
	Game.pending_day_advance = false
	Game.battle_return = "map"
	_prepare_for_battle_fn.call()
	_start_object_battle(hero_army, &"hero", hero)

func _start_object_battle(enemy_army: ArmyData, kind: StringName = &"neutral",
		enemy_hero_model: HeroModel = null) -> void:
	# Fight with the ACTIVE hero's army (the root's _current_army closure) —
	# never the stale Game.player_army snapshot, which only to_battle() itself
	# re-points and therefore lags behind hero switches/hires.
	var player: ArmyData = _army_fn.call()
	if player == null or player.is_empty():
		player = _fallback_army_fn.call()
	var opponent := Game.state.player_of(Game.pending_ai_side) \
			if Game.state != null and Game.pending_ai_side >= 0 else null
	var hero := _hero_fn.call() as Hero
	Game.battle_terrain = _map.terrain_at(hero.tile) if _map != null and hero != null else "grass"
	Game.to_battle(player, enemy_army, enemy_hero_model, kind,
			opponent != null and not opponent.is_ai and Game.pvp_control_allowed(),
			opponent.side if opponent != null else -1)

## An area spell killed both armies. The caster lost and already fell; the
## nominal winner has no troops either, so that hero falls too. A garrison
## with no hero in the gate has no hero to lose.
func _kill_wipeout_winner(player_won: bool, ai: PlayerState, hero_defense: bool) -> void:
	var human_attacked := Game.pending_town_battle_id >= 0 \
			and Game.pending_town_battle_side != (Game.state.active_player_side if Game.state != null else 0)
	var winner_is_attacker := (player_won == human_attacked) \
			if Game.pending_town_battle_id >= 0 else true
	if not (winner_is_attacker or hero_defense):
		return
	if player_won:
		_player_hero_death_fn.call()
	elif ai != null:
		_ai_hero_death_fn.call(ai)

## After returning from a map-triggered battle, capture/consume the object that
## started it (if the player won), then clear the pending marker.
func resolve_post_battle() -> void:
	var level_up_after: CanvasLayer = null
	Game.consume_battle_xp()   # award victory XP before any branch resets last_winner
	var level_up_hero := Game.state.human().active() if Game.state != null else null
	var local_side := Game.state.active_player_side if Game.state != null else 0
	var withdrew := Game.last_winner == 1 \
			and Game.last_battle_outcome in [&"retreat", &"surrender"]
	if withdrew:
		withdrew = Game.return_active_human_to_tavern(
				Game.last_battle_outcome == &"surrender")
	var defender_withdrew := Game.last_winner == 0 \
			and Game.last_battle_outcome in [&"retreat", &"surrender"]
	if defender_withdrew:
		defender_withdrew = Game.return_defender_to_tavern(
				Game.last_battle_outcome == &"surrender")
	if Game.pending_ai_battle or Game.pending_town_battle_id >= 0:
		var ai := _first_ai_fn.call() as PlayerState
		var player_won := Game.last_winner == 0
		# A hero standing in the gate fights this battle with his own army, so
		# the hero-vs-hero consequences (artifact spoils, the loser's death)
		# apply on top of the town changing hands.
		var hero_defense := Game.pending_town_hero_defense
		var local_hero := Game.state.human().active() if Game.state != null else null
		if Game.pending_town_battle_side == local_side:
			# AI assaulted the human town gate
			if player_won:
				if ai != null:
					if hero_defense and not defender_withdrew:
						_capture_spoils(local_hero, ai.active(), ai.is_ai)
					if not defender_withdrew:
						_ai_hero_death_fn.call(ai)
			else:
				# After a mutual wipe-out no attacker is left to take the gate.
				if not Game.last_battle_wipeout:
					capture_town(_map.object_by_id(Game.pending_town_battle_id) as TownObject, ai.side if ai != null else 1)
				if hero_defense and not withdrew:
					if ai != null:
						_capture_spoils(ai.active(), local_hero, false)
					_player_hero_death_fn.call()
		elif Game.pending_town_battle_id >= 0:
			# the human assaulted the AI or neutral town
			if player_won:
				if hero_defense and ai != null:
					if not defender_withdrew:
						_capture_spoils(local_hero, ai.active(), ai.is_ai)
						_ai_hero_death_fn.call(ai)
				if not Game.last_battle_wipeout:
					capture_town(_map.object_by_id(Game.pending_town_battle_id) as TownObject,
							local_side)
			elif not withdrew:
				if hero_defense and ai != null:
					_capture_spoils(ai.active(), local_hero, false)
				_player_hero_death_fn.call()
		else:
			# open-field hero vs hero
			if player_won:
				if ai != null:
					var human_winner := Game.state.human().active() if Game.state != null else null
					if not defender_withdrew:
						_capture_spoils(human_winner, ai.active(), true)
						_ai_hero_death_fn.call(ai)
			elif not withdrew:
				if ai != null and Game.state != null:
					_capture_spoils(ai.active(), Game.state.human().active(), false)
				_player_hero_death_fn.call()
		if Game.last_battle_wipeout:
			_kill_wipeout_winner(player_won, ai, hero_defense)
		if Game.saved_player_army != null:
			# Restore the hero's field army: to_battle() aliased Game.player_army
			# to the town garrison for this fight (see AIArrival).
			Game.player_army = Game.saved_player_army
			Game.saved_player_army = null
		Game.pending_ai_battle = false
		Game.pending_ai_side = -1
		Game.reset_pending_town_battle()
		Game.last_winner = -1
		Game.last_battle_outcome = &""
		Game.last_battle_wipeout = false
		Game.battle_return = "town"
		_present_pending_level_ups(level_up_hero)
		# This fight was not the guarded stack's, so nothing resolves a mine
		# queued behind one: drop the queue and the stale object marker.
		Game.pending_followup_object_id = -1
		Game.pending_object_id = -1
		return
	if Game.pending_object_id < 0:
		_present_pending_level_ups(level_up_hero)
		Game.last_battle_outcome = &""
		Game.pending_followup_object_id = -1
		return
	if Game.last_winner == 1:   # neutral/object side
		# Object battles return through a separate branch from hero-vs-hero and
		# town battles. A loss must still remove the active hero; previously this
		# branch only cleared the pending marker, leaving the defeated hero alive
		# and visible on the reloaded adventure map.
		if not withdrew:
			_player_hero_death_fn.call()
	elif Game.last_winner == 0:   # player side
		var obj := _map.object_by_id(Game.pending_object_id)
		if obj is NeutralStack:
			(obj as NeutralStack).consumed = true
			if _astar_fn.is_valid():
				var astar := _astar_fn.call() as PassabilityGrid
				if astar != null:
					astar.invalidate_guard_zones()
			Game.record_object_state(obj)
			var beaten := VisitResult.new()
			beaten.consumed = true
			interaction_resolved.emit(obj, beaten)   # the stack fades out: killfade
		elif obj is GuardedPickup:
			# Victory over a banded-guard site. Re-read the
			# SAME band the handler rolled and fought (rolled_band persisted through
			# the scene reload) and apply that band's reward. Human hero for exp/
			# artifact is the persisted active human hero (independent of scene
			# nodes, which don't exist yet this early in _ready); gold routes through
			# the human kingdom. The sprite STAYS (looted flag inert-gates re-visits);
			# per-type disappearance/ownership is each type's own call.
			var gp := obj as GuardedPickup
			var human := Game.state.human() if Game.state != null else null
			var hero_model: HeroModel = human.active() if human != null else null
			var reward_result := VisitResult.new()
			GuardedPickup.apply_reward(gp, gp.rolled_band, human, hero_model, Game.rng)
			if gp.rolled_band >= 0 and gp.rolled_band < gp.outcomes.size():
				var reward: Dictionary = (gp.outcomes[gp.rolled_band] as Dictionary).get("reward", {})
				var gold := int(reward.get("gold", 0))
				if gold != 0:
					reward_result.granted = {"gold": gold}
				reward_result.grant_exp = int(reward.get("exp", 0))
				reward_result.grant_artifact = gp.reward_artifact(gp.rolled_band)
			Game.record_object_state(gp)
			interaction_resolved.emit(gp, reward_result)
			if gp.type == "demon_cave":
				var victory_message := GuardedPickup.demon_cave_victory_message(gp.rolled_band)
				if victory_message != "":
					level_up_after = MapDialogs.demon_cave_info(_root, victory_message, reward_result.grant_artifact)
			elif GuardedPickup.VICTORY_MESSAGES.has(gp.type):
				var victory_text := String(GuardedPickup.VICTORY_MESSAGES[gp.type])
				if reward_result.grant_artifact != "":
					level_up_after = MapDialogs.artifact(_root, reward_result.grant_artifact, victory_text,
							int(reward_result.granted.get("gold", 0)))
				else:
					# heroes.exe shows the gold won under the text (0xb5129 -> 0xb4d38).
					level_up_after = MapDialogs.weekly_pickup(_root, gp.type, victory_text, reward_result.granted)
		elif obj is ArtifactPickup:
			var pickup := obj as ArtifactPickup
			var human_player := Game.state.human() if Game.state != null else null
			var winner := human_player.active() if human_player != null else null
			if winner != null and winner.add_artifact(pickup.artifact_id):
				pickup.consumed = true
				Game.record_object_state(pickup)
				_world.refresh_object(pickup.id)
				var pickup_result := VisitResult.new()
				pickup_result.consumed = true
				pickup_result.grant_artifact = pickup.artifact_id
				interaction_resolved.emit(pickup, pickup_result)
				level_up_after = MapDialogs.artifact(_root, pickup.artifact_id,
						ArtifactPickup.ROGUES_DEFEATED_MESSAGE
						% ArtifactCatalog.shared().display_name(pickup.artifact_id))
		elif obj is Mine:
			var prev_owner := obj.owner
			obj.owner = local_side
			Game.record_object_state(obj)
			if prev_owner != local_side:
				_world.refresh_object(obj.id)
				level_up_after = MapDialogs.mine_captured(_root, (obj as Mine).res)
		elif obj is DragonCity:
			# Victory over the 5-stack guard captures the
			# city permanently (Mine-shaped, not a one-shot reward) — 1000 gold/day
			# starts flowing on the NEXT advance_day via the per-owner sweep. Dragon
			# City has no `res` (unlike Mine), so spawn_mine_ownership's resource-cart
			# art doesn't apply; the generic side-tinted flag is the ownership tell,
			# plus an info dialog (mirrors MapDialogs.mine_captured's role).
			var dc_prev_owner := obj.owner
			obj.owner = local_side
			Game.record_object_state(obj)
			if dc_prev_owner != local_side:
				_world.refresh_object(obj.id)
				level_up_after = MapDialogs.info(_root, {"text": load("res://src/adventure/objects/handlers/dragon_city.gd").CONQUERED})
	if Game.last_winner == 0 and Game.pending_followup_object_id >= 0:
		# The hero won the guarding stack's fight while standing on the mine
		# he stepped onto: the mine is his now.
		var queued_hero_tile := level_up_hero.tile if level_up_hero != null else Vector2i(-1, -1)
		var queued_mine_dialog := _take_queued_mine(local_side, queued_hero_tile)
		if queued_mine_dialog != null:
			level_up_after = queued_mine_dialog
	Game.pending_followup_object_id = -1
	_present_pending_level_ups(level_up_hero, level_up_after)
	Game.pending_object_id = -1
	Game.last_winner = -1
	Game.last_battle_outcome = &""
	Game.battle_return = "town"

## Transfer the stable town model and its garrison/buildings to the new kingdom.
## The winner takes the loser's artifacts. Each Ultimate Artifact lost on the
## way gets the original's notice with its icon (heroes.exe 0xb5a7f, data
## 0x2995); a human is always on one side here.
const VANISHED_MESSAGE := "As you reach for the %s, it mysteriously disappears."

func _capture_spoils(winner: HeroModel, loser: HeroModel, loser_is_ai := false) -> void:
	var vanished: Array = []
	HeroModel.capture_artifacts(winner, loser, loser_is_ai, vanished)
	if _root == null:
		return
	for id: String in vanished:
		var text := VANISHED_MESSAGE % ArtifactCatalog.shared().display_name(id)
		if _root.has_method("queue_modal_dialog"):
			_root.call("queue_modal_dialog", func() -> CanvasLayer:
				return MapDialogs.artifact(_root, id, text)
			)
		else:
			MapDialogs.artifact(_root, id, text)

## Returns the "lost your last town" box when this capture raised one.
func capture_town(tw: TownObject, new_side: int) -> CanvasLayer:
	town_notice = null
	if tw == null:
		return null
	var prev := tw.owner
	tw.owner = new_side
	tw.garrison = null
	tw.params.erase("army")
	Game.record_object_state(tw)
	var town_name: String = String(tw.params.get("name", ""))
	if town_name == "":
		town_name = BuildingCatalog.faction_for_type(tw.town_type).capitalize()
	var old_player: PlayerState = null
	var new_player: PlayerState = null
	if Game.state != null:
		old_player = Game.state.player_of(prev)
		new_player = Game.state.player_of(new_side)
		var model: TownModel = old_player.remove_town(tw.id) if old_player != null else null
		if model == null:
			model = TownModel.new()
			model.object_id = tw.id
			model.town_name = town_name
			model.setup(0, {}, ArmyData.new(), tw.town_type)
			if tw.neutral_built.is_empty():
				model.init_start_buildings(Game.rng if Game != null else RandomNumberGenerator.new(), false)
			else:
				model.set_start_dwellings(tw.neutral_built)
			if not bool(tw.params.get("has_castle", true)):
				model.has_castle = false
			model.roll_guild(Game.rng if Game != null else RandomNumberGenerator.new())
		# The town changes hands empty: the garrison fought the winner (or died
		# with the gate hero). Troops that did not fit into that hero's five
		# slots -- or survivors left by an AI quick-fight -- stayed on the model,
		# and carrying them over showed the loser's army in the new owner's
		# garrison row.
		model.army = ArmyData.new()
		model.ship_launch_tile = tw.action_tile + Vector2i(-1, 1)
		var map_ref: MapData = _map if _map != null else (_root.get("_map") if _root != null and "_map" in _root else null)
		model.sea_access = map_ref.is_water(model.ship_launch_tile) if map_ref != null else false
		if new_player != null:
			new_player.add_town(model)
			new_player.select_town(tw.id)
			if Game != null and "prefer_active_town" in Game:
				Game.prefer_active_town = true
		if old_player != null:
			old_player.owns_town = not old_player.towns.is_empty()
			if not old_player.owns_town:
				if old_player.alive and not old_player.heroes.is_empty():
					old_player.townless_days_left = 7
				else:
					old_player.townless_days_left = -1
		for p: PlayerState in Game.state.players:
			p.owns_town = not p.towns.is_empty()
	var local_side := Game.state.active_player_side if Game.state != null else 0
	if prev == local_side and new_side != local_side:
		# The original tells you nothing when it takes a town you can spare
		# (DOS capture 2026-10-12, enemy hero took a second town: no dialog).
		# Only losing the last one speaks, heroes.exe 0xd28c8. "The enemy has
		# captured the town of XX!!" (0xd2c19) belongs to the scenario
		# lose-condition check, handled by the campaign branch below.
		if _root != null and old_player != null and not old_player.owns_town:
			var color_names := ["Blue", "Green", "Red", "Yellow"]
			var color_name: String = color_names[clampi(old_player.crest_idx / 4, 0, 3)]
			town_notice = MapDialogs.crest_info(_root, clampi(old_player.crest_idx / 4, 0, 3),
					"%s player, you have lost your last town.  If you do not conquer another town in the next week, you will be eliminated." % color_name)
	elif Game.game_mode == &"campaign" and Game.campaign != null \
			and Game.campaign.mission().objective == &"capture_gateway" \
			and tw.authored_owner == -1 and new_side != local_side:
		if _root != null:
			MapDialogs.info(_root, {"text": "The enemy has captured the town of %s!!" % town_name})
		Game.pending_defeat = true
		Game.pending_defeat_message = "The enemy has captured the town of %s!!" % town_name
	# The owner flag on the map is a sprite hung on the gate cells (heroes.exe
	# 0x7da4e); it only changes colour when the town object is redrawn. A town
	# taken by walking into it kept the loser's flag until the next scene
	# reload, so redraw it here -- after the model moved to the new owner, so
	# the castle art matches the town that was taken.
	if _world != null and is_instance_valid(_world):
		_world.refresh_object(tw.id)
	if _update_ui_fn.is_valid():
		_update_ui_fn.call()
	if _check_game_over_fn.is_valid():
		_check_game_over_fn.call()
	return town_notice

static func should_dissolve_pickup(obj: MapObject, vr: VisitResult) -> bool:
	if obj is ResourcePile:
		return true
	if obj != null and obj.is_walk_on_pickup() and not vr.show_dialog and vr.choice.is_empty() \
			and vr.free_dwelling == null and vr.recruit_dwelling == null and vr.join_offer_stack == null:
		return true
	return false
