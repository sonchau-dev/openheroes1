class_name RosterPanel
extends Control

## The 2-column wooden list box on the adventure right panel. Top-left cell = active
## hero (mobility bar + portrait); top-right cell = the player's town. Cell rects are
## measured from bord.png's shelf openings so art sits inside the wood frames.
## The left column holds up to 4 hero cells.

const MINIPORT := UiKit.ART + "miniport/%04d.png"  # small hero face (32x22)
const PORT_BG_FLIPPED := UiKit.ART + "portxtra/0000_flipped.png"  # pre-baked mirrored locator background (46x22)
const TOWN_LOCATOR := UiKit.ART + "locators/%04d.png"  # small castle/town list icon
const MOBILITY := UiKit.ART + "mobility/%04d.png"   # movement bar (7px wide)
const MOBILITY_MAX := 22   # frame 22 = solid full bar; 23-25 add one to three crosses
const HILITE_COLOR := Color8(208, 0, 0)   # red click-selection frame (no portrait-sized asset exists)
const SCROLL_THUMB := UiKit.ART + "scroll/0004.png"   # 8x17 list scrollbar thumb
## bord.png bakes both thumbs in at arbitrary heights; the original draws them
## at run time, so ours paints the baked ones out first.
const BAKED_THUMBS := [Rect2(540, 246, 8, 17), Rect2(612, 229, 8, 17)]
const THUMB_X := [540.0, 612.0]   # hero track, town track
const TRACK_TOP := 194   # black track interior, bord.png
const TRACK_BOTTOM := 285
## Each list's arrows and track sit in the 24 px wood gap right of its cells.
## Every pixel of that gap scrolls, so a fingertip can hit the 12 px arrows on a
## phone: the top 18 px is the up arrow, the bottom 18 px the down arrow, and
## the track between them jumps or drags the list to the touched spot.
const STRIP_X := [532.0, 604.0]   # hero list, town list
const STRIP_W := 24.0
const STRIP_TOP := 176.0
const STRIP_BOTTOM := 304.0
const ARROW_H := 18.0

# Shelf-opening rects inside bord.png. Each opening is 24 px tall and the
# wooden shelf divider makes the vertical pitch 32 px.
const TOWN_CELL := Rect2(556, 180, 48, 24)
const HERO_ROW_PITCH := 32

# Local offsets inside the cells to align exactly with original game coordinates
const MOBILITY_LOCAL_X := 1.0

var _player: PlayerState
var _heroes_nodes_fn: Variant
var _town_tex: Texture2D

var _rows: Array = []  # Array of Dictionaries: { clipper, port_bg, mobility_rect, portrait_rect }
var _town_rows: Array = []  # Array of Dictionaries: { clipper, rect }
var _town_scroll: int = 0

var _town_clipper: Control
var _town_rect: TextureRect

var _selected: int = 0   # 0 none, 1 hero cell, 2 town cell
var _scroll: int = 0
var _hero_count: int = 0
var _town_count: int = 0
var _thumb_tex: Texture2D
var _held_heroes: Array = []
var _held_active: int = -1
# Active rows last scrolled into view; the list follows a new selection only,
# so the arrows can scroll the selected row out of sight.
var _shown_active: int = -1
var _shown_active_town: int = -1
var _dragging_list: int = 0   # 1 hero track, 2 town track held down

signal hero_selected(idx: int)
signal town_selected

func get_hero_cell_rect(row_index: int) -> Rect2:
	return Rect2(484, 180 + row_index * HERO_ROW_PITCH, 48, 24)

func get_town_cell_rect(row_index: int) -> Rect2:
	return Rect2(556, 180 + row_index * HERO_ROW_PITCH, 48, 24)

## Movement bar frame for a hero's movement points (heroes.exe 0x9b8d8). The
## bar is absolute, not a share of the hero's own maximum: f = 22 MP / 60,
## truncated, so 60 MP fills its 22 px and a slow army's 40 MP shows 14. Past
## the full bar the crosses (frames 23-25) start at f 24, 27 and 31, which is
## 63, 74 and 85 MP (adventure-screen.md, checked against DOS saves).
static func mobility_frame(move_points: int) -> int:
	var f := maxi(0, move_points * MOBILITY_MAX / Hero.MAX_MOVE)
	if f > 30:
		return 25
	if f > 26:
		return 24
	return mini(f, 23)

