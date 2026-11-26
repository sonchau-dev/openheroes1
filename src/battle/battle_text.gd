class_name BattleText
extends RefCounted

## Authentic status-bar copy for hover commands and resolved combat reports.

const CreatureCatalogScript := preload("res://src/battle/creature_catalog.gd")

static func singular(unit: String) -> String:
	return CreatureCatalogScript.singular(unit)

static func plural(unit: String) -> String:
	return CreatureCatalogScript.plural(unit)

## Hover copy for the acting stack (heroes.exe 0xc32ea, pointer table at data
## 0x21340). Over a stack it can't act on, the bar offers info only for its
## own side's stacks; an enemy leaves it empty, unless a shooter is out of
## arrows: "No shots left!".
static func hover_hint(actor_unit: String, shots: int,
		target_unit: String, action: String, flying := false,
		own_target := true, out_of_shots := false) -> String:
	match action:
		"shoot":
			return shoot_hint(target_unit, shots)
		"melee", "move_melee":
			return "Attack %s" % singular(target_unit)
		"move":
			return move_hint(actor_unit, flying)
		_:
			if target_unit == "":
				return ""
			if own_target:
				return "View %s info." % singular(target_unit)
			if out_of_shots:
				return "No shots left!"
	return ""

## "Shoot centaur(7 shots left)", "Shoot centaur(1 shot left)": no space
## before the bracket (data 0x21350, 0xc3467).
static func shoot_hint(target_unit: String, shots: int) -> String:
	return "Shoot %s(%d shot%s left)" % [singular(target_unit), shots,
			"s" if shots > 1 else ""]

static func move_hint(actor_unit: String, flying: bool) -> String:
	return "%s %s here." % ["Fly" if flying else "Move", singular(actor_unit)]

## The DOS game reports an AI move by its travel phase, even when the move
## ends in a melee attack: "Fly gargoyle here." remains on the bar until the
## damage report replaces it. Stationary attacks use the regular command copy.
static func ai_decision(actor: BattleStack, action: Dictionary) -> String:
	var target: BattleStack = action.get("target") as BattleStack
	match String(action.get("action", "")):
		"move", "move_melee":
			return move_hint(actor.unit, actor.is_flying())
		"shoot":
			return shoot_hint(target.unit, actor.shots) if target != null else ""
		"melee":
			return "Attack %s" % singular(target.unit) if target != null else ""
	return ""

## Creature name for `count` creatures: singular for one, plural otherwise.
static func unit_name(unit: String, count: int) -> String:
	return singular(unit) if count == 1 else plural(unit)

## Morale lines, as the DOS bar words them (Arena Spells capture 2026-09-24:
## "Low morale causes the trolls to freeze in panic.", and "the troll" once a
## single Troll was left).
static func morale_freeze(unit: String, count: int) -> String:
	return "Low morale causes the %s to freeze in panic." % unit_name(unit, count)

static func morale_bonus(unit: String, count: int) -> String:
	return "High morale enables the %s to attack again." % unit_name(unit, count)

## What a spell's announcement calls it: "The fireball does 20 damage."
const SPELL_NOUNS := {
	"lightning_bolt": "lightning bolt",
	"fireball": "fireball",
	"starfall": "meteor shower",
	"meteor_shower": "elemental storm",
	"armageddon": "armaggedon",
}

## The line the DOS bar shows once a spell resolves, or "" for the spells that
## print none (buffs, curses, Turn Undead, Berserk, Teleport clear the bar).
## Recorded in the Arena Spells captures: "The lightning bolt does 50 damage to
## the paladins.", "The fireball does 20 damage.", "The meteor shower does 75
## damage.", "The elemental storm does 75 damage.", "2 cavalries rise from the
## dead!", and "The armaggedon does 150 damage." (heroes_000.avi, 2026-09-25;
## note authentic double-g matching heroes.exe offset 0x1078ea). Singular Resurrect
## follows the same pattern ("1 %s rises from the dead!", heroes.exe 0x1078c5).
static func spell_result(spell_id: String, spell: Dictionary, hits: Array) -> String:
	match String(spell.get("kind", "")):
		"damage":
			if hits.is_empty():
				return ""
			var noun: String = SPELL_NOUNS.get(spell_id, String(spell.get("name", "")).to_lower())
			var damage := int(hits[0].damage)
			if String(spell.get("target", "")) == "enemy_stack":
				var s: BattleStack = hits[0].stack
				return "The %s does %d damage to the %s." % [noun, damage,
						unit_name(s.unit, s.count + int(hits[0].killed))]
			return "The %s does %d damage." % [noun, damage]
		"resurrect":
			if hits.is_empty():
				return ""
			# Plural only above 1, so raising none reads "0 cavalry rises from
			# the dead!" (heroes.exe 0xc5ff9).
			var raised := int(hits[0].get("raised", 0))
			var unit := String((hits[0].stack as BattleStack).unit)
			if raised <= 1:
				return "%d %s rises from the dead!" % [raised, singular(unit)]
			return "%d %s rise from the dead!" % [raised, plural(unit)]
	return ""

