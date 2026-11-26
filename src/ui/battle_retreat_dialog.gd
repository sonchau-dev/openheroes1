# src/ui/battle_retreat_dialog.gd
class_name BattleRetreatDialog
extends MessageBox

## "Are you sure you want to retreat?" (0xc04d4): a Yes/No box at (195, 60)
## over the battlefield.

signal confirmed
signal cancelled

const BUTTON_SIZE := Vector2(96, 25)

func setup(message: String = "Are you sure you want to retreat?") -> void:
	build(message, YES_NO, [], false, 195, 60)

func dialog_rect() -> Rect2:
	return Rect2(window.position, window.size)

func button_rect(action: StringName) -> Rect2:
	match action:
		&"yes", &"confirm": return Rect2(window.position + window.get_node("Yes").position, BUTTON_SIZE)
		&"no", &"cancel": return Rect2(window.position + window.get_node("No").position, BUTTON_SIZE)
	return Rect2()

func choose(idx: int) -> void:
	if _closing:
		return
	if idx == 0:
		confirmed.emit()
	else:
		cancelled.emit()
	super.choose(idx)