## The red click-selection frame (kind 1 hero, 2 town) replaces the black line
## 4 px outside the portrait, leaving the slot's gold bevel inside it
## (campaign 1 recording at 3x, 2026-10-12).
static func selection_frame_rect(kind: int, row_index: int) -> Rect2:
	var x := 484.0 if kind == 1 else 556.0
	return Rect2(x - 4.0, 176.0 + row_index * HERO_ROW_PITCH, 56.0, 32.0)

func _init() -> void:
	# 4 Hero clippers
	for i in 4:
		var cell_rect := get_hero_cell_rect(i)
		var row := {}
		
		row.clipper = Control.new()
		row.clipper.position = cell_rect.position
		row.clipper.size = cell_rect.size
		row.clipper.clip_contents = true
		row.clipper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row.clipper)

		row.port_bg = TextureRect.new()
		row.port_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.port_bg.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		row.port_bg.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		row.port_bg.position = Vector2.ZERO
		row.port_bg.size = cell_rect.size
		row.port_bg.texture = UiKit.load_texture(PORT_BG_FLIPPED)
		row.clipper.add_child(row.port_bg)

		row.mobility_rect = TextureRect.new()
		row.mobility_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.mobility_rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		row.mobility_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		row.clipper.add_child(row.mobility_rect)

		row.portrait_rect = TextureRect.new()
		row.portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.portrait_rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		row.portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		row.clipper.add_child(row.portrait_rect)
		
		_rows.append(row)

	# 4 Town clippers
	for i in 4:
		var cell_rect := get_town_cell_rect(i)
		var t_row := {}
		t_row.clipper = Control.new()
		t_row.clipper.position = cell_rect.position
		t_row.clipper.size = cell_rect.size
		t_row.clipper.clip_contents = true
		t_row.clipper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(t_row.clipper)

		t_row.rect = TextureRect.new()
		t_row.rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t_row.rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		t_row.rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		t_row.clipper.add_child(t_row.rect)

		_town_rows.append(t_row)

	_town_clipper = _town_rows[0].clipper
	_town_rect = _town_rows[0].rect

static var _miniport_cache: Dictionary = {}
static var _town_locator_cache: Dictionary = {}
static var _mobility_cache: Dictionary = {}
static var _thumb_cache: Texture2D = null

static func get_miniport_texture(idx: int) -> Texture2D:
	if not _miniport_cache.has(idx):
		_miniport_cache[idx] = UiKit.load_texture(MINIPORT % idx)
	return _miniport_cache[idx]

static func get_town_locator_texture(sprite_id: int) -> Texture2D:
	if not _town_locator_cache.has(sprite_id):
		_town_locator_cache[sprite_id] = UiKit.load_texture(TOWN_LOCATOR % sprite_id)
	return _town_locator_cache[sprite_id]

static func get_mobility_texture(frame: int) -> Texture2D:
	if not _mobility_cache.has(frame):
		_mobility_cache[frame] = UiKit.load_texture(MOBILITY % frame)
	return _mobility_cache[frame]

static func get_thumb_texture() -> Texture2D:
	if _thumb_cache == null and ResourceLoader.exists(SCROLL_THUMB):
		_thumb_cache = UiKit.load_texture(SCROLL_THUMB)
	return _thumb_cache

var _last_town_sig: Array = []
var _last_hero_sig: Array = []

func _calc_town_sig() -> Array:
	if _player == null:
		return []
	var sig := [_player.owns_town, _player.active_town, _player.towns.size()]
	if _player.town != null:
		sig.append(_player.town.town_type)
		sig.append(_player.town.has_castle)
	for t: TownModel in _player.towns:
		sig.append(t.town_type)
		sig.append(t.has_castle)
	return sig

