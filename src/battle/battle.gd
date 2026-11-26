extends Node2D

## Interactive battle: drives the #4b engine — player commands their stacks by
## clicking, the enemy uses BattleAI, actions animate via BattleView, ends on
## a Victory/Defeat result. Headless auto-resolves both sides to a winner.
## Split into domain subcomponents:
## BattleWithdrawal, BattleSpellFlow, and BattleInput.
const BattlefieldGroundScript := preload("res://src/battle/battlefield_ground.gd")
const BattlefieldTentScript := preload("res://src/battle/battlefield_tent.gd")
const BattlefieldLayoutScript := preload("res://src/battle/battlefield_layout.gd")
const BattlefieldSiegeScript := preload("res://src/battle/battlefield_siege.gd")
const BattlefieldShipScript := preload("res://src/battle/battlefield_ship.gd")
const BattleTextScript := preload("res://src/battle/battle_text.gd")
const CreatureInfoDialogScript := preload("res://src/battle/creature_info_dialog.gd")
const BattleOutcomeScript := preload("res://src/battle/battle_outcome.gd")
const GeneralOptionsScript := preload("res://src/ui/battle_general_options.gd")
const SurrenderDialogScript := preload("res://src/ui/battle_surrender_dialog.gd")
const RetreatDialogScript := preload("res://src/ui/battle_retreat_dialog.gd")
const MessageDialogScript := preload("res://src/ui/battle_message_dialog.gd")
const PLAYER_SIDE := 0

## Combat cursors (cmbtmous.icn): 0 invalid, 1 move, 3 shoot, 5 view info, 7-14 directional swords.
const CMBT := "res://assets/art/cmbtmous/%04d.png"
const SPELL_ICON := UiKit.ART + "spells/%04d.png"
const CUR_INVALID := BattleInput.CUR_INVALID
const CUR_MOVE := BattleInput.CUR_MOVE
const CUR_SHOOT := BattleInput.CUR_SHOOT
const CUR_GENERAL := BattleInput.CUR_GENERAL
const CUR_VIEW := BattleInput.CUR_VIEW
const CUR_SPELL_BASE := BattleInput.CUR_SPELL_BASE
## [screen-angle°, sword sprite id] — 0°=E, 90°=S, 180°=W, -90°=N.
## Sword sprite tips: 8 E, 9 SE, 14 S, 10 SW, 11 W, 12 NW, 13 N, 7 NE.
const _SWORD_DIRS := BattleInput._SWORD_DIRS

const ARMY := [
	["swordsman", 10, 0, 0, 0],
	["archer", 8, 0, 0, 2],
	["pikeman", 12, 0, 0, 4],
	["cavalry", 4, 1, 6, 0],
	["swordsman", 8, 1, 6, 2],
	["ghost", 6, 1, 6, 3],
	["paladin", 2, 1, 6, 4],
]

const BAR_H := 20
const TB := UiKit.ART + "textbar/%04d.png"   # 0 message bar, 1/2 AUTO up/down, 3/4 SKIP up/down
## The recorded DOS game exposes the newly selected enemy for one 0.1s sample
## before movement starts. This lets the cycling outline register visually.
const AI_DECISION_HOLD_SECONDS := 0.1
## Authentic pause between the defender returning to idle and initiating its
## retaliation swing, measured as 6 frames at 70 FPS (~85 ms) from retail heroes.exe.
const RETALIATION_CADENCE := 0.08
## Long enough for the catapult arm to release and the rock to be mid-arc.
const CATAPULT_SHOT_DELAY := 1.36
const STANDALONE_SPELL_CHARGES := 99

const ARMAGEDDON_STEPS := BattleSpellFlow.ARMAGEDDON_STEPS
const ARMAGEDDON_STEP_SECONDS := BattleSpellFlow.ARMAGEDDON_STEP_SECONDS
const ARMAGEDDON_FADE_Z := BattleSpellFlow.ARMAGEDDON_FADE_Z
const ARMAGEDDON_FADE_SHADER := BattleSpellFlow.ARMAGEDDON_FADE_SHADER
const SPELL_HIT_EFFECTS := BattleSpellFlow.SPELL_HIT_EFFECTS
const SPELLBOOK_VIEW := BattleSpellFlow.SPELLBOOK_VIEW

const NO_HERO_TO_CAST := BattleSpellFlow.NO_HERO_TO_CAST
const ALREADY_CAST := BattleSpellFlow.ALREADY_CAST
const NO_SPELLS_TO_CAST := BattleSpellFlow.NO_SPELLS_TO_CAST
const NOT_ENOUGH_GOLD := BattleWithdrawal.NOT_ENOUGH_GOLD

signal _player_action(a: Dictionary)

var _withdrawal: BattleWithdrawal
var _spell_flow: BattleSpellFlow

var _state: BattleState:
	get:
		return _state_ref
	set(v):
		_state_ref = v
		if _withdrawal != null:
			_withdrawal.state = v
		if _spell_flow != null:
			_spell_flow.state = v

var _state_ref: BattleState = null

var _view: BattleView:
	get:
		return _view_ref
	set(v):
		_view_ref = v
		if _spell_flow != null:
			_spell_flow.view = v

var _view_ref: BattleView = null

var _layout: Dictionary = {}
var _siege_view: Node2D = null
var _siege_defender_side: int = -1
var _siege_faction: int = 0
var _prebattle_player: AudioStreamPlayer = null
var _prebattle_skipped: bool = false

var _await_actor: BattleStack = null   # set while waiting for this stack's command
var _cmbt_cache: Dictionary = {}
var _spell_cursor_cache: Dictionary = {}
var _cur_id: int = -2
var _auto: bool = false                 # AUTO button: hand both sides to the AI
var _status: Label = null
var _glow_stack: BattleStack = null     # stack currently outlined as active

var _info_dialog: CanvasLayer = null

# Backwards-compatible facades for properties moved into subcomponents:
var _general_options: CanvasLayer:
	get: return _withdrawal.general_options if _withdrawal != null else null
	set(v):
		if _withdrawal != null: _withdrawal.general_options = v

var _surrender_dialog: CanvasLayer:
	get: return _withdrawal.surrender_dialog if _withdrawal != null else null
	set(v):
		if _withdrawal != null: _withdrawal.surrender_dialog = v

var _retreat_dialog: CanvasLayer:
	get: return _withdrawal.retreat_dialog if _withdrawal != null else null
	set(v):
		if _withdrawal != null: _withdrawal.retreat_dialog = v

