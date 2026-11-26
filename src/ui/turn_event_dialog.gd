# src/ui/turn_event_dialog.gd
class_name TurnEventDialog
extends MessageBox

## The end-turn confirmation (0x9879c, Yes/No) and the astrologers' week and
## month proclamations (Okay).

var _yes_no := false

func setup(message: String, yes_no: bool) -> void:
	_yes_no = yes_no
	build(message, YES_NO if yes_no else OKAY)
