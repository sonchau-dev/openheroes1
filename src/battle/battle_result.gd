# src/battle/battle_result.gd
class_name BattleResult
extends CanvasLayer

## End-of-combat result screen.
## Both outcomes use the winlose.bmp dialog: wincmbt.bin and losecmbt.bin are
## 320x458 windows that heroes.exe opens at (159,2) (0xc15fd, 0xc1a18), with
## the scene rect (49,38) 223x125, the text field (28,176) 264 wide and OKAY
## at (120,414).
## Victory: animated wincmbt scene (the army cheers) + the XP award line.
## Defeat: the scene cutout holds the losecmbt panorama scrolling left while
## the hero rides in place (losewalk).
## Both list Battlefield Casualties and close via their own OKAY button.

signal closed

const WIN := UiKit.ART + "wincmbt/"
const LOSE_DIALOG := UiKit.ART + "winlose.png"
const LOSE_BG := UiKit.ART + "losecmbt.png"
const LOSE_BTN := UiKit.ART + "losecmbt/"
const WALK := UiKit.ART + "losewalk/"
const MONS32 := UiKit.ART + "mons32/"
const ARTIFACT_FRAME := UiKit.ART + "winloseb/0000.png"
const CAPTURED_ARTIFACT := "You have captured an enemy artifact!"
const CreatureCatalogScript := preload("res://src/battle/creature_catalog.gd")

const SCENE_SIZE := Vector2(223, 125)       # wincmbt backdrop size (spec.json)
const SCENE_ANIM_OFFSET := Vector2(19, 7)   # frames 1-6 offset (wincmbt spec.json)
const ANIM_FRAME_S := 0.15

# Shared dialog geometry (wincmbt.bin / losecmbt.bin). winlose.png is
# 324x459; the window clips it to its own 320x458, as the DOS capture shows.
const DIALOG_POS := Vector2(159, 2)
const DIALOG_SIZE := Vector2(320, 458)
const SCENE_POS := Vector2(49, 38)
const TEXT_POS := Vector2(28, 176)
const TEXT_SIZE := Vector2(264, 200)
const OKAY_POS := Vector2(120, 414)
# Casualty block (heroes.exe 0xc0bb8): header at y 260, the attacker's row
# at 280 and the defender's at 345, each a label, then 40 px icon slots
# (32x28 boxes, frame offset applied) 15 below and counts 46 below, or
# "None" 18 below.
const CASUALTY_HEADER_Y := 260
const CASUALTY_ROW_Y := [280, 345]
const CASUALTY_SLOT := 40

# Defeat animation (heroes.exe 0xc1c26..0xc1ce0): every 12 ticks of the 64 Hz
# timer the rider (anchored at screen 270,140, frame offset applied) takes
# the next of 8 frames and the panorama's source x moves 2 px, jumping back
# to 0 once past 416 (the 640-wide strip's last 223-wide slice). Both start
# at 0, and the first state is drawn twice before the first step.
const LOSE_STEP_S := 12.0 / 64.0
const LOSE_PAN_STEP := 2
const LOSE_PAN_MAX := 416
const RIDER_SCREEN := Vector2(270, 140)

var _root: Control = null           # victory dialog root
var _anim_sprite: TextureRect = null
var _anim_time := 0.0
var _anim_frame := 1                # cycles 1..6
var _walk: TextureRect = null       # defeat rider
var _walk_time := -LOSE_STEP_S
var _walk_frame := 0
var _lose_pan: TextureRect = null   # the panorama, slid left inside the cutout
var _lose_pan_x := 0
var _text: Label = null             # the window's one big text field
var _casualty_nodes: Array[Node] = []
var _artifact_queue: Array = []     # captured artifact ids still to show
var _artifact_nodes: Array[Node] = []

## The victory window's text field (heroes.exe 0xc15c3): the title from the
## table at data 0x216e0, then, when the winner has a hero, the experience
## line strcat'd onto it with no full stop (data 0xc328). The level variant
## (0xc472) is used only when the defender wins in a game with more than one
## human (0xc16a7).
static func victory_text(hero_name: String, xp: int, outcome: StringName = &"",
		levels := 0) -> String:
	var title := "A glorious victory!"
	if outcome == &"surrender":
		title = "The enemy has surrendered!"
	elif outcome == &"retreat":
		title = "The enemy has fled!"
	if hero_name == "":
		return title
	if levels > 0:
		return title + "\n\nFor valor in combat, %s receives %d experience, and gains %d level(s)." \
				% [hero_name, xp, levels]
	return title + "\n\nFor valor in combat, %s receives %d experience" % [hero_name, xp]