func _calc_hero_sig() -> Array:
	if _player == null:
		return []
	var displayed_heroes: Array = _held_heroes if not _held_heroes.is_empty() else _player.heroes
	var displayed_active := _held_active if not _held_heroes.is_empty() else _player.active_hero
	var nodes: Array = _heroes_nodes_fn.call() \
			if _held_heroes.is_empty() and _heroes_nodes_fn is Callable else []
	var sig := [displayed_heroes.size(), displayed_active, _selected]
	for idx in displayed_heroes.size():
		var h_model: HeroModel = displayed_heroes[idx]
		var h_node: Hero = nodes[idx] if idx < nodes.size() else null
		sig.append(h_model.portrait_idx)
		if h_node != null:
			sig.append(h_node.move_points)
			sig.append(h_node.tile)
			sig.append(h_node.travel_mode)
		else:
			sig.append(h_model.move_points)
	return sig


func setup(_rect: Rect2, player: PlayerState, heroes_nodes_fn: Variant, town_type: int, has_town: bool) -> void:
	_player = player
	_heroes_nodes_fn = heroes_nodes_fn
	var owns := has_town
	var t_type := town_type
	var castle := true
	if _player != null and not _player.towns.is_empty() and _player.town != null:
		owns = _player.owns_town
		t_type = _player.town.town_type
		castle = _player.town.has_castle
	_update_town_icon(t_type, owns, castle)

	# Original highlights the active hero from game start, not first click.
	if _selected == 0 and _player != null and not _player.heroes.is_empty():
		_selected = 1

	_last_town_sig.clear()
	_last_hero_sig.clear()
	refresh(true)

func _update_town_icon(town_type: int, has_town: bool, has_castle: bool = true) -> void:
	if not has_town:
		_town_tex = null
		for t_row: Dictionary in _town_rows:
			t_row.rect.texture = null
			t_row.rect.size = Vector2.ZERO
		return
	var sprite_id := BuildingCatalog.locator_sprite_id(town_type, has_castle)
	_town_tex = get_town_locator_texture(sprite_id)
	if not _town_rows.is_empty():
		_town_rows[0].rect.texture = _town_tex
		if _town_tex != null:
			var tw := float(_town_tex.get_width())
			var th := float(_town_tex.get_height())
			_town_rows[0].rect.position = (TOWN_CELL.size - Vector2(tw, th)) * 0.5
			_town_rows[0].rect.size = Vector2(tw, th)
		else:
			_town_rows[0].rect.size = Vector2.ZERO

