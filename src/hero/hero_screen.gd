extends Node2D

signal dismissed(hero: HeroModel)
signal closed

## HOMM1 hero detail screen, built over heroscrn.png (640x480 frame).
## Portrait, effective stats, army, and all fourteen native artifact slots.
## Built from Sprite2D + Label child nodes (same proven pattern as town_screen).

const BG := UiKit.ART + "heroscrn.png"
const PORT := UiKit.ART + "port%04d/0000.png"           # hero portrait (101x93)
const PANEL := UiKit.ART + "heroscrn/%04d.png"           # marble stat panels (82x93)
const EXIT_UP := UiKit.ART + "heroscrn/0006.png"         # vertical EXIT button (0008/9 = DISMISS)
const EXIT_DN := UiKit.ART + "heroscrn/0007.png"
const MONSTERS := UiKit.ART + "monsters/%04d.png"        # tall framed army portraits (26x64)
const GRASS := UiKit.ART + "strip/0003.png"              # landscape terrain cell fill (82x93)
const HORSE := UiKit.ART + "strip/0002.png"              # horse-engraved empty-slot fill (82x93)
const HILITE := UiKit.ART + "strip/0001.png"             # red highlight frame (82x93)
const BLANK_PANEL := UiKit.ART + "heroscrn/0003.png"     # blank marble panel (same bg as skills)
const CREST := UiKit.ART + "crst%04d/0000.png"           # full-cell crest (101x93): id = color*4 + class
const EXP_ICON := UiKit.ART + "heroscrn/0010.png"        # small gold EXP star (35x32)
const LUCK_GOOD := UiKit.ART + "heroscrn/0011.png"       # rainbow (26x17)
const LUCK_BAD := UiKit.ART + "heroscrn/0012.png"        # storm cloud (27x26)
const MORALE_GOOD := UiKit.ART + "heroscrn/0013.png"     # gold bird, wings up (26x26)
const MORALE_BAD := UiKit.ART + "heroscrn/0014.png"      # gold bird, resting (24x26)

# Visual order Attack, Defense, Spell Power, Knowledge -> heroscrn panel sprite ids.
# (0 books=knowledge, 1 shield=defense, 2 potions=power, 4 swords=attack; 3 is blank.)
const STAT_PANEL := [4, 1, 2, 0]   # attack(swords), defense(shield), power(potions), knowledge(books)
const STAT_LABEL := ["Attack Skill", "Defense Skill", "Spell Power", "Knowledge"]

# Frame grid (detected from heroscrn.png): two rows of six cells.
# Row 1 y=101..193: portrait(w101) | atk | def | pow | kno | morale/luck/exp.
# Row 2 y=200..292: secondary(w101) | 5 army slots. Wood slots below = artifacts (empty).
const ROW1_Y := 101
const ROW2_Y := 200
const CELL_H := 93
const CELL_W := 82
const PORT_POS := Vector2(49, 101)
const SKILL_X := [156, 244, 332, 420]   # atk/def/pow/kno cell left edges
const COMBO_X := 508                      # cell 5: morale + luck + exp
const ARMY_X := [156, 244, 332, 420, 508]
const MORALE_RECT := Rect2(508, 101, 82, 30)
const LUCK_RECT := Rect2(508, 131, 82, 30)
const EXP_RECT := Rect2(508, 161, 82, 33)
const DISMISS_RECT := Rect2(8, 318, 28, 121)
const DISMISS_UP := UiKit.ART + "heroscrn/0008.png"
const DISMISS_DN := UiKit.ART + "heroscrn/0009.png"

const EXIT_RECT := Rect2(602, 318, 28, 121)
const PREVIEW_LAYER := 300
const ARTIFACT_POS := [
	Vector2(51, 308), Vector2(130, 308), Vector2(209, 308), Vector2(288, 308),
	Vector2(367, 308), Vector2(446, 308), Vector2(525, 308),
	Vector2(51, 387), Vector2(130, 387), Vector2(209, 387), Vector2(288, 387),
	Vector2(367, 387), Vector2(446, 387), Vector2(525, 387),
]

