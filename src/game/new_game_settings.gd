class_name NewGameSettings
extends RefCounted

const DEFAULT_MAP_PATH := "res://data/maps/aes31000.json"

var map_path: String = DEFAULT_MAP_PATH
var game_difficulty: int = 1
var opponent_levels: Array[int] = [2, 2, 2]
var human_difficulties: Array[int] = [1, 1, 1]
var player_color: int = 0
var king_of_the_hill: bool = false
## One is a standard game. Two through four select local hot-seat play.
var human_player_count: int = 1
## Remote play: the same two seats as hot seat, but the second human sits on
## another machine. Set by the network setup screen before new_game().
var network: bool = false
## Optional deterministic seed. When non-zero, new_game seeds Game.rng with this value.
var fixed_seed: int = 0

func duplicate_settings() -> NewGameSettings:
	return from_dict(to_dict())

## Clamp fields and disable opponent slots the selected scenario cannot host.
## If the requested color is unavailable, prefer Blue and then authored order.
func normalize(info: ScenarioInfo = null) -> NewGameSettings:
	game_difficulty = clampi(game_difficulty, 0, 3)
	while opponent_levels.size() < 3:
		opponent_levels.append(0)
	if opponent_levels.size() > 3:
		opponent_levels.resize(3)
	for i in opponent_levels.size():
		opponent_levels[i] = clampi(int(opponent_levels[i]), 0, 4)
	while human_difficulties.size() < 3:
		human_difficulties.append(1)
	if human_difficulties.size() > 3:
		human_difficulties.resize(3)
	for i in human_difficulties.size():
		human_difficulties[i] = clampi(int(human_difficulties[i]), 0, 3)
	player_color = clampi(player_color, 0, 3)
	human_player_count = clampi(human_player_count, 1, 4)
	if info != null:
		map_path = info.path
		if not info.supported_human_counts.is_empty() \
				and not info.supported_human_counts.has(human_player_count):
			human_player_count = info.supported_human_counts[0]
		if not info.available_colors.has(player_color):
			player_color = 0 if info.available_colors.has(0) else info.available_colors[0]
		var capacity := maxi(0, info.seat_count - human_player_count)
		for i in range(capacity, 3):
			opponent_levels[i] = 0
	return self

func active_opponents() -> int:
	var count := 0
	for level in opponent_levels:
		if int(level) > 0:
			count += 1
	return count

## Authentic rating formula decoded from heroes.exe (offset 0x79503..0x79550).
## Base: (map_diff + 2) * 10 + map_size * 10 + game_diff * 10.
## Opponents: Human slots grant human_difficulty * 10; AI slots grant [-10, 5, 10, 15, 20].
## KotH: +5 for 2 active opponents, +10 for 3 active opponents.
func rating(info: ScenarioInfo = null) -> int:
	var map_diff := info.map_difficulty if info != null else 0
	var map_size := info.size if info != null else 0
	var value := (map_diff + 2) * 10 + map_size * 10 + game_difficulty * 10
	var human_opponents := clampi(human_player_count, 1, 4) - 1
	var ai_bonuses := [-10, 5, 10, 15, 20]
	for i in range(3):
		if i < human_opponents:
			var h_diff := human_difficulties[i] if i < human_difficulties.size() else 1
			value += clampi(h_diff, 0, 3) * 10
		else:
			var ai_idx := i - human_opponents
			var level := opponent_levels[ai_idx] if ai_idx < opponent_levels.size() else 0
			value += ai_bonuses[clampi(int(level), 0, 4)]
	if king_of_the_hill:
		var active := active_opponents()
		if active >= 3:
			value += 10
		elif active == 2:
			value += 5
	return value

static func starting_resources_for_difficulty(difficulty: int) -> Dictionary:
	match clampi(difficulty, 0, 3):
		0:
			return {"gold": 10000, "wood": 30, "ore": 30, "mercury": 10,
				"sulfur": 10, "crystal": 10, "gems": 10}
		1:
			return {"gold": 7500, "wood": 20, "ore": 20, "mercury": 5,
				"sulfur": 5, "crystal": 5, "gems": 5}
		2:
			return {"gold": 5000, "wood": 10, "ore": 10, "mercury": 0,
				"sulfur": 0, "crystal": 0, "gems": 0}
		_:
			return {"gold": 0, "wood": 0, "ore": 0, "mercury": 0,
				"sulfur": 0, "crystal": 0, "gems": 0}

func starting_resources(human_seat_index: int = 0) -> Dictionary:
	if human_seat_index == 0:
		return starting_resources_for_difficulty(game_difficulty)
	var opponent_idx := human_seat_index - 1
	var diff := human_difficulties[opponent_idx] if opponent_idx < human_difficulties.size() else 1
	return starting_resources_for_difficulty(diff)

func to_dict() -> Dictionary:
	return {
		"map_path": map_path,
		"game_difficulty": game_difficulty,
		"opponent_levels": opponent_levels.duplicate(),
		"human_difficulties": human_difficulties.duplicate(),
		"player_color": player_color,
		"king_of_the_hill": king_of_the_hill,
		"human_player_count": human_player_count,
		"network": network,
		"fixed_seed": fixed_seed,
	}

static func from_dict(data: Dictionary) -> NewGameSettings:
	var settings := NewGameSettings.new()
	settings.map_path = String(data.get("map_path", DEFAULT_MAP_PATH))
	settings.game_difficulty = int(data.get("game_difficulty", 1))
	settings.opponent_levels = []
	var raw: Variant = data.get("opponent_levels", [2, 2, 2])
	if raw is Array:
		for level in raw:
			settings.opponent_levels.append(int(level))
	settings.human_difficulties = []
	var raw_hd: Variant = data.get("human_difficulties", [1, 1, 1])
	if raw_hd is Array:
		for diff in raw_hd:
			settings.human_difficulties.append(int(diff))
	settings.player_color = int(data.get("player_color", 0))
	settings.king_of_the_hill = bool(data.get("king_of_the_hill", false))
	settings.human_player_count = int(data.get("human_player_count", 1))
	settings.network = bool(data.get("network", false))
	settings.fixed_seed = int(data.get("fixed_seed", 0))
	return settings.normalize()
