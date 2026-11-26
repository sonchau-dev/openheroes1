# src/ui/kingdom_overview.gd
class_name KingdomOverview
extends CanvasLayer

## Authentic Kingdom Overview report popup over the adventure map / town.
## Reads GameState + MapData; closes on Exit button or ESC key.

const OVERVIEW_ART := UiKit.ART + "overview/"
const RES_ART := UiKit.ART + "resource/"

const RES_ORDER := ["wood", "mercury", "ore", "sulfur", "crystal", "gems", "gold"]

signal closed

var _font_big: FontFile
var _font_small: FontFile
var _root: Control

static func _get_game_node() -> Node:
	var ml = Engine.get_main_loop()
	if ml is SceneTree and ml.root != null:
		return ml.root.get_node_or_null("Game")
	return null

func open(state = null, map = null) -> void:
	layer = 200
	_font_big = UiKit.font_big()
	_font_small = UiKit.font_small()

	_root = Control.new()
	_root.position = Vector2.ZERO
	_root.size = Vector2(640, 480)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var game_node := _get_game_node()
	var game_state: GameState = state if state != null else (game_node.get("state") if game_node != null and game_node.get("state") != null else null)
	var player: PlayerState = game_state.human() if (game_state != null and not game_state.players.is_empty()) else null
	var color_idx: int = clampi(player.crest_idx / 4, 0, 3) if player != null else 0
	var day_num: int = game_state.day if game_state != null else 1

	_draw_background(color_idx)
	_draw_header(day_num)
	_draw_heroes(player)
	_draw_castles(player)
	_draw_towns(player)
	_draw_mines(player, map)
	_draw_treasury(player, game_state, map)
	_draw_exit_button()

func _draw_background(color_idx: int) -> void:
	# Left colored banner (96x480)
	var ban := Sprite2D.new()
	ban.texture = load(UiKit.ART + "overban%d.png" % color_idx) as Texture2D
	ban.centered = false
	ban.position = Vector2.ZERO
	_root.add_child(ban)

	# Banner row title labels (from overwind.bin)
	UiKit.add_label(_root, "Heroes", Vector2(0, 32), Vector2(96, 16), _font_big, Color.WHITE)
	UiKit.add_label(_root, "Castles", Vector2(0, 113), Vector2(96, 16), _font_big, Color.WHITE)
	UiKit.add_label(_root, "Towns", Vector2(0, 201), Vector2(96, 16), _font_big, Color.WHITE)
	UiKit.add_label(_root, "Mines", Vector2(0, 289), Vector2(96, 16), _font_big, Color.WHITE)
	UiKit.add_label(_root, "Treasury", Vector2(0, 379), Vector2(96, 16), _font_big, Color.WHITE)

	# Main stone panel with rows and header (544x480)
	var main_panel := Sprite2D.new()
	main_panel.texture = load(UiKit.ART + "overmain.png") as Texture2D
	main_panel.centered = false
	main_panel.position = Vector2(96, 0)
	_root.add_child(main_panel)

func _draw_header(day_num: int) -> void:
	var month := (day_num - 1) / 28 + 1
	var week := ((day_num - 1) % 28) / 7 + 1
	var day := ((day_num - 1) % 7) + 1

	var header_text := "Kingdom Overview      Month %d, Week %d, Day %d" % [month, week, day]
	UiKit.add_label(_root, header_text, Vector2(96, 7), Vector2(544, 18), _font_big, Color.WHITE)

