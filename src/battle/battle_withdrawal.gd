class_name BattleWithdrawal
extends RefCounted

## General's Options, retreat, and surrender flows for combat.

const GeneralOptionsScript := preload("res://src/ui/battle_general_options.gd")
const SurrenderDialogScript := preload("res://src/ui/battle_surrender_dialog.gd")
const RetreatDialogScript := preload("res://src/ui/battle_retreat_dialog.gd")
const MessageDialogScript := preload("res://src/ui/battle_message_dialog.gd")
const BattleOutcomeScript := preload("res://src/battle/battle_outcome.gd")

const NOT_ENOUGH_GOLD := "You don't have enough gold!"

signal action_requested(action: Dictionary)
signal cast_requested(side: int)
signal status_changed(text: String)
signal cursor_changed(id: int)
signal dialog_closed()

var host: Node2D = null
var state: BattleState = null
var player_side: int = 0
var command_side_getter: Callable
var uses_player_input_checker: Callable
var await_actor_getter: Callable

var general_options: CanvasLayer = null
var general_options_side: int = -1
var surrender_side: int = -1
var surrender_dialog: CanvasLayer = null
var retreat_dialog: CanvasLayer = null
var message_dialog: CanvasLayer = null

func setup(p_host: Node2D, p_state: BattleState, p_player_side: int,
		p_command_side: Callable, p_uses_player_input: Callable, p_await_actor: Callable) -> void:
	host = p_host
	state = p_state
	player_side = p_player_side
	command_side_getter = p_command_side
	uses_player_input_checker = p_uses_player_input
	await_actor_getter = p_await_actor

func has_modal() -> bool:
	return general_options != null or surrender_dialog != null \
			or retreat_dialog != null or message_dialog != null

func player_has_battle_hero(side: int = -1) -> bool:
	if side < 0:
		side = player_side
	if state == null or state.heroes[side] == null:
		return false
	# An AI assault on a human town aliases the defending side to the garrison, not the
	# field hero. Garrison troops cannot cast, retreat, or surrender for a hero.
	var battle_army := Game.player_army if side == player_side else Game.enemy_army
	return battle_army == null \
			or (state.heroes[side] as HeroModel).army == battle_army

func open_general_options(force_enable: bool = false) -> void:
	open_general_options_for_side(-1, force_enable)

func open_general_options_for_side(tent_side: int, force_enable: bool = false, other_modal: bool = false) -> void:
	if has_modal() or other_modal:
		return
	var side := tent_side if tent_side >= 0 else _get_command_side()
	general_options_side = side
	var hero := state.heroes[side] as HeroModel if state != null else null
	if hero == null:
		# heroes.exe 0xc46b3: a heroless side has no window and no message.
		return
	var actor: BattleStack = _get_await_actor()
	var has_turn: bool = actor != null and actor.side == side
	var hero_commands: bool = player_has_battle_hero(side)
	var can_cast: bool = force_enable or (has_turn and hero_commands and hero.has_spellbook \
			and not state.cast_used[side])
	var can_retreat: bool = _uses_player_input(side) \
			and (force_enable or (has_turn and hero_commands and state.siege_defender_side != side))
	# Gold is checked only once the offer is accepted (heroes.exe 0xc053a).
	var opponent_hero: HeroModel = state.heroes[1 - side] as HeroModel if state != null else null
	var can_surrender: bool = _uses_player_input(side) \
			and (force_enable or (has_turn and hero_commands and opponent_hero != null))
	cursor_changed.emit(-1)
	var dialog := GeneralOptionsScript.new()
	dialog.setup(hero, can_cast, can_retreat, can_surrender)
	dialog.action_selected.connect(_on_general_action)
	dialog.status_changed.connect(func(t: String): status_changed.emit(t))
	dialog.tree_exited.connect(func():
		if general_options == dialog:
			general_options = null
			general_options_side = -1
			dialog_closed.emit())
	general_options = dialog
	if host != null:
		host.add_child(dialog)

func _on_general_action(action: StringName) -> void:
	var side := general_options_side
	general_options_side = -1
	general_options = null
	match action:
		&"cast":
			cast_requested.emit(side)
		&"retreat":
			request_retreat(side)
		&"surrender":
			request_surrender(side)

