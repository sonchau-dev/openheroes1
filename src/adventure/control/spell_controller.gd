class_name AdventureSpellController
extends RefCounted

signal spell_cast(spell_id: String, result_kind: String)

## Map-spell casting for the adventure map: KEY_C spellbook open + spell
## resolution/application. Root keeps the modal guard on the KEY_C handler and
## `teleport_hero` itself (it touches root's `_input`, `_fog`, `_cam`,
## `_walk_prev`); everything else needed to resolve and apply a cast spell
## lives here.

var _root: Node2D
var _map: MapData
var _hero_fn: Callable    # func() -> Hero
var _army_fn: Callable    # func() -> ArmyData (root._current_army)
var _teleport_fn: Callable   # func(tile: Vector2i) -> void (root.teleport_hero)
var _boats_changed_fn: Callable

func setup(root: Node2D, map: MapData, hero_fn: Callable, army_fn: Callable,
		teleport_fn: Callable, boats_changed_fn: Callable = Callable()) -> void:
	_root = root
	_map = map
	_hero_fn = hero_fn
	_army_fn = army_fn
	_teleport_fn = teleport_fn
	_boats_changed_fn = boats_changed_fn

## KEY_C: open the map spellbook for the player's hero (has_spellbook guard).
func open_spellbook() -> void:
	var hero_model := Game.ensure_player_hero(_army_fn.call())
	var has_map_spells := false
	if hero_model.has_spellbook and hero_model.spellbook != null:
		for spell_id in hero_model.spellbook.spells.keys():
			if hero_model.spellbook.spells[spell_id] > 0:
				var spell := SpellData.get_spell(spell_id)
				if String(spell.get("context", "")) == "map":
					has_map_spells = true
					break
	if not has_map_spells:
		MapDialogs.info(_root, {"lines": ["No spells to cast."]})
		return
	var sv = load("res://src/ui/spellbook_view.gd").new()
	_root.add_child(sv)
	sv.open(hero_model.spellbook, "map")
	sv.spell_picked.connect(cast)

## Resolve + apply a chosen map spell, spending its charge on any non-fail result.
func cast(id: String) -> void:
	var hero_model := Game.ensure_player_hero(_army_fn.call())
	var hero_node := _hero_fn.call() as Hero if _hero_fn.is_valid() else null
	var is_travel_spell := id in ["town_gate", "town_portal", "dimension_door"]
	if is_travel_spell:
		var current_mp: int = hero_node.move_points if hero_node != null else (hero_model.move_points if hero_model != null else -1)
		if current_mp == 0:
			MapDialogs.info(_root, {"lines": ["Your hero is too tired to cast this spell today.  Try again tomorrow."]})
			return

	var occupied: Array = []
	if _root != null and _root.has_method("occupied_hero_tiles"):
		occupied = _root.occupied_hero_tiles()
	elif Game.state != null:
		for p: PlayerState in Game.state.players:
			for hm: HeroModel in p.heroes:
				if hm.tile != Vector2i(-1, -1):
					occupied.append(hm.tile)
	var fog = _root.get("_fog") if _root != null and "_fog" in _root else null

	var ctx := {
		"hero": hero_model,
		"hero_tile": hero_node.tile if hero_node != null else Vector2i.ZERO,
		"players": Game.state.players if Game.state != null else [],
		"objects": _map.objects,
		"map": _map,
		"fog": fog,
		"occupied_tiles": occupied,
		"friendly_towns": _friendly_towns(false),
		"owned_towns": _friendly_towns(true),
		"state": Game.state,
		"side": Game.state.active_player_side if Game.state != null else 0,
	}
	var r := AdventureSpells.resolve(id, ctx)
	match String(r.kind):
		"target_dimdoor":
			_open_dimension_door(id, ctx)
			return
		"view":
			var vw = load("res://src/ui/view_world.gd").new()
			_root.add_child(vw)
			vw.open(_map, _map.objects, Game.state.players if Game.state != null else [],
					r.category, fog, hero_node)
		"teleport":
			_teleport_fn.call(r.dest)
		"pick_town":
			MapDialogs.town_picker(_root, r.towns, _teleport_fn)
		"summon_boat":
			var boat := Game.state.boat_by_id(int(r.boat_id)) if Game.state != null else null
			if boat == null:
				MapDialogs.info(_root, {"lines": ["Summon Boat failed!!!"]})
				return
			boat.tile = r.dest
			if _boats_changed_fn.is_valid():
				_boats_changed_fn.call()
		"identify_hero":
			var side: int = int(ctx.get("side", 0))
			if Game.state != null:
				var player := Game.state.player_of(side)
				if player != null:
					player.identify_hero_active = true
			MapDialogs.info(_root, {"text": String(r.get("text", "Enemy Heroes are now fully identifiable."))})
		"message", "info":
			MapDialogs.info(_root, r)
		"fail":
			MapDialogs.info(_root, {"lines": [String(r.text)]})
			return
	if is_travel_spell:
		if hero_node != null:
			hero_node.move_points = maxi(0, hero_node.move_points - 12)
		if hero_model != null:
			hero_model.move_points = maxi(0, hero_model.move_points - 12)
	spell_cast.emit(id, String(r.kind))
	hero_model.spellbook.cast(id)

