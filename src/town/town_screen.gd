extends Node2D

## Authentic data-driven town scene for all four HOMM1 factions. Buildings use
## their source ICN offsets; dwellings are per-pixel clickable.

const MONS32 := UiKit.ART + "mons32/"
const MONSTERS := UiKit.ART + "monsters/"
const EXIT_BTN := UiKit.ART + "swapbtn/"
const STRIP := UiKit.ART + "strip/0000.png"
const STATUSBAR := UiKit.ART + "bigbar/0000.png"
const CRST := UiKit.ART + "crst%04d/0000.png"
const PORT := UiKit.ART + "port%04d/0000.png"
const RES := UiKit.ART + "resource/"
const RES_ORDER := ["wood", "mercury", "ore", "sulfur", "crystal", "gems", "gold"]
const STRIP_Y := 248
const SLOTART := UiKit.ART + "strip/"
const HORSE_FILL := SLOTART + "0002.png"
const KING_WIDE_FILL := SLOTART + "0008.png"
const HILITE := SLOTART + "0001.png"
const SLOT_W := 82
const SLOT_H := 93
const HERO_X := 5
const UNIT_X := [112, 200, 288, 376, 464]
const RES_X := 552
const ROW_TOP := 262
const ROW_BOT := 361
const ROW_Y := [ROW_TOP, ROW_BOT]
const MAGEGLD := UiKit.ART + "magegld/"
const GUILD_SPRITE_IDS := TownScenery.GUILD_SPRITE_IDS
const ANIMATED_BUILDINGS := TownScenery.ANIMATED_BUILDINGS
const BUILDING_ANIM_FPS := TownScenery.BUILDING_ANIM_FPS
const CONSTRUCTION_REVEAL_DELAY := TownScenery.CONSTRUCTION_REVEAL_DELAY
const CONSTRUCTION_REVEAL_DISSOLVE := TownScenery.CONSTRUCTION_REVEAL_DISSOLVE
const CONSTRUCTION_REVEAL_DURATION := TownScenery.CONSTRUCTION_REVEAL_DURATION
const CONSTRUCTION_REVEAL_SHADER := TownScenery.CONSTRUCTION_REVEAL_SHADER
const WATER_CYCLE_SHADER := TownScenery.WATER_CYCLE_SHADER
const HERO_RECRUIT_REVEAL_DURATION := TownArmyPanel.HERO_RECRUIT_REVEAL_DURATION
const NO_ROOM_FOR_SPELLBOOK := "You must purchase a spell book to use the mage guild, but you currently have no room for a spell book.  Try giving one of your artifacts to another hero."

var _font_big: FontFile
var _font_small: FontFile

var _game: GameState
var _player: PlayerState
var _faction := "knight"
var _town: Dictionary = {}
var _town_name := "Sorpigal"
var _audio: TownAudio = null

var _scenery: TownScenery
var _army_panel: TownArmyPanel

# Modal dialogs
var _guild_screen: GuildScreen = null
var _build_screen: BuildScreen = null
var _kingdom_overview: CanvasLayer = null
var _ship_dialog: ShipPurchaseDialog = null
var _well_dialog: WellDialog = null
var _thieves_screen: ThievesScreen = null
var _buy_spellbook_dialog: BuySpellbookDialog = null
var _dlg: RecruitDialog = null
var _recruit_hero_dlg: RecruitHeroDialog = null
var _tavern_dialog: TavernDialog = null
var _dwelling_info_dialog: DwellingInfoDialog = null
var _pending_built_id := ""

# --- Facade properties for TownScenery ---
var _dwellings: Array:
	get: return _scenery.dwellings if _scenery != null else []
	set(v): if _scenery != null: _scenery.dwellings = v

var _guild_hits: Array:
	get: return _scenery.guild_hits if _scenery != null else []
	set(v): if _scenery != null: _scenery.guild_hits = v