var _message_dialog: CanvasLayer:
	get: return _withdrawal.message_dialog if _withdrawal != null else null
	set(v):
		if _withdrawal != null: _withdrawal.message_dialog = v

var _spellbook_view: Node:
	get: return _spell_flow.spellbook_view if _spell_flow != null else null
	set(v):
		if _spell_flow != null: _spell_flow.spellbook_view = v

var _pending_spell: String:
	get: return _spell_flow.pending_spell if _spell_flow != null else ""
	set(v):
		if _spell_flow != null: _spell_flow.pending_spell = v

var _player_side: int:
	get:
		return _player_side_val
	set(v):
		_player_side_val = v
		if _withdrawal != null:
			_withdrawal.player_side = v

var _player_side_val: int = PLAYER_SIDE

## Developer screenshots and fixtures (src/tools/shots/battle_shots.gd),
## loaded only when one of DEV_FLAGS is on the command line.
const SHOTS := "res://src/tools/shots/battle_shots.gd"
const DEV_FLAGS := ["--shot", "--seed=", "--terrain=", "--reference-obstacles", "--probe="]
var _shots = null

func _init() -> void:
	_withdrawal = BattleWithdrawal.new()
	_spell_flow = BattleSpellFlow.new()
	_withdrawal.setup(self, _state_ref, _player_side, _command_side, _uses_player_input, func(): return _await_actor)
	_spell_flow.setup(self, _state_ref, _view_ref, _withdrawal, _command_side, _uses_player_input, func(): return _auto, func(): return _await_actor)

	_withdrawal.action_requested.connect(func(a: Dictionary):
		if not _pending_spell.is_empty():
			_cancel_pending_spell()
		_player_action.emit(a))
	_withdrawal.cast_requested.connect(func(side: int):
		call_deferred("_on_cast", side))
	_withdrawal.status_changed.connect(_set_status)
	_withdrawal.cursor_changed.connect(_set_cmbt_cursor)
	_withdrawal.dialog_closed.connect(_update_combat_cursor)

	_spell_flow.action_requested.connect(func(a: Dictionary):
		_player_action.emit(a))
	_spell_flow.status_changed.connect(_set_status)
	_spell_flow.cursor_changed.connect(_set_cmbt_cursor)
	_spell_flow.dialog_closed.connect(_update_combat_cursor)

static func human_controls_battle_side(side: int,
		opponent_is_human: bool, player_side: int = PLAYER_SIDE) -> bool:
	return side == player_side or (side == 1 - player_side and opponent_is_human)

func _uses_player_input(side: int) -> bool:
	return human_controls_battle_side(side, Game.battle_opponent_is_human, _player_side)

func _command_side() -> int:
	return _await_actor.side if _await_actor != null and _uses_player_input(
			_await_actor.side) else _player_side

func _ready() -> void:
	Game.set_default_cursor()
	# Music stops, then one of the four battle tracks starts (0x896a7).
	Game.music.stop()
	Game.music.play(Game.music.battle_track())
	_player_side = Game.human_battle_side()
	_withdrawal.player_side = _player_side
	_siege_defender_side = Game.siege_defender_side()
	_siege_faction = Game.siege_faction()
	_shots = DevFlags.tool(SHOTS, DEV_FLAGS)
	if _shots != null:
		_shots.prepare(self)
	_draw_background()
	_draw_ground()
	var standalone_fixture := _uses_standalone_fixture()
	var battle_seed: int = 20260613
	if not standalone_fixture:
		battle_seed = randi()
	if _shots != null:
		battle_seed = _shots.battle_seed(battle_seed)

	# Siege battlefields never contain natural obstacles.
	if _siege_defender_side >= 0:
		_layout = {"terrain": "grass", "obstacles": []}
	elif Game.battlefield_kind == &"ship":
		_layout = BattlefieldShipScript.layout()
	elif _shots != null and _shots.reference_obstacles():
		_layout = BattlefieldLayoutScript.grass_reference()
	else:
		var battle_rng := RandomNumberGenerator.new()
		battle_rng.seed = battle_seed
		_layout = BattlefieldLayoutScript.generate(_battle_terrain(), battle_rng)
	if Game.battlefield_kind != &"ship":
		BattlefieldLayoutScript.paint_obstacles(self, _layout)
	_draw_tent()
	_draw_status_bar()
	if _siege_defender_side >= 0:
		_siege_view = BattlefieldSiegeScript.new()
		add_child(_siege_view)
		_siege_view.setup(_siege_faction, _siege_defender_side, Hex.ORIGIN, Hex.STEP)
	var stacks := _build_stacks()
	var new_state := BattleState.new()
	new_state.setup(stacks, battle_seed, BattlefieldLayoutScript.blocked_cells(_layout),
			_siege_defender_side, Game.siege_defender_has_tavern(),
			Game.siege_defender_tower_k(), Game.siege_defender_mage_guild_level())
	if standalone_fixture:
		_prepare_standalone_spell_targets(stacks)
	# Each side casts from its own book; heroes[1] stays null for neutral armies.
	if _player_side == 1:
		new_state.heroes[0] = Game.enemy_hero
		new_state.heroes[1] = _player_hero_for_battle(standalone_fixture)
	else:
		new_state.heroes[0] = _player_hero_for_battle(standalone_fixture)
		new_state.heroes[1] = Game.enemy_hero
	_state = new_state

	var new_view := BattleView.new()
	add_child(new_view)
	var headless := DisplayServer.get_name() == "headless"
	new_view.instant = headless
	new_view.setup(stacks, Hex.ORIGIN, Hex.STEP)
	_view = new_view
	if _siege_view != null:
		_siege_view.instant = headless

	if _shots != null and _shots.aborts_probe():
		get_tree().quit(1)
		return

	var smoke = DevFlags.smoke() if get_tree().current_scene == self else null
	if smoke != null:
		await smoke.battle(self)
		return

	if _shots != null and await _shots.run(self):
		return

	# AI may attack a different local human during its phase. The battle is fully
	# built behind this opaque gate, so no defender army/spells flash onscreen
	# before the correct person takes the seat.
	if Game.game_mode == &"hotseat" and Game.hotseat_handoff_pending \
			and Game.state != null:
		var handoff := HotseatHandoff.new()
		add_child(handoff)
		var defender := Game.state.human()
		handoff.open(defender.side, defender.crest_idx, Game.state.day, true)
		await handoff.confirmed
		Game.hotseat_handoff_pending = false
		handoff.queue_free()
	await _start_battle_audio()
	await _battle_loop()