func _draw_heroes(player: PlayerState) -> void:
	if player == null:
		return
	# Group heroes by class (0=Knight, 1=Barbarian, 2=Sorceress, 3=Warlock)
	var hero_counts := [0, 0, 0, 0]
	if not player.heroes.is_empty():
		for h: HeroModel in player.heroes:
			var cls_idx := _hero_class_index(h)
			if cls_idx >= 0 and cls_idx < 4:
				hero_counts[cls_idx] += 1
	elif player.hero_model != null:
		var cls_idx := _hero_class_index(player.hero_model)
		if cls_idx >= 0 and cls_idx < 4:
			hero_counts[cls_idx] += 1

	var col := 0
	for cls_idx in 4:
		var count: int = hero_counts[cls_idx]
		if count <= 0:
			continue
		# Positions from heroes.exe 0x7f0b4 (Kingdom Overview draw).
		var x_pos := 121 + col * 136
		var y_pos := 32

		# Horse sprite (overview 0..3)
		var horse := Sprite2D.new()
		horse.texture = load(OVERVIEW_ART + "%04d.png" % cls_idx) as Texture2D
		horse.centered = false
		horse.position = Vector2(x_pos, y_pos)
		_root.add_child(horse)

		# Purple shield crest (overview 0015, 33x38)
		var shield := Sprite2D.new()
		shield.texture = load(OVERVIEW_ART + "0015.png") as Texture2D
		shield.centered = false
		shield.position = Vector2(x_pos + 49, y_pos + 35)
		_root.add_child(shield)

		# Count text inside shield
		UiKit.add_label(_root, str(count), Vector2(x_pos + 48, y_pos + 45), Vector2(33, 16), _font_big, Color.WHITE)

		col += 1

func _hero_class_index(h: HeroModel) -> int:
	if h == null:
		return 0
	match h.hero_class.to_lower():
		"knight": return 0
		"barbarian": return 1
		"sorceress": return 2
		"warlock": return 3
		_: return h.crest_idx % 4

func _castle_sprite_index(f_idx: int) -> int:
	match f_idx:
		0: return 4 # Knight (Farm)
		1: return 6 # Barbarian (Plains)
		2: return 5 # Sorceress (Forest)
		3: return 7 # Warlock (Mountains)
		_: return 4

func _town_sprite_index(f_idx: int) -> int:
	match f_idx:
		0: return 8  # Knight (Farm)
		1: return 10 # Barbarian (Plains)
		2: return 9  # Sorceress (Forest)
		3: return 11 # Warlock (Mountains)
		_: return 8

func _draw_castles(player: PlayerState) -> void:
	if player == null:
		return
	# Group castles by faction (0=Knight, 1=Barbarian, 2=Sorceress, 3=Warlock)
	var castle_counts := [0, 0, 0, 0]
	for t: TownModel in player.towns:
		if t.has_castle:
			var f_idx := t.town_type
			if f_idx >= 0 and f_idx < 4:
				castle_counts[f_idx] += 1

	var col := 0
	for f_idx in 4:
		var count: int = castle_counts[f_idx]
		if count <= 0:
			continue
		# Positions from heroes.exe 0x7f210.
		var x_pos := 100 + col * 136
		var y_pos := 113

		# Castle sprite (overview 4..7: 4=Knight, 6=Barbarian, 5=Sorceress, 7=Warlock)
		# Note: Castle sprite already has the built-in purple scroll count box at the bottom.
		var castle := Sprite2D.new()
		castle.texture = load(OVERVIEW_ART + "%04d.png" % _castle_sprite_index(f_idx)) as Texture2D
		castle.centered = false
		castle.position = Vector2(x_pos, y_pos)
		_root.add_child(castle)

		# Count text inside built-in purple box
		UiKit.add_label(_root, str(count), Vector2(x_pos, y_pos + 60), Vector2(132, 16), _font_big, Color.WHITE)

		col += 1

