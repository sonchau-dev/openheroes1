class_name BattleSpellFlow
extends RefCounted

## Spell casting, spellbook UI, targeting, and combat spell visuals.

const BattleTextScript := preload("res://src/battle/battle_text.gd")
const SPELLBOOK_VIEW := "res://src/ui/spellbook_view.gd"
const ARMAGEDDON_FADE_SHADER := "res://src/battle/armageddon_fade.gdshader"
const ARMAGEDDON_STEPS := 32
const ARMAGEDDON_STEP_SECONDS := 1.0 / 12.0
const ARMAGEDDON_FADE_Z := 450

## Teleport plays two samples, sequentially. The cast executor (heroes.exe
## 0xc5a35) starts the spell bank as the stack disappears; the teleport case
## then rewrites the name to telein.82m (0xc5b54, string data 0x3150) and the
## common tail plays it (0xc6553) as the stack reappears. Each play goes
## through 0xd57c4, which loops until the sample ends, so the arrival sound
## never overlaps the disappearance sound.
const TELEPORT_ARRIVAL_SOUND := "TELEIN"

## Native loss/death bank for every damaging spell. These names are separate
## from each spell's cast animation: the struck creature still winces beneath
## the corresponding damage effect.
const SPELL_HIT_EFFECTS := {
	"fireball": &"redfire",
	"lightning_bolt": &"redfire",
	# Display name: Storm. Gold bursts on every stack in the 2026-09-24 Arena
	# Spells recording, which is the electric bank, not elecfire's flames.
	"meteor_shower": &"electric",
	"armageddon": &"redfire",
	"starfall": &"physical",      # Display name: Meteor Shower.
}

## Okay boxes from heroes.exe's battle (data 0x2dd7, 0x2dfa, 0x2e46).
const NO_HERO_TO_CAST := "You have no hero to cast a spell."
const ALREADY_CAST := "You have already cast a spell this round."
const NO_SPELLS_TO_CAST := "No spells to cast."

signal action_requested(action: Dictionary)
signal status_changed(text: String)
signal cursor_changed(id: int)
signal dialog_closed()

var host: Node2D = null
var state: BattleState = null
var view: BattleView = null
var withdrawal: BattleWithdrawal = null
var command_side_getter: Callable
var uses_player_input_checker: Callable
var auto_checker: Callable
var await_actor_getter: Callable

var pending_spell: String = ""          # spell id awaiting a target click, or "" (none)
var pending_spell_stack: BattleStack = null  # teleport stage 1: the stack being moved
var spellbook_view: Node = null

func setup(p_host: Node2D, p_state: BattleState, p_view: BattleView, p_withdrawal: BattleWithdrawal,
		p_command_side: Callable, p_uses_player_input: Callable, p_auto: Callable, p_await_actor: Callable) -> void:
	host = p_host
	state = p_state
	view = p_view
	withdrawal = p_withdrawal
	command_side_getter = p_command_side
	uses_player_input_checker = p_uses_player_input
	auto_checker = p_auto
	await_actor_getter = p_await_actor

func is_casting() -> bool:
	return not pending_spell.is_empty()

func has_modal() -> bool:
	return spellbook_view != null

## CAST button / hotkey (heroes.exe 0xbf9c9): each refusal is an Okay box.
## A hero without a book has no castable spells, so it gets "No spells to
## cast." (0x7dd26).
func on_cast(side: int = -1, other_modal: bool = false) -> void:
	if spellbook_view != null or other_modal or (withdrawal != null and withdrawal.has_modal()):
		return
	if _get_await_actor() == null:
		return
	if side < 0:
		side = _get_command_side()
	var hero: HeroModel = state.heroes[side] if state != null else null
	if hero == null:
		_open_message(NO_HERO_TO_CAST)
		return
	if state.cast_used[side]:
		_open_message(ALREADY_CAST)
		return
	if not hero.has_spellbook or hero.spellbook == null \
			or hero.spellbook.battle_spells().is_empty():
		_open_message(NO_SPELLS_TO_CAST)
		return
	open_spellbook(side)

func _open_message(msg: String) -> void:
	if withdrawal != null:
		withdrawal.open_message_dialog(msg)