func refresh(force: bool = false) -> bool:
	if _player == null:
		return false

	var town_sig := _calc_town_sig()
	var hero_sig := _calc_hero_sig()
	if not force and town_sig == _last_town_sig and hero_sig == _last_hero_sig:
		return false
	_last_town_sig = town_sig
	_last_hero_sig = hero_sig

	# Update town rows
	if not _player.towns.is_empty() and _player.town != null:
		var active_t: int = _player.active_town
		if active_t != _shown_active_town:
			_shown_active_town = active_t
			if active_t < _town_scroll:
				_town_scroll = active_t
			elif active_t >= _town_scroll + 4:
				_town_scroll = active_t - 3
		_town_scroll = clamp(_town_scroll, 0, max(0, _player.towns.size() - 4))

		_town_tex = null
		for i in 4:
			var t_row: Dictionary = _town_rows[i]
			var idx: int = _town_scroll + i
			if idx < _player.towns.size():
				var t_model: TownModel = _player.towns[idx]
				var sprite_id := BuildingCatalog.locator_sprite_id(t_model.town_type, t_model.has_castle)
				var tex := get_town_locator_texture(sprite_id)
				t_row.rect.texture = tex
				if idx == _player.active_town:
					_town_tex = tex
				if tex != null:
					var tw := float(tex.get_width())
					var th := float(tex.get_height())
					t_row.rect.position = (get_town_cell_rect(i).size - Vector2(tw, th)) * 0.5
					t_row.rect.size = Vector2(tw, th)
				else:
					t_row.rect.size = Vector2.ZERO
				t_row.clipper.visible = true
			else:
				t_row.rect.texture = null
				t_row.rect.size = Vector2.ZERO
				t_row.clipper.visible = false
		if _town_tex == null and not _player.towns.is_empty() and _town_rows[0].rect.texture != null:
			_town_tex = _town_rows[0].rect.texture
	elif not _player.owns_town:
		_town_tex = null
		for i in 4:
			_town_rows[i].clipper.visible = false
			_town_rows[i].rect.texture = null
			_town_rows[i].rect.size = Vector2.ZERO
	else:
		# Player owns town but towns array is empty (e.g. lightweight test mock or legacy setup)
		if _town_tex != null:
			_town_rows[0].rect.texture = _town_tex
			var tw := float(_town_tex.get_width())
			var th := float(_town_tex.get_height())
			_town_rows[0].rect.position = (TOWN_CELL.size - Vector2(tw, th)) * 0.5
			_town_rows[0].rect.size = Vector2(tw, th)
			_town_rows[0].clipper.visible = true
			for i in range(1, 4):
				_town_rows[i].clipper.visible = false
				_town_rows[i].rect.texture = null
				_town_rows[i].rect.size = Vector2.ZERO

	var displayed_heroes: Array = _held_heroes if not _held_heroes.is_empty() else _player.heroes
	var displayed_active := _held_active if not _held_heroes.is_empty() else _player.active_hero
	
	# Scroll tracking: keep active_hero in view
	var active: int = displayed_active
	if active != _shown_active:
		_shown_active = active
		if active < _scroll:
			_scroll = active
		elif active >= _scroll + 4:
			_scroll = active - 3
	_scroll = clamp(_scroll, 0, max(0, displayed_heroes.size() - 4))
	_hero_count = displayed_heroes.size()
	_town_count = _player.towns.size()
	
	var nodes: Array = _heroes_nodes_fn.call() \
			if _held_heroes.is_empty() and _heroes_nodes_fn is Callable else []
	
	for i in 4:
		var row: Dictionary = _rows[i]
		var idx: int = _scroll + i
		if idx < displayed_heroes.size():
			var h_model: HeroModel = displayed_heroes[idx]
			var tex := get_miniport_texture(h_model.portrait_idx)
			row.portrait_rect.texture = tex
			
			var pw := 32.0
			var ph := 22.0
			if tex != null:
				pw = float(tex.get_width())
				ph = float(tex.get_height())
			row.portrait_rect.position = (get_hero_cell_rect(i).size - Vector2(pw, ph)) * 0.5
			row.portrait_rect.size = Vector2(pw, ph)
			
			var h_node: Hero = null
			if idx < nodes.size():
				h_node = nodes[idx]
			
			var move_pts: int = 0
			var has_movement: bool = false
			if h_node != null:
				move_pts = h_node.move_points
				has_movement = h_node.has_enough_movement_to_move()
			else:
				move_pts = h_model.move_points
				has_movement = move_pts >= 4
			
			var frame: int = mobility_frame(move_pts) if has_movement else 0
			var mob_tex: Texture2D = get_mobility_texture(frame)
			row.mobility_rect.texture = mob_tex
			if mob_tex != null and frame > 0:
				var bw := float(mob_tex.get_width())
				var bh := float(mob_tex.get_height())
				row.mobility_rect.position = Vector2(MOBILITY_LOCAL_X, get_hero_cell_rect(i).size.y - 1 - bh)
				row.mobility_rect.size = Vector2(bw, bh)
				row.mobility_rect.visible = true
			else:
				row.mobility_rect.visible = false
			
			row.clipper.visible = true
		else:
			row.clipper.visible = false
	
	queue_redraw()
	return true

func hero_row_count() -> int:
	if not _held_heroes.is_empty():
		return _held_heroes.size()
	return _player.heroes.size() if _player != null else 0

func town_row_count() -> int:
	if _player != null and not _player.towns.is_empty() and _player.owns_town:
		return _player.towns.size()
	return 1 if _town_tex != null else 0

## Keep the pre-defeat roster painted while the KILLFADE cue plays. Gameplay
## state may remove the HeroModel immediately, but the original UI retains its
## portrait until the disappearance sound has completed.
func hold_hero_models(models: Array, active_index: int) -> void:
	_held_heroes = models.duplicate()
	_held_active = clampi(active_index, 0, maxi(0, _held_heroes.size() - 1))
	if not _held_heroes.is_empty():
		_selected = 1
	refresh()

