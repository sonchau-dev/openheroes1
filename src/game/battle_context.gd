class_name BattleContext
extends RefCounted

## Context, pending parameters, and resolution state for battles and sieges.

var _game: Node = null

const BATTLE_SCENE := "res://src/battle/battle.tscn"

var battle_kind: StringName = &"hero"
var battlefield_kind: StringName = &"land"
var battle_terrain: String = "grass"
var battle_opponent_is_human: bool = false
var battle_opponent_world_side: int = -1
var last_winner: int = -1
var last_battle_xp: int = 0
var last_battle_outcome: StringName = &""
var last_battle_wipeout: bool = false
var pending_object_id: int = -1
var pending_followup_object_id: int = -1
var battle_return: String = "town"

var pending_ai_battle: bool = false
## Seconds the battle screen is held back before it replaces the current
## scene. The hero-vs-hero engage sets it so the turn to face the opponent is
## on screen first (see Hero.ENGAGE_FACE_DELAY).
var battle_scene_hold: float = 0.0
var pending_ai_side: int = -1
var ai_turn_cursor: int = 0
var pending_town_battle_side: int = -1
var pending_town_battle_id: int = -1
var pending_town_faction: int = 0
var pending_town_has_castle: bool = false
var pending_town_hero_defense: bool = false
var pending_day_advance: bool = false
var pending_defeat: bool = false
var pending_defeat_message: String = ""
var saved_player_army: ArmyData = null

func _init(game_node: Node = null) -> void:
	_game = game_node

var game: Node:
	get:
		return _game if _game != null else Engine.get_main_loop().root.get_node_or_null("Game")

func reset() -> void:
	battle_kind = &"hero"
	battlefield_kind = &"land"
	battle_terrain = "grass"
	battle_opponent_is_human = false
	battle_opponent_world_side = -1
	last_winner = -1
	last_battle_xp = 0
	last_battle_outcome = &""
	last_battle_wipeout = false
	pending_object_id = -1
	pending_followup_object_id = -1
	battle_return = "town"
	pending_ai_battle = false
	battle_scene_hold = 0.0
	pending_ai_side = -1
	ai_turn_cursor = 0
	reset_pending_town_battle()
	pending_day_advance = false
	pending_defeat = false
	pending_defeat_message = ""
	saved_player_army = null

func to_battle(player: ArmyData, enemy: ArmyData, enemy_hero_model: HeroModel = null,
		kind: StringName = &"hero", opponent_is_human: bool = false,
		opponent_world_side: int = -1, delay: float = 0.0) -> void:
	var g := game
	if g != null:
		g.player_army = player
		g.enemy_army = enemy
		g.enemy_hero = enemy_hero_model
	battle_kind = kind
	battle_opponent_is_human = opponent_is_human
	battle_opponent_world_side = opponent_world_side
	last_battle_outcome = &""
	last_battle_wipeout = false
	battlefield_kind = &"ship" if kind != &"town" and (
			(g != null and g.player_hero != null and g.player_hero.travel_mode == &"sea") or
			(enemy_hero_model != null and enemy_hero_model.travel_mode == &"sea")) else &"land"
	if battle_terrain == "":
		battle_terrain = "grass"
	battle_scene_hold = delay
	if g != null and g.is_inside_tree():
		if delay > 0.0:
			_change_scene_after(delay)
		else:
			g.get_tree().change_scene_to_file(BATTLE_SCENE)

## Hold the current scene for `delay` seconds, then enter the battle screen.
## A hero that engages another hero turns to face it first, and that turn is a
## single frame of sprite swap: without the hold the battle screen would take
## over on the very next frame and the player would never see the two heroes
## square off. The battle context itself is already set when this is called.
func _change_scene_after(delay: float) -> void:
	var g := game
	if g == null or not is_instance_valid(g) or not g.is_inside_tree():
		return
	await g.get_tree().create_timer(delay).timeout
	battle_scene_hold = 0.0
	if g != null and is_instance_valid(g) and g.is_inside_tree():
		g.get_tree().change_scene_to_file(BATTLE_SCENE)

## Whether a human-owned opposing army may be played by a second person at this
## keyboard. Hot seat: yes. Remote play: no.
func pvp_control_allowed() -> bool:
	var g := game
	return g == null or g.game_mode != &"network"

