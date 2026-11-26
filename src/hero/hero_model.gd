class_name HeroModel
extends RefCounted

## Persistent hero data. Primary/status values below are base values; artifact
## modifiers are exposed through effective_*() and never mutate these fields.

var hero_name: String = ""
var portrait_idx: int = 0          # port%04d directory index
var crest_idx: int = 0             # smcrest id = color*4 + class (0 = blue knight)
var hero_class: String = "knight"
var sight_bonus: int = 0

# primary skills
var attack: int = 0
var defense: int = 0
var spell_power: int = 0
var knowledge: int = 0

# status
var experience: int = 0
## Highest experience level whose +1 primary-skill gain has been applied.
## XP can cross several thresholds at once, so this is intentionally separate
## from level(), which is derived from the current experience total.
var level_ups_applied: int = 1
## Runtime presentation queue. Stat gains are committed immediately and saved;
## the adventure UI drains these records into sequential native dialogs.
var pending_level_up_events: Array[Dictionary] = []
var morale: int = 0                # -3..3
var luck: int = 0                  # -3..3
## Negative morale penalty from battle retreat or surrender until next battle.
var cowardice: int = 0
## Waiting in the owner's tavern with the army it surrendered with. Hiring it
## back that week keeps that army instead of re-rolling the first slots
## (heroes.exe 0x75288 does re-roll; kept on purpose until a DOS run confirms
## it). Cleared when the weekly refresh sends the hero to the pool.
var kept_surrender_army := false
# Adventure-object modifiers that last through the hero's next battle. Keep
# these separate from permanent hero values so battle completion can consume
# only the temporary portion.
var temporary_morale: int = 0
var temporary_luck: int = 0
var temporary_morale_modifiers: Array[String] = []
var temporary_luck_modifiers: Array[String] = []
# Each per-battle booster records the persisted map object and the legacy
# hero-local visit id that must be removed from that object's visited_by list.
var battle_booster_visits: Array = []

# spellbook
var has_spellbook: bool = false
## A map-authored test hero keeps exactly the spells its preset lists: no
## guild teaches or refreshes it (see `tools/arena.py`).
var fixed_spellbook: bool = false
var spellbook: Spellbook = Spellbook.new()

var artifacts: Array = []          # String artifact ids

var army: ArmyData = null

var tile: Vector2i = Vector2i(-1, -1)
var planned_dest: Vector2i = Vector2i(-1, -1)
var move_points: int = -1
var max_move_points: int = 60
var travel_mode: StringName = &"land"
var carried_boat_id: int = -1
var facing: int = Direction.E

static func sample() -> HeroModel:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var h := HeroFactory.create_for_faction(0, rng)
	# Stable fixture for standalone scenes and unit tests. Real games use the
	# randomized HeroFactory path directly.
	h.hero_name = "Lord Kilburn"
	h.portrait_idx = 0
	h.experience = 0
	h.army = ArmyData.new()
	h.army.add("peasant", 30)
	h.army.add("archer", 6)
	return h

## Key under which map objects remember this hero's visits (Gazebo and the
## next-battle boosters). portrait_idx is the hero's slot in the 36-hero roster,
## so it is unique and follows the hero through defeat, the tavern and a rehire.
## The offset keeps these keys apart from the pre-v7 roster-slot keys
## (side * 100 + slot) that SaveGame migrates.
const VISIT_ID_BASE := 1000

func visit_id() -> int:
	return VISIT_ID_BASE + portrait_idx

func artifact_capacity() -> int:
	return 13 if has_spellbook else 14

func artifact_count(id: String) -> int:
	var canonical := ArtifactCatalog.shared().normalize(id)
	var count := 0
	for owned: Variant in artifacts:
		if ArtifactCatalog.shared().normalize(String(owned)) == canonical:
			count += 1
	return count

func has_artifact(id: String) -> bool:
	return artifact_count(id) > 0

