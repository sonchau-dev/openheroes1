# src/town/thieves_screen.gd
class_name ThievesScreen
extends CanvasLayer

## Thieves' Guild intel overlay reconstructed from thiefwin.bin (ui-bin-format.md).
## The native 640x262 STONEBAK panel covers the top of the adventure / town screen.
##
## Intelligence is tiered by kingdom Thieves' Guild count (KB 8.2 & castles.md):
## - 1 Guild: Towns, Castles, Heroes (rows 0..2)
## - 2 Guilds: Gold, Common Resources (rows 0..4)
## - 3 Guilds: Rare Resources, Obelisks (rows 0..6)
## - 4 Guilds: Total Army Strength (all 8 rows)

const BACKGROUND := UiKit.ART + "stonebak.png"
const FONT := UiKit.FONT
const SYSTEM := UiKit.ART + "system/"
const TREASURY := UiKit.ART + "treasury/"
const FLAG32 := UiKit.ART + "flag32/"

const ROWS := [
	{"key": "towns", "label": "Number of Towns:"},
	{"key": "castles", "label": "Number of Castles:"},
	{"key": "heroes", "label": "Number of Heroes:"},
	{"key": "gold", "label": "Gold in Treasury:"},
	{"key": "common_resources", "label": "Wood, Crystal & Ore:"},
	{"key": "rare_resources", "label": "Gems, Sulfur & Mercury:"},
	{"key": "obelisks", "label": "Number Obelisks Found:"},
	{"key": "army_strength", "label": "Total Army Strength:"},
]
const HEADERS := ["First", "Second", "Third", "Fourth"]
const HEADER_X := [254.0, 351.0, 448.0, 545.0]
const COLUMN_CENTERS := [294.5, 391.5, 488.5, 585.5]
const ROW_Y := [30.0, 56.0, 82.0, 108.0, 134.0, 160.0, 186.0, 212.0]

signal closed

var _exit_rect := Rect2(550, 236, 80, 25)
var _closing := false

static func unlocked_row_count(guild_count: int) -> int:
	if guild_count >= 4:
		return 8
	elif guild_count == 3:
		return 7
	elif guild_count == 2:
		return 5
	elif guild_count >= 1:
		return 3
	return 0

static func intel(players: Array, human_side: int = -1) -> Array:
	return _extract_intel(players, human_side)

static func _extract_intel(players: Array, exclude_side: int) -> Array:
	var result: Array = []
	for p: PlayerState in players:
		if p == null:
			continue
		if exclude_side >= 0 and p.side == exclude_side:
			continue
		var towns := 0
		var castles := 0
		var strength := 0.0
		if p.owns_town:
			if not p.towns.is_empty():
				towns = p.towns.size()
				for town: TownModel in p.towns:
					if town.has_castle:
						castles += 1
					strength += ArmyStrength.of(town.army)
			elif p.town != null:
				towns = 1
				if p.town.has_castle:
					castles += 1
				strength += ArmyStrength.of(p.town.army)
		for hero: HeroModel in p.heroes:
			strength += ArmyStrength.of(hero.army)
		var heroes := p.heroes.size()
		if heroes == 0 and p.hero_model != null:
			heroes = 1
			strength += ArmyStrength.of(p.hero_model.army)
		result.append({
			"side": p.side,
			"color": clampi(int(p.crest_idx / 4), 0, 3),
			"towns": towns,
			"castles": castles,
			"heroes": heroes,
			"gold": p.gold(),
			"common_resources": int(p.resources.get("wood", 0))
					+ int(p.resources.get("crystal", 0))
					+ int(p.resources.get("ore", 0)),
			"rare_resources": int(p.resources.get("gems", 0))
					+ int(p.resources.get("sulfur", 0))
					+ int(p.resources.get("mercury", 0)),
			"obelisks": p.puzzle_pieces.size(),
			"army_strength": int(round(strength)),
		})
	return result

static func rankings(players: Array) -> Dictionary:
	var rows := _extract_intel(players, -1)
	var result := {}
	for definition: Dictionary in ROWS:
		var key := String(definition["key"])
		result[key] = OracleScreen.rank_columns(rows, key)
	return result

func open(players: Array, human_side: int = 0, guild_count: int = -1) -> void:
	layer = 210

	if guild_count < 0:
		guild_count = 0
		for p: PlayerState in players:
			if p != null and p.side == human_side:
				guild_count = p.thieves_guild_count()
				break
		if guild_count == 0:
			guild_count = 1

	var blocker := ColorRect.new()
	blocker.name = "InputBlocker"
	blocker.color = Color(0, 0, 0, 0)
	blocker.position = Vector2.ZERO
	blocker.size = Vector2(640, 480)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)

	UiKit.add_texture(self, BACKGROUND, Vector2.ZERO)
	var font := UiKit.font_normal()
	for i in HEADERS.size():
		UiKit.add_label_rect(self, HEADERS[i], Rect2(HEADER_X[i], 3, 81, 16), font,
				Color8(240, 240, 240), HORIZONTAL_ALIGNMENT_CENTER)

	var num_rows: int = unlocked_row_count(guild_count)
	var ranked := rankings(players)
	for row_index in ROWS.size():
		var definition: Dictionary = ROWS[row_index]
		UiKit.add_label_rect(self, String(definition["label"]),
				Rect2(13, ROW_Y[row_index], 225, 16), font, Color8(240, 240, 240),
				HORIZONTAL_ALIGNMENT_RIGHT)
		if row_index < num_rows:
			var columns: Array = ranked.get(String(definition["key"]), [])
			for rank_index in mini(columns.size(), 4):
				OracleScreen.add_flag_group(self, columns[rank_index], COLUMN_CENTERS[rank_index], ROW_Y[row_index])

	# system/0000 status bar background
	UiKit.add_texture(self, SYSTEM + "0000.png", Vector2(10, 239), true)
	UiKit.add_texture(self, SYSTEM + "0000.png", Vector2(279, 239))
	UiKit.add_label_rect(self, "Thieves' Guild: Player Rankings", Rect2(10, 240, 538, 16), font,
			Color8(240, 240, 240), HORIZONTAL_ALIGNMENT_CENTER)

	var exit := TextureButton.new()
	exit.name = "Exit"
	exit.texture_normal = UiKit.load_texture(TREASURY + "0001.png")
	exit.texture_pressed = UiKit.load_texture(TREASURY + "0002.png")
	exit.position = _exit_rect.position
	exit.size = _exit_rect.size
	exit.pressed.connect(_close)
	add_child(exit)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if _exit_rect.has_point(mb.position):
				_close()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_close()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and (event.keycode == KEY_ESCAPE or event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		_close()
		get_viewport().set_input_as_handled()

func _close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()