func player_for_battle_side(battle_side: int) -> PlayerState:
	var g := game
	if g == null or g.state == null:
		return null
	if battle_side == human_battle_side():
		return g.state.human()
	return g.state.player_of(battle_opponent_world_side)

## Retreat and surrender preserve the hero as a future tavern recruit.
func return_active_human_to_tavern(preserve_army: bool) -> bool:
	var g := game
	if g == null or g.state == null or g.state.players.is_empty() or g.player_hero == null:
		return false
	var human: PlayerState = g.state.human()
	var withdrawing: HeroModel = human.active()
	if withdrawing == null or withdrawing != g.player_hero:
		return false
	if not human.return_to_tavern(withdrawing, preserve_army, g.rng):
		return false
	g.visiting_hero = null
	g.player_hero = human.active()
	if g.player_hero != null:
		g.player_army = g.player_hero.army
		g.hero_tile = g.player_hero.tile
		g.hero_move_points = g.player_hero.move_points
	else:
		g.player_army = ArmyData.new()
		g.hero_tile = g.town_tile if human.owns_town else Vector2i(-1, -1)
		g.hero_move_points = -1
		if not human.owns_town:
			pending_defeat = true
	return true

## Returns the defending hero to their owning player's tavern recruit reserve
## after retreat or surrender.
func return_defender_to_tavern(preserve_army: bool) -> bool:
	var g := game
	if g == null or g.state == null or g.state.players.is_empty() or g.enemy_hero == null:
		return false
	var defender_player: PlayerState = g.state.player_of(battle_opponent_world_side)
	if defender_player == null:
		return false
	var withdrawing: HeroModel = g.enemy_hero
	if not defender_player.heroes.has(withdrawing):
		for h: HeroModel in defender_player.heroes:
			if h.hero_name == withdrawing.hero_name:
				withdrawing = h
				break
	if not defender_player.return_to_tavern(withdrawing, preserve_army, g.rng):
		return false
	g.enemy_hero = null
	g.enemy_army = null
	return true

## Record the town this battle is fought at.
func set_pending_town_battle(town: TownObject, defender_side: int,
		hero_defense: bool = false) -> void:
	pending_town_battle_side = defender_side
	pending_town_battle_id = town.id if town != null else -1
	pending_town_faction = town.town_type if town != null else 0
	pending_town_has_castle = town_has_castle(town)
	pending_town_hero_defense = hero_defense

## Clear every marker describing the town a pending battle is fought at.
func reset_pending_town_battle() -> void:
	pending_town_battle_side = -1
	pending_town_battle_id = -1
	pending_town_faction = 0
	pending_town_has_castle = false
	pending_town_hero_defense = false

## True if the pending battle is a town/castle defense with NO defending hero
## (i.e. garrison only).
func is_garrison_only_town_defense() -> bool:
	if pending_town_hero_defense:
		return false
	if pending_town_battle_id < 0 and pending_town_battle_side < 0:
		return false
	var g := game
	var human_side: int = g.state.human().side if g != null and g.state != null and not g.state.players.is_empty() and g.state.human() != null else 0
	return pending_town_battle_side == human_side

## A hero parked on his own town gate defends it.
func mark_hero_defended_town(map: MapData, tile: Vector2i, defender_side: int) -> bool:
	var gate := map.own_town_gate_at(tile, defender_side) if map != null else null
	if gate == null:
		return false
	set_pending_town_battle(gate, gate.owner, true)
	return true

## The garrison of a hero-defended town fights alongside him.
func join_gate_garrison(defender_army: ArmyData) -> int:
	var g := game
	if not pending_town_hero_defense or defender_army == null \
			or g == null or g.state == null or pending_town_battle_id < 0:
		return 0
	var owner: PlayerState = g.state.player_of(pending_town_battle_side)
	if owner == null:
		return 0
	var town: TownModel = owner.town_by_object_id(pending_town_battle_id)
	if town == null or town.army == null:
		return 0
	return defender_army.absorb(town.army)

## Whether a town gate fights as a walled castle.
func town_has_castle(town: TownObject) -> bool:
	if town == null:
		return false
	var g := game
	if g != null and g.state != null and town.owner >= 0:
		var owner: PlayerState = g.state.player_of(town.owner)
		if owner != null:
			var model: TownModel = owner.town_by_object_id(town.id)
			if model != null:
				return model.has_castle
	return bool(town.params.get("has_castle", true))

