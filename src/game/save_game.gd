class_name SaveGame
extends RefCounted

## Save-slot service.
## One save = one JSON file in user://saves/<slot>.json. Envelope version 7.
## Pure static functions; the Game autoload owns applying an envelope to a run.

const SAVE_DIR := "user://saves"
const VERSION := 7
const AUTOSAVE_SLOT := "AUTOSAVE"
const CAMPAIGN_AUTOSAVE_SLOT := "CAMPAIGN_AUTOSAVE"
const HOTSEAT_AUTOSAVE_SLOT := "HOTSEAT_AUTOSAVE"
const NETWORK_AUTOSAVE_SLOT := "NETWORK_AUTOSAVE"
## GameState.to_dict() keys the envelope carries only when present.
const OPTIONAL_STATE_KEYS := ["last_week_event", "spawned_neutral_stacks", "hero_pool",
		"king_of_the_hill", "ultimate_artifact", "dug_tiles"]
## Where a dropped remote player's run is dumped, named after the original
## (KB homm1-native-data.md §5.3).
const PLYREXIT_SLOT := "PLYREXIT"
## A new game's name until it is first saved (heroes.exe 0x78734).
const NEW_GAME_NAME := "NEWGAME"
const MAX_NAME := 32
const BAD_CHARS := "/\\:*?\"<>|"

static func sanitize_slot(name: String) -> String:
	var out := ""
	for ch in name:
		if BAD_CHARS.contains(ch) or ch.unicode_at(0) < 32:
			continue
		out += ch
	return out.strip_edges().left(MAX_NAME)

static func build_envelope(state: GameState, object_state: Dictionary, map_path: String,
		town_tile: Vector2i,
		save_name: String = "", setup: NewGameSettings = null, game_mode: StringName = &"standard",
		campaign: CampaignState = null) -> Dictionary:
	var objs := {}
	for k in object_state:
		objs[str(k)] = object_state[k]
	var sd := state.to_dict()
	var saved_setup := setup.duplicate_settings() if setup != null else NewGameSettings.new()
	saved_setup.map_path = map_path
	var env := {
		"version": VERSION,
		"game_mode": String(game_mode),
		"campaign": campaign.to_dict() if campaign != null else null,
		"save_name": save_name,
		"timestamp": Time.get_datetime_string_from_system(),
		"day": sd["day"],
		"active_player_side": sd["active_player_side"],
		"map_path": map_path,
		"setup": saved_setup.to_dict(),
		"players": sd["players"],
		"boats": sd["boats"],
		"next_boat_id": sd["next_boat_id"],
		"map_object_state": objs,
		"game": {
			"town_tile": [town_tile.x, town_tile.y],
		},
	}
	for key: String in OPTIONAL_STATE_KEYS:
		if sd.has(key):
			env[key] = sd[key]
	return env

## "" = valid; otherwise a user-facing error message. Validate before mutate:
## callers must not touch any run state until this returns "".
static func validate(env: Dictionary) -> String:
	var version := int(env.get("version", -1))
	if version < 1 or version > VERSION:
		return "Unsupported save version (%s)" % str(env.get("version", "?"))
	if version >= 2 and not (env.get("setup", null) is Dictionary):
		return "Corrupt setup data"
	if version >= 5:
		var mode := String(env.get("game_mode", "standard"))
		if not ["standard", "campaign", "hotseat", "network"].has(mode):
			return "Corrupt game mode"
		if mode == "campaign" and not (env.get("campaign", null) is Dictionary):
			return "Corrupt campaign data"
	var players: Variant = env.get("players", null)
	if not (players is Array) or (players as Array).is_empty():
		return "Save has no players"
	var sides := []
	for p in (players as Array):
		if not (p is Dictionary) or not ((p as Dictionary).get("side", null) is float \
				or (p as Dictionary).get("side", null) is int) or sides.has(int(p["side"])):
			return "Corrupt player entry"
		sides.append(int(p["side"]))
	if env.has("map_object_state") and not (env["map_object_state"] is Dictionary):
		return "Corrupt save structure"
	if env.has("game") and not (env["game"] is Dictionary):
		return "Corrupt save structure"
	var mp := String(env.get("map_path", ""))
	if mp == "" or not FileAccess.file_exists(mp):
		return "Map file missing: %s" % mp
	return ""

static func _slot_path(slot: String, dir: String) -> String:
	return "%s/%s.json" % [dir, sanitize_slot(slot)]

static func write_slot(slot: String, env: Dictionary, dir: String = SAVE_DIR) -> String:
	if sanitize_slot(slot) == "":
		return "Empty save name"
	DirAccess.make_dir_recursive_absolute(dir)
	# Write beside the slot and rename over it, so a failed write cannot
	# leave a half-written save in place of the old one.
	var path := _slot_path(slot, dir)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "Cannot write save file (%s)" % error_string(FileAccess.get_open_error())
	f.store_string(JSON.stringify(env, "\t"))
	var err := f.get_error()
	f.close()
	if err == OK:
		err = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		return "Cannot write save file (%s)" % error_string(err)
	return ""

static func read_slot(slot: String, dir: String = SAVE_DIR) -> Dictionary:
	var path := _slot_path(slot, dir)
	if not FileAccess.file_exists(path):
		return {"error": "No such save: %s" % slot}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"error": "Cannot open save file"}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return {"error": "Corrupt save file: %s" % slot}
	var err := validate(parsed)
	if err != "":
		return {"error": err}
	return parsed

## Newest-first metadata for every readable slot (corrupt files are skipped).
## `mode` is a comma-separated allow-list ("" = every mode); the multiplayer
## load screen passes "hotseat,network" to show local and remote saves together.
static func list_slots(dir: String = SAVE_DIR, mode: String = "") -> Array:
	var allowed := PackedStringArray() if mode == "" else mode.split(",")
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for fname in d.get_files():
		if not fname.ends_with(".json"):
			continue
		var path := "%s/%s" % [dir, fname]
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if not (parsed is Dictionary):
			continue
		var saved_mode := String((parsed as Dictionary).get("game_mode", "standard"))
		if mode != "" and not allowed.has(saved_mode):
			continue
		var p: Dictionary = parsed as Dictionary
		out.append({
			"slot": fname.trim_suffix(".json"),
			"save_name": String(p.get("save_name", fname)),
			"day": int(p.get("day", 0)),
			"game_mode": saved_mode,
			"timestamp": String(p.get("timestamp", "")),
			"map_path": String(p.get("map_path", "")),
			"setup": p.get("setup", {}) if p.get("setup") is Dictionary else {},
			"campaign": p.get("campaign", null) if p.get("campaign") is Dictionary else null,
			"mtime": FileAccess.get_modified_time(path),
		})
	out.sort_custom(func(a, b): return int(a["mtime"]) > int(b["mtime"]))
	return out

static func delete_slot(slot: String, dir: String = SAVE_DIR) -> bool:
	var path := _slot_path(slot, dir)
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK
