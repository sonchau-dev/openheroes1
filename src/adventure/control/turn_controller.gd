class_name AdventureTurnController
extends Node

## End-turn / day-rollover / game-over-check for the adventure map. Root keeps
## the end-turn button guard (_ai_running / hero.is_moving()) and route-cancel
## before calling end_turn(); this controller owns the AI phase, the day
## rollover, and the win/loss check. Root still owns the game-over dialog
## itself (_show_game_over / _game_over_shown) since it also flips
## _ai_running to freeze input under the dialog.

signal ai_phase_changed(running: bool)
signal ai_player_started(side: int, color_index: int)
signal human_handoff_requested(side: int, color_index: int, new_day: bool)
## Remote play: the turn passes to a player on the other machine. The map
## transmits the run and parks on the waiting banner. Kept separate from the
## hot-seat signal so this controller never has to touch the net session.
signal remote_handoff_requested(side: int, new_day: bool)
signal new_day_started(day: int)
signal new_week_started(event: Dictionary)
signal player_eliminated(side: int)
signal townless_warning(side: int, days_left: int, message: String)
signal townless_banished(side: int, message: String)
## A kingdom with no heroes and no towns. heroes.exe tells the player (0xd1f40, 0x3e40).
signal player_vanquished(side: int, message: String)

## Reference timing from a DOS recording of a new day:
## After the final AI turn ends, the dawn card appears at 5.615s, the minimap
## returns at 5.757s, and the cursor becomes the move horse at 5.782s (~150ms).
## The dawn card then remains visible in the bottom-right panel while the player
## has full movement control.
const NEW_DAY_HOLD_SECONDS := 0.15

var _map: MapData
var _ai: AITurnRunner
var _hero_fn: Callable          # func() -> Hero
var _army_fn: Callable          # func() -> ArmyData (root._current_army)
var _persist_fn: Callable       # func() -> void (root._persist_hero)
var _update_ui_fn: Callable     # func() -> void (root._update_ui)
var _game_over_fn: Callable     # func(message: String) -> void (root._show_game_over)
var _follow_hero_fn: Callable   # func() -> void (root sets _following = true)
var _heroes_nodes_fn: Callable  # func() -> Array (root._heroes)

func setup(map: MapData, ai: AITurnRunner, hero_fn: Callable, army_fn: Callable,
		persist_fn: Callable, update_ui_fn: Callable, game_over_fn: Callable,
		follow_hero_fn: Callable, heroes_nodes_fn: Callable = Callable()) -> void:
	_map = map
	_ai = ai
	_hero_fn = hero_fn
	_army_fn = army_fn
	_persist_fn = persist_fn
	_update_ui_fn = update_ui_fn
	_game_over_fn = game_over_fn
	_follow_hero_fn = follow_hero_fn
	_heroes_nodes_fn = heroes_nodes_fn

## Human players act first in runtime order. The final human hands control to
## the AI phase; only that phase's completion rolls the shared day over. Remote
## play uses the same rotation — the second seat just lives on another machine,
## so whoever is last in the order runs the computer players and the day
## rollover locally before shipping the run back.
func end_turn() -> void:
	ai_phase_changed.emit(true)
	# KB calendar-economy.md §2.1 step 1: the original writes AUTOSAVE at the
	# end of the outgoing human's turn — before the remaining players and
	# before the day rolls over — so the file holds the day that was just
	# played, with the human's hero where they left it. The hero's end-of-turn
	# tile has to be in the model before it is written.
	_persist_fn.call()
	Game.autosave()
	if Game.state != null:
		var ending := Game.state.player_of(Game.state.active_player_side)
		if ending != null:
			ending.end_turn_townless()
			# KB calendar-economy.md 2.1 steps 2-3: the banishment check follows
			# the kingdom's own turn, before the computer players move.
			if _banish_if_expired(ending) and check_game_over():
				return
	if is_multi_kingdom() and Game.state != null:
		var next_human := Game.state.next_human_after(Game.state.active_player_side)
		if next_human != null:
			_request_handoff(next_human, false)
			return
	Game.ai_turn_cursor = Game.state.first_ai_side() if Game.state != null else 1
	await _run_remaining_ai()

## Resume after an AI-launched battle using the cursor persisted before the
## scene switch.  The defeated/attacking side has already been resolved.
## `notice` is a message the battle's outcome raised (the last town lost):
## heroes.exe shows it modally, so the computer players wait for OKAY.
func resume_ai_phase(notice: CanvasLayer = null) -> void:
	ai_phase_changed.emit(true)
	await await_notice(notice)
	await _run_remaining_ai()

## Hold the turn until a modal message raised mid-turn is dismissed.
## Headless runs have nobody to press OKAY.
func await_notice(notice: CanvasLayer) -> void:
	if notice != null and is_instance_valid(notice) and notice.has_signal("closed") \
			and DisplayServer.get_name() != "headless":
		await notice.closed

func _run_remaining_ai() -> void:
	var players := Game.state.ai_players() if Game.state != null else []
	while true:
		var ai: PlayerState = null
		for candidate: PlayerState in players:
			if candidate.side >= Game.ai_turn_cursor:
				ai = candidate
				break
		if ai == null:
			break
		# The cursor stays on this side until its turn is done: a battle swaps
		# the scene mid-turn and resume_ai_phase re-runs the side for the heroes
		# that have not moved yet.
		Game.ai_turn_cursor = ai.side
		if ai.alive:
			ai_player_started.emit(ai.side, clampi(ai.crest_idx / 4, 0, 4))
			if await _ai.run_turn(ai):
				return   # scene switches to battle; the side resumes on return
			ai.end_turn_townless()
			_banish_if_expired(ai)
		Game.ai_turn_cursor = ai.side + 1
	await finish_day()

## Day rollover: economy tick + refill every hero's movement. Runs after all AI turns.
func finish_day() -> void:
	# Consume the AI-battle marker FIRST: adventure_map._ready re-runs
	# finish_day whenever this is still true, so leaving it set advances the
	# day again on every town/battle/hero-screen round-trip.
	Game.pending_day_advance = false
	Game.ai_turn_cursor = 0
	var new_week := false
	if Game.state != null:
		new_week = Game.state.advance_day(_map.objects, Game.rng, _map)
		if new_week:
			# A scene change reloads the map and reapplies only recorded state.
			for o: MapObject in _map.objects:
				if o is Dwelling or o is WeeklyPickup or (o is TownObject and o.owner < 0):
					Game.record_object_state(o)
		var active_side := Game.state.active_player_side
		for player: PlayerState in Game.state.players:
			if not player.alive:
				continue
			var nodes: Array = (_heroes_nodes_fn.call() if _heroes_nodes_fn.is_valid() else []) \
					if player.side == active_side else _ai.heroes_for_side(player.side)
			for idx in player.heroes.size():
				var model: HeroModel = player.heroes[idx]
				model.max_move_points = Hero.calculate_model_max_move(
						model, _map.objects, player.side,
						player.ai_level if player.is_ai else 0)
				model.move_points = model.max_move_points
				if idx < nodes.size():
					var node := nodes[idx] as Hero
					if node != null:
						node.max_move_points = model.max_move_points
						node.move_points = model.move_points

	_follow_hero_fn.call()
	# Nodes and models pair by index. Pairing the active hero's node with
	# hero_model (heroes[0]) moved that hero, unseen, onto another hero's tile.
	if _ai != null:
		_ai.persist_heroes()
	_persist_fn.call()
	_update_ui_fn.call()
	_process_townless_players()
	if check_game_over():
		return
	if Game.state != null:
		new_day_started.emit(Game.state.day)
		if new_week:
			new_week_started.emit(Game.state.last_week_event.duplicate(true))
		if DisplayServer.get_name() != "headless":
			await get_tree().create_timer(NEW_DAY_HOLD_SECONDS).timeout
		if is_multi_kingdom():
			var first_human := Game.state.first_human()
			if first_human != null and first_human.side != Game.state.active_player_side:
				_request_handoff(first_human, true)
				return
	# No autosave here: the original writes it at the end of the outgoing
	# human's turn (see end_turn), so the file holds the day just played.
	ai_phase_changed.emit(false)

## Hot seat and remote play both run several human kingdoms, so they share the
## turn rotation and the multi-kingdom win check. The only difference is where
## the next human is sitting.
func is_multi_kingdom() -> bool:
	return Game.game_mode == &"hotseat" or Game.game_mode == &"network"

func _request_handoff(player: PlayerState, new_day: bool) -> void:
	if Game.game_mode == &"network":
		remote_handoff_requested.emit(player.side, new_day)
		return
	if new_day and not player.owns_town and not player.heroes.is_empty():
		if player.townless_days_left == 1:
			var msg := "%s player, this is your last day to capture a town, or you will be banished from this land." % player.color_name()
			townless_warning.emit(player.side, 1, msg)
		elif player.townless_days_left > 1:
			var msg := "%s player, you only have %d days left to capture a town, or you will be banished from this land." % [player.color_name(), player.townless_days_left]
			townless_warning.emit(player.side, player.townless_days_left, msg)
	human_handoff_requested.emit(player.side,
			clampi(player.crest_idx / 4, 0, 3), new_day)

func _process_townless_players() -> void:
	if Game.state == null:
		return
	var active_side := Game.state.active_player_side
	for player: PlayerState in Game.state.players:
		if not player.alive or player.owns_town or _banish_if_expired(player) \
				or player.is_ai or player.side != active_side:
			continue
		var color_name := player.color_name()
		if player.townless_days_left == 1:
			var msg := "%s player, this is your last day to capture a town, or you will be banished from this land." % color_name
			townless_warning.emit(player.side, 1, msg)
		elif player.townless_days_left > 1:
			var msg := "%s player, you only have %d days left to capture a town, or you will be banished from this land." % [color_name, player.townless_days_left]
			townless_warning.emit(player.side, player.townless_days_left, msg)

