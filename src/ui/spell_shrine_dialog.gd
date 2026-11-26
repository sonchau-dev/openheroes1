# src/ui/spell_shrine_dialog.gd
class_name SpellShrineDialog
extends MessageBox

## The spell shrine (text 0x39): the altar text with the spell icon and its
## name under it when the hero carries a spellbook (0xb3816), text only
## without one (0xb385c).

const TeachSpell := preload("res://src/adventure/objects/handlers/teach_spell.gd")

func setup(spell_id: String, has_spellbook: bool) -> void:
	var spell_name := String(SpellData.get_spell(spell_id).get("name", spell_id.capitalize()))
	var message: String = (TeachSpell.INTRO_WITH_BOOK if has_spellbook else TeachSpell.INTRO_NO_BOOK) % spell_name
	build("Shrine\n\n" + message, OKAY, [[ICON_SPELL, spell_id]] if has_spellbook else [])
