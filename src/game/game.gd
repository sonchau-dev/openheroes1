extends Node

## Autoload singleton: persistent run state (GameState) + subcomponents + scene routing.

const START_GOLD := 10000
const CASTLE_DAILY_INCOME := 1000
const TOWN_DAILY_INCOME := 250

const POINTER := SoftwareCursor.POINTER
const DEFAULT_SETTINGS_PATH := GameSettings.DEFAULT_SETTINGS_PATH
const MovementSpeed = GameSettings.MovementSpeed

# --- Subcomponents ---
var settings: GameSettings = null
var cursor: SoftwareCursor = null
var music: MusicPlayer = null
var run_setup: RunSetup = null
var battle: BattleContext = null
var save_glue: SaveGlue = null

# --- Run State ---
var state: GameState = null
var rng := RandomNumberGenerator.new()
var player_army: ArmyData = null
var enemy_army: ArmyData = null
var enemy_hero: HeroModel = null   # commands enemy_army's casts; null = neutral army
var current_hero: HeroModel = null   # hero whose detail screen is open
var player_hero: HeroModel = null    # the player's canonical hero (persists across scenes)
var visiting_hero: HeroModel = null  # hero standing in the town (entered via gate); null = remote view
var hero_tile: Vector2i = Vector2i(-1, -1)  # persisted adventure-map tile (survives scene changes)
var hero_move_points: int = -1              # persisted movement left (-1 = use the hero's default)
var town_tile: Vector2i = Vector2i(-1, -1)  # the town's gate tile (set by the map)
var town_gate_ids: Dictionary = {}           # Vector2i gate tile -> MapObject id
var selected_map_path: String = NewGameSettings.DEFAULT_MAP_PATH
var setup: NewGameSettings = NewGameSettings.new()
var game_mode: StringName = &"standard"
var campaign: CampaignState = null
var campaign_objective_event: StringName = &""
var campaign_show_intro: bool = false
var fade_in_pending: bool = false
var high_scores_mode: StringName = &""
var route_to_map: bool = true
var hotseat_handoff_pending: bool = false
var map_object_state: Dictionary = {}  # object id -> saved state dict (survives scene reloads)
var menu_opens_load: bool = false     # the next main menu starts on its Load panel
var prefer_active_town: bool = false   # retain currently selected human town when opening town screen
var autosave_dir: String = SaveGame.SAVE_DIR
var game_name: String = SaveGame.NEW_GAME_NAME   # the Save dialog's default file name

# --- Forwarded Settings Properties ---
var music_setting: int:
	get: return settings.music_setting
	set(v): settings.music_setting = v

var sfx_setting: int:
	get: return settings.sfx_setting
	set(v): settings.sfx_setting = v

var music_enabled: bool:
	get: return settings.music_enabled
	set(v): settings.music_enabled = v

var sfx_enabled: bool:
	get: return settings.sfx_enabled
	set(v): settings.sfx_enabled = v

var movement_speed: int:
	get: return settings.movement_speed
	set(v): settings.movement_speed = v

var autosave_enabled: bool:
	get: return settings.autosave_enabled
	set(v): settings.autosave_enabled = v

var show_path: bool:
	get: return settings.show_path
	set(v): settings.show_path = v

var view_enemy_movement: bool:
	get: return settings.view_enemy_movement
	set(v): settings.view_enemy_movement = v

var settings_path: String:
	get: return settings.settings_path
	set(v): settings.settings_path = v

# --- Forwarded Battle Properties ---
var battle_kind: StringName:
	get: return battle.battle_kind
	set(v): battle.battle_kind = v

var battlefield_kind: StringName:
	get: return battle.battlefield_kind
	set(v): battle.battlefield_kind = v

var battle_terrain: String:
	get: return battle.battle_terrain
	set(v): battle.battle_terrain = v

var battle_opponent_is_human: bool:
	get: return battle.battle_opponent_is_human
	set(v): battle.battle_opponent_is_human = v

var battle_opponent_world_side: int:
	get: return battle.battle_opponent_world_side
	set(v): battle.battle_opponent_world_side = v

var last_winner: int:
	get: return battle.last_winner
	set(v): battle.last_winner = v

var last_battle_xp: int:
	get: return battle.last_battle_xp
	set(v): battle.last_battle_xp = v

var last_battle_outcome: StringName:
	get: return battle.last_battle_outcome
	set(v): battle.last_battle_outcome = v

var last_battle_wipeout: bool:
	get: return battle.last_battle_wipeout
	set(v): battle.last_battle_wipeout = v

var pending_object_id: int:
	get: return battle.pending_object_id
	set(v): battle.pending_object_id = v

var pending_followup_object_id: int:
	get: return battle.pending_followup_object_id
	set(v): battle.pending_followup_object_id = v

var battle_return: String:
	get: return battle.battle_return
	set(v): battle.battle_return = v

var pending_ai_battle: bool:
	get: return battle.pending_ai_battle
	set(v): battle.pending_ai_battle = v

var pending_ai_side: int:
	get: return battle.pending_ai_side
	set(v): battle.pending_ai_side = v

