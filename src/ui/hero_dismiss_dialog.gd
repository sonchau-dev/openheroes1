# src/ui/hero_dismiss_dialog.gd
class_name HeroDismissDialog
extends MessageBox

## "Are you sure you want to dismiss this Hero?" (0xb1ae4): a Yes/No box at
## (177, 28) over the hero screen. Other confirmations reuse it.

func setup(message: String = "Are you sure you want to dismiss this Hero?") -> void:
	build(message, YES_NO, [], false)