func _start_battle_audio() -> void:
	if _view == null or _view.audio == null or not _view.audio.enabled:
		return
	if _view.instant:
		return
	if _view.audio.has_prebattle_fanfare():
		_prebattle_player = _view.audio.play_prebattle_fanfare()
		if _prebattle_player != null:
			var max_wait := 5.0
			if _prebattle_player.stream != null:
				max_wait = _prebattle_player.stream.get_length() + 0.1
			var elapsed := 0.0
			while is_instance_valid(_prebattle_player) and _prebattle_player.playing \
					and not _prebattle_skipped and elapsed < max_wait:
				await get_tree().process_frame
				elapsed += get_process_delta_time()
			if is_instance_valid(_prebattle_player) and _prebattle_player.playing:
				_prebattle_player.stop()
			_prebattle_player = null

func _build_stacks() -> Array:
	if Game.player_army != null and Game.enemy_army != null:
		if _player_side == 1:
			return BattleSetup.build_stacks(Game.enemy_army, Game.player_army, false)
		return BattleSetup.build_stacks(Game.player_army, Game.enemy_army,
				Game.battle_kind == &"neutral")
	# standalone / tests: sample matchup
	var out: Array = []
	for e in ARMY:
		var s := BattleStack.new()
		if s.setup(e[0], e[1], e[2], Vector2i(e[3], e[4])):
			out.append(s)
	return out

## Directly launching battle.tscn uses the sample armies above. Give that
## fixture a fully stocked caster without changing heroes supplied by the game.
func _uses_standalone_fixture() -> bool:
	return Game.player_army == null or Game.enemy_army == null

func _player_hero_for_battle(standalone_fixture: bool) -> HeroModel:
	if Game.is_garrison_only_town_defense():
		return null
	if Game.player_hero != null:
		return Game.player_hero
	return _standalone_spell_hero() if standalone_fixture else null

func _standalone_spell_hero() -> HeroModel:
	var hero := HeroModel.sample()
	hero.has_spellbook = true
	hero.knowledge = STANDALONE_SPELL_CHARGES
	for spell: Dictionary in SpellData.all():
		hero.spellbook.learn(String(spell.id), STANDALONE_SPELL_CHARGES)
	return hero

## Seed targets for combat-spell smoke testing: the sample enemy army includes
## a Ghost for Kill Undead, while one friendly stack starts hurt and cursed so
## Resurrect, Cure, and Dispel have an immediate visible effect.
func _prepare_standalone_spell_targets(stacks: Array) -> void:
	for stack: BattleStack in stacks:
		if stack.side != _player_side or not stack.is_alive():
			continue
		stack.apply_damage(mini(stack.hp_max * 2, stack.total_hp() - 1))
		stack.apply_spell_effect("curse", STANDALONE_SPELL_CHARGES)
		return

## Terrain that paints the ground and horizon; a siege is always on the grass arena.
func _ground_terrain() -> String:
	return "grass" if _siege_defender_side >= 0 else _battle_terrain()

func _battle_terrain() -> String:
	var terrain: String = _shots.terrain() if _shots != null else ""
	if terrain != "":
		return terrain
	if Game.battle_terrain != "":
		return Game.battle_terrain
	return "grass"

# --- turn loop ------------------------------------------------------------

## Close the acting stack's turn after `action`. Any turn-ending action rolls
## for good morale: the original's sunbird roll (heroes.exe 0x8ab26) is reached
## from the move-and-strike case and the melee case of the combat action switch,
## and a plain move is the same move-and-strike case. Waiting never rolls.
func _close_turn(actor: BattleStack, action: Dictionary) -> bool:
	return _state.finish_action(actor, String(action.get("action", "")))

func _auto_resolve() -> void:
	var iters := 0
	while _state.winner() == -1 and iters < 4000:
		var actor := _state.active()
		if actor == null:
			break
		_fire_catapult_engine(actor)
		_fire_tower_engine(actor)
		if _state.winner() != -1:
			break
		if not actor.can_act() or _state.fails_morale(
				actor, not _uses_player_input(actor.side)):
			_state.end_turn(false)
			iters += 1
			continue
		# heroes.exe 0xc2181: a stack acting on its own never prompts a cast.
		var cast := {} if actor.has_effect("berserk") \
				else BattleAISpell.choose(_state, actor.side)
		if not cast.is_empty():
			SpellCast.cast(_state, actor.side, cast.spell_id, cast.target)
		if not actor.is_alive():
			_state.end_turn(false)
			iters += 1
			continue
		var action := BattleAI.choose(_state, actor)
		_apply_engine(actor, action)
		_close_turn(actor, action)
		iters += 1

func _battle_loop() -> void:
	while _state.winner() == -1:
		await _info_closed()
		var actor := _state.active()
		if actor == null:
			break
		await _fire_catapult(actor)
		await _fire_tower(actor)
		if _state.winner() != -1:
			break
		if not actor.can_act():
			_state.end_turn(false)   # blind/paralyzed: no full action
			continue
		if _state.fails_morale(actor, not _uses_player_input(actor.side)):
			_set_status(BattleTextScript.morale_freeze(actor.unit, actor.count))
			await _view.play_morale(actor, false)
			_state.end_turn(false)
			continue
		_set_active_glow(actor)
		var action := await _resolve_action(actor)
		await _perform(actor, action)
		if _state.winner() != -1:
			break
		if _close_turn(actor, action):
			_set_active_glow(null)
			_set_status(BattleTextScript.morale_bonus(actor.unit, actor.count))
			await _view.play_morale(actor, true)
	_set_active_glow(null)
	await _info_closed()
	_show_result()

## The creature window is modal in the original: combat stands still while
## it is open, so auto combat cannot end the battle underneath it.
func _info_closed() -> void:
	while _info_dialog != null:
		await (Engine.get_main_loop() as SceneTree).process_frame

func _fire_catapult_engine(actor: BattleStack) -> void:
	var ai := not _uses_player_input(_state.siege_defender_side)
	while actor.side == _state.siege_attacker_side() and _state.catapult_pending:
		if _state.catapult_action(ai).is_empty():
			break