## Load the spellbook dynamically and wire its public signals by name.
func open_spellbook(side: int = -1) -> void:
	if not ResourceLoader.exists(SPELLBOOK_VIEW):
		return
	cursor_changed.emit(-1)
	var sb_view = load(SPELLBOOK_VIEW).new()
	if host != null:
		host.add_child(sb_view)
	spellbook_view = sb_view
	if sb_view.has_signal("spell_picked"):
		sb_view.spell_picked.connect(on_spell_picked)
	if sb_view.has_signal("closed"):
		sb_view.closed.connect(close_spellbook)
	if sb_view.has_signal("status_changed"):
		sb_view.status_changed.connect(func(t: String): status_changed.emit(t))
	if sb_view.has_method("open"):
		var actual_side := side if side >= 0 else _get_command_side()
		var hero: HeroModel = state.heroes[actual_side] if state != null else null
		if hero != null and hero.spellbook != null:
			sb_view.open(hero.spellbook, "battle")

func close_spellbook() -> void:
	if spellbook_view != null:
		spellbook_view.queue_free()
		spellbook_view = null
	dialog_closed.emit()

## A spell was picked in the book: enter targeting, or fire immediately for
## spells with no click-target (all_stacks/none, e.g. Meteor Shower, Dispel).
func on_spell_picked(spell_id: String) -> void:
	close_spellbook()
	var spell := SpellData.get_spell(spell_id)
	if spell.is_empty():
		return
	pending_spell = spell_id
	pending_spell_stack = null
	match String(spell.get("target", "")):
		"all_stacks", "none":
			fire_pending_spell(null)
		_:
			status_changed.emit(BattleTextScript.spell_target_prompt())
			dialog_closed.emit()

## Shared spell-targeting cancel: clears pending-cast state so it can't leak
## into the next actor's turn. Called from ESC / right-click, and from the
## SKIP / AUTO buttons (bailing out of "choose a target" must not leave the
## next stack's first click interpreted as a spell-target pick).
func cancel_pending_spell() -> void:
	pending_spell = ""
	pending_spell_stack = null
	dialog_closed.emit()

func fire_pending_spell(target) -> void:
	var id := pending_spell
	pending_spell = ""
	pending_spell_stack = null
	action_requested.emit({"action": "spell", "spell_id": id, "target": target})

## Translate a battlefield click into a target while `pending_spell` is set.
## Teleport is two-stage (own stack, then destination); everything else fires
## on the first valid click. An invalid click leaves targeting mode active.
func handle_spell_click(hex: Vector2i) -> void:
	var spell := SpellData.get_spell(pending_spell)
	var side := _get_command_side()
	if spell.is_empty():
		cancel_pending_spell()
		return
	if String(spell.get("kind", "")) == "teleport":
		if pending_spell_stack == null:
			var s := state.stack_at(hex)
			if s in SpellCast.valid_targets(state, side, pending_spell):
				pending_spell_stack = s
				status_changed.emit(BattleTextScript.TELEPORT_PROMPT)
			return
		var teleport_target := {"stack": pending_spell_stack, "dest": hex}
		if SpellCast.target_is_valid(state, side, pending_spell, teleport_target):
			fire_pending_spell(teleport_target)
		return
	var target = spell_target_from_click(hex)
	if target == null and not (String(spell.get("target", "")) in ["all_stacks", "none"]):
		return   # invalid pick — stay in targeting
	fire_pending_spell(target)

func spell_target_from_click(hex: Vector2i):
	var spell := SpellData.get_spell(pending_spell)
	var side := _get_command_side()
	match String(spell.get("target", "")):
		"cell_area":
			return hex if SpellCast.target_is_valid(
					state, side, pending_spell, hex) else null
		"all_stacks", "none":
			return null
		_:
			var s := state.stack_at(hex)
			return s if SpellCast.target_is_valid(
					state, side, pending_spell, s) else null

## Legal hover target for the current stage of a pending spell.
func spell_target_is_valid(hex: Vector2i) -> bool:
	var spell := SpellData.get_spell(pending_spell)
	var side := _get_command_side()
	if spell.is_empty():
		return false
	if String(spell.get("kind", "")) == "teleport":
		if pending_spell_stack == null:
			return state.stack_at(hex) in SpellCast.valid_targets(
					state, side, pending_spell)
		return SpellCast.target_is_valid(state, side, pending_spell,
				{"stack": pending_spell_stack, "dest": hex})
	return spell_target_from_click(hex) != null

