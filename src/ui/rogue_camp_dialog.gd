class_name RogueCampDialog
extends CanvasLayer

## Two-stage Wagon interaction measured from the supplied DOS references:
## encounter question first, then the shared RecruitDialog.

signal recruited(quantity: int)
signal closed

const BUYBUILD := UiKit.ART + "buybuild/"
const SYSTEM := UiKit.ART + "system/"
const OFFER_TEXT := "Distant sounds of music and\nlaughter draw you to a\ncolorful wagon housing\nrogues. Do you wish to have\nany rogues join your army?"

var _dwelling: Dwelling
var _player: PlayerState
var _army: ArmyData
var _offer_open := true
var _is_empty_offer := false

func setup(dwelling: Dwelling, player: PlayerState, army: ArmyData) -> void:
	_dwelling = dwelling
	_player = player
	_army = army
	layer = 200
	name = "RogueCampDialog"
	_show_offer()

func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

func _add_blocker() -> void:
	var blocker := ColorRect.new()
	blocker.name = "InputBlocker"
	blocker.color = Color(0, 0, 0, 0)
	blocker.position = Vector2.ZERO
	blocker.size = Vector2(640, 480)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)

func _dwelling_title() -> String:
	if _dwelling == null:
		return "Dwelling"
	if _dwelling.title != "":
		return _dwelling.title
	match _dwelling.unit:
		"rogue": return "Wagon"
		"nomad": return "Tents"
		"genie": return "Genie Lamp"
		_: return CreatureCatalog.singular(_dwelling.unit).capitalize()

func _dwelling_offer_text() -> String:
	if _dwelling == null:
		return ""
	if _dwelling.offer_text != "":
		return _dwelling.offer_text
	match _dwelling.unit:
		"rogue":
			return OFFER_TEXT
		"nomad":
			return "A group of tattered tents,\nbillowing in the sandy wind,\nbeckons you.  Do you wish to\nhave any nomads join you\nduring your travels?"
		"genie":
			return "You stumble upon a dented and\ntarnished lamp lodged deep in\nthe earth. Do you wish to\nrub the lamp?"
		_:
			return "Do you wish to have any\n%s join your army?" % CreatureCatalog.plural(_dwelling.unit)

func _dwelling_empty_text() -> String:
	if _dwelling == null:
		return ""
	if _dwelling.empty_text != "":
		return _dwelling.empty_text
	match _dwelling.unit:
		"rogue":
			return "A colorful rogues' wagon\nstands empty here.  Perhaps\nmore rogues will be here\nlater."
		"nomad":
			return "A group of tattered tents,\nbillowing in the sandy wind,\nbeckons you.  The tents are\nunoccupied.  Perhaps more\nnomads will be here later."
		_:
			return "There is no one here at\nthis time."

func _show_offer() -> void:
	_clear()
	_offer_open = true
	_is_empty_offer = (_dwelling != null and _dwelling.available <= 0)
	_add_blocker()

	var dialog := Control.new()
	dialog.name = "WagonOffer"
	dialog.position = Vector2(91, 38)
	dialog.size = Vector2(302, 246)
	dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dialog)

	var shadow := ColorRect.new()
	shadow.color = Color(0, 0, 0, 0.45)
	shadow.position = Vector2(18, 42)
	shadow.size = Vector2(286, 205)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.add_child(shadow)

	_add_segment(dialog, BUYBUILD + "0000.png", 8, true)
	_add_segment(dialog, BUYBUILD + "0000.png", 8, false)
	_add_segment(dialog, BUYBUILD + "0001.png", 85, true)
	_add_segment(dialog, BUYBUILD + "0001.png", 85, false)
	_add_segment(dialog, BUYBUILD + "0001.png", 130, true)
	_add_segment(dialog, BUYBUILD + "0001.png", 130, false)
	_add_middle_continuation(dialog, 175, 22)
	_add_segment(dialog, BUYBUILD + "0002.png", 197, true)
	_add_segment(dialog, BUYBUILD + "0002.png", 197, false)

	var font := UiKit.font()
	UiKit.add_label(dialog, _dwelling_title(), Vector2(8, 52), Vector2(286, 18), font,
			Color8(240, 240, 240), HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, "Title", 3)
	var prompt := _dwelling_empty_text() if _is_empty_offer else _dwelling_offer_text()
	UiKit.add_label(dialog, prompt, Vector2(20, 81), Vector2(262, 104), font,
			Color8(240, 240, 240), HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, "Description", 3)

	if _is_empty_offer:
		var okay := IcnButton.new()
		okay.name = "Okay"
		okay.setup(SYSTEM, 8, "okay")
		okay.position = Vector2(102, 204)
		okay.pressed.connect(func(_action): _close())
		dialog.add_child(okay)
	else:
		var yes := IcnButton.new()
		yes.name = "Yes"
		yes.setup(SYSTEM, 5, "yes")
		yes.position = Vector2(31, 204)
		yes.pressed.connect(func(_action): show_recruit())
		dialog.add_child(yes)

		var no := IcnButton.new()
		no.name = "No"
		no.setup(SYSTEM, 7, "no")
		no.position = Vector2(173, 204)
		no.pressed.connect(func(_action): _close())
		dialog.add_child(no)

func show_recruit() -> void:
	_clear()
	_offer_open = false
	var recruit := RecruitDialog.new()
	add_child(recruit)
	recruit.confirmed.connect(func(quantity: int) -> void:
		if _dwelling.recruit(quantity, _player, _army):
			recruited.emit(quantity))
	recruit.closed.connect(_close)
	recruit.open(_dwelling.unit, _dwelling.available, _dwelling.total_cost_for(1),
			_dwelling.max_recruitable(_player, _army))

func _close() -> void:
	closed.emit()
	queue_free()

func _add_segment(parent: Control, texture_path: String, y: float, flip: bool) -> void:
	var texture := load(texture_path) as Texture2D
	var rect := TextureRect.new()
	rect.texture = texture
	rect.position = Vector2(151 - texture.get_width() if flip else 151, y)
	rect.flip_h = flip
	rect.size = texture.get_size()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)

func _add_middle_continuation(parent: Control, y: float, height: float) -> void:
	var source := load(BUYBUILD + "0001.png") as Texture2D
	var crop := AtlasTexture.new()
	crop.atlas = source
	crop.region = Rect2(0, 0, source.get_width(), height)
	for flip in [true, false]:
		var rect := TextureRect.new()
		rect.texture = crop
		rect.position = Vector2(151 - source.get_width() if flip else 151, y)
		rect.flip_h = flip
		rect.size = Vector2(source.get_width(), height)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(rect)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	var key := (event as InputEventKey).keycode
	if _offer_open:
		if _is_empty_offer:
			if key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]:
				_close()
				get_viewport().set_input_as_handled()
		else:
			if key in [KEY_Y, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
				show_recruit()
				get_viewport().set_input_as_handled()
			elif key in [KEY_N, KEY_ESCAPE]:
				_close()
				get_viewport().set_input_as_handled()