## The defeat window's text field (heroes.exe 0xc192f), with or without a hero.
static func defeat_text(hero_name: String, outcome: StringName = &"") -> String:
	if hero_name == "":
		match outcome:
			&"surrender": return "Your forces surrender to the enemy, and depart in shame."
			&"retreat": return "Your cowardly forces flee from battle."
		return "Your forces suffer a bitter defeat."
	match outcome:
		&"surrender": return "%s surrenders to the enemy, and departs in shame." % hero_name
		&"retreat": return "The cowardly %s flees from battle." % hero_name
	return "Your forces suffer a bitter defeat, and %s abandons your cause." % hero_name

## casualties: [attacker_list, defender_list], each a list of
## {unit: String, killed: int} entries (one per stack that lost creatures).
## hero_name "" means the side had no hero. artifacts: ids taken from the
## beaten hero, each shown on its own page after OKAY (victory only).
func setup(won: bool, hero_name: String, xp: int, casualties: Array = [],
		outcome: StringName = &"", artifacts: Array = [], levels := 0) -> void:
	layer = 300
	# Input blocker: invisible over the battlefield — both dialogs float on the
	# fight's final state, as in the original.
	var blocker := ColorRect.new()
	blocker.color = Color(0, 0, 0, 0)
	blocker.size = Vector2(640, 480)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)
	if won:
		_artifact_queue = artifacts.duplicate()
		_build_victory(hero_name, xp, casualties, outcome, levels)
	else:
		_build_defeat(hero_name, casualties, outcome)

## The shared winlose.png dialog shell (both result screens). Leaves _root
## ready for scene/text/button children.
func _build_frame() -> void:
	_root = Control.new()
	_root.position = DIALOG_POS
	_root.size = DIALOG_SIZE
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.clip_contents = true
	add_child(_root)
	UiKit.add_texture(_root, LOSE_DIALOG, Vector2.ZERO)

func _build_victory(hero_name: String, xp: int, casualties: Array,
		outcome: StringName = &"", levels := 0) -> void:
	_build_frame()
	Game.music.play(MusicPlayer.BATTLE_WON)
	UiKit.add_texture(_root, WIN + "0000.png", SCENE_POS)
	_anim_sprite = UiKit.add_texture(_root, WIN + "0001.png", SCENE_POS + SCENE_ANIM_OFFSET)
	_add_text(victory_text(hero_name, xp, outcome, levels))
	var smalfont := UiKit.font_small()
	var before := _root.get_child_count()
	_add_casualties(casualties, smalfont)
	for i in range(before, _root.get_child_count()):
		_casualty_nodes.append(_root.get_child(i))
	var btn := IcnButton.new()
	btn.setup(WIN, 7, "okay")
	btn.position = OKAY_POS
	btn.pressed.connect(func(_a): _on_okay())
	_root.add_child(btn)

func _build_defeat(hero_name: String, casualties: Array,
		outcome: StringName = &"") -> void:
	_build_frame()
	Game.music.play(MusicPlayer.BATTLE_LOST)
	# Scene window: clips the wide panorama + rider to the dialog's built-in
	# cutout, so the 640-wide strip shows only a 223-wide slice.
	var window := Control.new()
	window.position = SCENE_POS
	window.size = SCENE_SIZE
	window.clip_contents = true
	window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(window)
	_lose_pan = TextureRect.new()
	_lose_pan.texture = UiKit.load_texture(LOSE_BG)
	_lose_pan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.add_child(_lose_pan)
	_walk = TextureRect.new()
	_walk.name = "Rider"
	_walk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.add_child(_walk)
	_show_lose_step()
	_add_text(defeat_text(hero_name, outcome))
	_add_casualties(casualties, UiKit.font_small())
	var btn := IcnButton.new()
	btn.setup(LOSE_BTN, 0, "okay")
	btn.position = OKAY_POS
	btn.pressed.connect(func(_a): _on_okay())
	_root.add_child(btn)

## The window's one bigfont field, wrapped the way the original fits a .bin box.
func _add_text(text: String) -> void:
	var font := UiKit.font_normal()
	# bigfont ink sits 2 px lower in the field than our Label puts it (DOS capture).
	_text = UiKit.add_label(_root, Homm1Font.wrap(font, text, TEXT_SIZE.x), TEXT_POS + Vector2(0, 2), TEXT_SIZE,
			font, Color8(240, 240, 240), HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, "", 0, Color.BLACK, 2)

