class_name TownArmyPanel
extends RefCounted

## Army management, resource display, slot interaction, and recruit reveal for town screen.

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
const HERO_RECRUIT_REVEAL_DURATION := 1.0
const CONSTRUCTION_REVEAL_SHADER := preload("res://src/town/building_reveal.gdshader")

var name_label: Label
var status_label: Label
var exit_btn: TextureButton
var army_nodes: Array = []
var pos_row: Array = [[], []]
var sel_row: int = -1
var sel_col: int = -1
var sel_shift: bool = false
var split_dialog: SplitDialog = null
var army_dialog: CreatureInfoDialog = null
var res_labels: Array = []

var hero_slot_art: Node2D = null
var crest_slot_art: Node2D = null
var hero_reveal_pending := false
var hero_reveal_active := false
var hero_reveal_elapsed := 0.0
var hero_reveal_parts: Array = []
var hero_reveal_underlay: Array = []

func apply_font(c: Control, size: int, font_big: FontFile, font_small: FontFile) -> void:
	var f := font_big if size > 12 else font_small
	if f != null:
		c.add_theme_font_override("font", f)
		c.add_theme_font_size_override("font_size", f.fixed_size)

func mk_label(root: Node2D, pos: Vector2, size: int, font_big: FontFile, font_small: FontFile) -> Label:
	var l := Label.new()
	l.position = pos
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	apply_font(l, size, font_big, font_small)
	root.add_child(l)
	return l

func draw_panel(root: Node2D, font_big: FontFile, font_small: FontFile, on_to_map_fn: Callable) -> void:
	var back := ColorRect.new()
	back.color = Color(0.05, 0.04, 0.03)
	back.position = Vector2(0, ROW_TOP)
	back.size = Vector2(640, 480 - ROW_TOP)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(back)

	hero_slot_art = Node2D.new()
	root.add_child(hero_slot_art)

	crest_slot_art = Node2D.new()
	root.add_child(crest_slot_art)

	var rp := ColorRect.new()
	rp.color = Color.BLACK
	rp.position = Vector2(RES_X, ROW_TOP)
	rp.size = Vector2(82, 192)
	rp.z_index = 2
	root.add_child(rp)
	res_labels.clear()
	res_labels.resize(RES_ORDER.size())
	var panel_cx := RES_X + 41
	var col_dx := 18

	var layout_map := {
		0: [0, 0],
		3: [0, 1],
		4: [1, 0],
		1: [1, 1],
		2: [2, 0],
		5: [2, 1],
	}

	var row_y_offsets: Array[int] = [2, 42, 86]
	var label_y_offsets: Array[int] = [30, 74, 114]

	for i in RES_ORDER.size():
		var tex := UiKit.load_texture(RES + "%04d.png" % i)
		var iw := float(tex.get_width()) if tex != null else 39.0
		var ic := Sprite2D.new()
		ic.texture = tex
		ic.centered = false
		ic.z_index = 3
		var vl := mk_label(root, Vector2.ZERO, 11, font_big, font_small)
		vl.add_theme_color_override("font_color", Color.WHITE)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vl.z_index = 3
		if i < 6:
			var slot = layout_map[i]
			var row: int = slot[0]
			var col: int = slot[1]
			var cx := panel_cx + (col_dx if col == 1 else -col_dx)
			var iy := ROW_TOP + row_y_offsets[row]
			var ly := ROW_TOP + label_y_offsets[row]
			ic.position = Vector2(cx - iw / 2.0, iy)
			vl.position = Vector2(cx - 18, ly)
			vl.size = Vector2(36, 12)
		else:
			var iy := ROW_TOP + 126
			ic.position = Vector2(panel_cx - iw / 2.0, iy)
			vl.position = Vector2(panel_cx - 30, iy + 26)
			vl.size = Vector2(60, 12)
		root.add_child(ic)
		res_labels[i] = vl

	var btn := TextureButton.new()
	btn.texture_normal = UiKit.load_texture(EXIT_BTN + "0000.png")
	btn.texture_pressed = UiKit.load_texture(EXIT_BTN + "0001.png")
	btn.position = Vector2(panel_cx - 40, ROW_TOP + 166)
	btn.z_index = 4
	exit_btn = btn
	btn.pressed.connect(on_to_map_fn)
	btn.mouse_entered.connect(func(): if status_label != null: status_label.text = "Exit town")
	btn.mouse_exited.connect(func(): if status_label != null and status_label.text == "Exit town": status_label.text = "")
	root.add_child(btn)

	var strip := UiKit.load_texture(STRIP)
	if strip != null:
		var fr := Sprite2D.new()
		fr.texture = strip
		fr.centered = false
		fr.position = Vector2(0, STRIP_Y)
		fr.z_index = 5
		root.add_child(fr)

	name_label = mk_label(root, Vector2(240, STRIP_Y + 1), 12, font_big, font_small)
	name_label.size = Vector2(160, 14)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.z_index = 6

	var bar := UiKit.load_texture(STATUSBAR)
	if bar != null:
		var left := Sprite2D.new()
		left.texture = bar
		left.centered = false
		left.flip_h = true
		left.position = Vector2(0, 480 - 20)
		left.z_index = 7
		root.add_child(left)
		var right := Sprite2D.new()
		right.texture = bar
		right.centered = false
		right.position = Vector2(320, 480 - 20)
		right.z_index = 7
		root.add_child(right)
	status_label = mk_label(root, Vector2(0, 480 - 16), 13, font_big, font_small)
	status_label.size = Vector2(640, 16)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color.WHITE)
	status_label.z_index = 8

