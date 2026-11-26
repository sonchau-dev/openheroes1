class_name AdventureInputController
extends Node

## Adventure-map pointer input: click-to-move with HOMM1 two-click confirm,
## route-arrow preview, adventure cursors, and edge-scroll direction.
## Movement execution stays on the scene root (path_confirmed signal).

signal hero_band_clicked
signal end_turn_requested
signal pan_requested(delta: Vector2)
signal spellbook_requested
signal puzzle_map_requested
signal dig_requested
signal campaign_info_requested
signal view_world_requested
signal kingdom_overview_requested
signal next_town_requested
signal next_hero_requested
signal adventure_options_requested
signal system_menu_requested
signal save_game_requested
signal load_game_requested
signal leave_game_requested(action: String)
signal open_selected_requested
signal path_confirmed(path: Array)
signal stop_hero_requested
signal route_changed
signal town_selected(town: TownObject)
signal town_double_clicked(town: TownObject)
signal hero_double_clicked
signal hero_selected

signal inspect_requested(screen_pos: Vector2, world_pos: Vector2)
signal inspect_dismissed

signal cheat_reveal_map_requested

## On-screen rect of the map viewport (the bord.png left cutout). Clicks outside it
## (right panel, buttons, border) are never treated as move commands.
const MAP_VIEW_RECT := Rect2(16, 16, 448, 448)

## Adventure cursors (advmice.icn): 0 pointer, 1 sunclock, 2 helmet, 3 castle,
## 4 move, 5 attack, 6 boat, 7 anchor, 8 meet, 9 interact, 28-31 red boat.
const ADVMICE := "res://assets/art/advmice/%04d.png"
const CUR_POINT := 0
const CUR_SUNCLOCK := 1
const CUR_HERO := 2
const CUR_CASTLE := 3
const CUR_MOVE := 4
const CUR_ATTACK := 5
## Frame 6 is the boat: board a boat ashore, sail to a water tile at sea.
const CUR_BOARD := 6
## Frame 7 is the anchor: a sailing hero lands on the shore.
const CUR_ANCHOR := 7
const CUR_MEET := 8
const CUR_INTERACT := 9
## Frames 28-31 are the red boat for a buoy or whirlpool; unlike the other
## cursors they carry the day count as `28 + k`, not `base + 6 x k`.
const CUR_RED_BOAT := 28

## The hot spots the original's advmice.mse gives the plain frames
## (data/knowledge_base/adventure-screen.md 7.2). The day-badge frames
## (10..27) keep the hot spot of the plain frame they are built from.
const CURSOR_HOTSPOTS := {
	0: Vector2(2, 3),    # gauntlet pointer
	1: Vector2(2, 3),    # gold sun clock
	2: Vector2(12, 11),  # helmet (one of your heroes)
	3: Vector2(12, 13),  # castle
	4: Vector2(15, 11),  # horse (move)
	5: Vector2(10, 10),  # sword (attack)
	6: Vector2(12, 13),  # boat
	7: Vector2(9, 12),   # anchor
	8: Vector2(7, 9),    # two arrows (meet one of your own heroes)
	9: Vector2(15, 15),  # rearing horse (visit)
}

## Authentic route arrows (route.icn): green set 14-27, red = green-14.
## Sprite selection lives in RouteArrows (see route_arrows.gd).
const ROUTE := "res://assets/art/route/"

var _map: MapData
var _hero: Hero
var _astar: PassabilityGrid
var _ai_hero_fn: Callable
var _ai_running_fn: Callable
## Width in viewport pixels of the edge-scroll band for a finger (a mouse uses 32):
## 16 px of border plus three quarters of a tile of map, so objects in the outer
## visible column stay easy to touch.
const TOUCH_EDGE_MARGIN := 40.0
## The status panel column. A finger down on it presses a HUD button (the system
## disk sits in its bottom corner) and must never turn into an edge scroll.
const TOUCH_HUD_RECT := Rect2(480, 0, 160, 480)
## Inside the frame the screen's right scroll band is only the panel's 16 px
## right border, which holds no button. Past the frame it is as wide as the rest.
const TOUCH_HUD_RIGHT_BAND := 16.0
## Width of the scroll band along the map view's right side, just left of the panel.
## The same width as the other edges, measured from the panel.
const TOUCH_MAP_RIGHT_BAND := TOUCH_EDGE_MARGIN
var _edge_blocked_fn: Callable
var _other_heroes_tiles_fn: Callable
var _boat_tile_at_world_fn: Callable
var _state_fn: Callable
var _selected_kind_fn: Callable

