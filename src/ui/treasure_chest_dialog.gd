# src/ui/treasure_chest_dialog.gd
class_name TreasureChestDialog
extends MessageBox

## Treasure chest (text 0x0b): a Yes/No box with the gold, "or" and the
## experience star (0xb2b86). Yes keeps the gold.

const DESCRIPTION := "After scouring the area, you fall upon a hidden treasure cache.  You may take the gold or distribute the gold to the peasants for experience.  Do you wish to keep the gold?"

var _gold_amount: int = 1000
var _exp_amount: int = 500

func setup(gold: int, exp: int) -> void:
	_gold_amount = gold
	_exp_amount = exp
	build("Chest\n\n" + DESCRIPTION, YES_NO, [[ICON_GOLD, gold], [ICON_EXPERIENCE, exp]], true, -1, -1, true)