func refresh(root: Node2D, town_name: String, game: GameState, player: PlayerState,
		town_data: Dictionary, font_small: FontFile) -> void:
	if name_label != null:
		name_label.text = town_name
	refresh_hero_slot()
	refresh_crest_slot(player, town_data)
	if game != null:
		for i in RES_ORDER.size():
			if i >= res_labels.size() or res_labels[i] == null:
				continue
			var rname: String = RES_ORDER[i]
			var v := game.gold() if rname == "gold" else int(game.resources.get(rname, 0))
			res_labels[i].text = str(v)
	for n in army_nodes:
		if is_instance_valid(n):
			if hero_reveal_pending and int(n.get_meta("army_row", -1)) == 1:
				hero_reveal_underlay.append(n)
			else:
				n.queue_free()
	army_nodes.clear()
	render_row(root, 0, game, font_small)
	render_row(root, 1, game, font_small)
	if sel_row >= 0 and sel_col >= 0 and sel_col < UNIT_X.size():
		var hl := Sprite2D.new()
		hl.texture = UiKit.load_texture(HILITE)
		hl.centered = false
		hl.position = Vector2(UNIT_X[sel_col], ROW_Y[sel_row])
		hl.z_index = 5
		root.add_child(hl)
		army_nodes.append(hl)

func refresh_hero_slot() -> void:
	if hero_slot_art == null:
		return
	for child in hero_slot_art.get_children():
		if hero_reveal_pending:
			hero_reveal_underlay.append(child)
		else:
			child.queue_free()
	var path := PORT % Game.visiting_hero.portrait_idx \
			if Game.visiting_hero != null else KING_WIDE_FILL
	var sprite := Sprite2D.new()
	sprite.texture = UiKit.load_texture(path)
	sprite.centered = false
	sprite.position = Vector2(HERO_X, ROW_BOT)
	sprite.z_index = 2
	hero_slot_art.add_child(sprite)

func refresh_crest_slot(player: PlayerState, town_data: Dictionary) -> void:
	if crest_slot_art == null:
		return
	for child in crest_slot_art.get_children():
		if hero_reveal_pending:
			hero_reveal_underlay.append(child)
		else:
			child.queue_free()
	var crest_idx := 0
	if player != null:
		var color_base: int = (player.crest_idx / 4) * 4
		crest_idx = Game.visiting_hero.crest_idx if Game.visiting_hero != null \
				else color_base + int(town_data.get("crest_class", 0))
	var sprite := Sprite2D.new()
	sprite.texture = UiKit.load_texture(CRST % crest_idx)
	sprite.centered = false
	sprite.position = Vector2(HERO_X, ROW_TOP)
	sprite.z_index = 2
	crest_slot_art.add_child(sprite)