var _pending_dest: Vector2i = Vector2i(-1, -1)
var _pending_path: Array = []
var _path_arrows: Array = []
var _arrow_pool: Array[Sprite2D] = []
static var _route_texture_cache: Dictionary = {}
var _route_parent: Node2D
var _cursor_cache: Dictionary = {}
var _cur_id: int = -1
var _last_hover_dest: Vector2i = Vector2i(-1, -1)
var _last_hover_hero_tile: Vector2i = Vector2i(-1, -1)
var _route_field: Dictionary = {}
var _route_field_key := ""
## The acting human's fog; null (tests, tools) routes as if all is explored.
var fog: FogLayer
## `--trace-pathfinding` (src/tools/pathfinding_trace.gd), else null.
var _trace = null
var _inspecting := false
var _cheat_buffer: int = 0
## True while the map ignores input (the engage hold before a battle).
var _input_blocked := false
const CHEAT_MODULO := 1000000

func get_cheat_buffer() -> int:
	return _cheat_buffer

func reset_cheat_buffer() -> void:
	_cheat_buffer = 0

## heroes.exe keeps the last six digits typed on the adventure map (data
## 0x3ff5c, x10 mod 1000000) and checks them against one code only: 101495
## reveals the map (file 0x96101). No other digit code exists in the binary.
func _process_cheat_digit(digit: int) -> void:
	_cheat_buffer = ((_cheat_buffer * 10) % CHEAT_MODULO) + digit
	if _cheat_buffer == 101495:
		_cheat_buffer = 0
		cheat_reveal_map_requested.emit()

func _blocked_heroes_dict() -> Dictionary:
	var blocked := {}
	if _other_heroes_tiles_fn.is_valid():
		var tiles: Array = _other_heroes_tiles_fn.call()
		for t in tiles:
			if t is Vector2i:
				blocked[t] = true
	return blocked

func _route_field_land_key(from: Vector2i, blocked: Dictionary) -> String:
	var dyn_sig := _astar.dynamic_solid_signature() if _astar != null and _astar.has_dynamic_solids() else ""
	var rev := _astar.guard_revision() if _astar != null else 0
	if blocked.is_empty() and dyn_sig == "":
		return "%d,%d:%s:%d" % [from.x, from.y, _hero.hero_class, rev]
	var parts: PackedStringArray = []
	var tiles: Array = blocked.keys()
	if tiles.size() > 1:
		tiles.sort_custom(func(a: Vector2i, b: Vector2i):
			return a.y < b.y or (a.y == b.y and a.x < b.x))
	for t: Vector2i in tiles:
		parts.append("%d,%d" % [t.x, t.y])
	return "%d,%d:%s:%s:%s:%d" % [from.x, from.y, _hero.hero_class, ";".join(parts), dyn_sig, rev]

func _find_path(from: Vector2i, to: Vector2i) -> Array:
	var state: GameState = _state_fn.call() if _state_fn.is_valid() else null
	var seen := fog.explored_cells() if fog != null else PackedByteArray()
	if _hero != null and _hero.travel_mode == &"land" and _map.is_land(to) \
			and (state == null or state.boat_at(to) == null):
		var target_guard := _astar.action_object_at(to) as NeutralStack
		if target_guard == null or not target_guard.is_armed():
			var blocked := _blocked_heroes_dict()
			# Explored cells only grow, so their count tells one fog from the next.
			var key := "%s:%d" % [_route_field_land_key(from, blocked), seen.count(1)]
			if key != _route_field_key:
				_route_field = Pathfinder.build_land_field(
						_astar, from, _hero.hero_class, -1, -1, null, -1, {},
						Vector2i(-1, -1), blocked, false, seen)
				_route_field_key = key
			return Pathfinder.path_from_field(_route_field, to)
	if _hero != null and state != null and _hero.travel_mode == &"sea":
		return _find_sea_path(from, to, state, seen)
	if _hero == null or state == null:
		return Pathfinder.find(_astar, from, to, _map,
				_hero.hero_class if _hero != null else "",
				_hero.move_points if _hero != null else -1,
				_hero.max_move_points if _hero != null else -1, seen)
	return Pathfinder.find_for(_astar, from, to, _map, state,
			_hero.travel_mode, _hero.hero_class,
			_hero.move_points, _hero.max_move_points, seen)

## A hero at sea shares one cheapest-route field across hover updates, as the
## land branch above does; searching afresh per hovered tile took about a
## second on a 72x72 sea map.
func _find_sea_path(from: Vector2i, to: Vector2i, state: GameState,
		seen: PackedByteArray = PackedByteArray()) -> Array:
	var boats := {}
	var boat_parts: PackedStringArray = []
	for boat: BoatState in state.boats:
		boats[boat.tile] = true
		boat_parts.append("%d,%d" % [boat.tile.x, boat.tile.y])
	var heroes := state.hero_tiles()
	heroes.erase(from)
	var hero_parts: PackedStringArray = []
	for tile: Vector2i in heroes:
		hero_parts.append("%d,%d" % [tile.x, tile.y])
	var dyn_sig := _astar.dynamic_solid_signature() if _astar != null and _astar.has_dynamic_solids() else ""
	var key := "sea:%d,%d:%s:%s:%s:%s:%d" % [from.x, from.y, _hero.hero_class,
			dyn_sig, ";".join(boat_parts),
			";".join(hero_parts), seen.count(1)]
	if key != _route_field_key:
		_route_field = Pathfinder.build_sea_field(_astar, from,
				_hero.hero_class, -1, boats, heroes, seen)
		_route_field_key = key
	return Pathfinder.path_from_field(_route_field, to)

