class_name DefeatPresenter
extends RefCounted

## Handles hero defeat lifecycle, fade-out visuals and audio, roster portrait holding,
## and deferred post-battle defeat presentations.

var pending_defeat_visuals: Array[Dictionary] = []

func handle_player_hero_death(hero_selection: HeroSelection, hud: AdventureHud,
		audio: AdventureAudio, root_node: Node2D = null,
		set_active_hero_fn: Callable = Callable()) -> void:
	var live_effect_started := false
	var deferred_effect_queued := false

	if Game.state != null and not Game.state.players.is_empty():
		var human := Game.state.human()
		var active_model := human.active()
		var active_idx := human.active_hero
		var portrait_finished := Callable()

		if active_model != null and hud != null and hud.roster_panel != null:
			hud.roster_panel.hold_hero_models(human.heroes, active_idx)
			portrait_finished = func(): release_defeat_roster(hud)

		if active_idx >= 0 and active_idx < hero_selection.heroes.size():
			var h_node: Hero = hero_selection.heroes[active_idx]
			hero_selection.heroes.remove_at(active_idx)
			if is_instance_valid(h_node):
				play_hero_defeat(h_node, audio, portrait_finished, root_node)
				live_effect_started = true

		if not live_effect_started and active_model != null:
			deferred_effect_queued = queue_defeat_visual(active_model, human.side)

		if active_model != null:
			human.defeat_hero(active_model, Game.rng, Game.state.hero_pool if Game.state != null else null)

		if human.heroes.is_empty():
			if not human.owns_town:
				Game.pending_defeat = true
			Game.player_hero = null
			hero_selection.hero = null
		else:
			if set_active_hero_fn.is_valid():
				set_active_hero_fn.call(0)
	else:
		if is_instance_valid(hero_selection.hero):
			hero_selection.heroes.erase(hero_selection.hero)
			play_hero_defeat(hero_selection.hero, audio, Callable(), root_node)
			live_effect_started = true
			hero_selection.hero = null
			Game.player_hero = null
			Game.pending_defeat = true

	if not live_effect_started and not deferred_effect_queued and audio != null:
		audio.play_one_shot("res://assets/art/KILLFADE.wav")

func queue_defeat_visual(model: HeroModel, side: int) -> bool:
	if model == null:
		return false
	var tile := model.tile
	if tile == Vector2i(-1, -1):
		if Game.state != null and side == Game.state.active_player_side:
			tile = Game.hero_tile
		elif Game.state != null:
			var p := Game.state.player_of(side)
			if p != null and p.active() != null:
				tile = p.active().tile
	if tile == Vector2i(-1, -1):
		return false
	pending_defeat_visuals.append({
		"side": side,
		"hero_class": model.hero_class,
		"tile": tile,
		"crest_idx": model.crest_idx,
		"travel_mode": model.travel_mode,
		"carried_boat_id": model.carried_boat_id,
		"facing": model.facing,
		"roster_models": Game.state.human().heroes.duplicate() \
				if Game.state != null and side == Game.state.active_player_side else [],
		"roster_active": Game.state.human().active_hero \
				if Game.state != null and side == Game.state.active_player_side else -1,
	})
	return true

func hold_pending_defeat_roster(hud: AdventureHud) -> void:
	if hud == null or hud.roster_panel == null:
		return
	for visual: Dictionary in pending_defeat_visuals:
		if Game.state == null or int(visual.get("side", -1)) != Game.state.active_player_side:
			continue
		var models: Array = visual.get("roster_models", [])
		if not models.is_empty():
			hud.roster_panel.hold_hero_models(models, int(visual.get("roster_active", 0)))
		return

func release_defeat_roster(hud: AdventureHud) -> void:
	if hud != null and hud.roster_panel != null:
		hud.roster_panel.release_held_hero_models()

func play_pending_defeat_visuals(map_data: MapData, world: AdventureWorldRenderer,
		fog: FogLayer, audio: AdventureAudio, hud: AdventureHud,
		root_node: Node2D = null) -> void:
	var visuals := pending_defeat_visuals.duplicate(true)
	pending_defeat_visuals.clear()
	for visual: Dictionary in visuals:
		var node := Hero.new()
		if world != null:
			world.add_actor(node)
		elif root_node != null:
			root_node.add_child(node)
		var tile := Vector2i(visual.get("tile", Vector2i.ZERO))
		node.setup(String(visual.get("hero_class", "knight")), tile,
				map_data.tile_size, map_data, int(visual.get("crest_idx", 0)))
		node.set_travel_mode(StringName(visual.get("travel_mode", &"land")),
				int(visual.get("carried_boat_id", -1)))
		var facing := int(visual.get("facing", Direction.E))
		node.face_towards(tile + Direction.DELTAS.get(facing, Vector2i.RIGHT))
		var side := int(visual.get("side", 0))
		var is_local := Game.state != null and side == Game.state.active_player_side
		node.visible = is_local or fog == null or fog.is_explored(tile)
		var on_finished := (func(): release_defeat_roster(hud)) if is_local else Callable()
		play_hero_defeat(node, audio, on_finished, root_node)

func play_hero_defeat(hero: Hero, audio: AdventureAudio,
		finished_callback: Callable = Callable(),
		root_node: Node2D = null) -> float:
	var duration := Hero.DEFAULT_DISAPPEAR_TIME
	if audio != null:
		var cue_length := audio.play_one_shot(
				"res://assets/art/KILLFADE.wav", finished_callback)
		if cue_length > 0.0:
			duration = cue_length
	elif finished_callback.is_valid() and root_node != null and root_node.is_inside_tree():
		root_node.get_tree().create_timer(duration).timeout.connect(finished_callback)
	if is_instance_valid(hero):
		hero.disappear(duration)
	return duration

func on_ai_hero_defeated(hero: Hero, audio: AdventureAudio,
		root_node: Node2D = null) -> void:
	play_hero_defeat(hero, audio, Callable(), root_node)
