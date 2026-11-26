class_name MapDialogs

## Modal helpers for the adventure map (plain v1 style, matches game_over_dialog.gd).

class InfoDialog extends MessageBox:
	## A right-click popup: no OKAY, gone when the button is let go (style 4).
	var hold := false
	## Set by info() before setup(): true when the box sits on a full-screen
	## panel (town, spellbook, system menu) rather than the adventure map.
	var screen_centered := false

	func setup(lines_or_text: Variant) -> void:
		layer = 220
		var text := ""
		if lines_or_text is Array:
			var parts: Array[String] = []
			for item in lines_or_text:
				parts.append(String(item))
			text = "\n".join(parts)
		else:
			text = String(lines_or_text)
		build(text, HOLD if hold else OKAY, [], not screen_centered)

	func _window_name() -> String:
		return "InfoDialog"


class ChoiceDialog extends CanvasLayer:
	signal chosen(idx: int)
	var on_pick: Callable
	var count: int = 1
	var _closing := false

	func _unhandled_input(event: InputEvent) -> void:
		if not (event is InputEventKey) or not event.pressed or event.echo:
			return
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			choose(0)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			choose(count - 1)
			get_viewport().set_input_as_handled()

	func choose(idx: int) -> void:
		if _closing:
			return
		_closing = true
		chosen.emit(idx)
		queue_free()
		if on_pick.is_valid():
			on_pick.call(idx)


## Authentic HOMM1 modal info dialog (evntwin1..3 BUYBUILD frame + SYSTEM OKAY).
static func info(parent: Node, data: Dictionary) -> CanvasLayer:
	var lines_or_text: Variant = data.get("lines", data.get("text", ""))
	var dlg := InfoDialog.new()
	dlg.on_close = data.get("on_close", Callable())
	dlg.hold = bool(data.get("hold", false))
	dlg.screen_centered = bool(data.get("centered", false))
	parent.add_child(dlg)
	dlg.setup(lines_or_text)
	return dlg

## Message box with a player's crest under the text (lost last town, days left
## to capture one, vanquished). `color_index`: 0 blue, 1 green, 2 red, 3 yellow.
static func crest_info(parent: Node, color_index: int, text: String) -> CanvasLayer:
	var dlg := CrestMessageDialog.new()
	parent.add_child(dlg)
	dlg.setup(color_index, text)
	return dlg

## End Turn is the only destructive adventure-map button that asks for
## confirmation, and only when at least one hero can still make a step.
static func end_turn_confirm(parent: Node, on_pick: Callable) -> CanvasLayer:
	var dlg := load("res://src/ui/turn_event_dialog.gd").new() as CanvasLayer
	parent.add_child(dlg)
	dlg.call("setup", "One or more Heroes may still move, are you sure you want to end your turn?", true)
	dlg.connect("chosen", func(idx: int): on_pick.call(idx))
	return dlg

## Week-boundary astrologer proclamation. The caller retains the returned
## layer so the dawn card can stay visible until the player dismisses it.
static func new_week(parent: Node, message: String) -> CanvasLayer:
	var dlg := load("res://src/ui/turn_event_dialog.gd").new() as CanvasLayer
	parent.add_child(dlg)
	dlg.call("setup", message, false)
	return dlg

## Town Portal with more than one friendly town: pick which one to jump to.
static func town_picker(parent: Node, towns: Array, on_pick: Callable) -> void:
	var dlg := CanvasLayer.new()
	dlg.layer = 200
	parent.add_child(dlg)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.position = Vector2.ZERO
	dim.size = Vector2(640, 480)
	dlg.add_child(dim)
	var panel := PanelContainer.new()
	panel.position = Vector2(220, 140)
	panel.custom_minimum_size = Vector2(200, 40.0 + towns.size() * 28.0)
	dlg.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	var title := Label.new()
	title.text = "Choose a town"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for t: Vector2i in towns:
		var btn := Button.new()
		btn.text = "Town (%d, %d)" % [t.x, t.y]
		btn.pressed.connect(func():
			dlg.queue_free()
			on_pick.call(t)
		)
		box.add_child(btn)