func _step_cost(from: Vector2i, to: Vector2i) -> int:
	var state: GameState = _state_fn.call() if _state_fn.is_valid() else null
	if _hero == null or state == null:
		return Hero.step_cost(from, to, _map, false,
				_hero.hero_class if _hero != null else "")
	var kind := TravelRules.step_kind(_map, _astar, state,
			_hero.travel_mode, from, to)
	return TravelRules.step_cost(kind, from, to, _map, _hero.hero_class)

func _straight_step_cost(from: Vector2i) -> int:
	return Hero.step_cost(from, from + Vector2i.RIGHT, _map,
			_hero != null and _hero.travel_mode == &"sea",
			_hero.hero_class if _hero != null else "")

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return screen_pos
	return vp.get_canvas_transform().affine_inverse() * screen_pos

func _global_mouse_position() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2.ZERO
	return _screen_to_world(Pointer.position(vp))

func _destination_at_world(world: Vector2) -> Vector2i:
	if _boat_tile_at_world_fn.is_valid():
		var picked: Variant = _boat_tile_at_world_fn.call(world)
		if picked is Vector2i and picked != Vector2i(-1, -1):
			return picked
	return Vector2i(int(world.x) / _map.tile_size, int(world.y) / _map.tile_size)

## The route ends by boarding a boat. The boat cursor shows however many days
## the route takes; its day badge says how many (adventure-screen.md 7.2).
func _can_show_board_cursor(dest: Vector2i, path: Array) -> bool:
	if _hero == null or _hero.travel_mode != &"land" or path.size() < 2:
		return false
	var state: GameState = _state_fn.call() if _state_fn.is_valid() else null
	if state == null or state.boat_at(dest) == null:
		return false
	for i in range(1, path.size()):
		var kind := TravelRules.step_kind(_map, _astar, state,
				_hero.travel_mode, path[i - 1], path[i])
		if kind == TravelRules.INVALID:
			return false
		if kind == TravelRules.BOARD:
			return i == path.size() - 1
	return false

func setup(map: MapData, hero: Hero, astar: PassabilityGrid,
		ai_hero_fn: Callable, ai_running_fn: Callable, edge_blocked_fn: Callable,
		other_heroes_tiles_fn: Callable = Callable(),
		boat_tile_at_world_fn: Callable = Callable(),
		state_fn: Callable = Callable(), route_parent: Node2D = null,
		selected_kind_fn: Callable = Callable()) -> void:
	_map = map
	_hero = hero
	_astar = astar
	_ai_hero_fn = ai_hero_fn
	_ai_running_fn = ai_running_fn
	_edge_blocked_fn = edge_blocked_fn
	_other_heroes_tiles_fn = other_heroes_tiles_fn
	_boat_tile_at_world_fn = boat_tile_at_world_fn
	_state_fn = state_fn
	_route_parent = route_parent
	_selected_kind_fn = selected_kind_fn
	_trace = DevFlags.tool("res://src/tools/pathfinding_trace.gd", ["--trace-pathfinding"])
	if _ai_running_fn.is_valid() and _ai_running_fn.call():
		show_sunclock_cursor()

## Block map input: clicks, keys and the HUD's move button are ignored. Used
## for the engage hold, where the fight is decided and the hero must not
## move out of the shot before the battle screen takes over.
func block_input() -> void:
	_input_blocked = true
	set_process_unhandled_input(false)

func unblock_input() -> void:
	_input_blocked = false
	set_process_unhandled_input(true)

func is_input_blocked() -> bool:
	return _input_blocked

## Re-point pathfinding/cursor logic at a newly-activated hero (Stage-5
## switching). Without this the controller keeps routing from the OLD hero.
func update_hero(h: Hero) -> void:
	_hero = h
	_invalidate_route_field()
	refresh_path()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		cancel_inspect()

func cancel_inspect() -> void:
	if _inspecting:
		_inspecting = false
		inspect_dismissed.emit()