func render_row(root: Node2D, row: int, game: GameState, font_small: FontFile) -> void:
	var y: int = ROW_Y[row]
	var army := army_for_row(row, game)
	var pos: Array = pos_row[row]
	if army != null:
		reconcile_pos(row, game)
	for c in UNIT_X.size():
		var slot = pos[c] if (army != null and c < pos.size()) else null
		var bg_path := HORSE_FILL
		if slot != null:
			bg_path = CreatureCatalog.slot_background(String(slot.unit))
		var bg := Sprite2D.new()
		bg.texture = UiKit.load_texture(bg_path)
		bg.centered = false
		bg.position = Vector2(UNIT_X[c], y)
		bg.z_index = 1
		tag_army_art(bg, row, c, slot != null)
		root.add_child(bg)
		army_nodes.append(bg)
		if slot == null:
			continue
		var idx := CreatureCatalog.native_id(String(slot.unit))
		var tex := UiKit.load_texture(MONSTERS + "%04d.png" % idx)
		var por := Sprite2D.new()
		por.texture = tex
		por.centered = false
		por.position = CreatureCatalog.card_position(idx, Vector2(UNIT_X[c], y))
		por.z_index = 2
		tag_army_art(por, row, c, true)
		root.add_child(por)
		army_nodes.append(por)
		var cnt := Label.new()
		cnt.text = str(slot.count)
		cnt.position = Vector2(UNIT_X[c], y + 80)
		cnt.size = Vector2(77, 12)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if font_small != null:
			cnt.add_theme_font_override("font", font_small)
			cnt.add_theme_font_size_override("font_size", font_small.fixed_size)
		cnt.add_theme_color_override("font_color", Color.WHITE)
		cnt.add_theme_color_override("font_outline_color", Color.BLACK)
		cnt.add_theme_constant_override("outline_size", 2)
		cnt.z_index = 6
		tag_army_art(cnt, row, c, true)
		root.add_child(cnt)
		army_nodes.append(cnt)

func tag_army_art(node: CanvasItem, row: int, col: int, occupied: bool) -> void:
	node.set_meta("army_row", row)
	node.set_meta("army_col", col)
	node.set_meta("army_occupied", occupied)

func army_for_row(row: int, game: GameState) -> ArmyData:
	if row == 0:
		return game.town.army if (game != null and game.town != null) else null
	return Game.visiting_hero.army if Game.visiting_hero != null else null

func reconcile_pos(row: int, game: GameState) -> void:
	var pos: Array = pos_row[row]
	if pos.size() != UNIT_X.size():
		pos.resize(UNIT_X.size())
	var army := army_for_row(row, game)
	if army == null:
		return
	var slots: Array = army.slots
	for c in pos.size():
		if pos[c] != null and not _holds_same(slots, pos[c]):
			pos[c] = null
	for s in slots:
		if _holds_same(pos, s):
			continue
		var c: int = int(s.get("col", -1))
		if c >= 0 and c < pos.size() and pos[c] == null:
			pos[c] = s
	for s in slots:
		if _holds_same(pos, s):
			continue
		for c in pos.size():
			if pos[c] == null:
				pos[c] = s
				s["col"] = c
				break

## True when `list` holds this very stack. Godot compares dictionaries by
## value, so two stacks of the same creature and count look alike to `has()`:
## a garrison holding both would lose one of them to the panel.
static func _holds_same(list: Array, stack: Dictionary) -> bool:
	for item in list:
		if is_same(item, stack):
			return true
	return false

func sync_army(row: int, game: GameState) -> void:
	var army := army_for_row(row, game)
	if army == null:
		return
	var ordered: Array = []
	for c in pos_row[row].size():
		var s = pos_row[row][c]
		if s != null:
			s["col"] = c
			ordered.append(s)
	army.slots = ordered

func slot_at(p: Vector2, game: GameState) -> Vector2i:
	for row in ROW_Y.size():
		if army_for_row(row, game) == null:
			continue
		var y: int = ROW_Y[row]
		if p.y < y or p.y >= y + SLOT_H:
			continue
		for c in UNIT_X.size():
			if p.x >= UNIT_X[c] and p.x < UNIT_X[c] + SLOT_W:
				return Vector2i(c, row)
	return Vector2i(-1, -1)

func count_occupied_row(row: int) -> int:
	if row < 0 or row >= pos_row.size():
		return 0
	var count := 0
	for s in pos_row[row]:
		if s != null:
			count += 1
	return count