func can_add_artifact(id: String) -> bool:
	var canonical := ArtifactCatalog.shared().normalize(id)
	if canonical == "spell_book":
		return not has_spellbook and artifacts.size() <= 13
	return ArtifactCatalog.shared().has(canonical) and artifacts.size() < artifact_capacity()

func add_artifact(id: String) -> bool:
	if not can_add_artifact(id):
		return false
	var canonical := ArtifactCatalog.shared().normalize(id)
	if canonical == "spell_book":
		has_spellbook = true
		return true
	artifacts.append(canonical)
	return true

func remove_artifact(id: String) -> bool:
	var canonical := ArtifactCatalog.shared().normalize(id)
	if canonical == "spell_book":
		return false
	for i in artifacts.size():
		if ArtifactCatalog.shared().normalize(String(artifacts[i])) == canonical:
			artifacts.remove_at(i)
			return true
	return false

## Move the beaten hero's artifacts in inventory order, stopping when the
## winner is full (heroes.exe 0xb5987). Only the Magic Book stays (it is
## stored separately); the Fizbin goes with the rest. An Ultimate Artifact
## is never taken: it disappears, whoever lost it, and its id is appended to
## `vanished` so the caller can say so. `loser_is_ai` is kept for callers;
## the original treats both kinds of loser alike.
static func capture_artifacts(winner: HeroModel, loser: HeroModel, _loser_is_ai: bool = false,
		vanished: Array = []) -> Array[String]:
	var captured: Array[String] = []
	if winner == null or loser == null:
		return captured
	var i := 0
	while i < loser.artifacts.size():
		var id := String(loser.artifacts[i])
		var canonical := ArtifactCatalog.shared().normalize(id)
		var art_def := ArtifactCatalog.shared().get_artifact(canonical)
		if not bool(art_def.get("ordinary", true)):
			loser.artifacts.remove_at(i)
			vanished.append(canonical)
			continue
		if canonical == "spell_book":
			i += 1
			continue
		if not winner.can_add_artifact(id):
			break
		loser.artifacts.remove_at(i)
		winner.artifacts.append(canonical)
		captured.append(canonical)
	return captured

## What capture_artifacts would take, without taking it. Ultimate Artifacts
## are left out, as the original's capture pages skip them (heroes.exe
## 0xc14b1).
static func capturable_artifacts(winner: HeroModel, loser: HeroModel) -> Array[String]:
	if winner == null or loser == null:
		return []
	var winner_had := winner.artifacts.duplicate()
	var loser_had := loser.artifacts.duplicate()
	var taken := capture_artifacts(winner, loser, true)
	winner.artifacts = winner_had
	loser.artifacts = loser_had
	return taken

func effective_attack() -> int:
	return attack + ArtifactCatalog.shared().effect_total(artifacts, "attack", hero_class)

func effective_defense() -> int:
	return defense + ArtifactCatalog.shared().effect_total(artifacts, "defense", hero_class)

func effective_spell_power() -> int:
	return spell_power + ArtifactCatalog.shared().effect_total(artifacts, "spell_power", hero_class)

func effective_knowledge() -> int:
	return knowledge + ArtifactCatalog.shared().effect_total(artifacts, "knowledge", hero_class)