## A townless kingdom whose countdown just ran out loses its heroes and the
## game (heroes.exe 0x7fa3d). True when the player was banished here.
func _banish_if_expired(player: PlayerState) -> bool:
	if not player.alive or player.owns_town or player.townless_days_left != 0:
		return false
	var color_name := player.color_name()
	var msg := "%s player, your heroes abandon you, and you are banished from this land." % color_name \
			if not player.is_ai else \
			"%s player's Heroes have abandoned him, and he is banished from this land." % color_name
	player.abandon_heroes(Game.rng, Game.state.hero_pool if Game.state != null else null)
	sweep_eliminated_player(player.side)
	player.alive = false
	townless_banished.emit(player.side, msg)
	_notify_remote_defeat(player.side, msg)
	return true

## Remote play: a kingdom eliminated on this machine is told on its own.
func _notify_remote_defeat(side: int, msg: String) -> void:
	if Game.game_mode == &"network" and side == Net.remote_side():
		Net.send_state(side, NetProtocol.KIND_FINAL, msg)

## Clear ownership of all map structures and boats held by an eliminated side.
func sweep_eliminated_player(side: int) -> void:
	if _map != null:
		for obj: MapObject in _map.objects:
			if (obj is Mine or obj is DragonCity or obj is Lighthouse or obj is TownObject) and obj.owner == side:
				obj.owner = -1
				Game.record_object_state(obj)
	if Game.state != null:
		for boat: BoatState in Game.state.boats:
			if boat.owner == side:
				boat.owner = -1
		var pl := Game.state.player_of(side)
		if pl != null:
			pl.towns.clear()
			pl.owns_town = false
	player_eliminated.emit(side)

## The human kingdom is defeated only after losing every hero and town (or a
## latched no-town defeat); a town-owning kingdom can still hire at its tavern.
func check_game_over() -> bool:
	if Game.state == null or Game.state.players.size() < 2:
		return false
	var human := Game.state.human()

	for player: PlayerState in Game.state.players:
		if player.alive and player.is_eliminated():
			player.alive = false
			sweep_eliminated_player(player.side)
			# The human's own defeat is the game-over screen's to announce,
			# except when other kingdoms play on and no game over follows.
			if player.side != Game.state.active_player_side or is_multi_kingdom():
				var msg := "%s player has been vanquished!" % player.color_name()
				player_vanquished.emit(player.side, msg)
				_notify_remote_defeat(player.side, msg)

	if is_multi_kingdom():
		Game.pending_defeat = false
		var living: Array = Game.state.players.filter(
				func(player: PlayerState): return player.alive)
		var living_humans: Array = living.filter(
				func(player: PlayerState): return not player.is_ai)
		if living_humans.is_empty():
			_game_over_fn.call("All human players have been defeated!")
			return true
		var living_teams := {}
		for player: PlayerState in living:
			living_teams[player.team] = true
		if living.size() <= 1 or living_teams.size() <= 1:
			var winner := living[0] as PlayerState
			var color_names := ["Blue", "Green", "Red", "Yellow"]
			var winner_name := "Computer" if winner.is_ai else String(
					color_names[clampi(winner.crest_idx / 4, 0, 3)])
			_game_over_fn.call("%s Player is victorious!" % winner_name)
			return true
		# Remote play: this machine's own kingdom is gone while the others play
		# on. Ship the run to the survivor and leave; without this the loser sits
		# on the waiting banner with nothing ever coming back.
		var local := Game.state.player_of(Game.state.active_player_side)
		if Game.game_mode == &"network" and local != null and not local.alive:
			Net.send_state(Net.remote_side(), NetProtocol.KIND_STATE, "", true)
			_game_over_fn.call("You have been defeated!")
			return true
		return false

	if Game.pending_defeat or (human != null and (not human.alive or (human.heroes.is_empty() and not human.owns_town))):
		var defeat_text: String = Game.pending_defeat_message if Game.pending_defeat_message != "" else "You have been defeated!"
		_game_over_fn.call(defeat_text)
		return true
	if Game.game_mode == &"campaign" and Game.campaign != null:
		if Game.campaign_objective_complete(_map):
			_game_over_fn.call(Game.campaign.mission().completion_text)
			return true
		if Game.campaign_objective_failed(_map):
			var fail_msg: String = Game.pending_defeat_message
			if fail_msg == "":
				if Game.campaign.mission().objective == &"dig_eye":
					fail_msg = "A great tragedy - the enemy has found the Eye of Goros!!!  The people abandon you, all is lost."
				else:
					fail_msg = "You have been defeated!"
			_game_over_fn.call(fail_msg)
			return true
		# A mission is won only by its own objective. On camp1 the original
		# played on after every computer town fell, with Gateway still
		# neutral (play-through recording, 2026-10-12).
		return false
	# Victory: every hostile side eliminated (hero dead AND town lost).
	var living_enemies: Array = Game.state.players.filter(
			func(player: PlayerState):
				return player.alive and (player.is_hostile_to(human) if human != null else player.is_ai))
	if living_enemies.is_empty():
		_game_over_fn.call("Victory! Your enemies are vanquished.")
		return true
	return false