func open_creature_dialog(root: Node2D, col: int, row: int, player: PlayerState, refresh_fn: Callable) -> void:
	if army_dialog != null:
		return
	if row < 0 or row >= pos_row.size() or col < 0 or col >= pos_row[row].size():
		return
	var slot = pos_row[row][col]
	if slot == null:
		return

	var unit_name := String(slot.get("unit", ""))
	var count := int(slot.get("count", 0))
	var morale := 0
	var luck := 0
	var hero_attack := 0
	var hero_defense := 0
	var allow_dismiss := true

	var has_tavern: bool = player != null and player.town != null and bool(player.town.built.get("tavern", false))
	if row == 1 and Game.visiting_hero != null:
		morale = clampi(Game.visiting_hero.total_morale() + (1 if has_tavern else 0), -3, 3)
		luck = Game.visiting_hero.effective_luck()
		hero_attack = Game.visiting_hero.effective_attack()
		hero_defense = Game.visiting_hero.effective_defense()
		allow_dismiss = count_occupied_row(1) > 1
	elif row == 0:
		morale = 1 if has_tavern else 0
		luck = 0
		hero_attack = 0
		hero_defense = 0
		allow_dismiss = true

	var dlg := CreatureInfoDialog.new()
	root.add_child(dlg)
	dlg.setup_slot(
		unit_name,
		count,
		morale,
		luck,
		hero_attack,
		hero_defense,
		allow_dismiss,
		Vector2(119, 20)
	)
	dlg.dismissed.connect(func():
		pos_row[row][col] = null
		sel_row = -1
		sel_col = -1
		sync_army(row, Game.state)
		refresh_fn.call()
	)
	dlg.closed.connect(func():
		army_dialog = null
		sel_row = -1
		sel_col = -1
		refresh_fn.call()
	)
	army_dialog = dlg

func on_slot_click(root: Node2D, col: int, row: int, shift_pressed: bool,
		player: PlayerState, game: GameState, refresh_fn: Callable) -> void:
	if sel_row < 0:
		if pos_row[row][col] != null:
			sel_row = row
			sel_col = col
			sel_shift = shift_pressed
	elif sel_row == row and sel_col == col:
		if pos_row[row][col] != null:
			open_creature_dialog(root, col, row, player, refresh_fn)
		else:
			sel_row = -1
			sel_col = -1
			sel_shift = false
	else:
		var is_shift: bool = shift_pressed or sel_shift or Input.is_key_pressed(KEY_SHIFT)
		sel_shift = false
		var src: Array = pos_row[sel_row]
		var dst: Array = pos_row[row]
		var src_slot = src[sel_col]
		var dst_slot = dst[col]
		var src_unit := String(src_slot.get("unit", "")) if src_slot != null else ""
		var dst_unit := String(dst_slot.get("unit", "")) if dst_slot != null else ""
		var src_count := int(src_slot.get("count", 0)) if src_slot != null else 0

		if sel_row != row:
			var existing_dst_col := -1
			for c in dst.size():
				if dst[c] != null and String(dst[c].get("unit", "")) == src_unit:
					existing_dst_col = c
					break

			var can_split: bool = is_shift and src_count > 1 and (
				(existing_dst_col < 0 and dst_slot == null) or
				(existing_dst_col >= 0 and (col == existing_dst_col or dst_slot == null))
			)
			if can_split:
				var max_move := src_count
				if sel_row == 1 and row == 0 and count_occupied_row(1) <= 1:
					max_move = src_count - 1
					if max_move < 1:
						if status_label != null:
							status_label.text = "Cannot move last army to garrison."
						return
				var from_name := "Hero's Army" if sel_row == 1 else "Garrison"
				var to_name := "Garrison" if sel_row == 1 else "Hero's Army"
				var target_col := existing_dst_col if existing_dst_col >= 0 else col
				open_split_dialog(root, src_unit, from_name, to_name, src_count, max_move,
						sel_row, sel_col, row, target_col, game, refresh_fn)
				return

			if existing_dst_col >= 0:
				if sel_row == 1 and row == 0 and count_occupied_row(1) <= 1:
					if status_label != null:
						status_label.text = "Cannot combine Hero's last army"
					return
				dst[existing_dst_col] = {
					"unit": src_unit,
					"count": int(dst[existing_dst_col].get("count", 0)) + int(src_slot.get("count", 0))
				}
				src[sel_col] = null
			else:
				if sel_row == 1 and row == 0 and count_occupied_row(1) <= 1 and dst_slot == null:
					if status_label != null:
						status_label.text = "Cannot move last army to garrison."
					return
				dst[col] = src_slot
				src[sel_col] = dst_slot
				if dst_slot != null:
					for c in src.size():
						if c != sel_col and src[c] != null and String(src[c].get("unit", "")) == dst_unit:
							src[c] = {"unit": dst_unit,
									"count": int(src[c].get("count", 0)) + int(dst_slot.get("count", 0))}
							src[sel_col] = null
							break
		else:
			if dst_slot != null and src_slot != null and dst_unit == src_unit:
				dst[col] = {
					"unit": dst_unit,
					"count": int(dst_slot.get("count", 0)) + int(src_slot.get("count", 0))
				}
				src[sel_col] = null
			else:
				dst[col] = src_slot
				src[sel_col] = dst_slot
		sel_row = -1
		sel_col = -1
		sync_army(0, game)
		sync_army(1, game)
	refresh_fn.call()