## Mark the event used. The HUD is an earlier sibling, so it sees unhandled input
## after us: a move that collects a pile beside the hero opens the resource popup
## mid-event, and an unconsumed press would reach the popup and close it at once.
func _consume() -> void:
	if is_inside_tree() and get_viewport() != null:
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if _input_blocked:
		return
	if _ai_running_fn.is_valid() and _ai_running_fn.call():
		return
	# Any mouse button click or key press while hero is moving cancels remaining
	# movement and halts the hero at the next tile (heroes.exe 0x93039).
	if _hero != null and _hero.is_moving():
		if (event is InputEventKey and event.pressed and not event.echo) \
				or (event is InputEventMouseButton and event.pressed) \
				or (event is InputEventScreenTouch and event.pressed):
			stop_hero_requested.emit()
			_consume()
			return
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE and _inspecting:
			cancel_inspect()
			return
		if _edge_blocked_fn.is_valid() and _edge_blocked_fn.call():
			return
	if event is InputEventKey and event.pressed and not event.echo:
		var delta := Vector2i.ZERO
		match event.keycode:
			KEY_LEFT, KEY_KP_4: delta = Vector2i.LEFT
			KEY_RIGHT, KEY_KP_6: delta = Vector2i.RIGHT
			KEY_UP, KEY_KP_8: delta = Vector2i.UP
			KEY_DOWN, KEY_KP_2: delta = Vector2i.DOWN
			KEY_KP_7, KEY_HOME: delta = Vector2i(-1, -1)
			KEY_KP_9, KEY_PAGEUP: delta = Vector2i(1, -1)
			KEY_KP_1, KEY_END: delta = Vector2i(-1, 1)
			KEY_KP_3, KEY_PAGEDOWN: delta = Vector2i(1, 1)
		if delta != Vector2i.ZERO:
			if event.ctrl_pressed:
				pan_requested.emit(Vector2(delta) * 32.0)
			elif _hero != null and not _hero.is_moving():
				var dest := _hero.tile + delta
				var path := _find_path(_hero.tile, dest)
				if path.size() == 2:
					cancel_route()
					_consume()
					path_confirmed.emit(path)
			return
		if event.keycode == KEY_E:
			end_turn_requested.emit()
			return
		if event.keycode == KEY_M:
			_consume()
			commit_pending()
			return
		if event.keycode in [KEY_H, KEY_TAB]:
			next_hero_requested.emit()
			return
		if event.keycode >= KEY_0 and event.keycode <= KEY_9:
			_process_cheat_digit(event.keycode - KEY_0)
			return
	if event is InputEventKey and event.pressed and event.keycode == KEY_C:
		spellbook_requested.emit()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_P:
		puzzle_map_requested.emit()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_D:
		dig_requested.emit()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_I:
		campaign_info_requested.emit()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_V:
		view_world_requested.emit()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_K:
		kingdom_overview_requested.emit()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_T:
		next_town_requested.emit()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_A:
		adventure_options_requested.emit()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_G:
		system_menu_requested.emit()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_S:
		save_game_requested.emit()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_L:
		load_game_requested.emit()
		return
	if event is InputEventKey and event.pressed and event.keycode in [KEY_N, KEY_Q]:
		leave_game_requested.emit("new_game" if event.keycode == KEY_N else "quit")
		return
	if event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		open_selected_requested.emit()
		return

	if event is InputEventMouseMotion:
		_update_cursor((event as InputEventMouseMotion).position)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if _edge_blocked_fn.is_valid() and _edge_blocked_fn.call():
				return
			if MAP_VIEW_RECT.has_point(mb.position):
				_inspecting = true
				inspect_requested.emit(mb.position, _global_mouse_position())
		else:
			_inspecting = false
			inspect_dismissed.emit()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _inspecting:
			cancel_inspect()
			return
		var mb := event as InputEventMouseButton
		var click_pos := mb.position
		if _edge_blocked_fn.is_valid() and _edge_blocked_fn.call():
			return
		if AdventureHud.HERO_BAND.has_point(click_pos):
			hero_band_clicked.emit()
			return
		if not MAP_VIEW_RECT.has_point(click_pos):
			return   # click was on the panel / buttons / border, not the map
		if _hero != null and _hero.is_moving():
			return   # heroless (dead, town held) or mid-walk: no move commands

		var world := _screen_to_world(click_pos)
		var dest := _destination_at_world(world)

		var state: GameState = _state_fn.call() if _state_fn.is_valid() else null
		var local_side := state.active_player_side if state != null else 0
		var town: TownObject = _map.town_at(dest) if _map != null else null
		if _enemy_hero_on(dest, state, local_side):
			town = null   # a hostile hero beside the gate is a target, not the town
		var is_friendly_town := (town != null and town.owner == local_side)
		var is_town_selected: bool = bool(_selected_kind_fn.call() == 2) if _selected_kind_fn.is_valid() else false
		var is_moving_to_town := (is_friendly_town and _hero != null and not is_town_selected \
				and dest == town.action_tile and _hero.tile != dest)

		if mb.double_click:
			if is_friendly_town and not is_moving_to_town:
				cancel_route()
				town_double_clicked.emit(town)
				return
			elif _hero != null and dest == _hero.tile:
				cancel_route()
				hero_double_clicked.emit()
				return

		if is_friendly_town and not is_moving_to_town:
			cancel_route()
			town_selected.emit(town)
			return

		if _hero == null:
			return

		if dest == _hero.tile:
			if _pending_dest != Vector2i(-1, -1):
				cancel_route()
				return
			var is_hero_selected := not is_town_selected
			cancel_route()
			if is_hero_selected:
				hero_double_clicked.emit()
			else:
				hero_selected.emit()
			return
		var path := _find_path(_hero.tile, dest)

		if path.size() < 2:
			cancel_route()
			return
		_consume()
		if (dest == _pending_dest and _hero.planned_dest == dest) or mb.double_click:
			# Second click on the same destination (or double-click): commit path.
			_pending_dest = dest
			_hero.planned_dest = dest
			_pending_path = path
			commit_pending()
		else:
			var g := _get_game()
			var show_path_on: bool = bool(g.show_path) if (g != null and "show_path" in g) else true
			if not show_path_on and not Input.is_key_pressed(KEY_CTRL):
				# 1-click movement when Show Path is disabled (unless Ctrl is held to trace path)
				_pending_dest = dest
				_hero.planned_dest = dest
				_pending_path = path
				commit_pending()
			else:
				# First click: show the route (green = reachable this turn, red = beyond).
				_pending_dest = dest
				_hero.planned_dest = dest
				_pending_path = path
				_trace_path_preview("click", path)
				draw_path(path)
				route_changed.emit()