func release_held_hero_models() -> void:
	_held_heroes.clear()
	_held_active = -1
	if _player == null or _player.heroes.is_empty():
		_selected = 0
	refresh()

func select_row(idx: int) -> void:
	if _player != null and idx >= 0 and idx < _player.heroes.size():
		_player.active_hero = idx
		hero_selected.emit(idx)
		_set_selected(1)
		refresh()

func select_town_row(idx: int) -> void:
	if _player != null and idx >= 0 and idx < _player.towns.size():
		_player.active_town = idx
		_set_selected(2)
		refresh()
		town_selected.emit()
	else:
		_set_selected(2)
		refresh()
		town_selected.emit()

func _open_town(game: Node) -> void:
	if game == null:
		return
	if "prefer_active_town" in game:
		game.prefer_active_town = true
	game.to_town()

## Which list's arrow-and-track strip holds the point: 1 hero, 2 town, 0 none.
static func strip_at(point: Vector2) -> int:
	if point.y < STRIP_TOP or point.y >= STRIP_BOTTOM:
		return 0
	for i in 2:
		if point.x >= STRIP_X[i] and point.x < STRIP_X[i] + STRIP_W:
			return i + 1
	return 0

func _list_count(list: int) -> int:
	return hero_row_count() if list == 1 else _player.towns.size() if _player != null else 0

func _scroll_list(list: int, value: int) -> void:
	value = clampi(value, 0, maxi(0, _list_count(list) - 4))
	if list == 1:
		_scroll = value
	else:
		_town_scroll = value
	refresh(true)

## Arrow strip press: step one row, or jump the thumb's centre to a track spot.
func _press_strip(list: int, y: float) -> void:
	var scroll := _scroll if list == 1 else _town_scroll
	if y < STRIP_TOP + ARROW_H:
		_scroll_list(list, scroll - 1)
	elif y >= STRIP_BOTTOM - ARROW_H:
		_scroll_list(list, scroll + 1)
	else:
		_dragging_list = list
		_drag_track(list, y)

func _drag_track(list: int, y: float) -> void:
	var travel := float(TRACK_BOTTOM - TRACK_TOP + 1 - 17)
	var max_scroll := maxi(0, _list_count(list) - 4)
	_scroll_list(list, roundi(clampf((y - TRACK_TOP - 8.5) / travel, 0.0, 1.0) * max_scroll))

## Claim input ONLY on the portrait cells, town cells and the two scroll strips.
func _has_point(point: Vector2) -> bool:
	if strip_at(point) != 0:
		return true
	var visible_count: int = 1
	if not _held_heroes.is_empty():
		visible_count = int(min(4, _held_heroes.size()))
	elif _player != null:
		visible_count = int(min(4, _player.heroes.size()))
	for i in visible_count:
		if get_hero_cell_rect(i).has_point(point):
			return true

	if _player != null and not _player.towns.is_empty() and _player.owns_town:
		var visible_town_count: int = int(min(4, _player.towns.size()))
		for i in visible_town_count:
			if get_town_cell_rect(i).has_point(point):
				return true
	elif _town_tex != null and TOWN_CELL.has_point(point):
		return true

	return false