const XP_THRESHOLDS := [
	0,          # Level 1
	1000,       # Level 2
	2000,       # Level 3
	3200,       # Level 4
	4500,       # Level 5
	6000,       # Level 6
	7700,       # Level 7
	9000,       # Level 8
	11000,      # Level 9
	13200,      # Level 10
	15500,      # Level 11
	18500,      # Level 12
	22100,      # Level 13
	26420,      # Level 14
	31604,      # Level 15
	37824,      # Level 16
	45288,      # Level 17
	54244,      # Level 18
	64991,      # Level 19
	77887,      # Level 20
	93362,      # Level 21
	111932,     # Level 22
	134216,     # Level 23
	160956,     # Level 24
	193044,     # Level 25
	231549,     # Level 26
	277755,     # Level 27
	333202,     # Level 28
	399738,     # Level 29
	479581,     # Level 30
	575392,     # Level 31
	690365,     # Level 32
	828332,     # Level 33
	993892,     # Level 34
	1192564,    # Level 35
	1430970,    # Level 36
	1717057,    # Level 37
	2060361,    # Level 38
	2472325,    # Level 39
	2966681,    # Level 40
	3559908,    # Level 41
	4271780,    # Level 42
	5126026,    # Level 43
	6151121,    # Level 44
	7381235,    # Level 45
	8857371,    # Level 46
	10628734,   # Level 47
	12754369,   # Level 48
	15305131,   # Level 49
	18366045,   # Level 50
	22039141,   # Level 51
	26446856,   # Level 52
	31736114,   # Level 53
	38083223,   # Level 54
	45699753,   # Level 55
	54839589,   # Level 56
	65807392,   # Level 57
	78968755,   # Level 58
	94762390,   # Level 59
	113714752,  # Level 60
	136457586,  # Level 61
	163748986,  # Level 62
	196498666,  # Level 63
	235798282,  # Level 64
	282957821,  # Level 65
	339549267,  # Level 66
	407459002,  # Level 67
	488950684,  # Level 68
	586740702,  # Level 69
	704088723,  # Level 70
	844906348,  # Level 71
	1013887498, # Level 72
	1216664878, # Level 73
	1459997734, # Level 74
	1751997161, # Level 75
]

const PRIMARY_SKILLS := [&"attack", &"defense", &"spell_power", &"knowledge"]
const PRIMARY_SKILL_LABELS := {
	&"attack": "Attack Skill",
	&"defense": "Defense Skill",
	&"spell_power": "Spell Power",
	&"knowledge": "Knowledge",
}

## HOMM1 handbook probabilities for the level being reached. Levels 2..9
## have class-specific rows; the final row is used from level 10 onward.
const LEVEL_UP_WEIGHTS := {
	"knight": [
		[20, 60, 10, 10], [60, 20, 10, 10], [20, 60, 10, 10],
		[25, 25, 25, 25], [20, 60, 10, 10], [60, 20, 10, 10],
		[20, 60, 10, 10], [20, 60, 10, 10], [25, 25, 25, 25],
	],
	"barbarian": [
		[70, 20, 5, 5], [20, 70, 5, 5], [70, 20, 5, 5],
		[40, 40, 10, 10], [70, 20, 5, 5], [20, 70, 5, 5],
		[70, 20, 5, 5], [70, 20, 5, 5], [40, 40, 10, 10],
	],
	"sorceress": [
		[5, 5, 20, 70], [5, 5, 70, 20], [5, 5, 20, 70],
		[10, 10, 40, 40], [10, 10, 30, 50], [10, 10, 50, 30],
		[10, 10, 30, 50], [10, 10, 30, 50], [20, 20, 30, 30],
	],
	"warlock": [
		[5, 5, 70, 20], [5, 5, 20, 70], [5, 5, 70, 20],
		[10, 10, 40, 40], [10, 10, 50, 30], [10, 10, 30, 50],
		[10, 10, 50, 30], [10, 10, 50, 30], [20, 20, 30, 30],
	],
}

func level() -> int:
	for i in range(XP_THRESHOLDS.size() - 1, -1, -1):
		if experience >= XP_THRESHOLDS[i]:
			return i + 1
	return 1

func next_level_experience() -> int:
	var lvl := level()
	if lvl < XP_THRESHOLDS.size():
		return XP_THRESHOLDS[lvl]
	return XP_THRESHOLDS[-1]

## Add XP and immediately commit every crossed level's stat gain. The returned
## records are also queued for the human UI; AI callers discard that queue.
func grant_experience(amount: int, rng: RandomNumberGenerator = null) -> Array[Dictionary]:
	if amount <= 0:
		return []
	experience += amount
	return process_level_ups(rng)