## Pick the adventure cursor for the tile under the mouse.
func _update_cursor(screen_pos: Vector2) -> void:
	if _ai_running_fn.is_valid() and _ai_running_fn.call():
		_set_cursor(CUR_SUNCLOCK)
		return
	if not MAP_VIEW_RECT.has_point(screen_pos) or (_hero != null and _hero.is_moving()):
		_set_cursor(CUR_POINT)
		return
	var world := _screen_to_world(screen_pos)
	var dest := _destination_at_world(world)

	if _hero != null and dest == _last_hover_dest and _hero.tile == _last_hover_hero_tile:
		return
	_last_hover_dest = dest
	_last_hover_hero_tile = _hero.tile if _hero != null else Vector2i(-1, -1)

	# The selected hero's own tile wears the helmet (0x98e8b, rule 3).
	if _hero != null and dest == _hero.tile:
		_set_cursor(CUR_HERO)
		return
	var state: GameState = _state_fn.call() if _state_fn.is_valid() else null
	var local_side := state.active_player_side if state != null else 0
	# Another of our own heroes stands on the tile: heroes.exe shows the
	# two-arrows "meet" cursor there (advmice frame 8), whatever else is on
	# the cell - the hero case comes before the town and the general case
	# (0x98e8b, rule 8), and the manual calls the cursor "brings the 'active'
	# hero to him, ready to exchange troops and artifacts".
	if _friendly_hero_on(dest, state, local_side):
		var meet_path := _find_path(_hero.tile, dest) if _hero != null else []
		_set_cursor(CUR_MEET + 6 * _day_badge(meet_path))
		return
	var town: TownObject = _map.town_at(dest) if _map != null else null
	if _enemy_hero_on(dest, state, local_side):
		town = null
	if town != null and town.owner == local_side:
		var is_town_selected: bool = bool(_selected_kind_fn.call() == 2) if _selected_kind_fn.is_valid() else false
		# With no hero selected every cell of our castle shows the castle
		# (rule 2). With one, only a blocked cell between castle cells above
		# and below does (rule 4); other blocked cells show the pointer, and
		# the gate and open cells fall to the general rule, so a gate inside
		# a guard zone wears the sword.
		if _hero == null or is_town_selected:
			_set_cursor(CUR_CASTLE)
			return
		if _astar != null and _astar.entry_mask(dest) == 0:
			var between := _map.town_at(dest + Vector2i.UP) == town \
					and _map.town_at(dest + Vector2i.DOWN) == town
			_set_cursor(CUR_CASTLE if between else CUR_POINT)
			return

	if _hero == null:
		_set_cursor(CUR_POINT)
		return

	var path := _find_path(_hero.tile, dest)
	# Every land cursor from the horse to the rearing horse carries the day
	# badge: base frame + 6 x k (0x99387..0x993b9).
	var badge := 6 * _day_badge(path)

	# A hero at sea cannot attack a hero ashore (heroes.exe 0xa89f2).
	if _enemy_hero_on(dest, state, local_side) \
			and not (_hero.travel_mode == &"sea" and _map.is_land(dest)):
		_set_cursor(CUR_ATTACK + badge)
		return

	var blocked_tiles: Array = _other_heroes_tiles_fn.call() if _other_heroes_tiles_fn.is_valid() else []
	if path.size() < 2:
		_set_cursor(CUR_POINT)        # unreachable / off-grid
	elif _hero.travel_mode == &"sea":
		_set_cursor(_sea_destination_cursor_id(dest, path))
	elif _can_show_board_cursor(dest, path):
		_set_cursor(CUR_BOARD + badge)
	else:
		var id := _destination_cursor_id(dest, blocked_tiles)
		_set_cursor(id + badge if id != CUR_POINT else id)

## The computer's active hero or any hostile hero stands on `tile`.
func _enemy_hero_on(tile: Vector2i, state: GameState, local_side: int) -> bool:
	var ai_hero: Hero = _ai_hero_fn.call() if _ai_hero_fn.is_valid() else null
	return (ai_hero != null and tile == ai_hero.tile) or _hostile_hero_at(tile, state, local_side)

