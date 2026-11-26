# src/ui/weekly_pickup_dialog.gd
class_name WeeklyPickupDialog
extends MessageBox

## Windmill (texts 0x44, 0x45) and Watermill ("Mill", 0x29, 0x2a) visits with
## the granted resource and its amount (0xb31e5, 0xb334b), and the plundered
## Graveyard or Shipwreck text (0x15, 0x3b) with the bad-morale bird (0xb4294).

## The visit texts' first lines. The plundered-site texts carry none.
const TITLES := {
	"windmill": "Windmill",
	"watermill": "Mill",
}

func setup(obj_type: String, message: String, granted: Dictionary) -> void:
	var title: String = TITLES.get(obj_type, "")
	var icons := []
	for res: String in granted:
		if res == "morale_bad":
			icons.append([ICON_BAD_MORALE, 0])
		elif RESOURCE_TYPES.has(res):
			icons.append([int(RESOURCE_TYPES[res]), int(granted[res])])
	build((title + "\n\n" if title != "" else "") + message, OKAY, icons.slice(0, 2))