## Generic N-button choice dialog (chest gold-vs-exp, etc. — VisitResult.choice).
## on_pick receives the chosen option's index; same plain-panel style as town_picker.
static func choice(parent: Node, prompt: String, labels: Array, metadata: Dictionary,
		on_pick: Callable) -> void:
	var choice_type := String(metadata.get("type", ""))
	if choice_type in ["demon_cave_enter", "demon_cave_ransom"]:
		demon_cave_choice(parent, prompt, on_pick)
		return
	if choice_type == "event_enter":
		event_choice(parent, String(metadata.get("title", "")), prompt, on_pick)
		return
	if choice_type == "demon_cave_death":
		var death_dialog := demon_cave_info(parent, prompt)
		death_dialog.connect("chosen", func(_idx: int): on_pick.call(0))
		return
	if choice_type == "artifact_paid":
		var artifact_id := String(metadata.get("artifact_id", ""))
		if artifact_id == "":
			for opt: Dictionary in metadata.get("options", []):
				if opt.has("artifact"):
					artifact_id = String(opt.get("artifact", ""))
					break
		paid_artifact_offer(parent, artifact_id, on_pick)
		return
	if choice_type == "chest":
		var gold := int(metadata.get("gold", 0))
		var exp := int(metadata.get("exp", 0))
		if gold > 0 and exp > 0:
			chest_choice(parent, gold, exp, on_pick)
			return
	var dlg := ChoiceDialog.new()
	dlg.on_pick = on_pick
	dlg.count = labels.size()
	dlg.layer = 200
	parent.add_child(dlg)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.position = Vector2.ZERO
	dim.size = Vector2(640, 480)
	dlg.add_child(dim)
	var panel := PanelContainer.new()
	panel.position = Vector2(200, 150)
	panel.custom_minimum_size = Vector2(240, 40.0 + labels.size() * 28.0)
	dlg.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	var title := Label.new()
	title.text = prompt
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(title)
	for i in labels.size():
		var idx := i
		var btn := Button.new()
		btn.text = String(labels[i])
		btn.pressed.connect(dlg.choose.bind(idx))
		box.add_child(btn)

static func mine_captured(parent: Node, res: String) -> CanvasLayer:
	var dlg = load("res://src/ui/mine_capture_dialog.gd").new()
	parent.add_child(dlg)
	dlg.setup(res)
	return dlg

## Canonical titled Daemon Cave event windows. Entry/ransom use native Yes/No
## controls; revisit, victory, and insufficient-gold death use native Okay.
static func demon_cave_choice(parent: Node, message: String, on_pick: Callable) -> CanvasLayer:
	var dlg := load("res://src/ui/demon_cave_dialog.gd").new() as CanvasLayer
	parent.add_child(dlg)
	dlg.call("setup", message, true)
	dlg.connect("chosen", func(idx: int): on_pick.call(idx))
	return dlg

static func demon_cave_info(parent: Node, message: String, artifact_id: String = "") -> CanvasLayer:
	var dlg := load("res://src/ui/demon_cave_dialog.gd").new() as CanvasLayer
	parent.add_child(dlg)
	dlg.call("setup", message, false, artifact_id)
	return dlg

## The same titled event window for the other heroes.exe visit messages
## (message table at data 0x20e44): Yes/No for a prompt, Okay otherwise.
static func event_choice(parent: Node, title_text: String, message: String,
		on_pick: Callable) -> CanvasLayer:
	# heroes.exe's ordinary Yes/No message box: the title is the copy's first
	# line, a blank line, then the body (message table "Title\n\nBody").
	var dlg := load("res://src/ui/turn_event_dialog.gd").new() as CanvasLayer
	parent.add_child(dlg)
	dlg.call("setup", title_text + "\n\n" + message, true)
	dlg.connect("chosen", func(idx: int): on_pick.call(idx))
	return dlg

## The original Oracle interaction is titled "Shrine". Its Okay button opens
## the ranking screen only after the introduction has closed.
static func shrine(parent: Node, message: String, on_close: Callable) -> CanvasLayer:
	var dlg := load("res://src/ui/shrine_dialog.gd").new() as CanvasLayer
	parent.add_child(dlg)
	dlg.call("setup", message)
	dlg.connect("closed", func():
		if on_close.is_valid():
			on_close.call()
	)
	return dlg

## Reference-confirmed Spell Shrine event window (evntwin4 / evntwin5).
static func spell_shrine(parent: Node, spell_id: String, has_spellbook: bool) -> CanvasLayer:
	var dlg := load("res://src/ui/spell_shrine_dialog.gd").new() as CanvasLayer
	parent.add_child(dlg)
	dlg.call("setup", spell_id, has_spellbook)
	return dlg

## Reference-confirmed Obelisk inscription window.
static func obelisk(parent: Node, message: String,
		on_close: Callable = Callable(), already_visited: bool = false) -> CanvasLayer:
	var dlg := load("res://src/ui/obelisk_dialog.gd").new() as CanvasLayer
	parent.add_child(dlg)
	dlg.call("setup", message, already_visited)
	dlg.connect("closed", func():
		if on_close.is_valid():
			on_close.call()
	)
	return dlg