func _fire_catapult(actor: BattleStack) -> void:
	var ai := not _uses_player_input(_state.siege_defender_side)
	while actor.side == _state.siege_attacker_side() and _state.catapult_pending:
		var shot := _state.catapult_action(ai)
		if shot.is_empty():
			return
		# heroes.exe prints nothing for a catapult shot (0x8b171 never calls
		# the status printer 0xc322f), so the status bar is left as it was.
		if _siege_view != null:
			await _siege_view.play_catapult(int(shot.row), int(shot.hp))

func _fire_tower_engine(actor: BattleStack) -> void:
	if actor.side == _state.siege_defender_side and _state.tower_pending:
		_state.tower_action()

func _fire_tower(actor: BattleStack) -> void:
	if actor.side == _state.siege_defender_side and _state.tower_pending:
		var shot := _state.tower_action()
		if shot.is_empty():
			return
		var target: BattleStack = shot.get("target")
		if target != null:
			_set_status(BattleTextScript.tower_report(target.unit,
					int(shot.get("damage", 0)), int(shot.get("killed", 0))))
			if _siege_view != null:
				await _siege_view.play_tower_shot(
						Hex.to_pixel(target.hex.x, target.hex.y, Hex.ORIGIN, Hex.STEP))
			if _view != null:
				await _view.play_losses(target, &"physical", int(shot.get("killed", 0)) > 0)

## Decide the active stack's action. Berserked stacks are forced into an attack;
## AI-controlled stacks use BattleAI; the player is asked, and a "spell" answer
## loops back to ask again (casting doesn't consume the stack's turn) until a
## real move/attack/skip comes back (or the battle ends mid-cast).
## AI-controlled stacks cast via BattleAISpell then act; under AUTO the player
## side is AI-driven too, including casting from the player's own book
## (authentic HOMM1 auto-combat — hitting AUTO hands your hero's spells to the AI).
func _resolve_action(actor: BattleStack) -> Dictionary:
	# Berserked (forced attack) stacks, and — via _battle_loop's can_act() skip —
	# blind/paralyzed stacks, never reach the AISpell cast below: they get no cast
	# window on this turn. In a multi-stack army the spell still gets cast, just
	# on a later stack's turn instead of this one's.
	if actor.has_effect("berserk"):
		return BattleAI.berserk_action(_state, actor)
	if not _uses_player_input(actor.side) or _auto:
		return await _resolve_ai_action(actor)
	var action := await _await_player(actor)
	# AUTO is handled before this stack takes its full action. This preserves the
	# active turn instead of treating the button click as a wait/skip command.
	if action.action == "auto":
		return await _resolve_ai_action(actor)
	while action.action == "spell":
		await _perform(actor, action)
		if _state.winner() != -1 or not actor.is_alive():
			return {"action": "pass"}
		# The turn goes on without the turn-start routine, so a spell's line
		# stays on the bar until the mouse moves (heroes.exe 0xc23f5).
		action = await _await_player(actor, false)
		if action.action == "auto":
			return await _resolve_ai_action(actor)
	# Defensive: every path that resolves a non-spell action should already
	# have cleared _pending_spell (see _cancel_pending_spell call sites), but
	# guard here too so a stale cast can never survive into the next turn.
	if not _pending_spell.is_empty():
		_cancel_pending_spell()
	return action

## Pick the computer's spell and troop action for either an enemy stack or the
## player's active stack after AUTO has been enabled.
func _resolve_ai_action(actor: BattleStack) -> Dictionary:
	var cast := BattleAISpell.choose(_state, actor.side)
	if not cast.is_empty():
		await _perform(actor, {"action": "spell", "spell_id": cast.spell_id, "target": cast.target})
		# A stack killed by its own area cast (meteor_shower/armageddon/fireball
		# via AUTO) must never reach BattleAI.choose below.
		if _state.winner() != -1 or not actor.is_alive():
			return {"action": "pass"}
	var action := BattleAI.choose(_state, actor)
	_set_status("Auto Combat" if _auto else BattleTextScript.ai_decision(actor, action))
	# play_move() correctly removes the contour at travel start. Hold the
	# decision pose first so an enemy mover's outline reaches the screen.
	if _view != null and not _view.instant:
		await get_tree().create_timer(AI_DECISION_HOLD_SECONDS).timeout
	return action

func _await_player(actor: BattleStack, clear_bar := true) -> Dictionary:
	_await_actor = actor
	if clear_bar:
		_set_status(_turn_prompt(actor))
	# Either a valid hex click or the SKIP button resolves this via _player_action.
	var a: Dictionary = await self._player_action
	_await_actor = null
	_set_cmbt_cursor(-1)
	return a

# --- general's options / withdrawal facades ------------------------------

func _player_has_battle_hero(side: int = -1) -> bool:
	return _withdrawal.player_has_battle_hero(side)

func _open_general_options(force_enable: bool = false) -> void:
	_withdrawal.open_general_options(force_enable)

func _open_general_options_for_side(tent_side: int, force_enable: bool = false) -> void:
	_withdrawal.open_general_options_for_side(tent_side, force_enable, _spell_flow.has_modal() or _info_dialog != null)

func _on_general_action(action: StringName) -> void:
	_withdrawal._on_general_action(action)

func _request_retreat(side: int = -1) -> void:
	_withdrawal.request_retreat(side)

func _open_retreat_dialog() -> void:
	_withdrawal.open_retreat_dialog()

func _confirm_retreat() -> void:
	_withdrawal.confirm_retreat()

func _request_surrender(side: int = -1) -> void:
	_withdrawal.request_surrender(side)

func _open_surrender_dialog(opponent: HeroModel, cost: int) -> void:
	_withdrawal.open_surrender_dialog(opponent, cost)

func _accept_surrender() -> void:
	_withdrawal.accept_surrender()

func _open_message_dialog(message: String) -> void:
	_withdrawal.open_message_dialog(message)

# --- spell casting facades -----------------------------------------------

func _on_cast(side: int = -1) -> void:
	_spell_flow.on_cast(side, _info_dialog != null)

func _open_spellbook(side: int = -1) -> void:
	_spell_flow.open_spellbook(side)

func _cancel_pending_spell() -> void:
	_spell_flow.cancel_pending_spell()
	if _await_actor != null:
		_set_status(_turn_prompt(_await_actor))
		if is_inside_tree():
			_update_combat_cursor()

func _handle_spell_click(hex: Vector2i) -> void:
	_spell_flow.handle_spell_click(hex)

func _spell_target_is_valid(hex: Vector2i) -> bool:
	return _spell_flow.spell_target_is_valid(hex)

func _spell_hover_status(hex: Vector2i, valid: bool) -> String:
	return _spell_flow.spell_hover_status(hex, valid)