var _castle_hit: Dictionary:
	get: return _scenery.castle_hit if _scenery != null else {}
	set(v): if _scenery != null: _scenery.castle_hit = v

var _common_hits: Array:
	get: return _scenery.common_hits if _scenery != null else []
	set(v): if _scenery != null: _scenery.common_hits = v

var _building_anims: Array:
	get: return _scenery.building_anims if _scenery != null else []
	set(v): if _scenery != null: _scenery.building_anims = v

var _construction_active: bool:
	get: return _scenery.construction_active if _scenery != null else false
	set(v): if _scenery != null: _scenery.construction_active = v

# --- Facade properties for TownArmyPanel ---
var _name_label: Label:
	get: return _army_panel.name_label if _army_panel != null else null
	set(v): if _army_panel != null: _army_panel.name_label = v

var _status_label: Label:
	get: return _army_panel.status_label if _army_panel != null else null
	set(v): if _army_panel != null: _army_panel.status_label = v

var _exit_btn: TextureButton:
	get: return _army_panel.exit_btn if _army_panel != null else null
	set(v): if _army_panel != null: _army_panel.exit_btn = v

var _army_nodes: Array:
	get: return _army_panel.army_nodes if _army_panel != null else []
	set(v): if _army_panel != null: _army_panel.army_nodes = v

var _pos_row: Array:
	get: return _army_panel.pos_row if _army_panel != null else [[], []]
	set(v): if _army_panel != null: _army_panel.pos_row = v

var _sel_row: int:
	get: return _army_panel.sel_row if _army_panel != null else -1
	set(v): if _army_panel != null: _army_panel.sel_row = v

var _sel_col: int:
	get: return _army_panel.sel_col if _army_panel != null else -1
	set(v): if _army_panel != null: _army_panel.sel_col = v

var _sel_shift: bool:
	get: return _army_panel.sel_shift if _army_panel != null else false
	set(v): if _army_panel != null: _army_panel.sel_shift = v

var _split_dialog: SplitDialog:
	get: return _army_panel.split_dialog if _army_panel != null else null
	set(v): if _army_panel != null: _army_panel.split_dialog = v

var _army_dialog: CreatureInfoDialog:
	get: return _army_panel.army_dialog if _army_panel != null else null
	set(v): if _army_panel != null: _army_panel.army_dialog = v

var _hero_slot_art: Node2D:
	get: return _army_panel.hero_slot_art if _army_panel != null else null
	set(v): if _army_panel != null: _army_panel.hero_slot_art = v

var _crest_slot_art: Node2D:
	get: return _army_panel.crest_slot_art if _army_panel != null else null
	set(v): if _army_panel != null: _army_panel.crest_slot_art = v

var _hero_reveal_pending: bool:
	get: return _army_panel.hero_reveal_pending if _army_panel != null else false
	set(v): if _army_panel != null: _army_panel.hero_reveal_pending = v

var _hero_reveal_active: bool:
	get: return _army_panel.hero_reveal_active if _army_panel != null else false
	set(v): if _army_panel != null: _army_panel.hero_reveal_active = v

var _hero_reveal_underlay: Array:
	get: return _army_panel.hero_reveal_underlay if _army_panel != null else []
	set(v): if _army_panel != null: _army_panel.hero_reveal_underlay = v

func _init() -> void:
	_scenery = load("res://src/town/town_scenery.gd").new()
	_army_panel = load("res://src/town/town_army_panel.gd").new()