var _font_big: FontFile
var _font_small: FontFile
var _hero: HeroModel
var _exit_sprite: Sprite2D
var _exit_pressed := false
var _dismiss_sprite: Sprite2D
var _dismiss_pressed := false
var _status_label: Label
var _name_label: Label
var _artifact_ids: Array[String] = []

var _army_slots: Array = []
var _selected_army_slot: int = -1
var _army_container: Node2D
var _army_dialog: CreatureInfoDialog = null
var _stat_dialog: CanvasLayer = null
var _spellbook_view: SpellbookView = null
## A look at a hero offered for hire, shown over Castle Options. EXIT closes
## it instead of changing scene. As in heroes.exe (0xb0ebb, 0xcf4fa), DISMISS
## is hidden while Castle Options is open, and a click on another army slot
## moves the highlight instead of swapping the troops.
var _preview := false
var _dismiss_allowed := true

func setup(hero: HeroModel, preview := false) -> void:
	_hero = hero
	_preview = preview

## Shows `hero` read-only over whatever is on screen and returns the screen;
## the overlay frees itself when the screen emits `closed`.
static func open_preview(parent: Node, hero: HeroModel) -> Node2D:
	var overlay := CanvasLayer.new()
	overlay.layer = PREVIEW_LAYER
	# Takes the mouse from the screens underneath and passes it on to
	# _unhandled_input, where this screen reads its clicks.
	var blocker := Control.new()
	blocker.size = Vector2(640, 480)
	blocker.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.add_child(blocker)
	var screen := (load("res://src/hero/hero_screen.tscn") as PackedScene).instantiate() as Node2D
	screen.setup(hero, true)
	overlay.add_child(screen)
	screen.closed.connect(overlay.queue_free)
	parent.add_child(overlay)
	return screen

func _enter_tree() -> void:
	# Before the children enter, so dialogs opened ahead of _ready are lifted too.
	if _preview and not get_tree().node_added.is_connected(_lift_preview_dialog):
		get_tree().node_added.connect(_lift_preview_dialog)

func _ready() -> void:
	_font_big = UiKit.font_big()
	_font_small = UiKit.font_small()
	if _preview:
		_dismiss_allowed = false
		_init_army()
		_build()
		return

	if _hero == null:
		var game_node := get_node_or_null("/root/Game")
		if game_node != null:
			_hero = game_node.current_hero
	if _hero == null:
		_hero = HeroModel.sample()
	# Developer screenshots and fixtures, only for those runs.
	var shots = DevFlags.tool("res://src/tools/shots/hero_shots.gd", ["--shot", "--hero-class="])
	if shots != null:
		shots.prepare(self)

	_dismiss_allowed = _can_dismiss()
	_init_army()
	_build()

	var smoke = DevFlags.smoke() if get_tree().current_scene == self else null
	if smoke != null:
		smoke.hero(self)
		return

	if shots != null:
		await shots.run(self)

func _init_army() -> void:
	_army_slots.clear()
	_army_slots.resize(5)
	_army_slots.fill(null)
	if _hero != null and _hero.army != null:
		_army_slots = _hero.army.to_columns()

func _build() -> void:
	UiKit.add_sprite(self, BG, Vector2.ZERO, 0)
	_build_portrait()
	_build_name()
	_build_primary_stats()
	_build_combo()
	_build_secondary()
	_build_army()
	_build_artifacts()
	_build_buttons()
	_build_status_bar()

func _build_portrait() -> void:
	UiKit.add_sprite(self, PORT % _hero.portrait_idx, PORT_POS, 1)