func _perform_spell(actor: BattleStack, a: Dictionary) -> void:
	await _spell_flow.perform_spell(actor, a)

static func armageddon_drain(step: int) -> float:
	return BattleSpellFlow.armageddon_drain(step)

func _play_storm(hits: Array) -> void:
	await _spell_flow.play_storm(hits)

func _resisted_line(spell_id: String, res: Dictionary) -> String:
	return _spell_flow.resisted_line(spell_id, res)

func _play_spell_visual(spell: Dictionary, target: Variant) -> void:
	await _spell_flow.play_spell_visual(spell, target)

func _view_feet_of(stack: BattleStack) -> Vector2:
	return _spell_flow.view_feet_of(stack)

# --- combat action execution ---------------------------------------------

func _apply_engine(actor: BattleStack, a: Dictionary) -> void:
	match a.action:
		"move":
			_state.move(actor, a.dest)
		"shoot":
			_state.shoot(actor, a.target)
		"melee":
			_state.melee(actor, a.target)
		"move_melee":
			_state.move(actor, a.dest)
			_state.melee(actor, a.target)

func _perform(actor: BattleStack, a: Dictionary) -> void:
	match a.action:
		"move":
			var from: Vector2i = actor.hex
			var path := _state.movement_path(actor, a.dest)
			_state.move(actor, a.dest)
			await _view.play_move(actor, from, path)
		"shoot":
			await _shoot_anim(actor, a.target)
			# The elves' second arrow is a whole second shot with its own luck
			# roll, fired once the first has landed (heroes.exe 0x8eeab).
			if _state.shoots_again(actor, a.target):
				await _shoot_anim(actor, a.target)
		"melee":
			await _melee_anim(actor, a.target)
		"move_melee":
			var from2: Vector2i = actor.hex
			var path2 := _state.movement_path(actor, a.dest)
			_state.move(actor, a.dest)
			await _view.play_move(actor, from2, path2)
			await _melee_anim(actor, a.target)
		"spell":
			await _perform_spell(actor, a)
		"retreat":
			var withdrawer_side := actor.side
			var winner_side := 1 - withdrawer_side
			Game.last_battle_outcome = &"retreat"
			_state.force_winner(winner_side)
		"surrender":
			var withdrawer_side := actor.side
			var winner_side := 1 - withdrawer_side
			var cost := BattleOutcomeScript.surrender_cost(_state.stacks, withdrawer_side)
			var payer := Game.player_for_battle_side(withdrawer_side)
			var receiver := Game.player_for_battle_side(winner_side)
			if payer != null and payer.gold() >= cost:
				payer.add_resources({"gold": -cost})
				if receiver != null:
					receiver.add_resources({"gold": cost})
				Game.last_battle_outcome = &"surrender"
				_state.force_winner(winner_side)
		_:
			pass

## One arrow: resolved, then played, so the target's count drops with the arrow
## that killed. Luck is announced before the shot (0x907f2 runs first), and the
## shooter stands again once the arrow lands (0x8d9fd at 0x8ee51), so the elves'
## second luck roll plays over a standing stack.
func _shoot_anim(actor: BattleStack, target: BattleStack) -> void:
	var report := _state.shoot_once(actor, target)
	await _announce_luck(actor, actor.count, report)
	await _view.play_shoot(actor, target)
	_set_status(BattleTextScript.damage_report(actor.unit,
			int(report.get("attacker_count", actor.count)), target.unit, report))
	await _view.play_losses(target, actor.attack_effect, report.killed > 0)
	await _play_strike_ability(report, target, actor)
	_view.play_idle(actor)

func _melee_anim(attacker: BattleStack, defender: BattleStack) -> void:
	# Each strike resolves just before it plays, as heroes.exe's strike routine
	# 0x8f5c6 does: luck (0x907f2) ahead of the swing, then the damage, then
	# the next strike. The attacker holds its swing pose while the defender
	# plays its wince, then idles.
	var attacker_count := attacker.count
	var r := _state.melee_strike(attacker, defender)
	await _announce_luck(attacker, attacker_count, r.attack)
	await _view.play_attack(attacker, defender, true, not r.attack_splashes.is_empty())
	_set_status(_strike_status(attacker, attacker_count, defender, r.attack, r.attack_splashes))
	await _play_struck(attacker, defender, r.attack, r.attack_splashes)
	_view.play_idle(attacker)
	var rr := _state.melee_retaliation(attacker, defender, r)
	if not rr.retaliation.is_empty():
		await _cadence_pause()
		var retaliators := int(rr.retaliation.get("attacker_count", defender.count))
		await _announce_luck(defender, retaliators, rr.retaliation)
		await _view.play_attack(defender, attacker, true, not rr.retaliation_splashes.is_empty())
		_set_status(_strike_status(defender, retaliators, attacker, rr.retaliation,
				rr.retaliation_splashes))
		await _play_struck(defender, attacker, rr.retaliation, rr.retaliation_splashes)
		_view.play_idle(defender)
	var second := _state.melee_second_strike(attacker, defender)
	if not second.is_empty():
		await _cadence_pause()
		await _announce_luck(attacker, attacker.count, second)
		await _view.play_attack(attacker, defender, true, false)
		_set_status(BattleTextScript.damage_report(attacker.unit,
				int(second.get("attacker_count", attacker.count)),
				defender.unit, second))
		await _view.play_losses(defender, attacker.attack_effect, second.killed > 0)
		await _play_strike_ability(second, defender, attacker)
		_view.play_idle(attacker)
	if attacker.has_effect("berserk"):
		attacker.clear_effect()   # KB 5.2: berserk ends once the stack has attacked

func _cadence_pause() -> void:
	if _view != null and _view.instant:
		return
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return
	await loop.create_timer(RETALIATION_CADENCE).timeout

## The line for a strike and the stacks it also hit. A hydra prints one line
## for everything it bit, victims counted as creatures (heroes.exe 0x8eec3).
## A dragon's line names only the first stack and its kills, but its damage
## figure is the one from the second stack when there is one: 0x90a3b writes
## the second hit's damage over the first and only the kills are restored
## (0x8fbd7, 0x8fbf9).
func _strike_status(attacker: BattleStack, attacker_count: int, defender: BattleStack,
		report: Dictionary, splashes: Array) -> String:
	if attacker.attack_all_adjacent:
		var damage := int(report.get("damage", 0))
		var killed := int(report.get("killed", 0))
		for hit: Dictionary in splashes:
			damage += int(hit.attack.get("damage", 0))
			killed += int(hit.attack.get("killed", 0))
		return BattleTextScript.hydra_report(attacker.unit, attacker_count, damage, killed)
	if not splashes.is_empty() and String(report.get("ability", "")) != "genie_halving":
		var shown := report.duplicate()
		shown["damage"] = int(splashes[0].attack.get("damage", 0))
		return BattleTextScript.damage_report(attacker.unit, attacker_count,
				defender.unit, shown)
	return BattleTextScript.damage_report(attacker.unit, attacker_count,
			defender.unit, report)

