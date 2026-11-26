# src/adventure/adventure_hud.gd
class_name AdventureHud
extends CanvasLayer

## Assembles the adventure-map chrome above the world: bord.png frame + minimap +
## button bar + hero banner. Reads map/hero/camera owned by adventure_map.

const HUD_FRAME := UiKit.ART + "hud_frame.png"
const MINIMAP_RECT := Rect2(480, 16, 144, 144)
# Band 176-304 is the 2-column hero/town list box: left = hero portrait, right = town.
# Bottom band 320-464 splits into a 3x2 command-button strip + a compact hero banner.
const ROSTER_BAND := Rect2(480, 176, 144, 128)
const BUTTON_BAND := Rect2(480, 320, 144, 72)
const HERO_BAND := Rect2(480, 392, 144, 72)

var minimap: Minimap
var roster_panel: RosterPanel
var button_bar: ButtonBar
var hero_panel: HeroPanel
var turn_transition_panel: TurnTransitionPanel
var resource_collect_panel: ResourceCollectPanel

signal button_action(name: String)
signal pan_requested(world_pos: Vector2)
signal hero_selected(idx: int)
signal town_selected
signal inspect_button_requested(button_idx: int, screen_pos: Vector2)
signal inspect_dismissed

func setup(map: MapData, player: PlayerState, heroes_nodes_fn: Callable, hero: Hero, cam: MapCamera, cam_view: Vector2, enemy_tile: Vector2i, hero_name: String, army: ArmyData, crest_idx: int = 0, town_type: int = 0, has_town: bool = false, fog: FogLayer = null) -> void:
	# panel background fills the right cutouts so map never bleeds through gaps
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.position = Vector2(466, 0)
	bg.size = Vector2(174, 480)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	minimap = Minimap.new()
	minimap.setup(map, hero, cam, MINIMAP_RECT, cam_view, enemy_tile, fog)
	minimap.pan_requested.connect(func(w): pan_requested.emit(w))
	add_child(minimap)

	button_bar = ButtonBar.new()
	button_bar.position = Vector2.ZERO
	button_bar.size = Vector2(640, 480)
	# MOUSE_FILTER_PASS: full-screen Control passes clicks outside button rects to the map
	# (_gui_input only calls accept_event() inside a button rect, so unmatched clicks propagate).
	button_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(button_bar)
	button_bar.setup(BUTTON_BAND)
	button_bar.action.connect(func(n): button_action.emit(n))
	button_bar.inspect_requested.connect(func(slot, pos): inspect_button_requested.emit(slot, pos))
	button_bar.inspect_dismissed.connect(func(): inspect_dismissed.emit())

	hero_panel = HeroPanel.new()
	hero_panel.position = Vector2.ZERO
	hero_panel.size = Vector2(640, 480)
	hero_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(hero_panel)
	hero_panel.setup(HERO_BAND, hero, army, hero_name, crest_idx, player)

	turn_transition_panel = TurnTransitionPanel.new()
	turn_transition_panel.position = Vector2.ZERO
	turn_transition_panel.size = Vector2(640, 480)
	add_child(turn_transition_panel)
	turn_transition_panel.setup(HERO_BAND)
	turn_transition_panel.transition_hidden.connect(func():
		if minimap != null:
			minimap.set_show_logo(false)
	)

	# frame overlay LAST so the wood border sits above the map; its black cutouts are
	# keyed to transparent so the map (left) and widgets (right) show through.
	var frame := TextureRect.new()
	frame.texture = _build_frame_texture()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)

	# roster portraits drawn AFTER the frame: the bord.png shelf art in this band is
	# opaque wood (not black), so it isn't punched transparent — portraits must sit on top.
	roster_panel = RosterPanel.new()
	roster_panel.position = Vector2.ZERO
	roster_panel.size = Vector2(640, 480)
	roster_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(roster_panel)
	roster_panel.setup(ROSTER_BAND, player, heroes_nodes_fn, town_type, has_town)
	roster_panel.hero_selected.connect(func(idx): hero_selected.emit(idx))
	roster_panel.town_selected.connect(func(): town_selected.emit())

	# Resource collect popup overlay
	resource_collect_panel = ResourceCollectPanel.new()
	resource_collect_panel.setup(HERO_BAND)
	add_child(resource_collect_panel)
	resource_collect_panel.popup_hidden.connect(func():
		if hero_panel != null:
			hero_panel.show_details = true
			hero_panel.refresh()
	)

## The pre-baked punched-out border (baked by tools/extract/bake.gd).
static var _frame_texture: Texture2D = null

func _build_frame_texture() -> Texture2D:
	if _frame_texture == null:
		_frame_texture = UiKit.load_texture(HUD_FRAME)
	return _frame_texture

func dismiss_resource_popup() -> void:
	if resource_collect_panel != null and resource_collect_panel.visible:
		resource_collect_panel.dismiss()

func show_resource_popup(res: String, amount: int) -> void:
	if turn_transition_panel != null and turn_transition_panel.visible:
		return
	if hero_panel != null:
		hero_panel.show_details = false
		hero_panel.refresh()
	if resource_collect_panel != null:
		resource_collect_panel.show_resource(res, amount)

## Re-point hero-bound widgets at a newly-activated hero (Stage-5 switching):
## HeroPanel captured name/army/crest by value and Minimap the boot hero node,
## so a switch must push the new refs into both. Setup stays untouched.
func set_active_hero(node: Hero, model: HeroModel) -> void:
	dismiss_resource_popup()
	hide_turn_transition()
	if minimap != null:
		minimap.set_hero(node)
	if hero_panel != null and model != null:
		hero_panel.set_hero(node, model.army, model.hero_name, model.crest_idx)

func show_ai_turn(player_color: int) -> void:
	dismiss_resource_popup()
	if hero_panel != null:
		hero_panel.reset_view()
	if turn_transition_panel != null:
		turn_transition_panel.show_ai_turn(player_color)
	if minimap != null:
		minimap.set_show_logo(true)

func show_new_day(day: int, hold: bool = false) -> void:
	dismiss_resource_popup()
	if hero_panel != null:
		hero_panel.reset_view()
	if turn_transition_panel != null:
		turn_transition_panel.show_new_day(day, hold)
	if minimap != null and not hold:
		minimap.set_show_logo(false)

func hide_turn_transition() -> void:
	if turn_transition_panel != null:
		turn_transition_panel.hide_transition()
	if minimap != null:
		minimap.set_show_logo(false)

func set_button_enabled(slot: int, enabled: bool) -> void:
	if button_bar != null:
		button_bar.set_button_enabled(slot, enabled)

func is_button_enabled(slot: int) -> bool:
	if button_bar != null:
		return button_bar.is_button_enabled(slot)
	return false

## Per-frame update for dynamic viewport elements (minimap camera box, animated popups).
## HeroPanel and RosterPanel are event-driven and do not refresh per frame.
func process_frame() -> void:
	if minimap != null:
		minimap.refresh_camera()
	if resource_collect_panel != null and resource_collect_panel.visible:
		resource_collect_panel.queue_redraw()

func refresh() -> void:
	if minimap != null:
		minimap.refresh()
	if roster_panel != null:
		roster_panel.refresh()
	if hero_panel != null:
		hero_panel.refresh()
	if resource_collect_panel != null and resource_collect_panel.visible:
		resource_collect_panel.queue_redraw()

