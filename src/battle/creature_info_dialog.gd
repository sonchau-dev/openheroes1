class_name CreatureInfoDialog
extends CanvasLayer

## Native HOMM1 troop window: VIEWARMY frame/count strip/animated unit/Exit control.

signal closed
signal dismissed

const CreatureCatalogScript := preload("res://src/battle/creature_catalog.gd")
const MONSTERS := UiKit.ART + "monsters/"
const VIEWARMY := UiKit.ART + "viewarmy/"

const DIALOG_POS := Vector2(42, 58)
const DIALOG_SIZE := Vector2(402, 229)
const PORTRAIT_BOX := Rect2(30, 39, 133, 132)

func setup(stack: BattleStack, morale := 0, luck := 0,
		effective_attack := -1, effective_defense := -1) -> void:
	_build(
		stack.unit,
		stack.count,
		morale,
		luck,
		effective_attack if effective_attack >= 0 else stack.attack,
		effective_defense if effective_defense >= 0 else stack.defense,
		false,
		DIALOG_POS,
		false,
		stack.shots,
		stack.attack,
		stack.defense,
		stack.damage_min,
		stack.damage_max,
		stack.hp_max,
		false
	)

func setup_slot(unit: String, count: int, morale := 0, luck := 0,
		hero_attack := 0, hero_defense := 0, allow_dismiss := false,
		pos := Vector2(119, 20)) -> void:
	var stats := CreatureCatalogScript.stats(unit)
	var base_atk: int = int(stats.get("attack", 0))
	var base_def: int = int(stats.get("defense", 0))
	var eff_atk: int = base_atk + hero_attack
	var eff_def: int = base_def + hero_defense
	_build(
		unit,
		count,
		morale,
		luck,
		eff_atk,
		eff_def,
		allow_dismiss,
		pos,
		true,
		int(stats.get("shots", 0)),
		base_atk,
		base_def,
		int(stats.get("damage_min", 0)),
		int(stats.get("damage_max", 0)),
		int(stats.get("hp", 1)),
		true
	)