## The struck stack and any splash victims react to one strike. heroes.exe
## runs every struck stack through one frame loop (0x90ded), so a hydra's
## bite and a dragon's two-hex line wince and die together.
func _play_struck(attacker: BattleStack, defender: BattleStack, report: Dictionary,
		splashes: Array) -> void:
	if splashes.is_empty():
		await _view.play_losses(defender, attacker.attack_effect, report.killed > 0)
		await _play_strike_ability(report, defender, attacker)
		return
	var hits: Array = [{"stack": defender, "splash": report.killed > 0}]
	for hit: Dictionary in splashes:
		hits.append({"stack": hit.target, "splash": hit.attack.killed > 0})
	await _view.play_losses_batch(hits, attacker.attack_effect)
	await _play_strike_ability(report, defender, attacker)
	for hit: Dictionary in splashes:
		await _play_strike_ability(hit.attack, hit.target, attacker)

## Luck gets its own status line, sound and animation before the swing
## (heroes.exe 0x907f2): the rainbow for good luck, the cloud for bad.
func _announce_luck(stack: BattleStack, count: int, report: Dictionary) -> void:
	var luck := int(report.get("luck", 0))
	if luck == 0:
		return
	_set_status(BattleTextScript.luck_line(stack.unit, count, luck > 0))
	await _view.play_luck(stack, luck > 0)

func _play_strike_ability(report: Dictionary, target: BattleStack,
		attacker: BattleStack = null) -> void:
	var ability := String(report.get("ability", ""))
	# Ghost growth mutates the attacking stack, while play_losses() refreshes
	# only the defender. Mirror the one-for-one increase on the battlefield as
	# soon as the killed creatures rise.
	if ability == "ghost_growth" and attacker != null:
		_view.refresh(attacker)
	if ability == "blind" or ability == "paralyze":
		await _play_spell_visual(SpellData.get_spell(ability), target)

# --- input + highlight ----------------------------------------------------

func _has_modal() -> bool:
	return (_withdrawal != null and _withdrawal.has_modal()) \
			or (_spell_flow != null and _spell_flow.has_modal()) \
			or _info_dialog != null

func _unhandled_input(event: InputEvent) -> void:
	if _prebattle_player != null and is_instance_valid(_prebattle_player) and _prebattle_player.playing:
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed and not event.echo):
			_prebattle_skipped = true
			_prebattle_player.stop()
			return

	# Battle dialogs are modal. Their full-screen controls normally consume
	# mouse input, but combat must enforce the lock too: a battlefield click
	# reaching this handler must never resolve the awaiting stack's action.
	if _has_modal():
		return
	if event is InputEventMouseMotion:
		_update_combat_cursor()
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if not _pending_spell.is_empty():
				_cancel_pending_spell()
				return
			var right_target := _state.stack_at(_hex_at(_pointer_world()))
			if right_target != null:
				_show_creature_info(right_target)
				return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _await_actor == null:
				return
			if not _pending_spell.is_empty():
				_handle_spell_click(_hex_at(_pointer_world()))
				return
			var mouse_pos := _pointer_world()
			var a := BattleInput.resolve(_state, _await_actor, _hex_at(mouse_pos), mouse_pos)
			if a.action != "invalid":
				emit_signal("_player_action", a)
			else:
				# Only the acting side's stacks open info on a left click; an
				# enemy out of reach does nothing (heroes.exe 0xc027b).
				var target := _state.stack_at(_hex_at(mouse_pos))
				if target != null and target.side == _await_actor.side:
					_show_creature_info(target)
			return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_A and (_await_actor != null or _auto):
			_on_auto()
		# Space is the combat loop's own skip (heroes.exe 0xbfad6); S is the
		# cmbtwin.bin hotkey of the SKIP button. Retreat and surrender keys
		# live only in the hero's General Options window, opened with H.
		elif event.keycode in [KEY_SPACE, KEY_S] and _await_actor != null:
			emit_signal("_player_action", {"action": "skip"})
		elif event.keycode == KEY_C and _await_actor != null:
			_on_cast()
		elif event.keycode == KEY_H and _await_actor != null:
			_open_general_options()
		elif event.keycode == KEY_T and _await_actor != null:
			_show_creature_info(_await_actor)
		elif event.keycode == KEY_ESCAPE and not _pending_spell.is_empty():
			_cancel_pending_spell()

func _show_creature_info(stack: BattleStack) -> void:
	if stack == null or _info_dialog != null:
		return
	_set_cmbt_cursor(-1)
	var dialog := CreatureInfoDialogScript.new()
	dialog.setup(
			stack,
			_state.morale_for(stack),
			_state.luck_for(stack),
			_state.attack_for(stack),
			_state.defense_for(stack))
	dialog.closed.connect(func():
		_info_dialog = null
		_update_combat_cursor())
	dialog.tree_exited.connect(func():
		if _info_dialog == dialog:
			_info_dialog = null
			_update_combat_cursor())
	_info_dialog = dialog
	add_child(dialog)

func _exit_tree() -> void:
	Game.set_default_cursor()

## Pointer in world space; a touch moves this, unlike the OS mouse position.
func _pointer_world() -> Vector2:
	return get_canvas_transform().affine_inverse() * Pointer.position(get_viewport())