func _ready() -> void:
	if Game.state == null:
		Game.new_game()
	_game = Game.state
	_player = _game.human() if _game != null else null
	if _player == null:
		Game.to_map()
		return
	if _player.town == null:
		if not _player.towns.is_empty():
			_player.active_town = 0
		else:
			var fallback_town := TownModel.new()
			fallback_town.setup(0, {}, ArmyData.new(), _player.crest_idx % 4)
			fallback_town.init_start_buildings(Game.rng if Game != null else RandomNumberGenerator.new(), false)
			_player.add_town(fallback_town)
	var shots = DevFlags.tool("res://src/tools/shots/town_shots.gd", ["--shot", "--probe="])
	if shots != null:
		shots.prepare(self)
	_faction = _player.town.faction
	Game.music.play(MusicPlayer.town_track(_faction))
	_town = BuildingCatalog.town_data(_faction)
	_town_name = _player.town.town_name if _player.town.town_name != "" \
		else String(_town.get("name", _faction.capitalize()))

	_font_big = UiKit.font_big()
	_font_small = UiKit.font_small()

	_audio = TownAudio.new()
	add_child(_audio)

	_draw_bg()
	_draw_buildings()
	_draw_panel()
	_refresh()

	if shots != null and shots.aborts_probe(self):
		get_tree().quit(1)
		return

	var is_standalone := (Game.selected_map_path == "" and Game.visiting_hero == null)
	var smoke = DevFlags.smoke() if get_tree().current_scene == self and is_standalone else null
	if smoke != null:
		await smoke.town(self)
		return

	if shots != null:
		await shots.run(self)

func _process(delta: float) -> void:
	if _scenery != null:
		_scenery.process(delta)
	if _army_panel != null:
		_army_panel.process(delta)

# --- Scene & Scenery delegations ---

func _ensure_water_material() -> ShaderMaterial:
	return _scenery.ensure_water_material()

func _draw_bg() -> void:
	_scenery.draw_bg(self, _town)

func _draw_buildings() -> void:
	_scenery.draw_buildings(self, _faction, _town, _game, _player)

func _place_building(dir: String, unit: String, depth: int, building_id := "") -> void:
	_scenery.place_building(self, dir, unit, depth, building_id, _faction, _town)

func _add_building_animation(dir: String, spec, depth: int, building_id := "") -> void:
	_scenery.add_building_animation(self, dir, spec, depth, building_id)

func _redraw_buildings() -> void:
	_scenery.redraw_buildings(self, _faction, _town, _game, _player)

func _draw_guild_refresh() -> void:
	_scenery.draw_guild_refresh(self, _player)

func _start_construction_reveal(building_id: String) -> void:
	_scenery.start_construction_reveal(self, building_id, _audio)

func _opaque_at(d: Dictionary, p: Vector2) -> bool:
	return _scenery.opaque_at(d, p)

func _castle_at(p: Vector2) -> bool:
	return _scenery.castle_at(p)

func _guild_at(p: Vector2) -> bool:
	return _scenery.guild_at(p)

func _dwelling_at(p: Vector2) -> Dictionary:
	return _scenery.dwelling_at(p)

func _common_at(p: Vector2) -> Dictionary:
	return _scenery.common_at(p)

static var _mask_cache: Dictionary = TownScenery._mask_cache

static func clear_mask_cache() -> void:
	TownScenery.clear_mask_cache()

static func load_tod_rect(name: String) -> Rect2:
	return TownScenery.load_tod_rect(name)

# --- Panel & Army delegations ---

func _draw_panel() -> void:
	_army_panel.draw_panel(self, _font_big, _font_small, _on_to_map)

func _refresh() -> void:
	_army_panel.refresh(self, _town_name, _game, _player, _town, _font_small)

func _sync_army(row: int) -> void:
	_army_panel.sync_army(row, _game)

func _slot_at(p: Vector2) -> Vector2i:
	return _army_panel.slot_at(p, _game)

func _count_occupied_row(row: int) -> int:
	return _army_panel.count_occupied_row(row)

func _open_creature_dialog(col: int, row: int) -> void:
	_army_panel.open_creature_dialog(self, col, row, _player, _refresh)

func _on_slot_click(col: int, row: int, shift_pressed: bool = false) -> void:
	_army_panel.on_slot_click(self, col, row, shift_pressed, _player, _game, _refresh)

