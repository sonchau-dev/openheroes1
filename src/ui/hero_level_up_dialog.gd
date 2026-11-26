# src/ui/hero_level_up_dialog.gd
class_name HeroLevelUpDialog
extends MessageBox

## A hero's level award (heroes.exe 0xb22c8, box 0xb25cf): the text with the
## hero's portrait in its surrendr frame under it (icon type 15).

## Order and names of the skill lines (heroes.exe data 0x20a78).
const SKILL_ORDER := [&"attack", &"defense", &"spell_power", &"knowledge"]
const SKILL_NAMES := ["Attack Skill", "Defense Skill", "Spell Power", "Knowledge"]

## One message for a whole award, however many levels it crosses:
## "%s has gained" + " a level." or " %d levels.", then one "%s +%d" line
## per primary skill that went up.
static func title_text(hero_name: String, levels: int) -> String:
	if levels == 1:
		return "%s has gained a level." % hero_name
	return "%s has gained %d levels." % [hero_name, levels]

static func skill_text(level_ups: Array) -> String:
	var lines: Array[String] = []
	for i in SKILL_ORDER.size():
		var gained := 0
		for event: Dictionary in level_ups:
			if StringName(event.get("skill", &"")) == SKILL_ORDER[i]:
				gained += 1
		if gained > 0:
			lines.append("%s +%d" % [SKILL_NAMES[i], gained])
	return "\n".join(lines)

## `level_ups` is every level event from one award (a single Dictionary is
## accepted as a one-level award).
func setup(hero: HeroModel, level_ups: Variant) -> void:
	var events: Array = level_ups if level_ups is Array else [level_ups]
	build(title_text(hero.hero_name, events.size()) + "\n\n" + skill_text(events), OKAY,
			[[ICON_PORTRAIT, hero.portrait_idx]])