## Another hero of the player's own side stands on `tile`: the original shows
## the two-arrows "meet" cursor over it (advmice frame 8) and walks the
## 'active' hero up to that hero, which opens the exchange window.
func _friendly_hero_on(tile: Vector2i, state: GameState, local_side: int) -> bool:
	if state == null or _hero == null or tile == _hero.tile:
		return false
	var me := state.player_of(local_side)
	if me == null:
		return false
	for h: HeroModel in me.heroes:
		if h != null and h.tile == tile:
			return true
	return false

## The day badge the original puts on the cursor: k is 0 while the route costs
## no more than the movement the hero has left today, and
## min(3, (cost - left) / max + 1) otherwise. The cursor frame is the base
## frame plus 6 x k (heroes.exe 0x99387..0x993b9).
func _day_badge(path: Array) -> int:
	if _hero == null or path.size() < 2:
		return 0
	var cost := 0
	for i in range(1, path.size()):
		cost += _step_cost(path[i - 1], path[i])
	var left := _hero.move_points
	var per_day := _hero.max_move_points
	if cost <= left or per_day <= 0:
		return 0
	return mini(3, (cost - left) / per_day + 1)

## A hero of a hostile player stands on `tile` (computer or another seat).
func _hostile_hero_at(tile: Vector2i, state: GameState, local_side: int) -> bool:
	if state == null:
		return false
	var me := state.player_of(local_side)
	for p: PlayerState in state.players:
		if p.side == local_side or (me != null and not p.is_hostile_to(me)):
			continue
		for h: HeroModel in p.heroes:
			if h.tile == tile:
				return true
	return false

## Cursor for a reachable land destination after town/boat/enemy-hero special
## cases. Exact objects and friendly heroes keep their own interaction intent;
## otherwise a tile that will trigger a wandering monster advertises combat.
func _destination_cursor_id(dest: Vector2i, blocked_tiles: Array = []) -> int:
	var od := _map.active_object_at_action(dest)
	if od != null:
		var id := _object_cursor_id(od)
		# A cell a wandering monster GUARDS shows the sword: the hero has to
		# fight that stack before it can reach the object. The pickup classes
		# keep the visit horse even inside such a zone (heroes.exe 0x98e8b).
		# Our own hero parked on the entrance keeps it too: the original shows
		# its meet cursor (8) there, which we do not have.
		if id == CUR_INTERACT and not _pickup_cursor_class(od) \
				and dest not in blocked_tiles \
				and _astar != null and _astar.protecting_stack_at(dest) != null:
			return CUR_ATTACK
		return id
	if dest in blocked_tiles:
		return CUR_INTERACT
	if _astar.protecting_stack_at(dest) != null:
		return CUR_ATTACK
	return CUR_MOVE         # reachable land (or walk onto the town entrance)

## Cursor for a reachable destination while sailing (adventure-screen.md 7.2,
## rule 8): the boat over open water, the red boat over a buoy or whirlpool,
## and the anchor over a shore the hero may land on. Every one carries the day
## badge, except the red boat whose own frames are 28 + k.
func _sea_destination_cursor_id(dest: Vector2i, path: Array) -> int:
	var k := _day_badge(path)
	if _map.is_land(dest):
		return CUR_ANCHOR + 6 * k
	var obj := _map.active_object_at_action(dest)
	if obj != null and obj.type in ["buoy", "whirlpool"]:
		return CUR_RED_BOAT + k
	return CUR_BOARD + 6 * k

## Cursor over an object's cell, per heroes.exe 0x98e8b..0x996ed.
##
## The original picks the cursor from the cell's OBJECT CLASS, not from what the
## object would do when visited. Every interactive object class the original
## ships (grave 0x0c, mine 0x19, obelisk 0x1b, fountain 9, chest 6, statue
## 0x24, shipwreck, demon cave 0x05, ...) is in the "visit" list, so the cell
## shows the REARING HORSE (frame 9) - the sword (frame 5) is reserved for a
## wandering monster stack standing there, an enemy hero and an enemy town gate.
##
## So a guarded site with no guardian on the map - the Graveyard, whose ghosts
## only appear when the visit is confirmed - is entered, not attacked: it wears
## the visit horse, not the sword.
static func _object_cursor_id(obj: MapObject) -> int:
	if obj == null:
		return CUR_INTERACT
	if obj is NeutralStack:
		return CUR_ATTACK            # a monster stack on the cell
	if obj is TownObject:
		# An enemy town gate shows the sword (0xc9145); our own town is
		# handled by the caller, which shows the visit horse.
		return CUR_ATTACK if obj.uses_attack_cursor() else CUR_INTERACT
	return CUR_INTERACT