## DOS bar text while aiming: "Cast Turn Undead on ghost" over a legal target,
## "Teleport Here" or "Invalid Teleport Destination" once a stack is picked for
## Teleport, and the stage's prompt otherwise.
func spell_hover_status(hex: Vector2i, valid: bool) -> String:
	var spell := SpellData.get_spell(pending_spell)
	if String(spell.get("kind", "")) == "teleport" and pending_spell_stack != null:
		return BattleTextScript.TELEPORT_HERE if valid else BattleTextScript.TELEPORT_INVALID
	if not valid:
		return BattleTextScript.TELEPORT_PROMPT if pending_spell_stack != null \
				else BattleTextScript.spell_target_prompt()
	var target := state.stack_at(hex)
	var on_stack := target != null and String(spell.get("target", "")) != "cell_area"
	return BattleTextScript.spell_target_hover(spell, target.unit if on_stack else "")

## Resolve and animate a cast. Does NOT consume the actor's turn — the caller
## (_resolve_action) re-awaits the same actor for its real action afterward.
func perform_spell(actor: BattleStack, a: Dictionary) -> void:
	var res: Dictionary = SpellCast.cast(state, actor.side, a.spell_id, a.target)
	if res.ok:
		var spell := SpellData.get_spell(a.spell_id)
		var resisted := resisted_line(String(a.spell_id), res)
		if resisted != "":
			# heroes.exe 0xc5968: RSBRYFZL and the line, and no spell effect.
			status_changed.emit(resisted)
			if host != null and host.is_inside_tree() and view != null and view.audio != null:
				view.audio.play_one_shot("res://assets/art/RSBRYFZL.wav")
			return
		# A human cast starts from a cleared bar (heroes.exe 0xc2391); a
		# computer's cast that prints nothing leaves the bar as it was.
		var line := BattleTextScript.spell_result(String(a.spell_id), spell, res.hits)
		if line != "" or (_uses_player_input(actor.side) and not _is_auto()):
			status_changed.emit(line)
		var cast_voice := play_spell_sound(spell)
		if String(a.spell_id) == "armageddon":
			await play_armageddon(res.hits)
			return
		if String(a.spell_id) == "meteor_shower":
			await play_storm(res.hits)
			return
		if String(a.spell_id) == "teleport":
			await play_teleport_arrival(spell, res.hits, cast_voice)
			return
		if String(spell.get("target", "")) == "cell_area":
			if a.target is Vector2i:
				await play_spell_visual(spell, a.target)
			if view != null and not res.hits.is_empty():
				var hit_effect: StringName = SPELL_HIT_EFFECTS.get(
						String(a.spell_id), &"physical")
				await view.play_losses_batch(res.hits, hit_effect)
			return
		# heroes.exe 0xc6643: Dispel and Cure play on every stack they clear at
		# the same moment (DOS recording 2.mov).
		if String(spell.get("kind", "")) in ["dispel", "cure"]:
			await play_spell_visuals_together(spell, res.hits.map(func(h): return h.stack))
			for hit: Dictionary in res.hits:
				if view != null:
					view.refresh(hit.stack)
			return
		for hit: Dictionary in res.hits:
			await play_spell_visual(spell, hit.stack)
			if hit.damage > 0 or hit.killed > 0:
				var hit_effect: StringName = SPELL_HIT_EFFECTS.get(
						String(a.spell_id), &"physical")
				if view != null:
					await view.play_losses(hit.stack, hit_effect, hit.killed > 0)
			else:
				if view != null:
					view.refresh(hit.stack)
	# A refused pick does nothing (heroes.exe 0xc51cb).

## Native Armageddon is one battlefield event: the whole screen drains to red,
## every affected stack burns and reacts together at the darkest step, and the
## palette comes back at once.
func play_armageddon(hits: Array) -> void:
	if view != null and view.instant:
		await view.play_losses_batch(hits, SPELL_HIT_EFFECTS["armageddon"])
		return
	var fade := make_armageddon_fade()
	if host != null:
		host.add_child(fade)
	if view != null:
		view.set_tags_hidden(true)
	var mat := fade.material as ShaderMaterial
	for step in range(1, ARMAGEDDON_STEPS + 1):
		mat.set_shader_parameter("drain", armageddon_drain(step))
		if host != null and host.is_inside_tree():
			await host.get_tree().create_timer(ARMAGEDDON_STEP_SECONDS).timeout
	if view != null:
		await view.play_losses_batch(hits, SPELL_HIT_EFFECTS["armageddon"])
	fade.queue_free()
	if view != null:
		view.set_tags_hidden(false)