var ai_turn_cursor: int:
	get: return battle.ai_turn_cursor
	set(v): battle.ai_turn_cursor = v

var pending_town_battle_side: int:
	get: return battle.pending_town_battle_side
	set(v): battle.pending_town_battle_side = v

var pending_town_battle_id: int:
	get: return battle.pending_town_battle_id
	set(v): battle.pending_town_battle_id = v

var pending_town_faction: int:
	get: return battle.pending_town_faction
	set(v): battle.pending_town_faction = v

var pending_town_has_castle: bool:
	get: return battle.pending_town_has_castle
	set(v): battle.pending_town_has_castle = v

var pending_town_hero_defense: bool:
	get: return battle.pending_town_hero_defense
	set(v): battle.pending_town_hero_defense = v

var pending_day_advance: bool:
	get: return battle.pending_day_advance
	set(v): battle.pending_day_advance = v

var pending_defeat: bool:
	get: return battle.pending_defeat
	set(v): battle.pending_defeat = v

var pending_defeat_message: String:
	get: return battle.pending_defeat_message
	set(v): battle.pending_defeat_message = v

var saved_player_army: ArmyData:
	get: return battle.saved_player_army
	set(v): battle.saved_player_army = v

func _init() -> void:
	settings = GameSettings.new()
	cursor = SoftwareCursor.new()
	music = MusicPlayer.new()
	music.settings = settings
	run_setup = RunSetup.new(self)
	battle = BattleContext.new(self)
	save_glue = SaveGlue.new(self)

func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title(ProjectSettings.get_setting("application/config/name", "HOMM1 Godot"))
	load_settings()
	if cursor.get_parent() == null:
		add_child(cursor)
	cursor.setup()
	cursor.set_default_cursor()
	if music.get_parent() == null:
		add_child(music)
	var font := Homm1Font.load_font("res://assets/art/font/")
	if font != null:
		var theme := Theme.new()
		theme.default_font = font
		theme.default_font_size = font.fixed_size
		theme.set_color("font_color", "Label", Color.WHITE)
		theme.set_color("font_color", "RichTextLabel", Color.WHITE)
		theme.set_color("font_color", "Button", Color.WHITE)
		theme.set_color("font_pressed_color", "Button", Color.WHITE)
		theme.set_color("font_hover_color", "Button", Color.WHITE)
		theme.set_color("font_focus_color", "Button", Color.WHITE)
		theme.set_color("font_hover_pressed_color", "Button", Color.WHITE)
		theme.set_color("font_disabled_color", "Button", Color.WHITE)
		get_tree().root.theme = theme

# --- Settings Forwarding ---
func get_music_volume() -> float:
	return settings.get_music_volume()

func get_sfx_volume() -> float:
	return settings.get_sfx_volume()

func save_settings() -> void:
	settings.save_settings()

func load_settings() -> void:
	settings.load_settings()

# --- Cursor Forwarding ---
func set_cursor_visible(p_visible: bool) -> void:
	if cursor != null:
		cursor.set_cursor_visible(p_visible)

func is_cursor_visible() -> bool:
	return cursor.is_cursor_visible() if cursor != null else true

func set_cursor(tex: Texture2D, hotspot: Vector2 = Vector2.ZERO) -> void:
	if cursor != null:
		cursor.set_cursor(tex, hotspot)

func set_default_cursor() -> void:
	if cursor != null:
		cursor.set_default_cursor()

# --- Run Setup Forwarding ---
func ensure_player_hero(army: ArmyData) -> HeroModel:
	return run_setup.ensure_player_hero(army)

func ensure_ai_players(map: MapData) -> void:
	run_setup.ensure_ai_players(map)

func new_game(new_settings: NewGameSettings = null) -> String:
	return run_setup.new_game(new_settings)

func new_campaign(ruler: int) -> String:
	return run_setup.new_campaign(ruler)

func restart_campaign_mission() -> String:
	return run_setup.restart_campaign_mission()

static func apply_hero_preset(hero: HeroModel, preset: Dictionary) -> HeroModel:
	return RunSetup.apply_hero_preset(hero, preset)

func apply_run_state(map: MapData) -> void:
	run_setup.apply_run_state(map)

func configure_map_for_run(map: MapData) -> String:
	return run_setup.configure_map_for_run(map)

func register_town_gate(object_id: int, tile: Vector2i) -> void:
	run_setup.register_town_gate(object_id, tile)

func resolve_town_visitor(hero: HeroModel = null, keep_active_town: bool = false) -> HeroModel:
	return run_setup.resolve_town_visitor(hero, keep_active_town)

func teach_hero_at_town(p: PlayerState, hero: HeroModel) -> void:
	run_setup.teach_hero_at_town(p, hero)

func activate_local_player(side: int) -> bool:
	return run_setup.activate_local_player(side)

func notify_campaign_event(event: StringName) -> void:
	run_setup.notify_campaign_event(event)

func campaign_objective_complete(map: MapData) -> bool:
	return run_setup.campaign_objective_complete(map)

func campaign_objective_failed(map: MapData) -> bool:
	return run_setup.campaign_objective_failed(map)

func complete_campaign_mission() -> Dictionary:
	return run_setup.complete_campaign_mission()