## Resolve all unprocessed thresholds one at a time. This preserves the native
## behavior when one large award crosses multiple levels: one independent roll
## and one presentation event per new level.
func process_level_ups(rng: RandomNumberGenerator = null) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	while level_ups_applied < level():
		var reached_level := level_ups_applied + 1
		var roll := rng.randi_range(0, 99) if rng != null else randi_range(0, 99)
		var skill := primary_skill_for_roll(hero_class, reached_level, roll)
		match skill:
			&"attack": attack += 1
			&"defense": defense += 1
			&"spell_power": spell_power += 1
			&"knowledge": knowledge += 1
		level_ups_applied = reached_level
		var event := {
			"level": reached_level,
			"skill": skill,
			"skill_label": String(PRIMARY_SKILL_LABELS[skill]),
		}
		results.append(event)
		pending_level_up_events.append(event)
	return results

func take_pending_level_up_events() -> Array[Dictionary]:
	var events := pending_level_up_events.duplicate(true)
	pending_level_up_events.clear()
	return events

func discard_pending_level_up_events() -> void:
	pending_level_up_events.clear()

## Pure weighted selector used by gameplay and tests. `roll` is clamped so
## callers can safely pass any integer while the probability bands stay exact.
static func primary_skill_for_roll(class_id: String, reached_level: int, roll: int) -> StringName:
	var class_rows: Array = LEVEL_UP_WEIGHTS.get(class_id, LEVEL_UP_WEIGHTS["knight"])
	var row_index := clampi(reached_level - 2, 0, 8)
	var weights: Array = class_rows[row_index]
	var value := clampi(roll, 0, 99)
	var accumulated := 0
	for i in weights.size():
		accumulated += int(weights[i])
		if value < accumulated:
			return PRIMARY_SKILLS[i]
	return PRIMARY_SKILLS[-1]

## heroes.exe 0xbe164: an army of one creature type is worth 0; otherwise one
## faction +1, two 0, three -1, four -2, five -3.
func army_morale_modifier() -> int:
	var units: Array[String] = []
	if army != null and army.slots != null:
		for slot in army.slots:
			if slot != null and String(slot.get("unit", "")) != "":
				units.append(String(slot.get("unit", "")))
	return composition_morale(units)

static func composition_morale(unit_names: Array[String]) -> int:
	var factions: Dictionary = {}
	var units: Dictionary = {}
	for unit_name in unit_names:
		units[unit_name] = true
		factions[String(CreatureCatalog.stats(unit_name).get("faction", "Neutral"))] = true
	if units.size() <= 1:
		return 0
	var modifier := 0
	if factions.size() == 1:
		modifier = 1
	elif factions.size() > 2:
		modifier = 2 - factions.size()
	return modifier

func total_morale() -> int:
	return clampi(morale + temporary_morale + cowardice + army_morale_modifier() +
			ArtifactCatalog.shared().effect_total(artifacts, "morale", hero_class), -3, 3)

func morale_title() -> String:
	var m := total_morale()
	if m > 0:
		return "Good Morale"
	elif m == 0:
		return "Neutral Morale"
	else:
		return "Bad Morale"

func luck_title() -> String:
	var l := effective_luck()
	if l > 0:
		return "Good Luck"
	elif l == 0:
		return "Neutral Luck"
	else:
		return "Bad Luck"