## Pick the combat cursor for the hovered hex (only while awaiting a player command).
func _update_combat_cursor() -> void:
	if not is_inside_tree() or _await_actor == null or not _await_actor.is_alive():
		_set_cmbt_cursor(-1)
		return
	var mouse_pos := _pointer_world()
	if mouse_pos.y >= 480 - BAR_H:
		_set_cmbt_cursor(-1)   # AUTO / SKIP strip keeps the arrow
		return
	var hex := _hex_at(mouse_pos)
	if not _pending_spell.is_empty():
		var valid := _spell_target_is_valid(hex)
		if valid:
			_set_spell_cursor(_pending_spell)
		else:
			_set_cmbt_cursor(CUR_INVALID)
		_set_status(_spell_hover_status(hex, valid))
		return
	_set_cmbt_cursor(_cursor_for(_await_actor, hex, mouse_pos))
	var target := _state.stack_at(hex)
	var action := BattleInput.resolve(_state, _await_actor, hex, mouse_pos)
	var hint := BattleTextScript.hover_hint(
			_await_actor.unit, _await_actor.shots,
			target.unit if target != null else "", String(action.action),
			_await_actor.is_flying(),
			target == null or target.side == _await_actor.side,
			_await_actor.is_shooter() and _await_actor.shots <= 0)
	_set_status(hint if hint != "" else _turn_prompt(_await_actor))

## Cursor id for the action the active stack would take against `hex`.
func _cursor_for(actor: BattleStack, hex: Vector2i, mouse_pos: Vector2 = Vector2.INF) -> int:
	return BattleInput.cursor_for(_state, actor, hex, mouse_pos, Hex.ORIGIN, Hex.STEP)

## Directional attack-sword sprite pointing from the attack hex toward the target.
func _sword_for(from_hex: Vector2i, target_hex: Vector2i) -> int:
	return BattleInput.sword_for(from_hex, target_hex, Hex.ORIGIN, Hex.STEP)

func _set_cmbt_cursor(id: int) -> void:
	if id == _cur_id:
		return
	_cur_id = id
	if id < 0:
		Game.set_default_cursor()   # restore game pointer
		return
	var tex: Texture2D = _cmbt_cache.get(id)
	if tex == null:
		tex = UiKit.load_texture(CMBT % id)
		_cmbt_cache[id] = tex
	if tex == null:
		Game.set_default_cursor()
		return
	Game.set_cursor(tex, Vector2(tex.get_width(), tex.get_height()) * 0.5)

func _set_spell_cursor(spell_id: String) -> void:
	var spell := SpellData.get_spell(spell_id)
	if spell.is_empty():
		_set_cmbt_cursor(CUR_INVALID)
		return
	var icon_id := int(spell.get("icon", -1))
	var cursor_id := CUR_SPELL_BASE + icon_id
	if cursor_id == _cur_id:
		return
	_cur_id = cursor_id
	var tex: Texture2D = _spell_cursor_cache.get(icon_id)
	if tex == null:
		tex = UiKit.load_texture(SPELL_ICON % icon_id)
		_spell_cursor_cache[icon_id] = tex
	if tex == null:
		_set_cmbt_cursor(CUR_INVALID)
		return
	Game.set_cursor(
			tex, Vector2(tex.get_width(), tex.get_height()) * 0.5)

func _hex_at(world: Vector2) -> Vector2i:
	return BattleInput.hex_at(world, Hex.ORIGIN, Hex.STEP)

func _highlight_active() -> void:
	var actor := _state.active()
	_set_active_glow(actor)

## Mark the active stack with a yellow outline tracing its silhouette.
func _set_active_glow(actor: BattleStack) -> void:
	if _glow_stack != null:
		var prev := _view.node_for(_glow_stack)
		if not prev.is_empty():
			prev.creature.set_outline(false)
	_glow_stack = actor
	if actor == null:
		return
	var n := _view.node_for(actor)
	if not n.is_empty():
		n.creature.set_outline(true)

# --- result and casualties ------------------------------------------------

func _show_result() -> void:
	BattleOutcomeScript.write_survivors(_state.stacks, _player_side, Game.player_army)
	BattleOutcomeScript.write_survivors(_state.stacks, 1 - _player_side, Game.enemy_army)
	var won := _state.winner() == _player_side
	Game.last_winner = 0 if won else 1
	Game.last_battle_wipeout = _state.stacks.all(func(s): return not s.is_alive())
	if Game.last_battle_outcome.is_empty():
		Game.last_battle_outcome = &"victory" if won else &"defeat"
	Game.complete_battle_lifetimes()
	_show_result_screen(won)

## Build the result screen. xp < 0 = compute from battle state; an explicit
func _show_result_screen(won: bool, xp: int = -1) -> void:
	# A side without a hero gets the window's heroless lines (heroes.exe
	# 0xc1763, 0xc1b0f).
	var hero: HeroModel = _state.heroes[_player_side] as HeroModel \
			if _player_has_battle_hero(_player_side) else null
	if xp < 0:
		var enemy_withdrew: bool = Game.last_battle_outcome == &"retreat" or Game.last_battle_outcome == &"surrender"
		xp = _state.xp_for(_player_side, enemy_withdrew) if won and hero != null else 0
	Game.last_battle_xp = xp if won and hero != null else 0
	var res := BattleResult.new()
	add_child(res)
	res.setup(won, hero.hero_name if hero != null else "", xp, _casualties(),
			Game.last_battle_outcome, _captured_artifacts(won, hero),
			_result_levels(won, hero, xp))
	# Map-triggered fights return to the map (to consume the stack / capture the
	# mine); town-triggered fights fall back to the town. Always shown, win or
	# lose, so a loss can still be resolved (defeat check, army handoff, etc.).
	res.closed.connect(func(): Game.to_map() if Game.battle_return == "map" else Game.to_town())

## The beaten hero's artifacts the winner takes, for the result window's
## pages. Nothing is taken from a hero who retreated or surrendered (heroes.exe
## 0xc1487). The real transfer happens on the map; this only previews it.
func _captured_artifacts(won: bool, hero: HeroModel) -> Array:
	var outcome := Game.last_battle_outcome
	if not won or hero == null or outcome == &"retreat" or outcome == &"surrender":
		return []
	var loser := _state.heroes[1 - _player_side] as HeroModel
	if loser == null:
		return []
	return HeroModel.capturable_artifacts(hero, loser)

## Levels named in the victory line: only for a defender's win in a game with
## more than one human (heroes.exe 0xc16a7).
func _result_levels(won: bool, hero: HeroModel, xp: int) -> int:
	if not won or hero == null or xp <= 0 or _player_side != 1 or Game.state == null:
		return 0
	var humans := 0
	for p: PlayerState in Game.state.players:
		if not p.is_ai:
			humans += 1
	if humans <= 1:
		return 0
	var before := hero.level()
	hero.experience += xp
	var gained := hero.level() - before
	hero.experience -= xp
	return gained