func record_object_state(obj: MapObject) -> void:
	run_setup.record_object_state(obj)

func apply_object_states(objects: Array) -> void:
	run_setup.apply_object_states(objects)

# --- Battle Context Forwarding ---
## `delay` holds the current scene on screen for that long before the battle
## screen takes over — the hero-vs-hero engage uses it so the turn to face
## the opponent is visible.
func to_battle(player: ArmyData, enemy: ArmyData, enemy_hero_model: HeroModel = null,
		kind: StringName = &"hero", opponent_is_human: bool = false,
		opponent_world_side: int = -1, delay: float = 0.0) -> void:
	battle.to_battle(player, enemy, enemy_hero_model, kind, opponent_is_human,
			opponent_world_side, delay)

func pvp_control_allowed() -> bool:
	return battle.pvp_control_allowed()

func player_for_battle_side(battle_side: int) -> PlayerState:
	return battle.player_for_battle_side(battle_side)

func return_active_human_to_tavern(preserve_army: bool) -> bool:
	return battle.return_active_human_to_tavern(preserve_army)

func return_defender_to_tavern(preserve_army: bool) -> bool:
	return battle.return_defender_to_tavern(preserve_army)

func set_pending_town_battle(town: TownObject, defender_side: int, hero_defense: bool = false) -> void:
	battle.set_pending_town_battle(town, defender_side, hero_defense)

func reset_pending_town_battle() -> void:
	battle.reset_pending_town_battle()

func is_garrison_only_town_defense() -> bool:
	return battle.is_garrison_only_town_defense()

func mark_hero_defended_town(map: MapData, tile: Vector2i, defender_side: int) -> bool:
	return battle.mark_hero_defended_town(map, tile, defender_side)

func join_gate_garrison(defender_army: ArmyData) -> int:
	return battle.join_gate_garrison(defender_army)

func town_has_castle(town: TownObject) -> bool:
	return battle.town_has_castle(town)

func siege_defender_side() -> int:
	return battle.siege_defender_side()

func human_battle_side() -> int:
	return battle.human_battle_side()

func siege_faction() -> int:
	return battle.siege_faction()

func siege_defender_town() -> TownModel:
	return battle.siege_defender_town()

func siege_defender_has_tavern() -> bool:
	return battle.siege_defender_has_tavern()

func siege_defender_tower_k() -> int:
	return battle.siege_defender_tower_k()

func siege_defender_mage_guild_level() -> int:
	return battle.siege_defender_mage_guild_level()

func consume_battle_xp() -> void:
	battle.consume_battle_xp()

func clear_hero_battle_modifiers(hero: HeroModel) -> void:
	battle.clear_hero_battle_modifiers(hero)

func complete_battle_lifetimes() -> void:
	battle.complete_battle_lifetimes()

# --- Save Glue Forwarding ---
func build_envelope(save_name: String) -> Dictionary:
	return save_glue.build_envelope(save_name)

func save_game(save_name: String, dir: String = SaveGame.SAVE_DIR) -> String:
	return save_glue.save_game(save_name, dir)

func autosave() -> void:
	save_glue.autosave()

func load_from_envelope(env: Dictionary) -> void:
	save_glue.load_from_envelope(env)

func load_game(slot: String, dir: String = SaveGame.SAVE_DIR) -> String:
	return save_glue.load_game(slot, dir)

func fill_absent_humans_with_ai() -> int:
	return save_glue.fill_absent_humans_with_ai()

# --- Scene Routing ---
func to_town(hero: HeroModel = null, keep_active_town: bool = false) -> void:
	if state != null and not state.players.is_empty():
		var human := state.human()
		if human == null or human.town == null or not human.owns_town or human.towns.is_empty():
			return
	visiting_hero = resolve_town_visitor(hero, keep_active_town)
	if visiting_hero != null and state != null and not state.players.is_empty():
		teach_hero_at_town(state.human(), visiting_hero)
	if is_inside_tree():
		get_tree().change_scene_to_file("res://src/town/town_screen.tscn")

func to_map() -> void:
	prefer_active_town = false
	if not route_to_map or not is_inside_tree():
		return
	get_tree().change_scene_to_file("res://src/adventure/adventure_map.tscn")

func to_menu(open_load: bool = false) -> void:
	menu_opens_load = open_load
	get_tree().change_scene_to_file("res://src/menu/main_menu.tscn")

func to_hero(model: HeroModel) -> void:
	current_hero = model
	get_tree().change_scene_to_file("res://src/hero/hero_screen.tscn")

## Clear all run state so a fresh New Game starts clean.
func reset() -> void:
	state = null
	player_army = null
	enemy_army = null
	enemy_hero = null
	player_hero = null
	current_hero = null
	visiting_hero = null
	hero_tile = Vector2i(-1, -1)
	hero_move_points = -1
	town_tile = Vector2i(-1, -1)
	town_gate_ids.clear()
	map_object_state = {}
	game_mode = &"standard"
	campaign = null
	campaign_objective_event = &""
	campaign_show_intro = false
	hotseat_handoff_pending = false
	if battle != null:
		battle.reset()