func _open_dimension_door(id: String, ctx: Dictionary) -> void:
	var dlg: DimensionDoorDialog = load("res://src/ui/dimension_door_dialog.gd").new()
	_root.add_child(dlg)
	dlg.open(_map)
	var hero_model: HeroModel = ctx.get("hero")
	var hero_node: Hero = _hero_fn.call() as Hero if _hero_fn.is_valid() else null
	# heroes.exe 0x968c6 spends the movement before the target screen opens, so a
	# cancel still costs it; the charge (0xb0b4c) goes only once a cast goes off.
	if hero_node != null:
		hero_node.move_points = maxi(0, hero_node.move_points - 12)
	if hero_model != null:
		hero_model.move_points = maxi(0, hero_model.move_points - 12)
	dlg.destination_selected.connect(func(dest: Vector2i):
		if not AdventureSpells.is_dimension_door_click_target(dest, ctx):
			return # 0xa39cc ignores the click and keeps the screen open
		dlg.close()
		if hero_model != null and hero_model.spellbook != null:
			hero_model.spellbook.cast(id) # spent on a land/water failure too (0x96a13)
		if not AdventureSpells.is_valid_dimension_door_dest(dest, ctx):
			MapDialogs.info(_root, {"lines": ["Dimension Door failed!!!"]})
			return
		_teleport_fn.call(dest)
		if hero_node != null:
			hero_node.view_dissolve(Hero.VIEW_DISSOLVE_TICKS_HUMAN)
		spell_cast.emit(id, "teleport")
	)

## Tiles of player-owned towns the hero isn't already standing on (Town Gate/
## Portal can't send the hero to a town it already occupies), excluding towns
## currently occupied by another friendly hero (KB spells.md 5.2 Town Gate note).
func _friendly_towns(include_occupied: bool = false) -> Array:
	var out: Array = []
	var hero_node := _hero_fn.call() as Hero if _hero_fn.is_valid() else null
	var hero_tile: Vector2i = hero_node.tile if hero_node != null else Vector2i(-1, -1)
	var occupied: Array = []
	if not include_occupied:
		if _root != null and _root.has_method("occupied_hero_tiles"):
			occupied = _root.occupied_hero_tiles()
		elif Game.state != null:
			for p: PlayerState in Game.state.players:
				for hm: HeroModel in p.heroes:
					if hm.tile != Vector2i(-1, -1):
						occupied.append(hm.tile)
	for o: MapObject in _map.objects:
		if o is TownObject and Game.state != null \
				and o.owner == Game.state.active_player_side:
			var dest := (o as TownObject).action_tile
			if dest != hero_tile and (include_occupied or not occupied.has(dest)):
				out.append(dest)
	return out