## Paid-artifact leprechaun offer dialog (evntwin5 + artifact icon + YES/NO).
static func paid_artifact_offer(parent: Node, artifact_id: String, on_pick: Callable) -> CanvasLayer:
	var dlg := load("res://src/ui/paid_artifact_dialog.gd").new() as CanvasLayer
	parent.add_child(dlg)
	dlg.call("setup_offer", artifact_id)
	dlg.connect("chosen", func(idx: int): on_pick.call(idx))
	return dlg

## Paid-artifact refusal dialog when declined (evntwin2 + OKAY).
static func paid_artifact_refusal(parent: Node, on_close: Callable = Callable()) -> CanvasLayer:
	var dlg := load("res://src/ui/paid_artifact_dialog.gd").new() as CanvasLayer
	parent.add_child(dlg)
	dlg.call("setup_refusal")
	if on_close.is_valid():
		dlg.connect("closed", on_close)
	return dlg

## Artifact-acquisition event window (encounter text + native inventory icon).
static func artifact(parent: Node, artifact_id: String, message: String = "",
		gold := 0) -> CanvasLayer:
	var dlg = load("res://src/ui/artifact_pickup_dialog.gd").new()
	parent.add_child(dlg)
	dlg.setup(artifact_id, message, gold)
	return dlg

## Artifact info box (heroes.exe 0xb1a7c): OKAY for a left-click, a
## press-and-hold popup for a right-click.
static func artifact_info(parent: Node, artifact_id: String, hold := false) -> void:
	var dlg = load("res://src/ui/artifact_info_dialog.gd").new()
	parent.add_child(dlg)
	dlg.setup(artifact_id, hold)

static func morale_info(parent: Node, hero: HeroModel) -> CanvasLayer:
	var dlg = load("res://src/ui/hero_stat_dialog.gd").new()
	parent.add_child(dlg)
	dlg.setup_morale(hero)
	return dlg

static func luck_info(parent: Node, hero: HeroModel) -> CanvasLayer:
	var dlg = load("res://src/ui/hero_stat_dialog.gd").new()
	parent.add_child(dlg)
	dlg.setup_luck(hero)
	return dlg

static func experience_info(parent: Node, hero: HeroModel) -> CanvasLayer:
	var dlg = load("res://src/ui/hero_stat_dialog.gd").new()
	parent.add_child(dlg)
	dlg.setup_experience(hero)
	return dlg

static func attack_info(parent: Node) -> CanvasLayer:
	var dlg = load("res://src/ui/hero_stat_dialog.gd").new()
	parent.add_child(dlg)
	dlg.setup_attack()
	return dlg

static func defense_info(parent: Node) -> CanvasLayer:
	var dlg = load("res://src/ui/hero_stat_dialog.gd").new()
	parent.add_child(dlg)
	dlg.setup_defense()
	return dlg

static func spell_power_info(parent: Node) -> CanvasLayer:
	var dlg = load("res://src/ui/hero_stat_dialog.gd").new()
	parent.add_child(dlg)
	dlg.setup_spell_power()
	return dlg

static func knowledge_info(parent: Node) -> CanvasLayer:
	var dlg = load("res://src/ui/hero_stat_dialog.gd").new()
	parent.add_child(dlg)
	dlg.setup_knowledge()
	return dlg

## Authentic confirmation popup using evntwin1 frame and YES/NO buttons.
## idx 0 = YES, idx 1 = NO / cancelled.
static func confirm(parent: Node, message: String, on_pick: Callable) -> CanvasLayer:
	var dlg = load("res://src/ui/hero_dismiss_dialog.gd").new()
	parent.add_child(dlg)
	dlg.layer = 220
	dlg.setup(message)
	dlg.chosen.connect(func(idx: int): on_pick.call(idx))
	return dlg

static func dismiss_hero_confirm(parent: Node, on_pick: Callable) -> CanvasLayer:
	return confirm(parent, "Are you sure you want to dismiss this Hero?", on_pick)

## One popup for an award, naming every level it crossed and the skills
## gained, as heroes.exe's 0xb22c8 builds it.
static func level_ups(parent: Node, hero: HeroModel, events: Array[Dictionary],
		on_finished: Callable = Callable()) -> CanvasLayer:
	if events.is_empty():
		if on_finished.is_valid():
			on_finished.call()
		return null
	var dlg := load("res://src/ui/hero_level_up_dialog.gd").new() as CanvasLayer
	parent.add_child(dlg)
	dlg.call("setup", hero, events)
	if on_finished.is_valid():
		dlg.connect("closed", on_finished)
	return dlg

