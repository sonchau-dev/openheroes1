# src/ui/hotseat_handoff.gd
class_name HotseatHandoff
extends MessageBox

## Hot-seat turn handoff: a black privacy shield over the map (or the whole
## screen in battle) and the "%s player turn." box with the player's crest
## (heroes.exe 0x80c71, 0xd29e2: icon type 9 at x 97).

signal confirmed

const COLOR_NAMES := ["Blue", "Green", "Red", "Yellow"]

var player_side: int = 0
var color_index: int = 0
var shown_day: int = 1
var _accepted := false

func open(side: int, crest_idx: int, day: int, full_screen: bool = false) -> void:
	player_side = side
	color_index = clampi(crest_idx / 4, 0, 3)
	shown_day = maxi(1, day)
	layer = 1000

	var shield := ColorRect.new()
	shield.name = "PrivacyShield"
	shield.color = Color.BLACK
	if full_screen:
		shield.size = Vector2(640, 480)
	else:
		# The map view inside bord.png.
		shield.position = Vector2(16, 16)
		shield.size = Vector2(448, 448)
	shield.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shield)

	build("%s player turn." % COLOR_NAMES[color_index], OKAY, [[ICON_CREST, color_index]], not full_screen)

## The caller frees the handoff once the seat is taken.
func choose(_idx: int) -> void:
	_confirm()

func _confirm() -> void:
	if _accepted:
		return
	_accepted = true
	confirmed.emit()