func morale_modifiers() -> Array[String]:
	var list: Array[String] = []
	if hero_class == "knight":
		list.append("Knight bonus +1")

	var factions: Dictionary = {}
	if army != null and army.slots != null:
		for slot in army.slots:
			if slot == null:
				continue
			var unit_name := String(slot.get("unit", ""))
			if unit_name == "":
				continue
			var faction := String(CreatureCatalog.stats(unit_name).get("faction", "Neutral"))
			factions[faction] = true

	if factions.size() == 1:
		var f: String = factions.keys()[0]
		var align_name := ""
		match f:
			"Knight": align_name = "human"
			"Barbarian": align_name = "plains"
			"Sorceress": align_name = "forest"
			"Warlock": align_name = "mountain"
			_: align_name = "neutral"
		list.append("All %s troops +1" % align_name)
	elif factions.size() == 3:
		list.append("Troops of 3 alignments -1")
	elif factions.size() == 4:
		list.append("Troops of 4 alignments -2")
	elif factions.size() >= 5:
		list.append("Troops of 5 alignments -3")

	var seen_arts: Dictionary = {}
	for art_id in artifacts:
		var norm := ArtifactCatalog.shared().normalize(String(art_id))
		if seen_arts.has(norm):
			continue
		seen_arts[norm] = true
		match norm:
			"medal_of_valor": list.append("Medal of Valor +1")
			"medal_of_courage": list.append("Medal of Courage +1")
			"medal_of_honor": list.append("Medal of Honor +1")
			"medal_of_distinction": list.append("Medal of Distinction +1")
			"fizbin": list.append("Fizbin of Misfortune -2")

	for mod in temporary_morale_modifiers:
		list.append(mod)
	if temporary_morale_modifiers.is_empty() and temporary_morale != 0:
		if temporary_morale == 1:
			list.append("Oasis visited +1")
		elif temporary_morale == 2:
			list.append("Statue visited +2")
		elif temporary_morale == -1:
			list.append("Graveyard robber -1")

	if cowardice != 0:
		list.append("Battle cowardice %d" % cowardice)

	if list.is_empty():
		list.append("none")
	return list

func luck_modifiers() -> Array[String]:
	var list: Array[String] = []
	var seen_luck_arts: Dictionary = {}
	for art_id in artifacts:
		var norm := ArtifactCatalog.shared().normalize(String(art_id))
		if seen_luck_arts.has(norm):
			continue
		seen_luck_arts[norm] = true
		match norm:
			"rabbit_foot": list.append("Lucky Rabbit's Foot +1")
			"golden_horseshoe": list.append("Golden Horseshoe +1")
			"lucky_coin": list.append("Gambler's Lucky Coin +1")
			"four_leaf_clover": list.append("Four-Leaf Clover +1")

	for mod in temporary_luck_modifiers:
		list.append(mod)
	if temporary_luck_modifiers.is_empty() and temporary_luck != 0:
		if temporary_luck == 1:
			list.append("Faerie ring visited +1")
		elif temporary_luck >= 2:
			list.append("Faerie ring visited +1")
			list.append("Fountain visited +1")

	if list.is_empty():
		list.append("none")
	return list

func morale_description() -> String:
	var m := total_morale()
	var desc := ""
	if m > 0:
		desc = "Good morale may give your\narmies extra attacks in\ncombat."
	elif m == 0:
		desc = "Neutral morale means your\narmies will never be blessed with\nextra attacks or freeze in combat."
	else:
		desc = "Bad morale may cause your\narmies to freeze in combat."
	desc += "\n\n\nCurrent Morale Modifiers:\n" + "\n".join(morale_modifiers())
	return desc

func luck_description() -> String:
	var l := effective_luck()
	var desc := ""
	if l > 0:
		desc = "Good luck sometimes lets\nyour armies get lucky attacks\n(double strength) in combat."
	elif l == 0:
		desc = "Neutral luck means your\narmies will never get lucky\nor unlucky attacks on the\nenemy."
	else:
		desc = "Bad luck sometimes falls on\nyour armies in combat, causing\ntheir attacks to only do half damage."
	desc += "\n\n\nCurrent Luck Modifiers:\n" + "\n".join(luck_modifiers())
	return desc

func effective_morale() -> int:
	return clampi(morale + temporary_morale + cowardice +
			ArtifactCatalog.shared().effect_total(artifacts, "morale", hero_class), -3, 3)

func effective_luck() -> int:
	return clampi(luck + temporary_luck +
			ArtifactCatalog.shared().effect_total(artifacts, "luck", hero_class), -3, 3)