## Green and blue lost after `step` of the 32 drain steps, as a colour fraction.
static func armageddon_drain(step: int) -> float:
	return float(clampi(step, 0, ARMAGEDDON_STEPS) * 4) / 255.0

## Native Storm (meteor_shower in rules tables) tiles storm.icn over the 640x448
## arena for the duration of the storm, then all struck stacks receive the
## electric burst damage reaction together at the end.
func play_storm(hits: Array) -> void:
	if view != null and view.instant:
		await view.play_losses_batch(hits, SPELL_HIT_EFFECTS["meteor_shower"])
		return
	var overlay := StormRainOverlay.new()
	if host != null:
		host.add_child(overlay)
	overlay.play()
	await overlay.finished
	if is_instance_valid(overlay):
		overlay.queue_free()
	if view != null:
		await view.play_losses_batch(hits, SPELL_HIT_EFFECTS["meteor_shower"])

func make_armageddon_fade() -> ColorRect:
	var fade := ColorRect.new()
	fade.name = "ArmageddonFade"
	fade.position = Vector2.ZERO
	fade.size = Vector2(640, 480)
	fade.z_index = ARMAGEDDON_FADE_Z
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load(ARMAGEDDON_FADE_SHADER)
	mat.set_shader_parameter("drain", 0.0)
	fade.material = mat
	return fade

## The Dragon or Dwarf line for a single-target spell that was shrugged off.
func resisted_line(spell_id: String, res: Dictionary) -> String:
	if not res.hits.is_empty() or res.resisted.size() != 1:
		return ""
	return BattleTextScript.spell_resisted(spell_id, (res.resisted[0] as BattleStack).unit)

func play_spell_sound(spell: Dictionary) -> AudioStreamPlayer:
	if host == null or not host.is_inside_tree() or view == null or view.audio == null:
		return null
	return view.audio.play_spell(spell)

## Teleport: heroes.exe 0xc5a35 starts the spell bank (SPELL02) and plays the
## departure streaks as the stack disappears; the teleport case then switches
## the sample to telein.82m (0xc5b54) and plays arrival streaks at the
## destination as the stack reappears. Both plays wait for their audio sample.
func play_teleport_arrival(spell: Dictionary, hits: Array,
		cast_voice: Variant = null) -> void:
	for hit: Dictionary in hits:
		var st: BattleStack = hit.stack
		var from_hex: Vector2i = hit.get("from_hex", st.hex)
		var dest_hex: Vector2i = hit.get("dest_hex", st.hex)

		# Keep logical hex at from_hex during departure so status icon stays aligned.
		st.hex = from_hex
		var from_pos: Vector2 = view.effect_anchor_for_hex(st, from_hex) if view != null \
				else Hex.to_pixel(from_hex.x, from_hex.y, Hex.ORIGIN, Hex.STEP)
		var dest_pos: Vector2 = view.effect_anchor_for_hex(st, dest_hex) if view != null \
				else Hex.to_pixel(dest_hex.x, dest_hex.y, Hex.ORIGIN, Hex.STEP)

		# Disappearance stage: streaks play on departing stack, stack hides, sample blocks.
		await play_spell_visual(spell, from_pos, from_hex.y)
		if view != null:
			view.set_stack_hidden(st, true)
		await _await_voice(cast_voice)

		# Commit destination hex and unhide at arrival cell.
		st.hex = dest_hex
		var arrival_voice := play_spell_sound_name(TELEPORT_ARRIVAL_SOUND)
		if view != null:
			view.refresh(st)
			view.set_stack_hidden(st, false)
		await play_spell_visual(spell, dest_pos, dest_hex.y)
		await _await_voice(arrival_voice)

func play_spell_sound_name(sound: String) -> AudioStreamPlayer:
	if host == null or not host.is_inside_tree() or view == null or view.audio == null:
		return null
	return view.audio.play_spell(sound)

## heroes.exe 0xd57c4 pumps the cast animation until the sample stops, so the
## caller advances only after the voice finishes. Headless runs are instant
## and have no audible voice to wait for. Untyped: a voice that already ended
## has freed itself, and a freed object fails a typed parameter.
func _await_voice(voice: Variant = null) -> void:
	if view != null and view.instant:
		return
	if is_instance_valid(voice) and (voice as AudioStreamPlayer).playing:
		await voice.finished