## Per-side casualty lists for the result screen: one {unit, killed} entry per
## stack that lost creatures, sides indexed 0=attacker / 1=defender.
func _casualties() -> Array:
	var cas: Array = [[], []]
	if _state == null:
		return cas
	for s: BattleStack in _state.stacks:
		var killed: int = s.count_initial - s.count
		if killed > 0:
			cas[s.side].append({"unit": s.unit, "killed": killed})
	return cas

# --- tent + status bar -----------------------------------------------------

## Attacker's hero tent on the left edge. Its body/class letter and banner color
## come from crest_idx (color*4 + class); clicking the authentic tent replaces
## the non-original CAST icon that used to occupy the status bar.
func _draw_tent() -> void:
	var side0_crest := _player_crest() if _player_side == 0 else _enemy_crest()
	var side1_crest := _enemy_crest() if _player_side == 0 else _player_crest()
	# Both tents answer the player: the acting side's opens its General's
	# Options, the other shows the opposing general with every command greyed
	# (heroes.exe 0xbfe18, 0xc03d5).
	var watched := _uses_player_input(0) or _uses_player_input(1)
	if side0_crest >= 0:
		if watched:
			BattlefieldTentScript.paint(self, side0_crest, func(): _open_general_options_for_side(0), _on_tent_hover.bind(0), _on_tent_exit)
		else:
			BattlefieldTentScript.paint(self, side0_crest, Callable(), Callable(), Callable())
	if side1_crest >= 0:
		if watched:
			BattlefieldTentScript.paint_defender(self, side1_crest, func(): _open_general_options_for_side(1), _on_tent_hover.bind(1), _on_tent_exit)
		else:
			BattlefieldTentScript.paint_defender(self, side1_crest)

func _player_crest() -> int:
	if _shots != null and _shots.crests.has(&"player"):
		return _shots.crests[&"player"]
	if _state != null and _state.heroes[_player_side] == null:
		return -1
	if Game.is_garrison_only_town_defense():
		return -1
	if Game.player_hero != null:
		return Game.player_hero.crest_idx
	elif Game.state != null and not Game.state.players.is_empty():
		return Game.state.human().crest_idx
	return 0

func _enemy_crest() -> int:
	if _shots != null and _shots.crests.has(&"enemy"):
		return _shots.crests[&"enemy"]
	return Game.enemy_hero.crest_idx if Game.enemy_hero != null else -1

func _on_tent_hover(side: int = -1) -> void:
	_set_cmbt_cursor(CUR_GENERAL)
	_set_status(tent_hover_text(side))

## "General's Options" over the acting side's tent, "View Opposing General"
## over the other (heroes.exe 0xbfe18, 0xbfe4b, data 0x21354/0x21358).
func tent_hover_text(side: int) -> String:
	return BattleWithdrawal.tent_hover_text(side, _await_actor)

func _on_tent_exit() -> void:
	_set_cmbt_cursor(-1)
	_set_status(_turn_prompt(_await_actor) if _await_actor != null else "")

## Bottom control bar from textbar.icn: AUTO, the full 544px message strip, and
## SKIP. Hero actions live on the tent, matching the original.
func _draw_status_bar() -> void:
	var top := 480 - BAR_H
	# AUTO (left) + SKIP (right) — real button art with up/down states.
	# heroes.exe 0xbf746: the bar names the button under the mouse.
	add_child(_make_tex_button(1, 2, Vector2(0, top), _on_auto, "Auto Combat"))
	add_child(_make_tex_button(3, 4, Vector2(640 - 48, top), _on_skip, "Skip This Unit"))
	# Message bar fills the middle (48..592). Mirror the left half so its gold swirl
	# sits next to AUTO, normal half on the right next to SKIP.
	add_child(_make_bar_half(Vector2(48, top), true))
	add_child(_make_bar_half(Vector2(320, top), false))
	_status = Label.new()
	_status.text = ""
	_status.position = Vector2(48, top)
	_status.size = Vector2(640 - 48 - 48, BAR_H)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.z_index = 402
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.add_theme_color_override("font_color", Color.WHITE)
	var font := UiKit.font_normal()
	if font != null:
		_status.add_theme_font_override("font", font)
		_status.add_theme_font_size_override("font_size", font.fixed_size)
	add_child(_status)

func _make_bar_half(pos: Vector2, flip: bool) -> TextureRect:
	var tr := UiKit.texture_rect(TB % 0, pos, flip)
	tr.z_index = 400
	return tr

func _make_tex_button(up: int, down: int, pos: Vector2, cb: Callable,
		hover := "") -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = UiKit.load_texture(TB % up)
	b.texture_pressed = UiKit.load_texture(TB % down)
	b.position = pos
	b.z_index = 402
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	if hover != "":
		b.mouse_entered.connect(_set_status.bind(hover))
		b.mouse_exited.connect(_set_status.bind(""))
	return b

func _set_status(t: String) -> void:
	if _status != null:
		_status.text = t

func _turn_prompt(_actor: BattleStack) -> String:
	# Native HOMM1 leaves the strip empty until a command hover supplies a hint.
	return ""

## SKIP: the active player stack waits (no-op turn).
func _on_skip() -> void:
	if _await_actor != null:
		_cancel_pending_spell()
		emit_signal("_player_action", {"action": "skip"})

## AUTO: hand the rest of the battle to the AI for both sides. Pressing it
## again hands control back from the next player stack's turn on.
func _on_auto() -> void:
	if _auto:
		_auto = false
		return
	_auto = true
	_cancel_pending_spell()
	_set_status("Auto Combat")
	if _await_actor != null:
		emit_signal("_player_action", {"action": "auto"})

# --- field render ---------------------------------------------------------

func _draw_background() -> void:
	var bg_path := BattlefieldGroundScript.background_path(Game.battlefield_kind,
			_siege_defender_side >= 0, _ground_terrain())
	var tex := UiKit.load_texture(bg_path)
	if tex == null:
		return
	var bg := UiKit.add_texture(self, bg_path, Vector2.ZERO)
	bg.size = Vector2(640, 102)
	var fill := ColorRect.new()
	fill.color = Color(0.20, 0.32, 0.12)
	fill.position = Vector2(0, 102)
	fill.size = Vector2(640, 480 - 102)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fill)

func _draw_ground() -> void:
	if Game.battlefield_kind == &"ship":
		BattlefieldShipScript.paint(self, Hex.ORIGIN, Hex.STEP, BattlefieldShipScript.layout())
	else:
		BattlefieldGroundScript.paint(self, Hex.ORIGIN, Hex.STEP, _ground_terrain())