func daily_gold_bonus() -> int:
	return ArtifactCatalog.shared().effect_total(artifacts, "daily_gold", hero_class)

func land_movement_bonus() -> int:
	return ArtifactCatalog.shared().effect_total(artifacts, "land_movement", hero_class) + \
			ArtifactCatalog.shared().effect_total(artifacts, "all_movement", hero_class)

func sea_movement_bonus() -> int:
	return ArtifactCatalog.shared().effect_total(artifacts, "sea_movement", hero_class) + \
			ArtifactCatalog.shared().effect_total(artifacts, "all_movement", hero_class)

func has_ballista() -> bool:
	return ArtifactCatalog.shared().effect_total(artifacts, "ballista", hero_class) > 0

func add_temporary_morale_modifier(tag: String, amount: int) -> void:
	temporary_morale += amount
	if tag != "":
		temporary_morale_modifiers.append(tag)

func add_temporary_luck_modifier(tag: String, amount: int) -> void:
	temporary_luck += amount
	if tag != "":
		temporary_luck_modifiers.append(tag)

## Remember which per-battle map booster must become eligible again when this
## hero completes a battle. Runtime map object ids are non-negative; tests and
## hand-built objects may use -1 and still receive the temporary stat.
func record_battle_booster_visit(object_id: int, hero_id: int) -> void:
	if object_id < 0:
		return
	for visit: Dictionary in battle_booster_visits:
		if int(visit.get("object_id", -1)) == object_id \
				and int(visit.get("hero_id", -1)) == hero_id:
			return
	battle_booster_visits.append({"object_id": object_id, "hero_id": hero_id})

## Consume all next-battle modifiers and return the map visits whose
## visited_by gates must be reopened. Idempotent after the first call.
func consume_battle_modifiers() -> Array:
	var visits := battle_booster_visits.duplicate(true)
	temporary_morale = 0
	temporary_luck = 0
	cowardice = 0
	temporary_morale_modifiers.clear()
	temporary_luck_modifiers.clear()
	battle_booster_visits.clear()
	return visits

## --- save/load ---

func to_dict() -> Dictionary:
	return {
		"hero_name": hero_name,
		"portrait_idx": portrait_idx,
		"crest_idx": crest_idx,
		"hero_class": hero_class,
		"sight_bonus": sight_bonus,
		"attack": attack,
		"defense": defense,
		"spell_power": spell_power,
		"knowledge": knowledge,
		"experience": experience,
		"level_ups_applied": level_ups_applied,
		"morale": morale,
		"luck": luck,
		"cowardice": cowardice,
		"kept_surrender_army": kept_surrender_army,
		"pending_level_up_events": pending_level_up_events.duplicate(true),
		"temporary_morale": temporary_morale,
		"temporary_luck": temporary_luck,
		"temporary_morale_modifiers": temporary_morale_modifiers.duplicate(),
		"temporary_luck_modifiers": temporary_luck_modifiers.duplicate(),
		"battle_booster_visits": battle_booster_visits.duplicate(true),
		"has_spellbook": has_spellbook,
		"fixed_spellbook": fixed_spellbook,
		"spellbook": spellbook.to_dict(),
		"artifacts": artifacts.duplicate(),
		"army": army.to_dict() if army != null else {},
		"tile": [tile.x, tile.y],
		"planned_dest": [planned_dest.x, planned_dest.y],
		"move_points": move_points,
		"max_move_points": max_move_points,
		"travel_mode": String(travel_mode),
		"carried_boat_id": carried_boat_id,
		"facing": facing,
	}

