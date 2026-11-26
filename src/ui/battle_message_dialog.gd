# src/ui/battle_message_dialog.gd
class_name BattleMessageDialog
extends MessageBox

## Battle notices such as "No spells to cast." (0x98c89): an Okay box at
## (177, 28) over the battlefield.

signal confirmed

const BUTTON_SIZE := Vector2(96, 25)

func setup(message: String = "No spells to cast.") -> void:
	build(message, OKAY, [], false)

func dialog_rect() -> Rect2:
	return Rect2(window.position, window.size)

func okay_button_rect() -> Rect2:
	return Rect2(window.position + window.get_node("Okay").position, BUTTON_SIZE)

func choose(idx: int) -> void:
	if _closing:
		return
	confirmed.emit()
	super.choose(idx)