func _build_name() -> void:
	var class_title := _hero.hero_class.capitalize()
	var text := _hero.hero_name
	if not text.is_empty() and not class_title.is_empty():
		if not text.ends_with(" the " + class_title):
			text = "%s the %s" % [text, class_title]
	_name_label = _centered_text(text, 81, 479, 73, 14, Color.WHITE)

func _build_primary_stats() -> void:
	# Each cell: skill label at top, marble icon panel filling the cell, value at bottom.
	var values := [_hero.effective_attack(), _hero.effective_defense(),
			_hero.effective_spell_power(), _hero.effective_knowledge()]
	for i in STAT_PANEL.size():
		var x: int = SKILL_X[i]
		UiKit.add_sprite(self, PANEL % STAT_PANEL[i], Vector2(x, ROW1_Y), 1)
		_centered_text(STAT_LABEL[i], x, CELL_W, ROW1_Y + 3, 12, Color.WHITE).z_index = 2
		_centered_text(str(values[i]), x, CELL_W, ROW1_Y + 72, 14, Color.WHITE).z_index = 2

func _build_combo() -> void:
	# Cell 5: marble panel (same bg as skills), morale/luck/exp stacked
	UiKit.add_sprite(self, BLANK_PANEL, Vector2(COMBO_X, ROW1_Y), 1)

	# Morale row (Y: ROW1_Y + 4)
	var em := _hero.total_morale()
	if em == 0:
		UiKit.add_sprite(self, UiKit.ART + "heroscrn/0017.png", Vector2(COMBO_X + 14, ROW1_Y + 7), 2)
	elif em > 0:
		var count := mini(em, 3)
		var start_x := COMBO_X + 9 if count == 2 else (COMBO_X + 28 if count == 1 else COMBO_X + 2)
		for i in count:
			UiKit.add_sprite(self, MORALE_GOOD, Vector2(start_x + i * 21, ROW1_Y + 4), 2)
	else:
		var count := mini(-em, 3)
		var start_x := COMBO_X + 11 if count == 2 else (COMBO_X + 29 if count == 1 else COMBO_X + 3)
		for i in count:
			UiKit.add_sprite(self, MORALE_BAD, Vector2(start_x + i * 21, ROW1_Y + 4), 2)

	# Luck row (Y: ROW1_Y + 34)
	var el := _hero.effective_luck()
	if el == 0:
		UiKit.add_sprite(self, UiKit.ART + "heroscrn/0016.png", Vector2(COMBO_X + 13, ROW1_Y + 34), 2)
	elif el > 0:
		var count := mini(el, 3)
		var start_x := COMBO_X + 9 if count == 2 else (COMBO_X + 28 if count == 1 else COMBO_X + 2)
		for i in count:
			UiKit.add_sprite(self, LUCK_GOOD, Vector2(start_x + i * 21, ROW1_Y + 38), 2)
	else:
		var count := mini(-el, 3)
		var start_x := COMBO_X + 9 if count == 2 else (COMBO_X + 28 if count == 1 else COMBO_X + 2)
		for i in count:
			UiKit.add_sprite(self, LUCK_BAD, Vector2(start_x + i * 21, ROW1_Y + 34), 2)

	# EXP row (Y: ROW1_Y + 60)
	UiKit.add_sprite(self, EXP_ICON, Vector2(COMBO_X + 9, ROW1_Y + 60), 2)
	var l := _outlined_text(str(_hero.experience), COMBO_X + 48, CELL_W - 48, ROW1_Y + 70, 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.size = Vector2(0, 0)

## Row-2 cell 0: secondary-skills container (no skills data yet) — full faction crest.
func _build_secondary() -> void:
	UiKit.add_sprite(self, CREST % _hero.crest_idx, Vector2(PORT_POS.x, ROW2_Y), 1)

func _build_army() -> void:
	if _army_container == null:
		_army_container = Node2D.new()
		_army_container.name = "ArmyContainer"
		add_child(_army_container)
	_rebuild_army()

func _rebuild_army() -> void:
	for child in _army_container.get_children():
		child.queue_free()

	for i in ARMY_X.size():
		var slot = _army_slots[i]
		var x: int = ARMY_X[i]
		if slot == null:
			_fill_cell_in(_army_container, HORSE, x, ROW2_Y, CELL_W)
		else:
			var unit_name := String(slot.get("unit", ""))
			var bg_path := CreatureCatalog.slot_background(unit_name)
			_fill_cell_in(_army_container, bg_path, x, ROW2_Y, CELL_W)
			var idx: int = CreatureCatalog.native_id(unit_name)
			var path := MONSTERS % (idx if idx >= 0 else 0)
			UiKit.add_sprite(_army_container, path, CreatureCatalog.card_position(idx if idx >= 0 else 0, Vector2(x, ROW2_Y)), 2)
			var count_lbl := _outlined_text_in(_army_container, str(slot.get("count", 0)), x, 77, ROW2_Y + 80, 12)
			count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

		if _selected_army_slot == i:
			UiKit.add_sprite(_army_container, HILITE, Vector2(x, ROW2_Y), 4)

	_update_status_bar()

func _build_artifacts() -> void:
	_artifact_ids.clear()
	# The Spell Book occupies the first visible slot (slot 1 to the left, index 0)
	# and reduces ordinary carrying capacity to thirteen.
	if _hero.has_spellbook:
		_artifact_ids.append("spell_book")
	for raw_id: Variant in _hero.artifacts:
		if _artifact_ids.size() >= 14:
			break
		_artifact_ids.append(ArtifactCatalog.shared().normalize(String(raw_id)))
	while _artifact_ids.size() < 14:
		_artifact_ids.append("")
	for i in ARTIFACT_POS.size():
		var id := _artifact_ids[i]
		if id == "" or not ArtifactCatalog.shared().has(id):
			continue
		UiKit.add_sprite(self, ArtifactCatalog.shared().artifact_icon_path(id), ARTIFACT_POS[i], 4)
		if ArtifactCatalog.shared().is_ultimate(id):
			UiKit.add_sprite(self, ArtifactCatalog.shared().slot_frame_path(id), ARTIFACT_POS[i] - Vector2(6, 6), 5)

func _fill_cell_in(parent: Node, path: String, x: float, y: float, cw: float) -> void:
	var tex := UiKit.load_texture(path)
	if tex == null:
		return
	var s := UiKit.add_sprite(parent, path, Vector2(x, y), 1)
	s.scale = Vector2(cw / tex.get_width(), float(CELL_H) / tex.get_height())

## White count/value text with a black outline (readable over any backdrop).
func _outlined_text(s: String, x: float, width: float, y: float, size: int) -> Label:
	return _outlined_text_in(self, s, x, width, y, size)

func _outlined_text_in(parent: Node, s: String, x: float, width: float, y: float, size: int) -> Label:
	var f := _font_big if size > 12 else _font_small
	var l := UiKit.add_label(parent, s, Vector2(x, y), Vector2(width, 0), f, Color.WHITE,
			HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, "", 2 if size <= 12 else 3, Color.BLACK)
	l.z_index = 3
	return l

func _build_buttons() -> void:
	if _dismiss_allowed:
		_dismiss_sprite = UiKit.add_sprite(self, DISMISS_UP, DISMISS_RECT.position, 2)
	_exit_sprite = UiKit.add_sprite(self, EXIT_UP, EXIT_RECT.position, 2)

func _build_status_bar() -> void:
	_status_label = _centered_text("", 0, 640, 461, 14, Color.WHITE)
	_status_label.name = "StatusLabel"
	_status_label.z_index = 5
	_update_status_bar()

func _update_status_bar(mouse_pos: Vector2 = Vector2(-1, -1)) -> void:
	if _status_label == null:
		return
	if _spellbook_view != null and mouse_pos.x >= 0:
		return   # the open book writes the bar itself (heroes.exe 0x7e444)
	if mouse_pos.x >= 0 and mouse_pos.y >= 0:
		if MORALE_RECT.has_point(mouse_pos):
			_status_label.text = "View %s Info" % _hero.morale_title()
			return
		if LUCK_RECT.has_point(mouse_pos):
			_status_label.text = "View %s Info" % _hero.luck_title()
			return
		if EXP_RECT.has_point(mouse_pos):
			_status_label.text = "View Experience Info"
			return
		for i in SKILL_X.size():
			if Rect2(SKILL_X[i], ROW1_Y, CELL_W, CELL_H).has_point(mouse_pos):
				_status_label.text = "View %s Info" % STAT_LABEL[i]
				return
		if DISMISS_RECT.has_point(mouse_pos) and _dismiss_allowed:
			_status_label.text = "Dismiss %s the %s" % [_hero.hero_name, _hero.hero_class.capitalize()]
			return
		if EXIT_RECT.has_point(mouse_pos):
			_status_label.text = "Exit Hero Screen"
			return
		var slot_idx := _army_slot_at(mouse_pos)
		if slot_idx >= 0:
			_status_label.text = army_hover_text(slot_idx)
			return
		for i in ARTIFACT_POS.size():
			if Rect2(ARTIFACT_POS[i], Vector2(64, 64)).has_point(mouse_pos):
				if i < _artifact_ids.size() and _artifact_ids[i] != "":
					if _artifact_ids[i] == "spell_book":
						_status_label.text = "View Spells"
					else:
						_status_label.text = "View %s Info" % ArtifactCatalog.shared().display_name(_artifact_ids[i])
				else:
					_status_label.text = "Empty"   # heroes.exe 0xce9f6
				return

	if _spellbook_view != null:
		_status_label.text = "View Spells"
	elif _selected_army_slot >= 0 and _selected_army_slot < _army_slots.size() and _army_slots[_selected_army_slot] != null:
		var unit_name := String(_army_slots[_selected_army_slot].get("unit", ""))
		var singular_name := CreatureCatalog.singular(unit_name)
		_status_label.text = "Select %s" % singular_name.to_lower()
	elif _hero != null:
		_status_label.text = "%s the %s has %d experience." % [
			_hero.hero_name, _hero.hero_class.capitalize(), _hero.experience
		]
	else:
		_status_label.text = ""

func _centered_text(s: String, x: float, width: float, y: float, size: int, color: Color) -> Label:
	return _centered_text_in(self, s, x, width, y, size, color)

func _centered_text_in(parent: Node, s: String, x: float, width: float, y: float, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = s
	l.position = Vector2(x, y)
	l.size = Vector2(width, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var f := _font_big if size > 12 else _font_small
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", f.fixed_size)
	l.add_theme_color_override("font_color", color)
	l.z_index = 5
	parent.add_child(l)
	return l

func _count_occupied_slots() -> int:
	var count := 0
	for s in _army_slots:
		if s != null:
			count += 1
	return count

func _sync_army() -> void:
	_hero.army.set_columns(_army_slots)

func _army_slot_at(p: Vector2) -> int:
	if p.y < ROW2_Y or p.y >= ROW2_Y + CELL_H:
		return -1
	for i in ARMY_X.size():
		if p.x >= ARMY_X[i] and p.x < ARMY_X[i] + CELL_W:
			return i
	return -1

## heroes.exe 0xce787: with a stack picked (and not a view-only screen), an
## empty slot reads "Move <picked>" and another stack "Exchange <picked>
## with <that>"; otherwise "Select <name>" or "Empty". Names are the lower
## case singular (table 0x20ab0).
func army_hover_text(slot_idx: int) -> String:
	var hovered = _army_slots[slot_idx] if slot_idx < _army_slots.size() else null
	var picked = _army_slots[_selected_army_slot] \
			if _selected_army_slot >= 0 and _selected_army_slot < _army_slots.size() else null
	if picked != null and slot_idx != _selected_army_slot and not _preview:
		var picked_name := CreatureCatalog.singular(String(picked.get("unit", ""))).to_lower()
		if hovered == null:
			return "Move %s" % picked_name
		return "Exchange %s with %s" % [picked_name,
				CreatureCatalog.singular(String(hovered.get("unit", ""))).to_lower()]
	if hovered == null:
		return "Empty"
	return "Select %s" % CreatureCatalog.singular(String(hovered.get("unit", ""))).to_lower()

func _on_army_slot_clicked(slot_idx: int) -> void:
	if _preview and _selected_army_slot >= 0 and _selected_army_slot != slot_idx:
		if _army_slots[slot_idx] != null:
			_selected_army_slot = slot_idx
			_rebuild_army()
		return
	if _selected_army_slot < 0:
		# First click: if slot is occupied, select and highlight it
		if _army_slots[slot_idx] != null:
			_selected_army_slot = slot_idx
			_rebuild_army()
	elif _selected_army_slot == slot_idx:
		# Second click on already selected slot: open the unit popup window!
		_open_creature_dialog(slot_idx)
	else:
		# Clicked a different slot: swap, move, or merge
		var src = _army_slots[_selected_army_slot]
		var dst = _army_slots[slot_idx]
		if dst == null:
			_army_slots[slot_idx] = src
			_army_slots[_selected_army_slot] = null
		elif String(dst.get("unit", "")) == String(src.get("unit", "")):
			_army_slots[slot_idx] = {
				"unit": dst.get("unit", ""),
				"count": int(dst.get("count", 0)) + int(src.get("count", 0))
			}
			_army_slots[_selected_army_slot] = null
		else:
			_army_slots[slot_idx] = src
			_army_slots[_selected_army_slot] = dst
		_selected_army_slot = -1
		_sync_army()
		_rebuild_army()

func _open_creature_dialog(slot_idx: int) -> void:
	if _army_dialog != null or slot_idx < 0 or slot_idx >= _army_slots.size():
		return
	var slot = _army_slots[slot_idx]
	if slot == null:
		return

	var unit_name := String(slot.get("unit", ""))
	var count := int(slot.get("count", 0))
	var allow_dismiss := not _preview and _count_occupied_slots() > 1

	var dlg := CreatureInfoDialog.new()
	add_child(dlg)
	dlg.setup_slot(
		unit_name,
		count,
		_hero.total_morale(),
		_hero.effective_luck(),
		_hero.effective_attack(),
		_hero.effective_defense(),
		allow_dismiss,
		Vector2(119, 20)
	)
	dlg.dismissed.connect(func():
		_army_slots[slot_idx] = null
		_selected_army_slot = -1
		_sync_army()
		_rebuild_army()
	)
	dlg.closed.connect(func():
		_army_dialog = null
		_selected_army_slot = -1
		_rebuild_army()
	)
	_army_dialog = dlg

func _open_morale_dialog() -> void:
	if _army_dialog != null or _stat_dialog != null:
		return
	_stat_dialog = MapDialogs.morale_info(self, _hero)
	_stat_dialog.closed.connect(func(): _stat_dialog = null)

func _open_luck_dialog() -> void:
	if _army_dialog != null or _stat_dialog != null:
		return
	_stat_dialog = MapDialogs.luck_info(self, _hero)
	_stat_dialog.closed.connect(func(): _stat_dialog = null)

func _open_exp_dialog() -> void:
	if _army_dialog != null or _stat_dialog != null:
		return
	_stat_dialog = MapDialogs.experience_info(self, _hero)
	_stat_dialog.closed.connect(func(): _stat_dialog = null)

func _open_primary_stat_dialog(stat_idx: int) -> void:
	if _army_dialog != null or _stat_dialog != null:
		return
	match stat_idx:
		0:
			_stat_dialog = MapDialogs.attack_info(self)
		1:
			_stat_dialog = MapDialogs.defense_info(self)
		2:
			_stat_dialog = MapDialogs.spell_power_info(self)
		3:
			_stat_dialog = MapDialogs.knowledge_info(self)
	if _stat_dialog != null:
		_stat_dialog.closed.connect(func(): _stat_dialog = null)

func _open_dismiss_dialog() -> void:
	if not _dismiss_allowed:
		return
	if _army_dialog != null or _stat_dialog != null or _spellbook_view != null:
		return
	_stat_dialog = MapDialogs.dismiss_hero_confirm(self, func(idx: int):
		if idx == 0:
			_dismiss_hero()
	)
	_stat_dialog.closed.connect(func(): _stat_dialog = null)

## heroes.exe 0xb0ebb hides DISMISS when the screen is opened from a town
## (where `visiting_hero` is set, see _exit_screen) and for a kingdom's last
## hero while it owns no town (player bytes 0x13 and 0x56).
func _can_dismiss() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var game_node = tree.root.get_node_or_null("Game") if tree != null and tree.root != null else null
	if game_node == null:
		return true
	if game_node.visiting_hero != null:
		return false
	if game_node.state != null:
		for player: PlayerState in game_node.state.players:
			if player.heroes.has(_hero):
				return player.heroes.size() > 1 or not player.towns.is_empty()
	return true

func _dismiss_hero() -> void:
	dismissed.emit(_hero)
	var tree := Engine.get_main_loop() as SceneTree
	var game_node = tree.root.get_node_or_null("Game") if tree != null and tree.root != null else null
	if game_node != null:
		if game_node.state != null:
			for player: PlayerState in game_node.state.players:
				if player.heroes.has(_hero):
					player.dismiss_hero(_hero, game_node.rng)
					break
		if game_node.visiting_hero == _hero:
			game_node.visiting_hero = null
		if game_node.current_hero == _hero:
			game_node.current_hero = null
		if game_node.player_hero == _hero:
			var human_player: PlayerState = game_node.state.human() if game_node.state != null else null
			if human_player != null and not human_player.heroes.is_empty():
				game_node.player_hero = human_player.active()
			else:
				game_node.player_hero = null
				game_node.player_army = ArmyData.new()
				game_node.hero_tile = game_node.town_tile if (human_player != null and human_player.owns_town) else Vector2i(-1, -1)
				game_node.hero_move_points = -1
				if human_player != null and not human_player.owns_town:
					game_node.pending_defeat = true

		if game_node.visiting_hero != null:
			game_node.to_town(game_node.visiting_hero)
		else:
			game_node.to_map()
	else:
		closed.emit()

## The dialogs this screen opens sit on fixed layers meant for a screen on
## layer 0; in a preview they are lifted by the overlay's layer to stay on top.
## Deferred because most dialogs set their layer after entering the tree.
func _lift_preview_dialog(node: Node) -> void:
	if node is CanvasLayer and is_ancestor_of(node):
		_lift_layer.call_deferred(node)

func _lift_layer(dialog: CanvasLayer) -> void:
	if is_instance_valid(dialog):
		dialog.layer += PREVIEW_LAYER

func _open_spellbook() -> void:
	if _spellbook_view != null or _hero == null or not _hero.has_spellbook:
		return
	_status_label.text = "View Spells"
	_spellbook_view = SpellbookView.new()
	add_child(_spellbook_view)
	_spellbook_view.closed.connect(func():
		_spellbook_view = null
		_update_status_bar()
	)
	_spellbook_view.status_changed.connect(func(text: String): _status_label.text = text)
	_spellbook_view.open(_hero.spellbook, "view")

func _exit_screen() -> void:
	closed.emit()
	if _preview:
		return
	var tree := Engine.get_main_loop() as SceneTree
	var game_node = tree.root.get_node_or_null("Game") if tree != null and tree.root != null else null
	if game_node != null:
		if game_node.visiting_hero != null:
			game_node.to_town(game_node.visiting_hero)
		else:
			game_node.to_map()

func _unhandled_input(event: InputEvent) -> void:
	if _army_dialog != null or _stat_dialog != null or _spellbook_view != null:
		return

	if event is InputEventKey:
		var ek := event as InputEventKey
		if ek.pressed and not ek.echo:
			# herowind.bin: Exit is Esc; Dismiss has no key.
			if ek.keycode == KEY_ESCAPE:
				_exit_screen()
				get_viewport().set_input_as_handled()
				return

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_update_status_bar(mm.position)

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var p := mb.position

		# Right click: immediate creature info popup on occupied slot or stat dialog
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if MORALE_RECT.has_point(p):
				_open_morale_dialog()
				return
			if LUCK_RECT.has_point(p):
				_open_luck_dialog()
				return
			if EXP_RECT.has_point(p):
				_open_exp_dialog()
				return
			for i in SKILL_X.size():
				if Rect2(SKILL_X[i], ROW1_Y, CELL_W, CELL_H).has_point(p):
					_open_primary_stat_dialog(i)
					return

			var slot_idx := _army_slot_at(p)
			if slot_idx >= 0 and _army_slots[slot_idx] != null:
				_selected_army_slot = slot_idx
				_rebuild_army()
				_open_creature_dialog(slot_idx)
				return
			for i in ARTIFACT_POS.size():
				if Rect2(ARTIFACT_POS[i], Vector2(64, 64)).has_point(p) \
						and i < _artifact_ids.size() and _artifact_ids[i] != "":
					# Right-click shows the info text as a hold popup, the
					# Magic Book's too (heroes.exe 0xcf5ff).
					MapDialogs.artifact_info(self, _artifact_ids[i], true)
					return

		# Left click:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if MORALE_RECT.has_point(p):
					_open_morale_dialog()
					return
				if LUCK_RECT.has_point(p):
					_open_luck_dialog()
					return
				if EXP_RECT.has_point(p):
					_open_exp_dialog()
					return
				for i in SKILL_X.size():
					if Rect2(SKILL_X[i], ROW1_Y, CELL_W, CELL_H).has_point(p):
						_open_primary_stat_dialog(i)
						return

				var slot_idx := _army_slot_at(p)
				if slot_idx >= 0:
					_on_army_slot_clicked(slot_idx)
					return

				if DISMISS_RECT.has_point(p) and _dismiss_allowed:
					_dismiss_pressed = true
					_dismiss_sprite.texture = UiKit.load_texture(DISMISS_DN)
					return
				if EXIT_RECT.has_point(p):
					_exit_pressed = true
					_exit_sprite.texture = UiKit.load_texture(EXIT_DN)
					return
			else:
				# Mouse release
				if DISMISS_RECT.has_point(p) and _dismiss_pressed:
					_dismiss_pressed = false
					_dismiss_sprite.texture = UiKit.load_texture(DISMISS_UP)
					_open_dismiss_dialog()
					return
				elif _dismiss_pressed:
					_dismiss_pressed = false
					_dismiss_sprite.texture = UiKit.load_texture(DISMISS_UP)

				if EXIT_RECT.has_point(p) and _exit_pressed:
					_exit_pressed = false
					_exit_sprite.texture = UiKit.load_texture(EXIT_UP)
					_exit_screen()
					return
				elif _exit_pressed:
					_exit_pressed = false
					_exit_sprite.texture = UiKit.load_texture(EXIT_UP)

				# Artifact release check
				for i in ARTIFACT_POS.size():
					if Rect2(ARTIFACT_POS[i], Vector2(64, 64)).has_point(p) \
							and i < _artifact_ids.size() and _artifact_ids[i] != "":
						if _artifact_ids[i] == "spell_book":
							_open_spellbook()
						else:
							MapDialogs.artifact_info(self, _artifact_ids[i])
						return
