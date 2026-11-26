# src/ui/shrine_dialog.gd
class_name ShrineDialog
extends MessageBox

## The Oracle's shrine (text 0x38): titled, no icon.

func setup(message: String) -> void:
	build("Shrine\n\n" + message)