func _draw_towns(player: PlayerState) -> void:
	if player == null:
		return
	# Group unwalled towns by faction
	var town_counts := [0, 0, 0, 0]
	for t: TownModel in player.towns:
		if not t.has_castle:
			var f_idx := t.town_type
			if f_idx >= 0 and f_idx < 4:
				town_counts[f_idx] += 1

	var col := 0
	for f_idx in 4:
		var count: int = town_counts[f_idx]
		if count <= 0:
			continue
		# Positions from heroes.exe 0x7f342.
		var x_pos := 100 + col * 136
		var y_pos := 201

		# Town sprite (overview 8..11: 8=Knight, 10=Barbarian, 9=Sorceress, 11=Warlock)
		# Note: Town sprite already has the built-in purple scroll count box at the bottom.
		var town := Sprite2D.new()
		town.texture = load(OVERVIEW_ART + "%04d.png" % _town_sprite_index(f_idx)) as Texture2D
		town.centered = false
		town.position = Vector2(x_pos, y_pos)
		_root.add_child(town)

		# Count text inside built-in purple box
		UiKit.add_label(_root, str(count), Vector2(x_pos, y_pos + 60), Vector2(132, 16), _font_big, Color.WHITE)

		col += 1

func _draw_mines(player: PlayerState, map: MapData) -> void:
	if player == null:
		return
	# Count mines owned by player.side
	var mine_counts := {
		"wood": 0,
		"mercury": 0,
		"ore": 0,
		"sulfur": 0,
		"crystal": 0,
		"gems": 0,
		"gold": 0,
	}

	if map != null:
		for obj: MapObject in map.objects:
			if obj is Mine and obj.owner == player.side:
				var m := obj as Mine
				if mine_counts.has(m.res):
					mine_counts[m.res] += 1
	else:
		var gn := _get_game_node()
		if gn != null and gn.get("map_object_state") != null:
			var mos: Dictionary = gn.get("map_object_state")
			for obj_id in mos:
				var s: Dictionary = mos[obj_id]
				if int(s.get("owner", -1)) == player.side:
					var res_type: String = String(s.get("res", ""))
					if mine_counts.has(res_type):
						mine_counts[res_type] += 1

	var mine_types := ["wood", "mercury", "ore", "sulfur", "crystal", "gems", "gold"]
	var col := 0
	for res_type: String in mine_types:
		var count: int = mine_counts[res_type]
		if count <= 0:
			continue
		# Positions from heroes.exe 0x7f461.
		var x_pos := 100 + col * 77
		var y_pos := 289

		_draw_mine_sprite(res_type, Vector2(x_pos, y_pos))

		UiKit.add_label(_root, str(count), Vector2(x_pos, 355), Vector2(72, 16), _font_big, Color.WHITE)

		col += 1

func _draw_mine_sprite(res_type: String, pos: Vector2) -> void:
	match res_type:
		"wood":
			var spr := Sprite2D.new()
			spr.texture = load(OVERVIEW_ART + "0012.png") as Texture2D
			spr.centered = false
			spr.position = pos
			_root.add_child(spr)
		"mercury":
			var spr := Sprite2D.new()
			spr.texture = load(OVERVIEW_ART + "0013.png") as Texture2D
			spr.centered = false
			spr.position = pos
			_root.add_child(spr)
		"ore", "sulfur", "crystal", "gems", "gold":
			# Base cave frame (overview 14, 72x66)
			var base := Sprite2D.new()
			base.texture = load(OVERVIEW_ART + "0014.png") as Texture2D
			base.centered = false
			base.position = pos
			_root.add_child(base)

			var overlay_id := 16
			var offset := Vector2(41, 34)
			match res_type:
				"ore":
					overlay_id = 16
					offset = Vector2(41, 34)
				"sulfur":
					overlay_id = 17
					offset = Vector2(41, 36)
				"crystal":
					overlay_id = 18
					offset = Vector2(39, 35)
				"gems":
					overlay_id = 19
					offset = Vector2(41, 35)
				"gold":
					overlay_id = 20
					offset = Vector2(41, 31)

			var ov := Sprite2D.new()
			ov.texture = load(OVERVIEW_ART + "%04d.png" % overlay_id) as Texture2D
			ov.centered = false
			ov.position = pos + offset
			_root.add_child(ov)

