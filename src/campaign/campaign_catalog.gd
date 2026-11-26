class_name CampaignCatalog
extends RefCounted

const LEADER_NAMES := ["Lord Ironfist", "Lord Slayer", "Queen Lamanda", "Lord Alamar"]
## Flag color of each ruler, indexed by ruler (= castle faction): red, green,
## yellow, blue. Player colors run 0 blue, 1 green, 2 red, 3 yellow.
const LEADER_COLORS := [2, 1, 3, 0]

static func color_for(leader: int) -> int:
	return LEADER_COLORS[clampi(leader, 0, 3)]
const TITLES := ["", "Gateway", "The Archipelago", "The Wounded Land", "Free-for-All",
		"Castle Ironfist", "Castle Slayer", "Castle Lamanda", "Castle Alamar", "King-of-the-Hill"]

const DESCRIPTIONS := ["",
	"You have established a foothold in the new land.  This small island is fiercely contested by three other factions, all vying to capture the strategic town - Gateway.  The town is located in the center of the island, and so dominates its surroundings that the other factions will surrender to the lord that captures it.  Beware the dragon guardian of Gateway!",
	"Your way to the mainland is blocked by the Archipelago of the Ancients, a series of four large islands, each held by a different lord.  The opposition must all be subdued, and they are better led this time.  Boats are a necessity - use them wisely!",
	"Chaos.  A maelstrom of combat plagues the land.  The people suffer, but will rally behind the wielder of the Eye of Goros, an artifact that can heal the wounded land.  It was buried and lost eons ago.  The first lord to uncover the Eye will unite the people and conquer the land - but it lies in a vast territory with only pieces of a puzzle to guide the way.",
	"With the founding of a homeland, the other lords now take you seriously.  All seek to dominate the central continent, and each is suspicious of the others.  The territory is huge, the opposition distant.  Resources are scarce and should be fiercely defended.  You must be the last lord left to claim victory.",
	"The land of the knights, led by Lord Ironfist, is divided by the twisting Floodwater River.  Ironfist is counting on the river to protect him.  The only town suitable to boat-building lies upon the river far to the east.  To defeat Ironfist, you must capture his home castle in the far northwest.",
	"Far to the north, beyond the Trackless Desert, lies the Frozen Wastes.  It is the homeland of Lord Slayer and his barbarian followers.  Once the mountain pass has been breached by either side, barbarian raiders will stream south.  The desert may harbor unknown allies who can aid you.  Slayer's castle lies just northeast of the pass.",
	"Warned of your approach, the sorceress Queen Lamanda worked on a dreadful magic and sank the approach to the only port.  You must find the teleport gate to assault the southwestern land and capture the port.  The only landfall is far to the northeast.  From there you must struggle through the forest maze to locate her castle in the extreme northwest.",
	"The warlocks' castle lies shrouded in the smokey volcanic rift.  To reach Lord Alamar's home castle in the extreme southeast, you must wander through the Minotaur Maze.  The warlocks are overconfident and not expecting an attack, so sure are they that none can navigate the maze.  Gargoyles have been set to dissuade invaders from the true path.",
	"Final victory lies within your grasp - but the defeated warlords have pooled their last resources and have banded together against you.  If you can bend the dragons to your will and force them to side with you, all the other warlords will submit and the land will be yours to rule.  Capture the Dragon Citadel on the central island and victory is yours!"
]

const COMPLETION := ["",
	"Gateway has fallen!  The other lords have abandoned their castles and fled.  They have alerted their homelands and now gather their forces.  Speed is of the essence.",
	"The Archipelago of the Ancients has been subdued and added to your domain.  On the horizon lies a vast, unexplored - and hostile - continent.",
	"The healing power of the Eye of Goros spreads throughout the land.  The population unites behind you and the other lords retreat.  The war for domination begins.",
	"With your victory, the other lords have made their final retreat.  They must each in turn be fought one-on-one in their homelands, and their personal castles must be captured.",
	"The knights are broken in battle!  You have conquered their homeland.",
	"The barbarian castle has been overthrown and their army scattered!",
	"You have burst through the forest maze and destroyed Lamanda's castle.",
	"You have followed the gargoyles to the castle of Lord Alamar and have shattered the might of the warlocks.",
	"The dragons join your cause and the competing warlords capitulate.  You now rule a vast and united land as the one true King!"
]

const OBJECTIVES: Array[StringName] = [&"capture_gateway", &"eliminate", &"dig_eye",
		&"eliminate", &"capture_home", &"capture_home", &"capture_home", &"capture_home",
		&"capture_dragon_city"]

## Concise scenario descriptions that fit the 3-line description box on reqextra (<= 52 px).
## Mission 2 is the exact description extracted from BEM20234.MAP in the original game;
## other missions are concise scenario descriptions distilled from the heroes.exe briefings.
const MAP_DESCRIPTIONS := ["",
	"Three factions contest this island, vying to capture the strategic town - Gateway.",
	"Many islands make up this area, each with its own rewards and obstacles.",
	"A maelstrom of combat plagues the land. Uncover the Eye of Goros to claim victory.",
	"All lords seek to dominate the central continent. Be the last lord left standing.",
	"Cross the Floodwater River to capture Lord Ironfist's castle in the northwest.",
	"Breach the mountain pass into the Frozen Wastes to defeat Lord Slayer's horde.",
	"Find the teleport gate and navigate the forest maze to capture Queen Lamanda.",
	"Navigate the Minotaur Maze in the volcanic rift to overthrow Lord Alamar.",
	"Capture the Dragon Citadel on the central island to claim final victory."
]

## Computer-player level per mission (1 Dumb, 2 Average, 3 Smart), from the
## table heroes.exe reads when it loads CAMPn.CMP (code file 0x7a055, data
## 0x2053b + 82 x (n - 1), bytes 1..3). Gateway's DOS autosave stores level 1
## for all three computer players. Missions 5..8 field one merged opponent.
const AI_LEVELS := [0, 1, 2, 2, 2, 3, 3, 3, 3, 3]

static func ai_level(id: int) -> int:
	return AI_LEVELS[id] if id >= 1 and id < AI_LEVELS.size() else 2

static func mission(id: int) -> CampaignMission:
	if id < 1 or id > 9:
		return null
	return CampaignMission.new(id, TITLES[id], DESCRIPTIONS[id], COMPLETION[id],
			OBJECTIVES[id - 1], id - 5 if id >= 5 and id <= 8 else -1,
			MAP_DESCRIPTIONS[id])

static func route_for(leader: int) -> Array[int]:
	var route: Array[int] = [1, 2, 3, 4]
	for id in range(5, 9):
		if id - 5 != leader:
			route.append(id)
	route.append(9)
	return route