## In every castle siege the castle is on the right (battle side 1).
func siege_defender_side() -> int:
	if not pending_town_has_castle:
		return -1
	return 1

## Which battle side the human controls.
## A settlement defense always puts the defender on the right and the attacker
## on the left (KB battlefield.md §2: "Attacker (Left): column 0", "Defender
## (Right): column 6"). A town without a castle has no walls and no archer
## tower, but the sides do not change: the human still defends, the computer
## hero still attacks. Tying the sides to the castle flag put the defending
## garrison on the attacking side and the enemy in the town's own half of the
## field.
func human_battle_side() -> int:
	var g := game
	if pending_town_battle_side >= 0 and g != null and g.state != null:
		var human: PlayerState = g.state.human()
		if human != null and pending_town_battle_side == human.side:
			return 1
	return 0

## Castle art follows the besieged town's own type, whoever owns it.
func siege_faction() -> int:
	if pending_town_battle_id >= 0:
		return clampi(pending_town_faction, 0, 3)
	var g := game
	if pending_town_battle_side >= 0 and g != null and g.state != null:
		var owner: PlayerState = g.state.player_of(pending_town_battle_side)
		if owner != null:
			return clampi(owner.crest_idx % 4, 0, 3)
	return clampi(pending_town_faction, 0, 3)

## The defending TownModel during a castle siege battle, or null.
## Only the settlement under attack may supply the archer tower's strength, the
## Mage Guild level and the Tavern bonus. Falling back to another of the
## owner's settlements (its first town model, the starting castle) would dress
## a town's defense in the main castle's numbers.
func siege_defender_town() -> TownModel:
	var g := game
	if pending_town_battle_side < 0 or g == null or g.state == null:
		return null
	var owner: PlayerState = g.state.player_of(pending_town_battle_side)
	if owner == null:
		return null
	if pending_town_battle_id < 0:
		return null
	return owner.town_by_object_id(pending_town_battle_id)

## The Tavern increases morale for troops defending the castle (+1 morale).
func siege_defender_has_tavern() -> bool:
	var town := siege_defender_town()
	return town != null and town.built.has("tavern")

## Scaling coefficient k for the siege arrow tower based on built town buildings.
func siege_defender_tower_k() -> int:
	var town := siege_defender_town()
	return town.siege_tower_k() if town != null else 5

## Mage Guild level in the defending castle (adds to tower attack).
func siege_defender_mage_guild_level() -> int:
	var town := siege_defender_town()
	return town.mage_guild_level if town != null else 0

## Apply the stashed battle XP to the active human hero (player win only).
func consume_battle_xp() -> void:
	var g := game
	if last_winner == 0 and last_battle_xp > 0 \
			and g != null and g.state != null and not g.state.players.is_empty() \
			and not is_garrison_only_town_defense():
		var hm: HeroModel = g.state.human().active()
		if hm != null:
			hm.grant_experience(last_battle_xp, g.rng)
	last_battle_xp = 0

func clear_hero_battle_modifiers(hero: HeroModel) -> void:
	if hero == null:
		return
	for visit: Dictionary in hero.consume_battle_modifiers():
		_clear_battle_booster_visit(
				int(visit.get("object_id", -1)),
				int(visit.get("hero_id", -1)))

func complete_battle_lifetimes() -> void:
	var g := game
	if g == null:
		return
	var participants: Array = []
	if g.player_hero != null and not is_garrison_only_town_defense():
		participants.append(g.player_hero)
	if g.enemy_hero != null and not participants.has(g.enemy_hero):
		participants.append(g.enemy_hero)
	for hero: HeroModel in participants:
		clear_hero_battle_modifiers(hero)

func _clear_battle_booster_visit(object_id: int, hero_id: int) -> void:
	var g := game
	if g == null or object_id < 0 or not g.map_object_state.has(object_id):
		return
	var saved: Dictionary = g.map_object_state[object_id].duplicate(true)
	var raw_visits: Variant = saved.get("visited_by", [])
	if not raw_visits is Array:
		return
	var visited_by: Array = raw_visits
	visited_by.erase(hero_id)
	if visited_by.is_empty():
		saved.erase("visited_by")
	else:
		saved["visited_by"] = visited_by
	g.map_object_state[object_id] = saved
