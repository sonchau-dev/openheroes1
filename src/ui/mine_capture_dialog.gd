# src/ui/mine_capture_dialog.gd
class_name MineCaptureDialog
extends MessageBox

## Mine capture window: heroes.exe visit texts 0x00, 0x2b..0x2f and 0x37
## (data 0x20e44) with the resource icon captioned "n/day" (0xb2928).

const MINE_TEXTS := {
	"wood": "Sawmill\n\nYou gain control of a sawmill. It will provide you with two units of wood per day.",
	"ore": "Ore Mine\n\nYou gain control of an ore mine. It will provide you with two units of ore per day.",
	"mercury": "Alchemist\n\nYou have taken control of the local Alchemist shop. It will provide you with one unit of Mercury per day.",
	"sulfur": "Sulfur Mine\n\nYou gain control of a sulfur mine. It will provide you with one unit of sulfur per day.",
	"crystal": "Crystal Mine\n\nYou gain control of a crystal mine. It will provide you with one unit of crystal per day.",
	"gems": "Gem Mine\n\nYou gain control of a gem mine. It will provide you with one unit of gems per day.",
	"gold": "Gold Mine\n\nYou gain control of a gold mine. It will provide you with 1000 gold per day.",
}
const PER_DAY := {"wood": 2, "ore": 2, "gold": 1000}

var _res_type: String = "wood"

func setup(res: String) -> void:
	_res_type = res
	build(String(MINE_TEXTS.get(res, "")), OKAY,
			[[int(RESOURCE_TYPES.get(res, 0)), -int(PER_DAY.get(res, 1))]])
