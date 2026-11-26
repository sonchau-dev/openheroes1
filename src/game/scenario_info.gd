class_name ScenarioInfo
extends RefCounted

## Lightweight scenario header used by menus.  It deliberately contains no
## terrain, objects, or decor, so browsing the catalog never constructs a map.

var path: String = ""
var name: String = ""
var description: String = ""
var map_difficulty: int = 0
var size: int = 0
var supported_human_counts: Array[int] = []
var available_colors: Array[int] = []
var native_order: int = 0
var seat_count: int = 0

static func from_header(path_value: String, data: Dictionary, order: int) -> ScenarioInfo:
	var info := ScenarioInfo.new()
	info.path = path_value
	info.name = String(data.get("name", ""))
	info.description = String(data.get("description", ""))
	info.map_difficulty = clampi(int(data.get("map_difficulty", 0)), 0, 3)
	info.size = clampi(int(data.get("size", 0)), 0, 2)
	info.native_order = order
	for count in data.get("supported_human_counts", []):
		var n := int(count)
		if n >= 1 and n <= 4 and not info.supported_human_counts.has(n):
			info.supported_human_counts.append(n)
	var players: Variant = data.get("players", [])
	if players is Array:
		for player in players:
			if player is Dictionary:
				var color := int(player.get("color", -1))
				if color >= 0 and color <= 3 and not info.available_colors.has(color):
					info.available_colors.append(color)
	info.available_colors.sort()
	info.supported_human_counts.sort()
	info.seat_count = info.available_colors.size()
	if info.seat_count == 0 and players is Array:
		info.seat_count = (players as Array).size()
	return info

static func from_dict(data: Dictionary) -> ScenarioInfo:
	var info := ScenarioInfo.new()
	info.path = String(data.get("path", ""))
	info.name = String(data.get("name", ""))
	info.description = String(data.get("description", ""))
	info.map_difficulty = clampi(int(data.get("map_difficulty", 0)), 0, 3)
	info.size = clampi(int(data.get("size", 0)), 0, 2)
	info.native_order = int(data.get("native_order", 0))
	for count in data.get("supported_human_counts", []):
		var n := int(count)
		if n >= 1 and n <= 4 and not info.supported_human_counts.has(n):
			info.supported_human_counts.append(n)
	for color in data.get("available_colors", []):
		var c := int(color)
		if c >= 0 and c <= 3 and not info.available_colors.has(c):
			info.available_colors.append(c)
	info.available_colors.sort()
	info.supported_human_counts.sort()
	info.seat_count = int(data.get("seat_count", info.available_colors.size()))
	return info

func is_valid() -> bool:
	return path != "" and name != "" and seat_count > 0

func to_dict() -> Dictionary:
	return {
		"path": path,
		"name": name,
		"description": description,
		"map_difficulty": map_difficulty,
		"size": size,
		"supported_human_counts": supported_human_counts.duplicate(),
		"available_colors": available_colors.duplicate(),
		"native_order": native_order,
		"seat_count": seat_count,
	}