func request_retreat(side: int = -1) -> void:
	if side < 0:
		side = _get_command_side()
	var actor: BattleStack = _get_await_actor()
	if not _uses_player_input(side) or actor == null or not player_has_battle_hero(side):
		return
	if actor.side != side:
		return
	# A besieged hero's Retreat is greyed out (heroes.exe 0xc4a1a); no text.
	if state != null and state.siege_defender_side == side:
		return
	open_retreat_dialog()

func open_retreat_dialog() -> void:
	if retreat_dialog != null:
		return
	cursor_changed.emit(-1)
	var dialog := RetreatDialogScript.new()
	dialog.setup()
	dialog.confirmed.connect(confirm_retreat)
	dialog.cancelled.connect(func():
		retreat_dialog = null
		dialog_closed.emit())
	dialog.tree_exited.connect(func():
		if retreat_dialog == dialog:
			retreat_dialog = null
			dialog_closed.emit())
	retreat_dialog = dialog
	if host != null:
		host.add_child(dialog)

func confirm_retreat() -> void:
	retreat_dialog = null
	if _get_await_actor() != null:
		action_requested.emit({"action": "retreat"})

func request_surrender(side: int = -1) -> void:
	if side < 0:
		side = _get_command_side()
	var actor: BattleStack = _get_await_actor()
	if not _uses_player_input(side) or actor == null or not player_has_battle_hero(side):
		return
	if actor.side != side:
		return
	# Surrender is greyed out without an opposing hero (heroes.exe 0xc49a4).
	var opponent_hero: HeroModel = state.heroes[1 - side] as HeroModel if state != null else null
	if opponent_hero == null:
		return
	surrender_side = side
	var cost := BattleOutcomeScript.surrender_cost(state.stacks, side) if state != null else 0
	open_surrender_dialog(opponent_hero, cost)

func open_surrender_dialog(opponent: HeroModel, cost: int) -> void:
	if surrender_dialog != null:
		return
	cursor_changed.emit(-1)
	var dialog := SurrenderDialogScript.new()
	dialog.setup(opponent, cost)
	dialog.accepted.connect(accept_surrender)
	dialog.declined.connect(func():
		surrender_dialog = null
		dialog_closed.emit())
	dialog.tree_exited.connect(func():
		if surrender_dialog == dialog:
			surrender_dialog = null
			dialog_closed.emit())
	surrender_dialog = dialog
	if host != null:
		host.add_child(dialog)

## The offer is made whatever the treasury holds; a short purse is refused
## only after Accept, with an Okay box, and the battle goes on (heroes.exe
## 0xc053a-0xc0570).
func accept_surrender() -> void:
	surrender_dialog = null
	var side := surrender_side if surrender_side >= 0 else _get_command_side()
	surrender_side = -1
	var payer := Game.player_for_battle_side(side)
	var cost := BattleOutcomeScript.surrender_cost(state.stacks, side) if state != null else 0
	if payer == null or payer.gold() < cost:
		open_message_dialog(NOT_ENOUGH_GOLD)
		return
	if _get_await_actor() != null:
		action_requested.emit({"action": "surrender"})

func open_message_dialog(message: String) -> void:
	if message_dialog != null:
		return
	cursor_changed.emit(-1)
	var dialog := MessageDialogScript.new()
	dialog.setup(message)
	dialog.closed.connect(func():
		message_dialog = null
		dialog_closed.emit())
	dialog.tree_exited.connect(func():
		if message_dialog == dialog:
			message_dialog = null
			dialog_closed.emit())
	message_dialog = dialog
	if host != null:
		host.add_child(dialog)

## "General's Options" over the acting side's tent, "View Opposing General"
## over the other (heroes.exe 0xbfe18, 0xbfe4b, data 0x21354/0x21358).
static func tent_hover_text(side: int, await_actor: BattleStack) -> String:
	if side >= 0 and await_actor != null and await_actor.side != side:
		return "View Opposing General"
	return "General's Options"

func _get_command_side() -> int:
	return command_side_getter.call() if command_side_getter.is_valid() else player_side

func _uses_player_input(side: int) -> bool:
	return uses_player_input_checker.call(side) if uses_player_input_checker.is_valid() else false

func _get_await_actor() -> BattleStack:
	return await_actor_getter.call() if await_actor_getter.is_valid() else null