func _open_split_dialog(unit: String, from_name: String, to_name: String, src_count: int, max_move: int,
		s_row: int, s_col: int, d_row: int, d_col: int) -> void:
	_army_panel.open_split_dialog(self, unit, from_name, to_name, src_count, max_move,
			s_row, s_col, d_row, d_col, _game, _refresh)

func _start_hero_recruit_reveal() -> void:
	_army_panel.start_hero_recruit_reveal()

func _finish_hero_recruit_reveal() -> void:
	_army_panel.finish_hero_recruit_reveal()

static func _hover_name(unit: String) -> String:
	return TownArmyPanel.hover_name(unit)

# --- Modal Dialogs & Navigation ---

func _is_modal_active() -> bool:
	return _dlg != null or _guild_screen != null or _recruit_hero_dlg != null \
			or _tavern_dialog != null or _dwelling_info_dialog != null or _build_screen != null \
			or _kingdom_overview != null or _ship_dialog != null or _army_dialog != null \
			or _buy_spellbook_dialog != null or _well_dialog != null or _thieves_screen != null \
			or _split_dialog != null

func _on_to_map() -> void:
	Game.visiting_hero = null
	Game.to_map()

func _set_exit_greyed(greyed: bool) -> void:
	if _exit_btn == null:
		return
	_exit_btn.disabled = greyed
	_exit_btn.modulate = Color(0.5, 0.5, 0.5) if greyed else Color.WHITE

func _open_guild() -> void:
	if _guild_screen != null or _buy_spellbook_dialog != null:
		return
	if _player == null or _player.town == null or _player.town.mage_guild_level <= 0:
		return
	var hero: HeroModel = Game.visiting_hero
	if hero != null and not hero.has_spellbook:
		if hero.artifacts.size() >= 14:
			MapDialogs.info(self, {"lines": [NO_ROOM_FOR_SPELLBOOK], "centered": true})
			return
		_open_buy_spellbook(hero)
		return
	_guild_screen = GuildScreen.new()
	add_child(_guild_screen)
	_guild_screen.closed.connect(_on_guild_closed)
	_guild_screen.open(_player, hero)
	_set_exit_greyed(true)

func _open_buy_spellbook(hero: HeroModel) -> void:
	if _buy_spellbook_dialog != null or _guild_screen != null:
		return
	if _status_label != null:
		_status_label.text = "Mage Guild"
	_buy_spellbook_dialog = BuySpellbookDialog.new()
	add_child(_buy_spellbook_dialog)
	_buy_spellbook_dialog.closed.connect(_on_buy_spellbook_closed)
	_buy_spellbook_dialog.bought.connect(_on_buy_spellbook_bought)
	_buy_spellbook_dialog.open(_player, hero)

func _on_buy_spellbook_closed() -> void:
	_buy_spellbook_dialog = null
	_refresh()

func _on_buy_spellbook_bought() -> void:
	_buy_spellbook_dialog = null
	_refresh()

func _on_guild_closed() -> void:
	_guild_screen = null
	_set_exit_greyed(false)
	_draw_guild_refresh()
	_refresh()

func _open_build() -> void:
	if _build_screen != null:
		return
	_build_screen = BuildScreen.new()
	add_child(_build_screen)
	_build_screen.closed.connect(_on_build_closed)
	_build_screen.building_built.connect(_on_building_built)
	_build_screen.recruit_hero_requested.connect(_on_build_recruit_hero)
	_build_screen.recruit_hero_viewed.connect(_view_recruit_hero)
	_build_screen.recruit_hero_view_ended.connect(_end_view_recruit_hero)
	if _game.town.has_castle:
		_build_screen.open(_player, Game.visiting_hero)
		_set_exit_greyed(true)
	else:
		_build_screen.open_dialog_only(_player, "castle")

func _on_building_built(id: String) -> void:
	_pending_built_id = id

func _on_build_closed() -> void:
	var reveal_id := _pending_built_id
	_pending_built_id = ""
	_build_screen = null
	_set_exit_greyed(false)
	_redraw_buildings()
	_refresh()
	if reveal_id != "":
		_start_construction_reveal(reveal_id)