func _build(unit: String, count: int, morale: int, luck: int,
		effective_attack: int, effective_defense: int, allow_dismiss: bool,
		dialog_pos: Vector2, show_base_and_effective: bool,
		shots: int = -1, base_attack: int = -1, base_defense: int = -1,
		damage_min: int = -1, damage_max: int = -1, hp: int = -1,
		rich_spirit: bool = false) -> void:
	layer = 250

	var blocker := ColorRect.new()
	blocker.name = "InputBlocker"
	blocker.color = Color(0, 0, 0, 0)
	blocker.size = Vector2(640, 480)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.gui_input.connect(_on_blocker_input)
	add_child(blocker)

	var dialog := Control.new()
	dialog.name = "CreatureInfo"
	dialog.position = dialog_pos
	dialog.size = DIALOG_SIZE
	dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dialog)

	var background := UiKit.add_texture(dialog, VIEWARMY + "0000.png")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var font := UiKit.font_normal()
	var stats := CreatureCatalogScript.stats(unit)
	var title_name := CreatureCatalogScript.singular(unit).capitalize()
	UiKit.add_label(dialog, title_name, Vector2(190, 22), Vector2(185, 18),
			font, Color8(240, 240, 240), HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, "Title")

	# Animated creature walking/standing in place at native 10 FPS measured from original video
	var anim_creature := Creature.new()
	anim_creature.name = "AnimatedCreature"
	anim_creature.setup(StringName(unit))
	anim_creature.set_custom_fps(10.0)
	if anim_creature.has_anim(&"wip"):
		anim_creature.play(&"wip")
	elif anim_creature.has_anim(&"walk"):
		anim_creature.play(&"walk")
	else:
		anim_creature.play(&"idle")
	var center_off_x := 0.0
	var cur_anim := anim_creature.current_anim()
	var frames := anim_creature.get_anim_frames(cur_anim)
	if not frames.is_empty() and frames[0].body_tex != null:
		var tex: Texture2D = frames[0].body_tex
		center_off_x = float(frames[0].body_off.x) + float(tex.get_width()) / 2.0
	anim_creature.position = Vector2(round(110.5 - center_off_x), 168.0)
	dialog.add_child(anim_creature)

	# Static portrait node preserved for backwards compatibility and test verification
	var native_id := CreatureCatalogScript.native_id(unit)
	var portrait := load(MONSTERS + "%04d.png" % (native_id if native_id >= 0 else 0)) as Texture2D
	if portrait != null:
		var image := TextureRect.new()
		image.name = "Portrait"
		image.texture = portrait
		image.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.position = PORTRAIT_BOX.position
		image.size = PORTRAIT_BOX.size
		image.visible = false
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dialog.add_child(image)

	var count_back := UiKit.add_texture(dialog, VIEWARMY + "0001.png", Vector2(41, 174))
	count_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.add_label(dialog, str(count), Vector2(41, 174), Vector2(142, 38),
			font, Color8(240, 240, 240), HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, "Count")

	var b_atk := base_attack if base_attack >= 0 else int(stats.get("attack", 0))
	var b_def := base_defense if base_defense >= 0 else int(stats.get("defense", 0))
	var atk_str := "%d (%d)" % [b_atk, effective_attack] if (show_base_and_effective and effective_attack != b_atk) else str(effective_attack)
	var def_str := "%d (%d)" % [b_def, effective_defense] if (show_base_and_effective and effective_defense != b_def) else str(effective_defense)

	var d_min := damage_min if damage_min >= 0 else int(stats.get("damage_min", 0))
	var d_max := damage_max if damage_max >= 0 else int(stats.get("damage_max", 0))
	var dmg_str := str(d_min) if (d_min == d_max and show_base_and_effective) else "%d-%d" % [d_min, d_max]

	var hp_val := hp if hp >= 0 else int(stats.get("hp", 1))
	var unit_shots := shots if shots >= 0 else int(stats.get("shots", 0))

	var rows: Array = [
		["AttackSkill", "Attack Skill:", atk_str],
		["DefenseSkill", "Defense Skill:", def_str],
	]
	if unit_shots > 0:
		rows.append(["Shots", "Shots:", str(unit_shots)])
	rows.append(["Damage", "Damage:", dmg_str])
	rows.append(["HitPoints", "Hit Points:", str(hp_val)])
	rows.append(["Speed", "Speed:", String(stats.get("speed_name", "Slow"))])
	rows.append(["Morale", "Morale:", _spirit_name(int(morale), rich_spirit, false)])
	rows.append(["Luck", "Luck:", _spirit_name(int(luck), rich_spirit, true)])

	var row_y := 42.0 if unit_shots > 0 else 46.0
	var step_y := 15.0 if unit_shots > 0 else 16.0

	for i in rows.size():
		var row: Array = rows[i]
		_add_stat_row(dialog, String(row[0]), String(row[1]), String(row[2]), row_y + i * step_y, font)

	if allow_dismiss:
		var dismiss_button := IcnButton.new()
		dismiss_button.name = "Dismiss"
		dismiss_button.setup(VIEWARMY, 2, "dismiss")
		dismiss_button.position = Vector2(200, 181)
		dismiss_button.pressed.connect(func(_action):
			dismissed.emit()
			_close()
		)
		dialog.add_child(dismiss_button)

		var exit_button := IcnButton.new()
		exit_button.name = "Exit"
		exit_button.setup(VIEWARMY, 4, "exit")
		exit_button.position = Vector2(295, 181)
		exit_button.pressed.connect(func(_action): _close())
		dialog.add_child(exit_button)
	else:
		var exit_button := IcnButton.new()
		exit_button.name = "Exit"
		exit_button.setup(VIEWARMY, 4, "exit")
		exit_button.position = Vector2(282, 181)
		exit_button.pressed.connect(func(_action): _close())
		dialog.add_child(exit_button)

func _spirit_name(value: int, rich: bool = false, is_luck: bool = false) -> String:
	if not rich:
		if value > 0:
			return "Good"
		if value < 0:
			return "Bad"
		return "Normal"
	if is_luck:
		match clampi(value, -3, 3):
			3: return "Irish"
			2: return "Great"
			1: return "Good"
			0: return "Normal"
			-1: return "Bad"
			-2: return "Awful"
			-3: return "Cursed"
			_: return "Normal"
	else:
		match clampi(value, -3, 3):
			3: return "Blood!"
			2: return "Great"
			1: return "Good"
			0: return "Normal"
			-1: return "Poor"
			-2: return "Awful"
			-3: return "Treason"
			_: return "Normal"

func _add_stat_row(parent: Control, key: String, label_text: String, value_text: String,
		y: float, font: Font) -> void:
	var full_text := "%s %s" % [label_text, value_text]
	UiKit.add_label(parent, full_text,
			Vector2(190, y), Vector2(186, 16), font, Color8(240, 240, 240),
			HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, key)
	var val_lbl := UiKit.add_label(parent, value_text,
			Vector2(190, y), Vector2(186, 16), font, Color8(240, 240, 240),
			HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, "Value" + key)
	val_lbl.visible = false

func _on_blocker_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_close()
			get_viewport().set_input_as_handled()

func _close() -> void:
	closed.emit()
	queue_free()
