# src/ui/hero_stat_dialog.gd
class_name HeroStatDialog
extends MessageBox

## The hero screen's morale, luck, experience and primary skill boxes: the
## title and its text in one message box over the hero screen (x 177).

enum DialogType { MORALE, LUCK, EXPERIENCE, ATTACK, DEFENSE, SPELL_POWER, KNOWLEDGE }

var _dialog_type: DialogType
var _hero: HeroModel

func setup_morale(hero: HeroModel) -> void:
	_hero = hero
	_dialog_type = DialogType.MORALE
	_build(hero.morale_title(), hero.morale_description())

func setup_luck(hero: HeroModel) -> void:
	_hero = hero
	_dialog_type = DialogType.LUCK
	_build(hero.luck_title(), hero.luck_description())

func setup_experience(hero: HeroModel) -> void:
	_hero = hero
	_dialog_type = DialogType.EXPERIENCE
	_build("Level %d" % hero.level(),
			"Current experience %d\nNext level %d" % [hero.experience, hero.next_level_experience()])

func setup_attack() -> void:
	_dialog_type = DialogType.ATTACK
	_build("Attack Skill", "Your attack skill is a bonus added to each creature's attack skill.")

func setup_defense() -> void:
	_dialog_type = DialogType.DEFENSE
	_build("Defense Skill", "Your defense skill is a bonus added to each creature's defense skill.")

func setup_spell_power() -> void:
	_dialog_type = DialogType.SPELL_POWER
	_build("Spell Power", "Your spell power determines the length or power of a spell.")

func setup_knowledge() -> void:
	_dialog_type = DialogType.KNOWLEDGE
	_build("Knowledge", "Your Knowledge is the number of each spell you are able to memorize.")

func _build(title_text: String, desc_text: String) -> void:
	build(title_text + "\n\n" + desc_text, OKAY, [], false)