## Battlefield Casualties: header, then per side a label and a centred row
## of mons32 icons with the killed count under each (heroes.exe 0xc0bb8).
func _add_casualties(casualties: Array, font: Font) -> void:
	if casualties.size() < 2:
		return
	_add_line("Battlefield Casualties", CASUALTY_HEADER_Y, font)
	for side: int in 2:
		var y: int = CASUALTY_ROW_Y[side]
		_add_line("Attacker" if side == 0 else "Defender", y, font)
		_add_casualty_row(casualties[side], y, font)

func _add_line(text: String, y: float, font: Font) -> Label:
	return UiKit.add_label(_root, text, Vector2(0, y), Vector2(DIALOG_SIZE.x, 20), font)

func _add_casualty_row(row: Array, y: float, font: Font) -> void:
	var shown: Array = row.filter(func(e: Dictionary) -> bool:
		return CreatureCatalogScript.native_id(String(e.get("unit", ""))) >= 0)
	if shown.is_empty():
		_add_line("None", y + 18, font)
		return
	var x := (DIALOG_SIZE.x - CASUALTY_SLOT * shown.size()) / 2 + 3
	for entry: Dictionary in shown:
		var idx: int = CreatureCatalogScript.native_id(String(entry.get("unit", "")))
		var tex: Texture2D = MapArtResolver.get_atlas_texture("mons32/%04d.png" % idx)
		if tex == null:
			tex = UiKit.load_texture(MONS32 + "%04d.png" % idx)
		if tex != null:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.position = Vector2(x, y + 15) + Vector2(SpecLoader.sprite(MONS32, idx).get("offset", Vector2i.ZERO))
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_root.add_child(tr)
		UiKit.add_label(_root, str(entry.get("killed", 0)), Vector2(x, y + 46), Vector2(32, 12), font)
		x += CASUALTY_SLOT

func _process(delta: float) -> void:
	if _anim_sprite != null:
		_anim_time += delta
		if _anim_time >= ANIM_FRAME_S:
			_anim_time = 0.0
			_anim_frame = _anim_frame % 6 + 1   # 1..6 loop
			var tex := UiKit.load_texture(WIN + "%04d.png" % _anim_frame)
			if tex != null:
				_anim_sprite.texture = tex
	if _walk != null:
		_walk_time += delta
		while _walk_time >= LOSE_STEP_S:
			_walk_time -= LOSE_STEP_S
			_walk_frame = (_walk_frame + 1) % 8
			_lose_pan_x += LOSE_PAN_STEP
			if _lose_pan_x > LOSE_PAN_MAX:
				_lose_pan_x = 0
			_show_lose_step()

func _show_lose_step() -> void:
	_lose_pan.position.x = -_lose_pan_x
	var sp := SpecLoader.sprite(WALK, _walk_frame)
	_walk.texture = UiKit.load_texture(WALK + "%04d.png" % _walk_frame)
	_walk.position = RIDER_SCREEN - DIALOG_POS - SCENE_POS + Vector2(sp.get("offset", Vector2i.ZERO))

## Each OKAY first pages through the captured artifacts: the casualties are
## cleared and the text field, frame, icon and name show one artifact, with a
## pickup sound (heroes.exe 0xc0626, 0xc07a4, 0xc08d5).
func _on_okay() -> void:
	if not _artifact_queue.is_empty():
		_show_artifact(String(_artifact_queue.pop_front()))
		return
	closed.emit()
	queue_free()

func _show_artifact(id: String) -> void:
	for n: Node in _casualty_nodes + _artifact_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_casualty_nodes.clear()
	_artifact_nodes.clear()
	if _text != null:
		_text.text = CAPTURED_ARTIFACT
	var catalog := ArtifactCatalog.shared()
	for node: Node in [UiKit.add_texture(_root, ARTIFACT_FRAME, Vector2(120, 310)),
			UiKit.add_texture(_root, catalog.artifact_icon_path(id), Vector2(128, 318))]:
		if node != null:
			_artifact_nodes.append(node)
	var smalfont := UiKit.font_small()
	_artifact_nodes.append(UiKit.add_label(_root, catalog.display_name(id),
			Vector2(0, 394), Vector2(320, 14), smalfont))
	if not is_inside_tree():
		return
	var g := get_node_or_null("/root/Game")
	if g == null or not ("sfx_enabled" in g) or bool(g.sfx_enabled):
		var player := AudioStreamPlayer.new()
		player.stream = load(AdventureAudio.random_pickup_path()) as AudioStream
		add_child(player)
		player.finished.connect(player.queue_free)
		player.play()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()
		_on_okay()

