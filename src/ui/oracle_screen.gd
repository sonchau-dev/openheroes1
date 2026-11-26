class_name OracleScreen
extends CanvasLayer

## The Oracle map object is presented as "Shrine" in the original game. It
## grants the complete four-level Thieves' Guild comparison: every player is
## ranked in eight categories, with ties sharing a column as colored flags.
##
## Layout is decoded from thiefwin.bin (data/knowledge_base/ui-bin-format.md): the
## native 640x262 STONEBAK panel covers only the top of the adventure screen,
## leaving the live map visible below it.

const BACKGROUND := UiKit.ART + "stonebak.png"
const SYSTEM := UiKit.ART + "system/"
const TREASURY := UiKit.ART + "treasury/"
const FLAG32 := UiKit.ART + "flag32/"

const ROWS := [
	{"key": "towns", "label": "Number of Towns:"},
	{"key": "castles", "label": "Number of Castles:"},
	{"key": "heroes", "label": "Number of Heroes:"},
	{"key": "gold", "label": "Gold in Treasury:"},
	{"key": "common_resources", "label": "Wood, Crystal & Ore:"},
	{"key": "rare_resources", "label": "Gems, Sulphur & Mercury:"},
	{"key": "obelisks", "label": "Number Obelisks Found:"},
	{"key": "army_strength", "label": "Total Army Strength:"},
]
const HEADERS := ["First", "Second", "Third", "Fourth"]
const HEADER_X := [254.0, 351.0, 448.0, 545.0]
const COLUMN_CENTERS := [294.5, 391.5, 488.5, 585.5]
const ROW_Y := [30.0, 56.0, 82.0, 108.0, 134.0, 160.0, 186.0, 212.0]
const FLAG_STEP := 16.0
## Native left-to-right order inside a tied rank group, measured from the
## supplied four-flag reference: blue, yellow, green, red.
const TIE_COLOR_ORDER := {0: 0, 3: 1, 1: 2, 2: 3}

signal closed

var _exit_rect := Rect2(550, 236, 80, 25)
var _closing := false

## Full intelligence includes the visiting kingdom too: this is a comparison,
## not an opponent-only list. human_side remains in the signature for callers
## shared with the older placeholder implementation.
static func intel(players: Array, _human_side: int = 0) -> Array:
	var result: Array = []
	for p: PlayerState in players:
		if p == null:
			continue
		var towns := p.towns.size() if p.owns_town else 0
		var castles := 0
		var strength := 0.0
		if p.owns_town:
			for town: TownModel in p.towns:
				if town.has_castle:
					castles += 1
				strength += ArmyStrength.of(town.army)
		for hero: HeroModel in p.heroes:
			strength += ArmyStrength.of(hero.army)
		var heroes := p.heroes.size()
		# Some focused tests/legacy saves predate the multi-hero array.
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

## Dense ranking: tied players share one column and the next distinct score is
## shown in the next column. This is what the original flag table displays.
static func rank_columns(rows: Array, key: String) -> Array:
	var ordered := rows.duplicate(true)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var av := int(a.get(key, 0))
		var bv := int(b.get(key, 0))
		if av == bv:
			var a_color := int(a.get("color", 0))
			var b_color := int(b.get("color", 0))
			return int(TIE_COLOR_ORDER.get(a_color, a_color)) \
					< int(TIE_COLOR_ORDER.get(b_color, b_color))
		return av > bv
	)
	var columns: Array = []
	var previous_score := 0
	var have_score := false
	for row: Dictionary in ordered:
		var score := int(row.get(key, 0))
		if not have_score or score != previous_score:
			columns.append([])
			previous_score = score
			have_score = true
		(columns.back() as Array).append(int(row.get("color", 0)))
	return columns

static func rankings(players: Array, human_side: int = 0) -> Dictionary:
	var rows := intel(players, human_side)
	var result := {}
	for definition: Dictionary in ROWS:
		var key := String(definition["key"])
		result[key] = rank_columns(rows, key)
	return result

func open(players: Array, human_side: int = 0) -> void:
	layer = 210

	var blocker := ColorRect.new()
	blocker.name = "InputBlocker"
	blocker.color = Color(0, 0, 0, 0)
	blocker.position = Vector2.ZERO
	blocker.size = Vector2(640, 480)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)

	UiKit.add_texture(self, BACKGROUND, Vector2.ZERO)
	var font := UiKit.font()
	for i in HEADERS.size():
		UiKit.add_label_rect(self, HEADERS[i], Rect2(HEADER_X[i], 3, 81, 16),
				font, Color8(240, 240, 240), HORIZONTAL_ALIGNMENT_CENTER)

	var ranked := rankings(players, human_side)
	for row_index in ROWS.size():
		var definition: Dictionary = ROWS[row_index]
		UiKit.add_label_rect(self, String(definition["label"]),
				Rect2(13, ROW_Y[row_index], 225, 16), font, Color8(240, 240, 240), HORIZONTAL_ALIGNMENT_RIGHT)
		var columns: Array = ranked.get(String(definition["key"]), [])
		for rank_index in mini(columns.size(), 4):
			add_flag_group(self, columns[rank_index], COLUMN_CENTERS[rank_index], ROW_Y[row_index])

	# system/0000 is one 269px half of the native status bar. Mirror it for
	# the left cap and place the original at the decoded center seam.
	UiKit.add_texture(self, SYSTEM + "0000.png", Vector2(10, 239), true)
	UiKit.add_texture(self, SYSTEM + "0000.png", Vector2(279, 239))
	UiKit.add_label_rect(self, "Shrine - Player Rankings", Rect2(10, 240, 538, 16),
			font, Color8(240, 240, 240), HORIZONTAL_ALIGNMENT_CENTER)

	var exit := TextureButton.new()
	exit.name = "Exit"
	exit.texture_normal = load(TREASURY + "0001.png") as Texture2D
	exit.texture_pressed = load(TREASURY + "0002.png") as Texture2D
	exit.position = _exit_rect.position
	exit.size = _exit_rect.size
	exit.pressed.connect(_close)
	add_child(exit)

static func add_flag_group(target: Node, colors: Array, center_x: float, y: float) -> void:
	var count := colors.size()
	if count == 0:
		return
	var group_width := 18.0 + float(count - 1) * FLAG_STEP
	var x := center_x - group_width * 0.5
	for color_value: int in colors:
		var frame := clampi(color_value, 0, 3) * 2 + 1
		UiKit.add_texture(target, FLAG32 + "%04d.png" % frame, Vector2(round(x), y))
		x += FLAG_STEP

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		_close()
		get_viewport().set_input_as_handled()

func _close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()