## Object classes the original exempts from the guard-zone sword (heroes.exe
## 0x995a6): skeleton 4, chest 6, campfire 8, lamp 0x0b, resource 0x1d and
## artifact 0x30 keep the visit horse even inside a monster's control zone.
## The fountain (9), obelisk (0x1b) and statue (0x24) are not exempt, although
## the hero stops beside them too. A native Genie Lamp converts as a genie
## dwelling, so it is matched by its unit as well as by the lamp types.
static func _pickup_cursor_class(obj: MapObject) -> bool:
	if obj == null:
		return false
	if obj is Dwelling and (obj as Dwelling).unit == "genie":
		return true
	return obj.type in PICKUP_CURSOR_TYPES

const PICKUP_CURSOR_TYPES := ["skeleton", "chest", "campfire", "ancient_lamp",
	"genie_lamp", "resource", "artifact"]

func _set_cursor(id: int) -> void:
	if id == _cur_id:
		return
	_cur_id = id
	var tex: Texture2D = _cursor_cache.get(id)
	if tex == null:
		tex = load(ADVMICE % id) as Texture2D
		_cursor_cache[id] = tex
	if tex == null:
		return
	var game := _get_game()
	if game != null:
		game.set_cursor(tex, _cursor_hotspot(id))

## The hot spot of a cursor frame. The day-badge frames (10..27) keep the hot
## spot of the plain frame they were built from (advmice.mse).
static func _cursor_hotspot(id: int) -> Vector2:
	if id >= CUR_RED_BOAT and id <= CUR_RED_BOAT + 3:
		return Vector2(12, 12)   # red boat (advmice.mse)
	var base := id
	if id >= 10 and id <= 27:
		base = 4 + (id - 10) % 6
	return CURSOR_HOTSPOTS.get(base, Vector2.ZERO)

## Modal adventure-map overlays own pointer input while they are visible. Route
## the swap through this controller (instead of setting Input directly) so the
## cached cursor id stays in sync and map hover cursors resume after dismissal.
func show_pointer_cursor() -> void:
	_set_cursor(CUR_POINT)

func show_sunclock_cursor() -> void:
	_set_cursor(CUR_SUNCLOCK)

func refresh_cursor() -> void:
	var vp := get_viewport()
	var mpos := Pointer.position(vp) if vp != null else Vector2.ZERO
	_update_cursor(mpos)

func edge_scroll_direction() -> Vector2:
	if _edge_blocked_fn.call():
		return Vector2.ZERO

	var vp := get_viewport()
	if vp == null:
		return Vector2.ZERO
	var mouse_pos := Pointer.position(vp)
	var scroll_dir := Vector2.ZERO
	var margin := 32.0
	var bounded := true
	var touch := _touch_node()
	if touch != null and touch.owns_pointer():
		# A finger has no hover: scroll only while one is held in the edge band.
		# The band reaches past the frame, since the letterbox bars on a phone
		# are where a thumb lands "on the edge" of the screen.
		if not touch.is_edge_hold_active():
			return Vector2.ZERO
		if TOUCH_HUD_RECT.has_point(mouse_pos) and mouse_pos.x < 640.0 - TOUCH_HUD_RIGHT_BAND:
			return Vector2.ZERO
		# The band covers the outer ring of the visible map, so a quick touch
		# there must stay a tap: only a held finger takes the map over.
		if touch.hold_seconds() < touch.pan_hold_duration:
			return Vector2.ZERO
		margin = TOUCH_EDGE_MARGIN
		bounded = false

	if not bounded or (mouse_pos.x >= 0.0 and mouse_pos.x <= 640.0 and mouse_pos.y >= 0.0 and mouse_pos.y <= 480.0):
		if mouse_pos.x <= margin:
			scroll_dir.x = -1.0
		elif mouse_pos.x >= 640.0 - margin:
			scroll_dir.x = 1.0
		if not bounded and mouse_pos.x >= TOUCH_HUD_RECT.position.x - TOUCH_MAP_RIGHT_BAND \
				and mouse_pos.x < TOUCH_HUD_RECT.position.x:
			scroll_dir.x = 1.0

		if mouse_pos.y <= margin:
			scroll_dir.y = -1.0
		elif mouse_pos.y >= 480.0 - margin:
			scroll_dir.y = 1.0

	if not bounded and scroll_dir != Vector2.ZERO:
		touch.mark_pan()
	return scroll_dir.normalized()

func _touch_node() -> Node:
	var vp := get_viewport()
	if vp == null or vp.get_tree() == null:
		return null
	return vp.get_tree().root.get_node_or_null("TouchInput")

static func _route_texture(idx: int) -> Texture2D:
	if not _route_texture_cache.has(idx):
		var rel := "route/%04d.png" % idx
		var tex: Texture2D = MapArtResolver.get_atlas_texture(rel)
		if tex == null:
			tex = load(ROUTE + "%04d.png" % idx) as Texture2D
		_route_texture_cache[idx] = tex
	return _route_texture_cache[idx]