const RES_RECTS := [
	Rect2(124, 379, 40, 32), # wood
	Rect2(192, 379, 40, 32), # mercury
	Rect2(260, 379, 40, 32), # ore
	Rect2(328, 379, 40, 32), # sulfur
	Rect2(396, 379, 40, 32), # crystal
	Rect2(464, 379, 40, 32), # gems
	Rect2(532, 386, 82, 25), # gold
]
const RES_LABEL_RECTS := [
	Rect2(124, 411, 40, 12), # wood
	Rect2(192, 411, 40, 12), # mercury
	Rect2(260, 411, 40, 12), # ore
	Rect2(328, 411, 40, 12), # sulfur
	Rect2(396, 411, 40, 12), # crystal
	Rect2(464, 411, 40, 12), # gems
	Rect2(532, 411, 82, 12), # gold
]

func _draw_treasury(player: PlayerState, game_state: GameState, map: MapData = null) -> void:
	# 7 Resource icons with amounts (from overwind.bin layout)
	for i in RES_ORDER.size():
		var rname: String = RES_ORDER[i]
		var tex := load(RES_ART + "%04d.png" % i) as Texture2D
		var icon_rect: Rect2 = RES_RECTS[i]
		var label_rect: Rect2 = RES_LABEL_RECTS[i]

		var ic := Sprite2D.new()
		ic.texture = tex
		ic.centered = false
		var iw := float(tex.get_width()) if tex != null else icon_rect.size.x
		var ih := float(tex.get_height()) if tex != null else icon_rect.size.y
		# Center icon inside its slot
		var ix := icon_rect.position.x + (icon_rect.size.x - iw) / 2.0
		var iy := icon_rect.position.y + (icon_rect.size.y - ih) / 2.0
		ic.position = Vector2(ix, iy)
		_root.add_child(ic)

		var val := 0
		if player != null:
			val = game_state.gold() if (rname == "gold" and game_state != null) else int(player.resources.get(rname, 0))
		UiKit.add_label(_root, str(val), label_rect.position, label_rect.size, _font_small, Color.WHITE)

	# "Total Gold Per Day:" purple box (201x46 at 255, 430 from overwind.bin)
	var gold_box := Sprite2D.new()
	gold_box.texture = load(OVERVIEW_ART + "0023.png") as Texture2D
	gold_box.centered = false
	gold_box.position = Vector2(255, 430)
	_root.add_child(gold_box)

	UiKit.add_label(_root, "Total Gold Per Day:", Vector2(255, 434), Vector2(201, 12), _font_small, Color.WHITE)

	var total_income := 0
	if player != null:
		total_income = player.daily_income
		for hero: HeroModel in player.heroes:
			total_income += hero.daily_gold_bonus()
		if map != null:
			for obj: MapObject in map.objects:
				if obj is Mine and obj.owner == player.side and (obj as Mine).res == "gold":
					total_income += (obj as Mine).daily
				elif obj is DragonCity and obj.owner == player.side:
					total_income += 1000
		else:
			var gn := _get_game_node()
			if gn != null and gn.get("map_object_state") != null:
				var mos: Dictionary = gn.get("map_object_state")
				for obj_id in mos:
					var s: Dictionary = mos[obj_id]
					if int(s.get("owner", -1)) == player.side:
						if String(s.get("res", "")) == "gold":
							total_income += int(s.get("daily", 1000))
						elif String(s.get("type", "")) == "dragon_city":
							total_income += 1000
	elif game_state != null:
		total_income = game_state.daily_income
	else:
		total_income = 1000

	UiKit.add_label(_root, str(total_income), Vector2(255, 450), Vector2(201, 16), _font_big, Color.WHITE)

func _draw_exit_button() -> void:
	var btn := TextureButton.new()
	btn.texture_normal = load(OVERVIEW_ART + "0021.png") as Texture2D
	btn.texture_pressed = load(OVERVIEW_ART + "0022.png") as Texture2D
	btn.position = Vector2(552, 450)
	btn.pressed.connect(_on_exit_pressed)
	_root.add_child(btn)

func _on_exit_pressed() -> void:
	closed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_on_exit_pressed()
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_on_exit_pressed()
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
			return