func open_split_dialog(root: Node2D, unit: String, from_name: String, to_name: String,
		src_count: int, max_move: int, s_row: int, s_col: int, d_row: int, d_col: int,
		game: GameState, refresh_fn: Callable) -> void:
	if split_dialog != null:
		return
	var dlg := SplitDialog.new()
	root.add_child(dlg)
	split_dialog = dlg
	dlg.open(unit, from_name, to_name, 1, max_move)
	dlg.confirmed.connect(func(qty: int):
		var src: Array = pos_row[s_row]
		var dst: Array = pos_row[d_row]
		var s_slot = src[s_col]
		if s_slot == null:
			return
		if dst[d_col] == null:
			dst[d_col] = { "unit": unit, "count": qty }
		else:
			dst[d_col] = { "unit": unit, "count": int(dst[d_col].get("count", 0)) + qty }
		var rem := int(s_slot.get("count", 0)) - qty
		if rem <= 0:
			src[s_col] = null
		else:
			src[s_col] = { "unit": unit, "count": rem }
		sel_row = -1
		sel_col = -1
		sync_army(0, game)
		sync_army(1, game)
		refresh_fn.call()
	)
	dlg.closed.connect(func():
		split_dialog = null
		sel_row = -1
		sel_col = -1
		refresh_fn.call()
	)

func start_hero_recruit_reveal() -> void:
	if hero_reveal_active:
		finish_hero_recruit_reveal()
	hero_reveal_parts.clear()
	var targets: Array = []
	if crest_slot_art != null and crest_slot_art.get_child_count() > 0:
		targets.append(crest_slot_art.get_child(crest_slot_art.get_child_count() - 1))
	if hero_slot_art != null and hero_slot_art.get_child_count() > 0:
		targets.append(hero_slot_art.get_child(hero_slot_art.get_child_count() - 1))
	for node: CanvasItem in army_nodes:
		if int(node.get_meta("army_row", -1)) == 1 \
				and bool(node.get_meta("army_occupied", false)):
			targets.append(node)
	for node: CanvasItem in targets:
		var reveal_material := ShaderMaterial.new()
		reveal_material.shader = CONSTRUCTION_REVEAL_SHADER
		reveal_material.set_shader_parameter("reveal_progress", 0.0)
		reveal_material.set_shader_parameter("pattern_offset", node.get_global_transform().origin)
		reveal_material.set_shader_parameter("block_size", 1.0)
		hero_reveal_parts.append({
			"node": node,
			"material": node.material,
			"reveal_material": reveal_material,
		})
		node.material = reveal_material
	hero_reveal_pending = false
	hero_reveal_elapsed = 0.0
	hero_reveal_active = not hero_reveal_parts.is_empty()

func apply_hero_recruit_reveal() -> void:
	var progress := clampf(hero_reveal_elapsed / HERO_RECRUIT_REVEAL_DURATION, 0.0, 1.0)
	for part: Dictionary in hero_reveal_parts:
		(part.reveal_material as ShaderMaterial).set_shader_parameter("reveal_progress", progress)

func finish_hero_recruit_reveal() -> void:
	for part: Dictionary in hero_reveal_parts:
		var node: CanvasItem = part.node
		if is_instance_valid(node):
			node.material = part.material
	for node: CanvasItem in hero_reveal_underlay:
		if is_instance_valid(node):
			node.queue_free()
	hero_reveal_parts.clear()
	hero_reveal_underlay.clear()
	hero_reveal_pending = false
	hero_reveal_active = false
	hero_reveal_elapsed = 0.0

func process(delta: float) -> void:
	if hero_reveal_active:
		hero_reveal_elapsed += delta
		apply_hero_recruit_reveal()
		if hero_reveal_elapsed >= HERO_RECRUIT_REVEAL_DURATION:
			finish_hero_recruit_reveal()

static func hover_name(unit: String) -> String:
	return CreatureCatalog.singular(unit).to_lower()
