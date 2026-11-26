class_name ArtifactCatalog
extends RefCounted

## Canonical HOMM1 artifact metadata. Both inventory (artifact/) and adventure
## map (art32/) sheets use the same native frame ordering.

const DEFAULT_PATH := "res://data/artifacts/catalog.json"
const ARTIFACT_ICON := "res://assets/art/artifact/%04d.png"
const ARTIFACT_SMALL_ICON := "res://assets/art/artfx/%04d.png"

static var _shared: ArtifactCatalog

var defs: Dictionary = {}
var _aliases: Dictionary = {}
var _by_frame: Dictionary = {}

static func shared() -> ArtifactCatalog:
	if _shared == null:
		_shared = load_catalog()
	return _shared

static func load_catalog(path: String = DEFAULT_PATH) -> ArtifactCatalog:
	var parsed := JsonFile.read_dict(path)
	if parsed.is_empty():
		push_error("ArtifactCatalog: %s is not a valid JSON object" % path)
		return null
	var catalog := ArtifactCatalog.new()
	for raw_id: Variant in parsed.keys():
		var id := String(raw_id)
		var definition: Dictionary = (parsed[raw_id] as Dictionary).duplicate(true)
		definition["id"] = id
		definition["art_frame"] = int(definition.get("frame", -1))
		definition["art32_frame"] = int(definition.get("frame", -1))
		catalog.defs[id] = definition
		catalog._aliases[id] = id
		catalog._by_frame[int(definition.frame)] = id
		for alias: Variant in definition.get("aliases", []):
			catalog._aliases[String(alias).to_lower()] = id
	return catalog

func normalize(id: String) -> String:
	var key := id.strip_edges().to_lower().replace("-", "_").replace(" ", "_")
	return String(_aliases.get(key, key))

func has(id: String) -> bool:
	return defs.has(normalize(id))

func get_artifact(id: String) -> Dictionary:
	return (defs.get(normalize(id), {}) as Dictionary).duplicate(true)

func from_frame(frame: int, map_frame: bool = false) -> String:
	# Frame 37 is a random-artifact placeholder in native map data, but it is
	# the Spell Book in the inventory sheet. Importers pass map_frame=true.
	if map_frame and frame == 37:
		return ""
	return String(_by_frame.get(frame, ""))

## The artifact's name as heroes.exe shows it everywhere (table at data
## 0x208b0): hover, capture page, dig, Rogues, leprechaun, skeleton.
func display_name(id: String) -> String:
	var d := get_artifact(id)
	return String(d.get("name", normalize(id).capitalize()))

## The info box text, one string with its short title first (heroes.exe
## table at data 0x20948, shown by 0xb1a7c).
func info_text(id: String) -> String:
	return String(get_artifact(id).get("info", display_name(id)))

## The text shown when the artifact is picked up on the map (data 0x209e0).
func pickup_text(id: String) -> String:
	return String(get_artifact(id).get("pickup_text", ""))

## The four dig-only Ultimate Artifacts (native ids 0-3). They are never in the
## random pool, so `ordinary` is false for exactly these.
func is_ultimate(id: String) -> bool:
	var d := get_artifact(id)
	return not d.is_empty() and not bool(d.get("ordinary", false)) \
			and int(d.get("frame", -1)) in [0, 1, 2, 3]

## The native 76x76 slot border drawn around an artifact icon: the ornate
## heroscrn frame 15 for an Ultimate Artifact, plain frame 5 for the rest.
func slot_frame_path(id: String) -> String:
	return "res://assets/art/heroscrn/%04d.png" % (15 if is_ultimate(id) else 5)

func artifact_icon_path(id: String) -> String:
	return ARTIFACT_ICON % int(get_artifact(id).get("frame", -1))

## The 32x32 artifact icon used in the hero exchange / swap window (artfx.icn).
func artifact_small_icon_path(id: String) -> String:
	return ARTIFACT_SMALL_ICON % int(get_artifact(id).get("frame", -1))

func ordinary_pool() -> Array[String]:
	var out: Array[String] = []
	for id: String in defs:
		if bool(defs[id].get("ordinary", false)) and bool(defs[id].get("random_pool", false)):
			out.append(id)
	out.sort_custom(func(a: String, b: String):
		return int(defs[a].frame) < int(defs[b].frame))
	return out

func effect_total(artifacts: Array, effect_type: String, hero_class: String = "") -> int:
	var total := 0
	var seen := {}
	for raw_id: Variant in artifacts:
		var id := normalize(String(raw_id))
		var d: Dictionary = defs.get(id, {})
		if d.is_empty() or String(d.get("effect_type", "")) != effect_type:
			continue
		if not bool(d.get("stacking", false)) and seen.has(id):
			continue
		seen[id] = true
		if effect_type == "sea_movement" and hero_class == "sorceress":
			total += int(d.get("sorceress_value", d.get("effect_value", 0)))
		else:
			total += int(d.get("effect_value", 0))
	return total

func is_transferable(id: String) -> bool:
	return bool(get_artifact(id).get("transferable", false))

func ai_value(id: String) -> float:
	var d := get_artifact(id)
	if d.is_empty():
		return 0.0
	var signed_value := float(d.get("effect_value", 0))
	var value := absf(signed_value)
	match String(d.get("effect_type", "")):
		"attack", "defense": return value * 550.0
		"spell_power", "knowledge": return value * 450.0
		"morale", "luck": return value * 650.0 if signed_value > 0.0 else -1000.0
		"daily_gold": return value * 3.0
		"land_movement", "sea_movement", "all_movement": return value * 45.0
		"ballista": return 1200.0
		_: return 0.0
