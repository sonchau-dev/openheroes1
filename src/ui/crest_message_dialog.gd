# src/ui/crest_message_dialog.gd
class_name CrestMessageDialog
extends MessageBox

## Message box with a player's crest under the text (heroes.exe icon type 9):
## lost last town, days left to capture one, vanquished, remote drop.

func setup(color_index: int, message: String) -> void:
	build(message, OKAY, [[ICON_CREST, color_index]])
