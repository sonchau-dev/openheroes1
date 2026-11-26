# src/ui/campfire_dialog.gd
class_name CampfireDialog
extends MessageBox

## Campfire visit: text 0x0e with the gold first and the other resource beside
## it (0xb3001).

func setup(message: String, granted: Dictionary) -> void:
	var icons := []
	if granted.has("gold"):
		icons.append([ICON_GOLD, int(granted["gold"])])
	for res: String in granted:
		if res != "gold" and RESOURCE_TYPES.has(res):
			icons.append([int(RESOURCE_TYPES[res]), int(granted[res])])
	build("Campfire\n\n" + message, OKAY, icons.slice(0, 2))