static func from_dict(d: Dictionary) -> HeroModel:
	var h := HeroModel.new()
	h.hero_name = String(d.get("hero_name", ""))
	h.portrait_idx = int(d.get("portrait_idx", 0))
	h.crest_idx = int(d.get("crest_idx", 0))
	h.hero_class = String(d.get("hero_class", HeroFactory.class_for_faction(h.crest_idx % 4)))
	h.sight_bonus = int(d.get("sight_bonus", 2 if h.hero_class == "warlock" else 0))
	h.attack = int(d.get("attack", 0))
	h.defense = int(d.get("defense", 0))
	h.spell_power = int(d.get("spell_power", 0))
	h.knowledge = int(d.get("knowledge", 0))
	h.experience = int(d.get("experience", 0))
	# Existing saves predate level-up processing and already contain their
	# authored primary stats. Treat their current XP level as reconciled rather
	# than unexpectedly modifying a hero as soon as the save is opened.
	h.level_ups_applied = clampi(int(d.get("level_ups_applied", h.level())), 1, h.level())
	h.morale = int(d.get("morale", 0))
	h.luck = int(d.get("luck", 0))
	h.cowardice = int(d.get("cowardice", 0))
	h.kept_surrender_army = bool(d.get("kept_surrender_army", false))
	h.pending_level_up_events = []
	var raw_events: Variant = d.get("pending_level_up_events", [])
	if raw_events is Array:
		for ev: Variant in raw_events:
			if ev is Dictionary:
				var dev := ev as Dictionary
				var clean_ev: Dictionary = {}
				for k in dev:
					var key := String(k)
					var val = dev[k]
					if val is float and float(int(val)) == val:
						clean_ev[key] = int(val)
					elif key == "skill":
						clean_ev[key] = StringName(String(val))
					else:
						clean_ev[key] = val
				h.pending_level_up_events.append(clean_ev)
	h.temporary_morale = int(d.get("temporary_morale", 0))
	h.temporary_luck = int(d.get("temporary_luck", 0))
	h.temporary_morale_modifiers = []
	for m in d.get("temporary_morale_modifiers", []):
		h.temporary_morale_modifiers.append(String(m))
	h.temporary_luck_modifiers = []
	for l in d.get("temporary_luck_modifiers", []):
		h.temporary_luck_modifiers.append(String(l))
	h.battle_booster_visits = []
	var visits: Variant = d.get("battle_booster_visits", [])
	if visits is Array:
		for visit: Variant in visits:
			if visit is Dictionary:
				h.record_battle_booster_visit(
						int(visit.get("object_id", -1)),
						int(visit.get("hero_id", -1)))
	h.has_spellbook = bool(d.get("has_spellbook", false))
	h.fixed_spellbook = bool(d.get("fixed_spellbook", false))
	h.spellbook = Spellbook.from_dict(d.get("spellbook", {}))
	h.artifacts = []
	for a_id in d.get("artifacts", []):
		var saved_id := String(a_id)
		# Normalize known legacy aliases while preserving unknown/modded IDs.
		var canonical := ArtifactCatalog.shared().normalize(saved_id) \
				if ArtifactCatalog.shared().has(saved_id) else saved_id
		# Very old/modded saves may have put the book in the ordinary artifact
		# array. Canonical storage has always used the dedicated boolean.
		if canonical == "spell_book":
			h.has_spellbook = true
			continue
		h.artifacts.append(canonical)
	h.army = ArmyData.from_dict(d.get("army", {}))
	var t: Variant = d.get("tile", null)
	if t is Array and (t as Array).size() == 2:
		h.tile = Vector2i(int(t[0]), int(t[1]))
	var pd: Variant = d.get("planned_dest", null)
	if pd is Array and (pd as Array).size() == 2:
		h.planned_dest = Vector2i(int(pd[0]), int(pd[1]))
	h.move_points = int(d.get("move_points", -1))
	h.max_move_points = int(d.get("max_move_points", 60))
	h.travel_mode = StringName(String(d.get("travel_mode", "land")))
	if h.travel_mode != &"sea":
		h.travel_mode = &"land"
	h.carried_boat_id = int(d.get("carried_boat_id", -1))
	h.facing = int(d.get("facing", Direction.E))
	return h
