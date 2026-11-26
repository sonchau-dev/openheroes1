class_name HighScoreStore
extends RefCounted

const PATH := "user://high_scores.json"
const CAMPAIGN_DEFAULT_DAYS := [500, 700, 900, 1200, 1500, 1700, 2000, 2400, 3200, 4400]
const CAMPAIGN_DEFAULT_PLAYERS := [
	"Maximus", "Antoine", "Astra", "Agar", "Vatawna",
	"Vesper", "Ambrose", "Troyan", "Jojosh", "Wrathmont",
]
const CAMPAIGN_DEFAULT_LEADERS := [0, 1, 2, 3, 2, 3, 0, 2, 1, 3]
const STANDARD_DEFAULT_PLAYERS := [
	"Lord Kilburn", "Tsabu", "Sir Galant", "Thundax", "Lord Haart",
	"Ariel", "Rebecca", "Sandro", "Crodo", "Barok",
]
const STANDARD_DEFAULT_LANDS := [
	"The Jester", "Two if by Sea", "Knight's Quest", "Crossroads", "Shangri-La",
	"River's End", "Pathways", "Squirrel Lake", "Continentia", "The Claw",
]
const STANDARD_DEFAULT_SCORES := [130, 110, 90, 70, 60, 50, 40, 30, 20, 10]

## The tables the DOS original ships with, read off its High Scores screens.
static func defaults() -> Dictionary:
	var campaign: Array = []
	var standard: Array = []
	for i in CAMPAIGN_DEFAULT_DAYS.size():
		campaign.append({"player": CAMPAIGN_DEFAULT_PLAYERS[i],
			"leader": CAMPAIGN_DEFAULT_LEADERS[i], "days": CAMPAIGN_DEFAULT_DAYS[i],
			"title": creature_title(creature_for_campaign_days(CAMPAIGN_DEFAULT_DAYS[i]))})
		standard.append({"player": STANDARD_DEFAULT_PLAYERS[i], "land": STANDARD_DEFAULT_LANDS[i],
			"score": STANDARD_DEFAULT_SCORES[i],
			"title": creature_title(creature_for_score(STANDARD_DEFAULT_SCORES[i]))})
	return {"campaign": campaign, "standard": standard}

## The rank name the screen prints beside a row: the creature's name.
static func creature_title(unit: String) -> String:
	return unit.capitalize()

static func load_scores(path: String = PATH) -> Dictionary:
	var data := JsonFile.read_dict(path)
	if data.is_empty():
		return defaults()
	if not (data.get("campaign", null) is Array) or not (data.get("standard", null) is Array):
		return defaults()
	return data

## The 28 ranks, lowest first. heroes.exe keeps both ranking tables as 28
## (threshold, creature id) word pairs: standard at data 0x20334 (file
## 0x1249d8), campaign at data 0x203a4 (file 0x124a48), read by 0xd36f4.
const CREATURE_RANKING: Array[String] = [
	"peasant", "goblin", "sprite", "centaur", "rogue",
	"orc", "archer", "gargoyle", "dwarf", "pikeman",
	"wolf", "nomad", "elf", "griffin", "swordsman",
	"ogre", "druid", "minotaur", "cavalry", "ghost",
	"unicorn", "troll", "hydra", "paladin", "genie",
	"cyclops", "phoenix", "dragon",
]

## Standard score thresholds; the highest rank whose threshold the score reaches.
const STANDARD_SCORE_THRESHOLDS: Array[int] = [
	0, 7, 14, 21, 28, 35, 42, 49, 56, 63,
	70, 77, 84, 91, 98, 105, 112, 119, 126, 133,
	140, 147, 154, 161, 168, 175, 182, 189,
]

## Campaign day thresholds; the highest rank whose threshold the days do not
## exceed. Slower than 3600 days falls back to peasant.
const CAMPAIGN_DAY_THRESHOLDS: Array[int] = [
	3600, 3400, 3200, 3000, 2600, 2400, 2200, 2000, 1800, 1600,
	1500, 1400, 1300, 1200, 1100, 1000, 900, 800, 750, 700,
	650, 600, 550, 500, 450, 400, 350, 300,
]

const MINIMON_FRAMES: Dictionary = {
	"peasant": 0, "archer": 7, "pikeman": 14, "swordsman": 21,
	"cavalry": 28, "paladin": 35, "goblin": 42, "orc": 49,
	"wolf": 56, "ogre": 63, "troll": 70, "cyclops": 77,
	"sprite": 84, "dwarf": 91, "elf": 98, "druid": 105,
	"unicorn": 112, "phoenix": 119, "centaur": 126, "gargoyle": 133,
	"griffin": 140, "minotaur": 147, "hydra": 154, "dragon": 161,
	"rogue": 168, "nomad": 175, "ghost": 182, "genie": 189,
}

static func qualifies_campaign(days: int, path: String = PATH) -> bool:
	var data := load_scores(path)
	var campaign: Array = data.get("campaign", [])
	if campaign.size() < 10:
		return true
	return days < int(campaign[-1].get("days", 999999))

## Maps a standard final score to one of the 28 creature ranks.
static func creature_for_score(score: int) -> String:
	for i in range(STANDARD_SCORE_THRESHOLDS.size() - 1, -1, -1):
		if score >= STANDARD_SCORE_THRESHOLDS[i]:
			return CREATURE_RANKING[i]
	return CREATURE_RANKING[0]

## Maps campaign completion days to one of the 28 creature ranks.
static func creature_for_campaign_days(days: int) -> String:
	for i in range(CAMPAIGN_DAY_THRESHOLDS.size() - 1, -1, -1):
		if days <= CAMPAIGN_DAY_THRESHOLDS[i]:
			return CREATURE_RANKING[i]
	return CREATURE_RANKING[0]

static func minimon_frame_for_creature(unit: String) -> int:
	return int(MINIMON_FRAMES.get(unit, 0))

static func record_campaign(player: String, leader: int, days: int, path: String = PATH) -> void:
	var data := load_scores(path).duplicate(true)
	data.campaign.append({"player": player, "leader": clampi(leader, 0, 3),
		"days": maxi(1, days), "title": "High King"})
	data.campaign.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.days) < int(b.days))
	data.campaign.resize(mini(10, data.campaign.size()))
	_write(data, path)

static func qualifies_standard(score: int, path: String = PATH) -> bool:
	var data := load_scores(path)
	var standard: Array = data.get("standard", [])
	if standard.size() < 10:
		return true
	return score > int(standard[-1].get("score", 0))

static func record_standard(player: String, land: String, score: int,
		title: String, path: String = PATH) -> void:
	var data := load_scores(path).duplicate(true)
	data.standard.append({"player": player, "land": land, "score": score, "title": title})
	data.standard.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.score) > int(b.score))
	data.standard.resize(mini(10, data.standard.size()))
	_write(data, path)

static func _write(data: Dictionary, path: String) -> void:
	var base := path.get_base_dir()
	if base != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base))
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	var err := FileAccess.get_open_error()
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))
		err = file.get_error()
		file.close()
		if err == OK:
			err = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_warning("Cannot write high scores (%s)" % error_string(err))
	JsonFile.invalidate(path)