func play_spell_visual(spell: Dictionary, target: Variant, hex_y_override: int = -1) -> void:
	if view != null and view.instant:
		return
	var anim := String(spell.get("anim", ""))
	if anim.is_empty():
		return
	var pos: Vector2
	var hex_y: int = 0
	if target is BattleStack:
		pos = view_feet_of(target)
		hex_y = target.hex.y
	elif target is Vector2i:
		pos = Hex.to_pixel(target.x, target.y, Hex.ORIGIN, Hex.STEP)
		hex_y = target.y
	elif target is Vector2:
		pos = target
		hex_y = hex_y_override if hex_y_override >= 0 else clampi(
				int((pos.y - Hex.ORIGIN.y) / Hex.STEP.y), 0, Hex.ROWS - 1)
	else:
		return
	# heroes.exe 0xc6fbb: Meteor Shower draws each frame on the aimed cell and
	# all six neighbours at once (DOS recording 7.mov shows debris over all 7).
	if target is Vector2i and String(spell.get("anim_cells", "")) == "area":
		var cells: Array = [target]
		for n: Vector2i in Hex.neighbors(target.x, target.y):
			if Hex.in_bounds(n.x, n.y):
				cells.append(n)
		var pending := {"left": cells.size()}
		for c: Vector2i in cells:
			var e := spawn_spell_effect(spell, Hex.to_pixel(c.x, c.y, Hex.ORIGIN, Hex.STEP), c.y)
			if e.is_queued_for_deletion():   # no frames: already finished
				pending.left -= 1
			else:
				e.finished.connect(func() -> void: pending.left -= 1)
		while pending.left > 0:
			if host != null and host.is_inside_tree():
				await host.get_tree().process_frame
			else:
				break
		return
	var eff := spawn_spell_effect(spell, pos, hex_y)
	# heroes.exe 0xc6223 (Curse), 0xc6288 (Berzerker), 0xc62e6 (Paralyze): the
	# target is put in its wince pose between the bank's two passes and held
	# until the cast ends. Blind, Slow, Haste and the buffs never wince.
	var winced := false
	if bool(spell.get("anim_wince", false)) and target is BattleStack and view != null:
		winced = true
		eff.pass_started.connect(func(_i: int) -> void: view.hold_wince(target))
	if is_instance_valid(eff) and not eff.is_queued_for_deletion():   # no frames: already finished
		await eff.finished
	if winced and view != null:
		view.play_idle(target)

func spawn_spell_effect(spell: Dictionary, pos: Vector2, hex_y: int) -> Effect:
	var eff := Effect.new()
	if host != null:
		host.add_child(eff)
	eff.z_index = 250 + hex_y
	eff.mirror = bool(spell.get("anim_mirror", false))
	eff.play(pos, StringName(String(spell.get("anim", ""))), int(spell.get("anim_passes", 1)))
	return eff

## Start the spell's cast animation on every stack at once and return when
## the last one ends.
func play_spell_visuals_together(spell: Dictionary, stacks: Array) -> void:
	if stacks.is_empty() or (view != null and view.instant):
		return
	var pending := {"left": stacks.size()}
	var done := func() -> void:
		pending.left -= 1
	for stack: BattleStack in stacks:
		run_visual(spell, stack, done)   # not awaited: all run at once
	while pending.left > 0:
		if host != null and host.is_inside_tree():
			await host.get_tree().process_frame
		else:
			break

func run_visual(spell: Dictionary, stack: BattleStack, done: Callable) -> void:
	await play_spell_visual(spell, stack)
	done.call()

func view_feet_of(stack: BattleStack) -> Vector2:
	if view != null and not view.node_for(stack).is_empty():
		return view.effect_anchor(stack)
	return Hex.to_pixel(stack.hex.x, stack.hex.y, Hex.ORIGIN, Hex.STEP)

func _get_command_side() -> int:
	return command_side_getter.call() if command_side_getter.is_valid() else 0

func _uses_player_input(side: int) -> bool:
	return uses_player_input_checker.call(side) if uses_player_input_checker.is_valid() else false

func _is_auto() -> bool:
	return auto_checker.call() if auto_checker.is_valid() else false

func _get_await_actor() -> BattleStack:
	return await_actor_getter.call() if await_actor_getter.is_valid() else null
