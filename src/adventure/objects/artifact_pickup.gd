class_name ArtifactPickup
extends MapObject

const PRICE := 2000
## heroes.exe visit messages 0x46 (shown before the Rogue battle) and 0x4a
## (after winning it).
const GUARDED_MESSAGE := "Artifact\n\nYou come upon an ancient artifact.  As you reach for it, a pack of Rogues leap out of the brush to guard their stolen loot."
## heroes.exe data 0x292c, shown at 0xb3a5c when the hero has 14 artifacts;
## the artifact stays, with no fight and no leprechaun offer.
## After Yes without the gold; the leprechaun stays (message 0x49).
const NO_GOLD_MESSAGE := "You try to pay the leprechaun, but realize that you don't have 2000 gold.  The leprechaun stamps his foot and ignores you."
const FULL_LOAD_MESSAGE := "You cannot pick up this artifact, you already have a full load!"
const ROGUES_DEFEATED_MESSAGE := "Upon defeating the Rogues, you search their corpses and discover the %s."
const MODES := ["free", "guarded", "paid"]

var artifact_id: String = ""
var encounter_mode: String = ""
var resolved: bool = false
var authored_artifact: bool = false
var authored_mode: bool = false

static func mode_for_roll(roll: float) -> String:
	if roll < 0.60:
		return "free"
	if roll < 0.80:
		return "guarded"
	return "paid"

func resolve(id: String, mode: String) -> void:
	artifact_id = ArtifactCatalog.shared().normalize(id) if id != "" else ""
	encounter_mode = mode if mode in MODES else "free"
	resolved = true

func is_armed() -> bool:
	return resolved and artifact_id != "" and not consumed and encounter_mode == "guarded"

## Artifacts always advertise an interaction, even when Rogues guard them. The
## encounter is discovered by approaching the artifact; only visible wandering
## creature stacks and their control zones use the sword cursor.
func uses_attack_cursor() -> bool:
	return false

func guard_army() -> ArmyData:
	var guard := ArmyData.new()
	# Do not use ArmyData.add(): five identical Rogue entries are five distinct
	# native stacks and must not merge into one.
	for _i in 5:
		guard.slots.append({"unit": "rogue", "count": 10})
	return guard

func on_visit(ctx: VisitContext) -> VisitResult:
	var result := VisitResult.new()
	result.source_object = self
	if consumed or not resolved or artifact_id == "":
		return result
	if ctx.hero_model == null or not ctx.hero_model.can_add_artifact(artifact_id):
		result.message = FULL_LOAD_MESSAGE
		result.show_dialog = true
		return result
	# heroes.exe 0xb5f12 marks the cell visited; from then on the computer
	# values the artifact by its known encounter (0x719e1).
	mark_visited(ctx.hero_id)
	match encounter_mode:
		"guarded":
			result.start_battle = guard_army()
			result.message = GUARDED_MESSAGE
		"paid":
			# The offer always comes first; the purse is checked after Yes
			# (heroes.exe 0xb3c4f..0xb3cc5).
			result.choice = {
				"type": "artifact_paid",
				"artifact_id": artifact_id,
				"prompt": offer_text(artifact_id),
				"object": self,
				"options": [
					{"label": "Pay 2000 Gold", "pay": PRICE, "artifact": artifact_id},
					{"label": "Decline", "decline_artifact": true},
				],
			}
		_:
			consumed = true
			result.consumed = true
			result.grant_artifact = artifact_id
			result.message = ArtifactCatalog.shared().pickup_text(artifact_id)
			result.show_dialog = true
	return result

## The leprechaun's offer (heroes.exe data 0x20f60, without its "Artifact"
## title line, which the dialog draws).
static func offer_text(id: String) -> String:
	return "A leprechaun offers you the %s for the small price of 2000 gold.  Do you wish to buy this artifact?" \
			% ArtifactCatalog.shared().display_name(id)

func save_state() -> Dictionary:
	var state := super.save_state()
	state["artifact_id"] = artifact_id
	state["encounter_mode"] = encounter_mode
	state["resolved"] = resolved
	return state

func apply_state(state: Dictionary) -> void:
	super.apply_state(state)
	artifact_id = ArtifactCatalog.shared().normalize(String(state.get("artifact_id", artifact_id))) \
			if String(state.get("artifact_id", artifact_id)) != "" else ""
	encounter_mode = String(state.get("encounter_mode", encounter_mode))
	resolved = bool(state.get("resolved", resolved))

func to_spec() -> Dictionary:
	var spec := super.to_spec()
	# Runtime random resolution belongs in save state, not authored map JSON.
	if authored_artifact and artifact_id != "":
		spec["artifact_id"] = artifact_id
	if authored_mode and encounter_mode != "":
		spec["encounter_mode"] = encounter_mode
	return spec