func _on_build_recruit_hero() -> void:
	_open_recruit_hero_dialog()

func _open_kingdom_overview() -> void:
	if _is_modal_active():
		return
	_kingdom_overview = load("res://src/ui/kingdom_overview.gd").new()
	add_child(_kingdom_overview)
	_kingdom_overview.closed.connect(_on_kingdom_overview_closed)
	_kingdom_overview.open(Game.state, null)

func _on_kingdom_overview_closed() -> void:
	_kingdom_overview = null

func _open_recruit(unit: String) -> void:
	if _game.town.army == null or not _game.town.army.can_add(unit):
		MapDialogs.info(self, {"lines": ["There is no room in the garrison for this army."], "centered": true})
		return
	var costs := {"gold": _game.town.cost_of(unit)}
	costs.merge(_game.town.rare_cost_of(unit))
	_dlg = RecruitDialog.new()
	add_child(_dlg)
	_dlg.confirmed.connect(func(quantity: int) -> void:
		_game.town.recruit(unit, quantity, _player)
		_refresh())
	_dlg.closed.connect(func() -> void: _dlg = null)
	_dlg.open(unit, int(_game.town.available.get(unit, 0)), costs,
			_game.town.max_recruitable(unit, _player))

func _open_recruit_hero_dialog(candidate_override: Array = []) -> void:
	if Game.visiting_hero != null or not _player.can_hire():
		return

	var candidates := candidate_override if not candidate_override.is_empty() \
			else HeroPool.candidates(Game.rng, _player.heroes, _game.town.town_type,
					_player.returning_heroes, _player.side)
	if candidates.is_empty():
		return

	_recruit_hero_dlg = RecruitHeroDialog.new()
	add_child(_recruit_hero_dlg)
	if _build_screen != null:
		_build_screen.set_process_input(false)
	_recruit_hero_dlg.closed.connect(_on_recruit_hero_closed)
	_recruit_hero_dlg.recruited.connect(_on_candidate_selected)
	_recruit_hero_dlg.open(_player, candidates, Game.town_tile)

func _view_recruit_hero() -> void:
	if _recruit_hero_dlg != null:
		return
	var candidates := HeroPool.candidates(Game.rng, _player.heroes, _game.town.town_type,
			_player.returning_heroes, _player.side)
	if candidates.is_empty():
		return
	_recruit_hero_dlg = RecruitHeroDialog.new()
	add_child(_recruit_hero_dlg)
	_recruit_hero_dlg.closed.connect(func() -> void: _recruit_hero_dlg = null)
	_recruit_hero_dlg.open(_player, candidates, Game.town_tile, true)

func _end_view_recruit_hero() -> void:
	if _recruit_hero_dlg != null:
		_recruit_hero_dlg.close()

func _on_recruit_hero_closed() -> void:
	_recruit_hero_dlg = null
	if _build_screen != null:
		_build_screen.set_process_input(true)

func _on_candidate_selected(h: HeroModel) -> void:
	_finish_hero_recruit_reveal()
	if _audio != null:
		_audio.play_build()
	h.crest_idx = (_player.crest_idx / 4) * 4 + (h.crest_idx % 4)
	Game.visiting_hero = h
	_recruit_hero_dlg = null
	_hero_reveal_pending = true
	if _build_screen != null:
		_build_screen._close()
	else:
		_refresh()
	_start_hero_recruit_reveal()

func _open_tavern_dialog() -> void:
	if _tavern_dialog != null:
		return
	_tavern_dialog = TavernDialog.new()
	add_child(_tavern_dialog)
	Game.music.play(MusicPlayer.TAVERN)
	_tavern_dialog.closed.connect(func():
		_tavern_dialog = null
		Game.music.play(MusicPlayer.town_track(_faction))
		_refresh()
	)
	_tavern_dialog.open()