func draw_path(path: Array) -> void:
	clear_path()
	var remaining := _hero.move_points
	var current_day := true
	var state: GameState = _state_fn.call() if _state_fn.is_valid() else null
	var parent: Node = _route_parent if _route_parent != null else self
	for i in range(1, path.size()):
		var prev: Vector2i = path[i - 1]
		var cur: Vector2i = path[i]
		var kind := TravelRules.MOVE
		if state != null:
			kind = TravelRules.step_kind(_map, _astar, state,
					_hero.travel_mode, prev, cur)
		var green := false
		if current_day and kind != TravelRules.INVALID:
			if not TravelRules.is_walk(kind):
				green = remaining > 0
				remaining = 0
				current_day = false
			else:
				var raw_cost := _step_cost(prev, cur)
				var straight_cost := _straight_step_cost(prev)
				green = Pathfinder.can_take_today(
						raw_cost, straight_cost, remaining)
				if green:
					remaining -= Pathfinder.current_day_step_cost(
							raw_cost, straight_cost, remaining)
				else:
					current_day = false
		var idx: int
		var flip := false
		if i == path.size() - 1:
			idx = RouteArrows.DEST_GREEN if green else RouteArrows.DEST_RED
		else:
			var arrow_style: Array = RouteArrows.select(cur - prev, path[i + 1] - cur)
			idx = arrow_style[0] if green else arrow_style[0] - 14
			flip = arrow_style[1]

		var spr: Sprite2D
		while not _arrow_pool.is_empty():
			var candidate: Sprite2D = _arrow_pool.pop_back()
			if candidate != null and is_instance_valid(candidate) and not candidate.is_queued_for_deletion():
				spr = candidate
				break
		if spr == null:
			spr = Sprite2D.new()
			spr.centered = true
			spr.z_index = 0
			parent.add_child(spr)
		elif spr.get_parent() != parent:
			if spr.get_parent() != null:
				spr.get_parent().remove_child(spr)
			parent.add_child(spr)

		spr.texture = _route_texture(idx)
		spr.centered = true
		spr.flip_h = flip
		spr.z_index = 0
		spr.position = Vector2(cur.x * _map.tile_size + _map.tile_size * 0.5, cur.y * _map.tile_size + _map.tile_size * 0.5)
		spr.visible = true
		_path_arrows.append(spr)

func clear_path() -> void:
	for a in _path_arrows:
		if a != null and is_instance_valid(a):
			a.visible = false
			_arrow_pool.append(a)
	_path_arrows.clear()

## Clear the visual route AND forget the pending destination (used when the
## player's turn state changes out from under the preview: cancel click, teleport).
func cancel_route() -> void:
	_inspecting = false
	clear_path()
	_pending_dest = Vector2i(-1, -1)
	_pending_path.clear()
	_invalidate_route_field()
	if _hero != null:
		_hero.planned_dest = Vector2i(-1, -1)
	route_changed.emit()

func _invalidate_route_field() -> void:
	_route_field.clear()
	_route_field_key = ""
	_last_hover_dest = Vector2i(-1, -1)
	_last_hover_hero_tile = Vector2i(-1, -1)

## Recompute and draw the path for the current hero's planned destination.
func refresh_path() -> void:
	if _hero == null or _hero.planned_dest == Vector2i(-1, -1) or _hero.planned_dest == _hero.tile:
		if _hero != null and _hero.planned_dest == _hero.tile:
			_hero.planned_dest = Vector2i(-1, -1)
		clear_path()
		_pending_dest = Vector2i(-1, -1)
		_pending_path.clear()
		route_changed.emit()
		return

	_pending_dest = _hero.planned_dest
	var path := _find_path(_hero.tile, _pending_dest)

	if path.size() < 2:
		_hero.planned_dest = Vector2i(-1, -1)
		_pending_dest = Vector2i(-1, -1)
		_pending_path.clear()
		_invalidate_route_field()
		clear_path()
		route_changed.emit()
		return

	_pending_path = path
	_trace_path_preview("refresh", path)
	draw_path(path)
	route_changed.emit()

## Opt-in diagnostic for identifying stale or mismatched runtime code. Keep it
## on committed previews only: cursor hover also asks for paths and would flood
## the terminal with otherwise indistinguishable traces.
func _trace_path_preview(reason: String, path: Array) -> void:
	if _trace != null and _hero != null:
		_trace.record(reason, _hero, _pending_dest, path)

static func _get_game() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop != null and loop.root != null and loop.root.has_node("Game"):
		return loop.root.get_node("Game")
	return null

## Commit the pending route (same as a second click on the destination, or pressing 'M').
func commit_pending() -> void:
	if _input_blocked:
		return
	if _hero == null or _hero.is_moving() or not _hero.has_enough_movement_to_move():
		return
	if _hero.planned_dest == Vector2i(-1, -1) or _hero.planned_dest == _hero.tile:
		return

	var path := _find_path(_hero.tile, _hero.planned_dest)

	if path.size() < 2:
		cancel_route()
		return

	_pending_path = path
	clear_path()
	path_confirmed.emit(path)
	route_changed.emit()
