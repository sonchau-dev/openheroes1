# src/ui/free_dwelling_dialog.gd
class_name FreeDwellingDialog
extends MessageBox

## Free dwelling join prompt (texts 0x17 + 3k) and the wandering Followers
## offer (0x30): a Yes/No box titled by the text's first line.

func setup(title_text: String, message: String) -> void:
	build((title_text + "\n\n" if title_text != "" else "") + message, YES_NO)