## Status-bar copy while a spell is being aimed (same capture): the prompt
## after picking it, then the hover over a legal target.
static func spell_target_prompt() -> String:
	return "Select Spell Target"

static func spell_target_hover(spell: Dictionary, target_unit: String) -> String:
	var name := String(spell.get("name", ""))
	if target_unit == "":
		return "Cast %s" % name
	return "Cast %s on %s" % [name, singular(target_unit)]

const TELEPORT_PROMPT := "Select teleport destination."
const TELEPORT_HERE := "Teleport Here"
const TELEPORT_INVALID := "Invalid Teleport Destination"

## Spells whose single target is checked for Dragons and Dwarves, with a
## status line when they shrug it off (heroes.exe 0xc593b: Lightning Bolt,
## Slow, Curse, Turn Undead, Dispel Magic, Berzerker, Paralyze).
const RESIST_CHECKED := ["lightning_bolt", "slow", "curse", "kill_undead",
		"dispel", "berserk", "paralyze"]

## The line for a stack that resisted `spell_id`, or "" when the original
## prints none.
static func spell_resisted(spell_id: String, unit: String) -> String:
	if not spell_id in RESIST_CHECKED:
		return ""
	match unit:
		"dragon":
			return "Dragons are not affected by magic!"
		"dwarf":
			return "The Dwarves' magic resistance canceled the spell!"
	return ""

## The strike line on the status bar (heroes.exe 0x8e241 ranged, 0x8f5c6
## melee and retaliation): "Archers do 12 Damage.  2 peasants perish.", two
## spaces after the first sentence. Blind, paralyze and ghost growth add
## nothing; a genie's halving replaces the whole line (0x8fbff).
## `report` is the dictionary returned by BattleRules.attack().
static func damage_report(attacker_unit: String, attacker_count: int,
		defender_unit: String, report: Dictionary) -> String:
	var subject := _subject(attacker_unit, attacker_count)
	if String(report.get("ability", "")) == "genie_halving":
		return "%s %s half the enemy troops!" % [subject,
				"destroys" if attacker_count <= 1 else "destroy"]
	return _strike_line(subject, attacker_count, int(report.get("damage", 0)),
			int(report.get("killed", 0)), unit_name(defender_unit, int(report.get("killed", 0))))

## A hydra's bite is one line for every stack it hits, its victims counted as
## "creatures" (heroes.exe 0x8eec3, names 0x16dc/0x16e5).
static func hydra_report(attacker_unit: String, attacker_count: int,
		damage: int, killed: int) -> String:
	return _strike_line(_subject(attacker_unit, attacker_count), attacker_count,
			damage, killed, "creature" if killed == 1 else "creatures")

## The castle tower's shot (heroes.exe 0x8bedb, formats 0x156b and 0x1594),
## with one space after the first sentence: "Garrison does 12 Damage. 2
## peasants perish."
static func tower_report(target_unit: String, damage: int, killed: int) -> String:
	var out := "Garrison does %d Damage." % damage
	if killed > 0:
		out += " %d %s %s." % [killed, unit_name(target_unit, killed),
				"perishes" if killed == 1 else "perish"]
	return out

## Luck is its own line, shown before the strike, with no full stop
## (heroes.exe 0x907f2, data 0x17cc and 0x17e8).
static func luck_line(unit: String, count: int, good: bool) -> String:
	if good:
		return "Good luck shines on the %s" % unit_name(unit, count)
	return "Bad luck descends on the %s" % unit_name(unit, count)

static func _subject(unit: String, count: int) -> String:
	var name := unit_name(unit, count)
	return name.left(1).to_upper() + name.substr(1)

static func _strike_line(subject: String, attacker_count: int, damage: int,
		killed: int, victims: String) -> String:
	var out := "%s %s %d Damage." % [subject, "does" if attacker_count <= 1 else "do", damage]
	if killed > 0:
		out += "  %d %s %s." % [killed, victims, "perishes" if killed == 1 else "perish"]
	return out