func _open_dwelling_info(d: Dictionary) -> void:
	if _dwelling_info_dialog != null:
		return
	var unit: String = String(d.get("unit", ""))
	if unit == "":
		return
	var bldg_id: String = String(d.get("id", ""))
	if bldg_id == "":
		bldg_id = BuildingCatalog.dwelling_for_unit(unit, _faction)
	var is_built := _player.town != null and _player.town.is_built(bldg_id)
	var avail: int = int(_player.town.available.get(unit, 0)) if _player.town != null else 0
	var recruit_dict: Dictionary = TownModel._recruit_data(_faction).get(unit, {}) as Dictionary
	var growth: int = int(recruit_dict.get("growth", 0))
	if _player.town != null and _player.town.is_built("well"):
		growth += 2

	var cost_dict: Dictionary = {"gold": _player.town.cost_of(unit)} if _player != null and _player.town != null else {}
	if _player != null and _player.town != null:
		var rare: Dictionary = _player.town.rare_cost_of(unit)
		for k in rare:
			cost_dict[k] = rare[k]

	_dwelling_info_dialog = DwellingInfoDialog.new()
	add_child(_dwelling_info_dialog)
	_dwelling_info_dialog.closed.connect(func():
		_dwelling_info_dialog = null
		_refresh()
	)
	_dwelling_info_dialog.open(unit, avail, growth, is_built, cost_dict)

func _open_ship_dialog() -> void:
	if _ship_dialog != null:
		return
	_ship_dialog = ShipPurchaseDialog.new()
	add_child(_ship_dialog)
	_ship_dialog.closed.connect(func():
		_ship_dialog = null
		_refresh())
	_ship_dialog.open(_player, Game.state)

func _open_well_dialog() -> void:
	if _well_dialog != null:
		return
	_well_dialog = WellDialog.new()
	add_child(_well_dialog)
	_well_dialog.closed.connect(func():
		_well_dialog = null
		_refresh())
	_well_dialog.open(_game.town, _faction)

func _open_thieves_dialog() -> void:
	if _thieves_screen != null:
		return
	_thieves_screen = ThievesScreen.new()
	add_child(_thieves_screen)
	_thieves_screen.closed.connect(func():
		_thieves_screen = null
		_refresh())
	var players: Array = _game.players if (_game != null and not _game.players.is_empty()) else [_player]
	_thieves_screen.open(players, _player.side)

# --- Input Handling ---

