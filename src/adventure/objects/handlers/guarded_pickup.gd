extends RefCounted
## GuardedPickup handler: battle-then-banded-reward.
## First visit rolls ONE outcome band (weighted by each band's `p` via the seeded
## Game.rng) and returns start_battle = that band's guard army. The reward is NOT
## applied here — InteractionResolver.resolve_post_battle() re-reads the same
## rolled band's reward and applies it on victory (via GuardedPickup.apply_reward),
## so a battle the player loses grants nothing. A looted site is inert (no battle);
## guarded types may surface a post-loot message via params, default no-op.

func visit(obj: MapObject, ctx: VisitContext) -> VisitResult:
	var gp := obj as GuardedPickup
	var r := VisitResult.new()
	if gp == null:
		return r
	if GuardedPickup.ENTRY_PROMPTS.has(gp.type):
		if not gp.entry_confirmed:
			var entry: Dictionary = GuardedPickup.ENTRY_PROMPTS[gp.type]
			r.source_object = gp
			r.choice = {
				"type": "event_enter",
				"title": String(entry["title"]),
				"prompt": String(entry["prompt"]),
				"object": gp,
				"options": [
					{"label": "Yes", "confirm_entry": true},
					{"label": "No"},
				],
			}
			return r
		gp.entry_confirmed = false
	if gp.looted:
		if gp.type == "demon_cave":
			r.message = GuardedPickup.DEMON_CAVE_EMPTY_MESSAGE
			r.show_dialog = true
			return r
		# Post-loot revisit. Default: inert (no battle, no effect). A guarded type
		# may declare a data-driven `looted_effect` in params so future guarded
		# sites reuse this seam without a bespoke branch. The Graveyard sets {morale: -1, message} — revisiting a plundered
		# graveyard saps the army's morale (HOMM1) until its next battle.
		# Never a battle.
		var eff: Variant = gp.params.get("looted_effect", null)
		if eff is Dictionary:
			var ed: Dictionary = eff
			var dm := int(ed.get("morale", 0))
			if dm != 0 and _hero_flags_clear(ctx.hero_model):
				var tag := ""
				match gp.type:
					"graveyard": tag = "Graveyard robber -1"
					"shipwreck": tag = "Shipwreck robber -1"
					_: tag = "%s robber %d" % [gp.type.capitalize(), dm]
				ctx.hero_model.add_temporary_morale_modifier(tag, dm)
			var msg := String(ed.get("message", ""))
			if msg != "":
				r.message = msg
				r.show_dialog = true
		return r
	# The original Daemon Cave always asks permission before rolling its one-time
	# result. Declining neither rolls nor loots it; accepting is consumed by the
	# resolver as an immediate second visit with entry_confirmed=true.
	if gp.type == "demon_cave" and not gp.entry_confirmed:
		r.source_object = gp
		r.choice = {
			"type": "demon_cave_enter",
			"title": GuardedPickup.DEMON_CAVE_TITLE,
			"prompt": GuardedPickup.DEMON_CAVE_ENTER_MESSAGE,
			"object": gp,
			"options": [
				{"label": "Yes", "enter_demon_cave": true},
				{"label": "No"},
			],
		}
		return r
	if gp.type == "demon_cave":
		gp.entry_confirmed = false
	if gp.rolled_band < 0:
		gp.rolled_band = GuardedPickup.roll_band(gp.outcomes, Game.rng)
	var band: Dictionary = gp.outcomes[gp.rolled_band] if gp.rolled_band >= 0 and gp.rolled_band < gp.outcomes.size() else {}
	if band.has("ransom"):
		# Demon Cave RANSOM band (no fight, no plain reward): the hero is
		# captured and the demon demands `ransom` gold; refusing destroys the
		# hero. heroes.exe 0xb410a never clears the cell's byte 9 here, so the
		# cave stays a trap for every later visitor. The pay/destroy_hero side
		# effects land in InteractionResolver.apply_choice.
		var ransom := int(band.get("ransom", 0))
		var player: PlayerState = Game.state.player_of(ctx.player_side) if Game.state != null else null
		var options: Array = []
		# Only offer to pay when the kingdom can actually afford it — a broke
		# captured hero can only be destroyed (authentic HOMM1 ruling).
		if player != null and player.gold() >= ransom:
			options = [
				{"label": "Yes", "pay": ransom},
				{"label": "No", "destroy_hero": true},
			]
			r.choice = {
				"type": "demon_cave_ransom",
				"title": GuardedPickup.DEMON_CAVE_TITLE,
				"prompt": GuardedPickup.DEMON_CAVE_RANSOM_MESSAGE,
				"object": gp,
				"options": options,
			}
		else:
			# The original does not show a meaningless one-option "Refuse" prompt
			# when the kingdom cannot pay. It states the fatal outcome, then the
			# native Okay button closes the event and destroys the hero.
			r.choice = {
				"type": "demon_cave_death",
				"title": GuardedPickup.DEMON_CAVE_TITLE,
				"prompt": GuardedPickup.DEMON_CAVE_BROKE_MESSAGE,
				"object": gp,
				"options": [{"label": "Okay", "destroy_hero": true}],
			}
		r.source_object = gp
		return r
	var guard := gp.guard_army()
	if guard.is_empty():
		# "Reward with no fight" band (Demon Cave victory bands or future direct grants):
		# apply the band's reward NOW via the shared seam and stay battle-free.
		var player: PlayerState = Game.state.player_of(ctx.player_side) if Game.state != null else null
		GuardedPickup.apply_reward(gp, gp.rolled_band, player, ctx.hero_model, Game.rng)
		r.source_object = gp
		if gp.type == "demon_cave":
			r.message = GuardedPickup.demon_cave_victory_message(gp.rolled_band)
			r.show_dialog = true
		return r
	r.start_battle = guard
	return r

## heroes.exe lowers morale only when the hero's whole flag word (+0xae) is
## zero (0xb429c, 0xb4391). The word holds the robber bits themselves, every
## pending buoy/oasis/statue/fountain/faerie-ring bonus and the boat bit 0x80,
## so a repeat search, a hero with any of those bonuses, or a sailing hero at
## a Shipwreck loses nothing. Battle clears the visit bits (0xb2146).
static func _hero_flags_clear(hero: HeroModel) -> bool:
	return hero != null and hero.travel_mode != &"sea" \
			and hero.temporary_morale == 0 and hero.temporary_luck == 0 \
			and hero.temporary_morale_modifiers.is_empty() \
			and hero.temporary_luck_modifiers.is_empty()
