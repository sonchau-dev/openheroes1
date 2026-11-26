class_name MapObject
extends RefCounted

## Base for every interactive adventure-map object. Behavior lives in catalog
## handlers; subclasses hold fields and (if mutable) save_state()/apply_state().

var id: int = -1                       # stable index assigned at load; key for persistence
var type: String = ""                  # object kind; see keys in data/objects/catalog.json
var tile: Vector2i = Vector2i.ZERO     # where the art sits
var action_tile: Vector2i = Vector2i.ZERO  # tile the hero steps on to trigger
var owner: int = -1                    # -1 = neutral; else player side
var params: Dictionary = {}            # generic authored data (catalog default_params merged under map spec)
var visited_by: Array = []             # hero ids that already visited (once-per-hero boosters)
var consumed: bool = false             # true once a one-shot object is spent (lifted
                                        # here from ResourcePile/NeutralStack so generic catalog-driven
                                        # pickups — artifact/chest/campfire — can vanish too; the duck-typed
                                        # `"consumed" in obj` checks in map_data.gd/pathfinder.gd already
                                        # covered any object, this just gives every object the field.)
## Scenario-start artifact allocation for artifact-producing sites. Ground
## artifacts use ArtifactPickup.artifact_id; sites use this shared override.
var resolved_artifact_id: String = ""
var artifact_assignment_resolved: bool = false
## A skeleton's map-start roll (heroes.exe 0x7ac69 sets its B9 flag to 2 for 10%
## of them): true when searching it yields an artifact, or gold if none is left.
var has_find: bool = false
## The sprites the source .map itself paints for this object, as
## [[dx, dy, "dir/NNNN.png"], ...] relative to `tile`, back plate first. Imported
## HOMM1 scenarios fill this in; hand-authored maps leave it empty and fall back
## to the catalog's `art` entry. When it is set it also fixes the anchor: the
## object's own tile IS the tile the hero steps on (the .map's B8 marks exactly
## the interactive cell). V3 stores those visuals in MapData.render_parts.
var authored_interaction_tiles: Array[Vector2i] = []
var entry_rule: String = ""
var map_art: bool = false

func has_map_art() -> bool:
	return map_art

## All equivalent map cells that trigger this object. action_tile remains the
## canonical destination used by save data and AI; catalog action_offsets add
## aliases for wide objects without duplicating their state or handler.
func interaction_tiles() -> Array[Vector2i]:
	if not authored_interaction_tiles.is_empty():
		return authored_interaction_tiles.duplicate()
	var out: Array[Vector2i] = []
	var canonical_offset := ObjectCatalog.shared().action_offset(type)
	for off: Vector2i in ObjectCatalog.shared().action_offsets(type):
		out.append(action_tile + off - canonical_offset)
	return out

## Called when a hero arrives on an interaction tile. Behavior lives in the catalog
## handler for this type; objects without one do nothing.
func on_visit(ctx: VisitContext) -> VisitResult:
	var h: Variant = ObjectCatalog.shared().handler(type)
	if h == null:
		return VisitResult.new()
	return h.visit(self, ctx)

## True if visiting this object (while unbeaten/unowned) forces a battle.
func is_armed() -> bool:
	return false

## True when visiting this object starts a fight. The adventure cursor reads
## this only for a town (TownObject: an enemy town gate shows the sword). Every
## other object's cursor comes from its class in
## AdventureInputController._object_cursor_id (heroes.exe 0x98e8b..0x996ed),
## so an armed site such as a Graveyard still shows the rearing horse.
func uses_attack_cursor() -> bool:
	return is_armed()

## True for walk-on collectibles (resource piles, chest, campfire, artifact,
## skeleton). The hero halts one tile short of these and collects from there —
## it never steps onto the object's tile (authentic HOMM1 engage behavior;
## see AdventureMap._confirm_path stop-before handling). Buildings that happen
## to use the same pickup/weekly_pickup handlers (windmill, watermill: catalog
## `entry: "building"`) are excluded — like Mine, the hero rides fully onto
## the action tile (visual bug report + reference screenshot: windmill's door
## sits on that tile, and the hero should occupy it, not stop in front).
func is_walk_on_pickup() -> bool:
	if ObjectCatalog.shared().stop_before(type):
		return true
	var hid := ObjectCatalog.shared().handler_id(type)
	if hid != "pickup" and hid != "weekly_pickup":
		return false
	return ObjectCatalog.shared().entry(type) != "building"

func mark_visited(hero_id: int) -> void:
	if not visited_by.has(hero_id):
		visited_by.append(hero_id)

func was_visited_by(hero_id: int) -> bool:
	return visited_by.has(hero_id)

## Persisted mutable state (owner/consumed/stock/visited_by). Subclasses call
## super and merge their own keys in.
func save_state() -> Dictionary:
	var d := {}
	if not visited_by.is_empty():
		d["visited_by"] = visited_by.duplicate()
	if consumed:
		d["consumed"] = consumed
	if resolved_artifact_id != "":
		d["resolved_artifact_id"] = resolved_artifact_id
	if artifact_assignment_resolved:
		d["artifact_assignment_resolved"] = true
	if has_find:
		d["has_find"] = true
	return d

func apply_state(s: Dictionary) -> void:
	var v: Variant = s.get("visited_by", null)
	if v is Array:
		visited_by = []
		for e in (v as Array):
			visited_by.append(int(e))
	consumed = bool(s.get("consumed", consumed))
	var resolved_id := String(s.get("resolved_artifact_id", resolved_artifact_id))
	resolved_artifact_id = ArtifactCatalog.shared().normalize(resolved_id) if resolved_id != "" else ""
	artifact_assignment_resolved = bool(s.get("artifact_assignment_resolved", artifact_assignment_resolved))
	has_find = bool(s.get("has_find", has_find))

## Authored-schema serialization (MapSaverJson). Subclasses extend the dict.
## action_tile is derived at load; runtime state (spell rolls, consumption)
## is Game.record_object_state territory — neither is emitted here.
## NOTE: `params` holds catalog defaults merged in at load, so re-saving a map
## bakes the current defaults into the authored file — later catalog rebalances
## won't reach maps that were re-saved.
func to_spec() -> Dictionary:
	var d := {"type": type, "tile": [tile.x, tile.y]}
	if not authored_interaction_tiles.is_empty():
		var interactions: Array = []
		for t: Vector2i in authored_interaction_tiles:
			interactions.append([t.x, t.y])
		d["interaction_tiles"] = interactions
		d["entry"] = entry_rule
	if not params.is_empty():
		d["params"] = params
	return d

static func army_rows(a: ArmyData) -> Array:
	var rows: Array = []
	for s: Dictionary in a.slots:
		rows.append([String(s.unit), int(s.count)])
	return rows