func _unhandled_input(event: InputEvent) -> void:
	if not is_node_ready() or _status_label == null:
		return
	if _construction_active or _hero_reveal_active:
		return
	if _is_modal_active():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_on_to_map()
			return
	if event is InputEventMouseMotion:
		var p: Vector2 = (event as InputEventMouseMotion).position
		var hit_slot := _slot_at(p)
		if hit_slot.x >= 0:
			if _sel_row < 0:
				if _pos_row[hit_slot.y][hit_slot.x] == null:
					_status_label.text = "Empty"
				else:
					var u: String = String(_pos_row[hit_slot.y][hit_slot.x].get("unit", ""))
					_status_label.text = "Select %s" % _hover_name(u)
			else:
				var src_slot = _pos_row[_sel_row][_sel_col]
				var dst_slot = _pos_row[hit_slot.y][hit_slot.x]
				var src_u: String = String(src_slot.get("unit", "")) if src_slot != null else ""
				var target_has_same := false
				if _sel_row != hit_slot.y:
					for c in _pos_row[hit_slot.y].size():
						var s = _pos_row[hit_slot.y][c]
						if s != null and String(s.get("unit", "")) == src_u:
							target_has_same = true
							break
				if hit_slot.y == _sel_row and hit_slot.x == _sel_col:
					_status_label.text = "View %s" % _hover_name(src_u)
				elif target_has_same or (dst_slot != null and String(dst_slot.get("unit", "")) == src_u):
					if _sel_row == 1 and hit_slot.y == 0 and _count_occupied_row(1) <= 1:
						_status_label.text = "Cannot combine Hero's last army"
					else:
						_status_label.text = "Combine %s armies" % _hover_name(src_u)
				elif dst_slot == null:
					if _sel_row == 1 and hit_slot.y == 0 and _count_occupied_row(1) <= 1:
						_status_label.text = "Cannot move last army to garrison."
					else:
						_status_label.text = "Move %s" % _hover_name(src_u)
				else:
					var dst_u: String = String(dst_slot.get("unit", ""))
					_status_label.text = "Exchange %s with %s" % [
						_hover_name(src_u),
						_hover_name(dst_u)
					]
			return
		if Rect2(HERO_X, ROW_TOP, 101, 93).has_point(p):
			_status_label.text = "Kingdom Overview"
			return
		if Game.visiting_hero != null and Rect2(HERO_X, ROW_BOT, 101, 93).has_point(p):
			_status_label.text = "View Hero"
			return
		if Rect2(549, ROW_TOP + 166, 80, 25).has_point(p):
			_status_label.text = "Exit town"
			return
		var common := _common_at(p)
		if not common.is_empty():
			match String(common.id):
				"well":
					_status_label.text = "Well"
				"tavern":
					_status_label.text = "Tavern"
				"thieves_guild":
					_status_label.text = "Thieves' Guild"
				"shipyard":
					_status_label.text = "Dock"
				_:
					_status_label.text = String(BuildingCatalog.entry(common.id, _faction).get("name", common.id))
			return
		if _guild_at(p):
			_status_label.text = "Mage Guild"
			return
		if _castle_at(p):
			_status_label.text = "Castle" if (_game != null and _game.town != null and _game.town.has_castle) else "Tent"
			return
		var d := _dwelling_at(p)
		if not d.is_empty():
			_status_label.text = "Recruit %s" % CreatureCatalog.singular(String(d.unit)).to_lower()
			return
		_status_label.text = ""
		return
	if event is InputEventMouseButton and event.pressed:
		var p: Vector2 = (event as InputEventMouseButton).position
		if event.button_index == MOUSE_BUTTON_RIGHT:
			var hit := _slot_at(p)
			if hit.x >= 0 and _pos_row[hit.y][hit.x] != null:
				_sel_row = hit.y
				_sel_col = hit.x
				_refresh()
				_open_creature_dialog(hit.x, hit.y)
				return
			if Game.visiting_hero != null and Rect2(HERO_X, ROW_BOT, 101, 93).has_point(p):
				Game.to_hero(Game.visiting_hero)
				return
			var best := _dwelling_at(p)
			if not best.is_empty():
				_open_dwelling_info(best)
				return
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if Rect2(HERO_X, ROW_TOP, 101, 93).has_point(p):
				_open_kingdom_overview()
				return
			var common := _common_at(p)
			if not common.is_empty():
				match String(common.id):
					"shipyard":
						_open_ship_dialog()
						return
					"thieves_guild":
						_open_thieves_dialog()
						return
					"tavern":
						_open_tavern_dialog()
						return
					"well":
						_open_well_dialog()
						return
			if Game.visiting_hero != null \
					and Rect2(HERO_X, ROW_BOT, 101, 93).has_point(p):
				Game.to_hero(Game.visiting_hero)
				return
			var hit := _slot_at(p)
			if hit.x >= 0:
				if event.double_click and _pos_row[hit.y][hit.x] != null:
					_sel_row = hit.y
					_sel_col = hit.x
					_refresh()
					_open_creature_dialog(hit.x, hit.y)
					return
				var shift_pressed: bool = event.shift_pressed or Input.is_key_pressed(KEY_SHIFT)
				_on_slot_click(hit.x, hit.y, shift_pressed)
				return
			if _guild_at(p):
				_open_guild()
				return
			if _castle_at(p):
				_open_build()
				return
			var best := _dwelling_at(p)
			if not best.is_empty():
				_open_recruit(best.unit)