func _gui_input(event: InputEvent) -> void:
	# The control that took the press keeps the motion, so a drag may leave the track.
	if event is InputEventMouseMotion and _dragging_list != 0:
		accept_event()
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_drag_track(_dragging_list, event.position.y)
		else:
			_dragging_list = 0
		return
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging_list = 0
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var list := strip_at(event.position)
		if list != 0:
			accept_event()
			if _player != null:
				_press_strip(list, event.position.y)
			return
		var game = Engine.get_main_loop().root.get_node_or_null("Game")
		# The held portrait is visual-only; the defeated model has already left
		# gameplay and must not be selectable during the brief sound tail.
		if not _held_heroes.is_empty():
			for i in mini(4, _held_heroes.size()):
				if get_hero_cell_rect(i).has_point(event.position):
					accept_event()
					return
		if _player != null:
			var visible_count: int = int(min(4, _player.heroes.size()))
			for i in visible_count:
				var hero_rect := get_hero_cell_rect(i)
				if hero_rect.has_point(event.position):
					accept_event()
					var idx: int = _scroll + i
					if i == 0 and _scroll > 0 and event.position.y < hero_rect.get_center().y:
						_scroll_list(1, _scroll - 1)
						return
					elif i == 3 and _scroll + 4 < _player.heroes.size() and event.position.y > hero_rect.get_center().y:
						_scroll_list(1, _scroll + 1)
						return
					var was_selected := (_selected == 1 and _player != null and _player.active_hero == idx)
					select_row(idx)
					if (event.double_click or was_selected) and game != null:
						game.to_hero(_player.heroes[idx])
					return

		if _player != null and not _player.towns.is_empty() and _player.owns_town:
			var visible_town_count: int = int(min(4, _player.towns.size()))
			for i in visible_town_count:
				var town_rect := get_town_cell_rect(i)
				if town_rect.has_point(event.position):
					accept_event()
					var idx: int = _town_scroll + i
					if i == 0 and _town_scroll > 0 and event.position.y < town_rect.get_center().y:
						_scroll_list(2, _town_scroll - 1)
						return
					elif i == 3 and _town_scroll + 4 < _player.towns.size() and event.position.y > town_rect.get_center().y:
						_scroll_list(2, _town_scroll + 1)
						return
					var was_selected := (_selected == 2 and _player.active_town == idx)
					select_town_row(idx)
					if (event.double_click or was_selected) and game != null:
						_open_town(game)
					return
		elif TOWN_CELL.has_point(event.position) and _town_tex != null:
			accept_event()
			var was_selected := (_selected == 2)
			_set_selected(2)
			town_selected.emit()
			if (event.double_click or was_selected) and game != null:
				_open_town(game)
			return

func get_selected_kind() -> int:
	return _selected

func set_selected_kind(which: int) -> void:
	_set_selected(which)

func _set_selected(which: int) -> void:
	if _selected == which:
		return
	_selected = which
	queue_redraw()

## Top of a list's scrollbar thumb. A list that fits leaves it centred in the
## track: y 232 on both lists, with one hero and one town or with two heroes and
## three towns (campaign 1 recording, 2026-10-12). A longer list spreads it
## over the track by scroll position; that case is not in the recording.
static func scroll_thumb_y(count: int, scroll: int) -> int:
	var travel := TRACK_BOTTOM - TRACK_TOP + 1 - 17
	var max_scroll := maxi(0, count - 4)
	if max_scroll == 0:
		return TRACK_TOP + ceili(travel / 2.0)
	return TRACK_TOP + roundi(float(travel) * clampi(scroll, 0, max_scroll) / max_scroll)

## Scrollbar thumbs, then the red click-selection frame around the picked cell
func _draw() -> void:
	if _thumb_tex == null:
		_thumb_tex = get_thumb_texture()
	if _thumb_tex != null:
		for r: Rect2 in BAKED_THUMBS:
			draw_rect(r, Color.BLACK)
		draw_texture(_thumb_tex, Vector2(THUMB_X[0], scroll_thumb_y(_hero_count, _scroll)))
		draw_texture(_thumb_tex, Vector2(THUMB_X[1], scroll_thumb_y(_town_count, _town_scroll)))
	if _selected == 1:
		var active := _held_active if not _held_heroes.is_empty() \
				else _player.active_hero if _player != null else -1
		if active >= _scroll and active < _scroll + 4:
			var row_idx: int = active - _scroll
			_draw_frame(selection_frame_rect(1, row_idx))
	elif _selected == 2:
		var active_t: int = _player.active_town if _player != null and not _player.towns.is_empty() else 0
		if active_t >= _town_scroll and active_t < _town_scroll + 4:
			var row_idx: int = active_t - _town_scroll
			_draw_frame(selection_frame_rect(2, row_idx))

## A 1 px outline on the rect's own outer pixels.
func _draw_frame(r: Rect2) -> void:
	draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), HILITE_COLOR)
	draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(r.size.x, 1)), HILITE_COLOR)
	draw_rect(Rect2(r.position, Vector2(1, r.size.y)), HILITE_COLOR)
	draw_rect(Rect2(r.position + Vector2(r.size.x - 1, 0), Vector2(1, r.size.y)), HILITE_COLOR)