## Windmill/Watermill weekly-visit popup (title + keeper-of-the-mill flavor
## text + granted resource icon/amount, matching a human-supplied reference
## screenshot). `granted` empty means the "nothing available this week" revisit.
static func weekly_pickup(parent: Node, obj_type: String, message: String, granted: Dictionary) -> CanvasLayer:
	var dlg = load("res://src/ui/weekly_pickup_dialog.gd").new()
	parent.add_child(dlg)
	dlg.setup(obj_type, message, granted)
	return dlg

## Campfire visit window: message 0x0e with the gold and resource granted.
static func campfire(parent: Node, message: String, granted: Dictionary) -> CanvasLayer:
	var dlg := CampfireDialog.new()
	parent.add_child(dlg)
	dlg.setup(message, granted)
	return dlg

## Statue/gazebo/fountain/etc. stat_boost visit popup (StatBoostDialog).
static func stat_boost(parent: Node, obj_type: String, message: String,
		already_visited: bool = false, amount: int = 1000) -> CanvasLayer:
	var dlg = load("res://src/ui/stat_boost_dialog.gd").new()
	parent.add_child(dlg)
	dlg.setup(obj_type, message, already_visited, amount)
	return dlg

static func recruit_dwelling(parent: Node, dwelling: Dwelling, player: PlayerState,
		army: ArmyData, on_recruited: Callable) -> CanvasLayer:
	var dlg := load("res://src/ui/rogue_camp_dialog.gd").new() as CanvasLayer
	parent.add_child(dlg)
	dlg.call("setup", dwelling, player, army)
	dlg.connect("recruited", func(quantity: int): on_recruited.call(quantity))
	return dlg

static func rogue_camp(parent: Node, dwelling: Dwelling, player: PlayerState,
		army: ArmyData, on_recruited: Callable) -> CanvasLayer:
	return recruit_dwelling(parent, dwelling, player, army, on_recruited)

static func chest_choice(parent: Node, gold: int, exp: int, on_pick: Callable) -> void:
	var dlg = load("res://src/ui/treasure_chest_dialog.gd").new()
	parent.add_child(dlg)
	dlg.setup(gold, exp)
	dlg.chosen.connect(func(idx: int): on_pick.call(idx))

## Authentic HOMM1 free dwelling confirmation popup (Thatched Hut, etc.).
static func free_dwelling(parent: Node, dwelling: Dwelling, on_pick: Callable) -> CanvasLayer:
	var dlg := load("res://src/ui/free_dwelling_dialog.gd").new() as CanvasLayer
	parent.add_child(dlg)
	# The visit message's own title (heroes.exe messages 0x17..0x25: Hut,
	# Thatched Hut, Cottage), not the object name the quick info shows.
	var title_text: String = load("res://src/adventure/objects/handlers/dwelling.gd").visit_title(dwelling)
	if title_text == "":
		var unit := dwelling.unit
		match unit:
			"nomad":
				title_text = "Desert Tent"
			"rogue":
				title_text = "Wagon Camp"
			"genie":
				title_text = "Ancient Lamp"
			_:
				for faction: String in BuildingCatalog.FACTIONS:
					var dw_id := BuildingCatalog.dwelling_for_unit(unit, faction)
					if dw_id != "":
						title_text = String(BuildingCatalog.entry(dw_id, faction).get("name", ""))
						break
				if title_text == "":
					title_text = "%s Hut" % CreatureCatalog.singular(unit).capitalize()
	var plural_name := CreatureCatalog.plural(dwelling.unit).to_lower()
	var message := "A group of %s with a desire for greater glory wish to join you. Do you accept?" % plural_name
	dlg.call("setup", title_text, message)
	dlg.connect("chosen", func(idx: int): on_pick.call(idx))
	return dlg

## Authentic HOMM1 wandering monster join offer ("Followers").
## Uses evntwin2 frame and YES/NO buttons.
static func followers_join(parent: Node, unit: String, on_pick: Callable) -> CanvasLayer:
	var dlg := load("res://src/ui/free_dwelling_dialog.gd").new() as CanvasLayer
	parent.add_child(dlg)
	var title_text := "Followers"
	var plural_name := CreatureCatalog.plural(unit).to_lower()
	var message := "A group of %s with a desire for greater glory wish to join you. Do you accept?" % plural_name
	dlg.call("setup", title_text, message)
	dlg.connect("chosen", func(idx: int): on_pick.call(idx))
	return dlg

## Authentic HOMM1 refusal message after declining a join offer.
## Insulted by your refusal of their offer, the monsters attack!
static func followers_refusal(parent: Node, on_dismiss: Callable) -> CanvasLayer:
	var dlg := info(parent, {
		"title": "Followers",
		"lines": ["Insulted by your refusal of", "their offer, the monsters attack!"],
		"on_close": on_dismiss,
	})
	return dlg

