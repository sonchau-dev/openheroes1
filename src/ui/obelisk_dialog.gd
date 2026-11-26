# src/ui/obelisk_dialog.gd
class_name ObeliskDialog
extends MessageBox

## Obelisk texts 0x32 and 0x33: titled, no icon.

func setup(message: String, _already_visited: bool = false) -> void:
	build("Obelisk\n\n" + message)
