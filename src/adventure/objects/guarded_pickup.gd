class_name GuardedPickup
extends MapObject

## Canonical English copy recovered from the bundled original HOMM1 executable.
## The game consistently titles this event "Daemon Cave", despite the map object
## and project type using the modernized `demon_cave` identifier.
const DEMON_CAVE_TITLE := "Daemon Cave"
const DEMON_CAVE_ENTER_MESSAGE := "The cave is dank and musty.  Two large red eyes glow eerily within the blackness.  Do you wish to enter?"
const DEMON_CAVE_EMPTY_MESSAGE := "Moisture congeals on the walls and trickles slowly down to the ground.  Except for the evidence of a battle, the cave is empty."
const DEMON_CAVE_RANSOM_MESSAGE := "You are captured by a large daemon.  He offers to let you free for 2500 gold, otherwise he will devour you.  Do you pay?"
const DEMON_CAVE_BROKE_MESSAGE := "Seeing that you do not have 2500 gold, the daemon slashes you with its claws, and the last thing you see is a red haze."
const DEMON_CAVE_EXP_MESSAGE := "A large daemon emerges from the shadows and you attack. After an exhausting battle, you emerge victorious and receive 1000 experience points."
const DEMON_CAVE_EXP_ARTIFACT_MESSAGE := "A large daemon emerges from the shadows and you attack. After an exhausting battle, you emerge victorious and receive 1000 experience points and an artifact."
const DEMON_CAVE_EXP_GOLD_MESSAGE := "A large daemon emerges from the shadows and you attack. After an exhausting battle, you emerge victorious and receive 1000 experience points and 2500 gold."

## heroes.exe asks before every Graveyard and Shipwreck visit, plundered or
## not (Yes/No, messages 0x14 and 0x3a). Yes on a plundered site shows the
## "find nothing" text and lowers morale; Yes otherwise fights the ghosts, and
## a win always reads "find something!" (0xb507f, messages 0x16 and 0x3c).
const ENTRY_PROMPTS := {
	"graveyard": {"title": "Graveyard",
		"prompt": "You tentatively approach the burial ground of ancient warriors.  Do you want to search the graves?"},
	"shipwreck": {"title": "Shipwreck",
		"prompt": "The rotting hulk of a great pirate ship creaks eerily as it is pushed against the rocks.  Do you wish to search the shipwreck?"},
}
const PLUNDERED_MESSAGES := {
	"graveyard": "Upon defeating the ghosts you spend several hours searching the graves and find nothing.  Such a despicable act reduces your army's morale.",
	"shipwreck": "Upon defeating the ghosts you spend several hours sifting through the debris and find nothing.  Such a despicable act reduces your army's morale.",
}
const VICTORY_MESSAGES := {
	"graveyard": "Upon defeating the ghosts you search the graves and find something!",
	"shipwreck": "Upon defeating the ghosts you sift through the debris and find something!",
}

## Generic "battle then banded reward" site. Mirrors the
## Mine/NeutralStack guard pattern but generalizes it: at first visit the handler
## rolls ONE outcome band (weighted by each band's `p` via Game.rng), fights that
## band's guard army, and — on victory — InteractionResolver applies that same
## band's reward. No object is placed by this seam; Graveyard, Demon Cave and
## Dragon City supply real catalog entries whose default_params carry the
## authentic outcome tables: Graveyard and Shipwreck field authentic Ghost
## formations, Dragon City fields 5 Dragons, and Demon Cave reproduces the
## original executable's narrative event outcomes.

## Each entry: {p: float (weight), guard: [[unit,count],…], reward: {gold?, exp?, artifact?}}.
## Sourced from params.outcomes (catalog default merged under authored spec).
var outcomes: Array = []

## Which band this instance rolled at visit-time. -1 = not yet rolled. Persisted
## (survives the post-battle scene reload) so the reward the resolver applies on
## victory matches the guard the player just fought.
var rolled_band: int = -1

## True once the reward has been claimed. A looted site is inert (revisitable but
## yields nothing by default; a type may add a post-loot message via params).
var looted: bool = false

## Human-only, transient acknowledgement of the native Yes/No entry prompt.
## It is deliberately not persisted: the resolver consumes it immediately by
## visiting the same object again, while a declined prompt leaves the cave fresh.
var entry_confirmed: bool = false

static func demon_cave_victory_message(band: int) -> String:
	match band:
		1:
			return DEMON_CAVE_EXP_MESSAGE
		2:
			return DEMON_CAVE_EXP_GOLD_MESSAGE
		3:
			return DEMON_CAVE_EXP_ARTIFACT_MESSAGE
	return ""

## The artifact a band hands out: the allocator's (or the rolled random) pick
## once resolved, else the catalog id; "" for a band without one.
func reward_artifact(band: int) -> String:
	if band < 0 or band >= outcomes.size():
		return ""
	var reward: Dictionary = (outcomes[band] as Dictionary).get("reward", {})
	if not reward.has("artifact"):
		return ""
	if artifact_assignment_resolved and resolved_artifact_id != "":
		return resolved_artifact_id
	return String(reward.get("artifact", ""))

## Armed until looted (an un-looted site always forces the roll-and-battle path).
## In authentic HOMM1, Demon Cave is a narrative event without tactical combat.
func is_armed() -> bool:
	return not looted and type != "demon_cave"

## The guard army for the currently-rolled band. Empty ArmyData when unrolled or
## out of range (the handler only asks after assigning rolled_band).
func guard_army() -> ArmyData:
	return guard_army_for(rolled_band)

## The guard army of outcome band `band`; empty when out of range.
func guard_army_for(band: int) -> ArmyData:
	var ad := ArmyData.new()
	if band < 0 or band >= outcomes.size():
		return ad
	var rows: Variant = (outcomes[band] as Dictionary).get("guard", [])
	if rows is Array:
		for row: Variant in (rows as Array):
			if row is Array and (row as Array).size() == 2:
				ad.add(String((row as Array)[0]), int((row as Array)[1]), false)
	return ad

## Weighted band pick. Weights are each outcome's `p`; if they don't sum to 1 the
## walk normalizes by their total (treats `p` as relative weights). All-zero /
## empty weights fall back to the first band. Deterministic for a seeded rng.
static func roll_band(bands: Array, rng: RandomNumberGenerator) -> int:
	if bands.is_empty():
		return -1
	var total := 0.0
	for o: Variant in bands:
		total += maxf(0.0, float((o as Dictionary).get("p", 0.0)))
	if total <= 0.0:
		return 0
	var x := rng.randf() * total
	var acc := 0.0
	for i in bands.size():
		acc += maxf(0.0, float((bands[i] as Dictionary).get("p", 0.0)))
		if x < acc:
			return i
	return bands.size() - 1

## Apply the rolled band's reward on victory. Extractable/static so the resolver
## (human) and AITurnRunner (AI) share one authentic path and headless tests can
## exercise it without a battle. `player` receives gold (PlayerState.add_resources,
## gold routes to the town); `hero_model` receives exp + artifact. Sets `looted`.
## Guards against an unrolled / out-of-range band (no-op, no loot flag flip).
static func apply_reward(obj: GuardedPickup, band: int, player: PlayerState,
		hero_model: HeroModel, rng: RandomNumberGenerator = null) -> void:
	if obj == null or band < 0 or band >= obj.outcomes.size():
		return
	var reward: Dictionary = (obj.outcomes[band] as Dictionary).get("reward", {})
	var gold := int(reward.get("gold", 0))
	if gold != 0 and player != null:
		player.add_resources({"gold": gold})
	var exp := int(reward.get("exp", 0))
	if exp > 0 and hero_model != null:
		hero_model.grant_experience(exp, rng)
	var art := obj.resolved_artifact_id if obj.artifact_assignment_resolved \
			else String(reward.get("artifact", ""))
	if art == "random" or art == "random_artifact":
		var pool := ArtifactCatalog.shared().ordinary_pool()
		if not pool.is_empty():
			var idx := rng.randi_range(0, pool.size() - 1) if rng != null else 0
			art = pool[idx]
			obj.resolved_artifact_id = art
			obj.artifact_assignment_resolved = true
		else:
			art = ""
	if art != "" and hero_model != null:
		if ArtifactCatalog.shared().has(art):
			hero_model.add_artifact(art)
		elif hero_model.artifacts.size() < hero_model.artifact_capacity():
			# Preserve legacy/modded site IDs from pre-catalog maps and saves.
			hero_model.artifacts.append(art)
	# No morale change on a win: heroes.exe's guarded encounter (0xb507f) never
	# touches morale. The penalty belongs to searching a plundered site.
	obj.looted = true

func save_state() -> Dictionary:
	var d := super.save_state()
	d["rolled_band"] = rolled_band
	d["looted"] = looted
	return d

func apply_state(s: Dictionary) -> void:
	super.apply_state(s)
	rolled_band = int(s.get("rolled_band", rolled_band))  # JSON ints load as floats
	looted = bool(s.get("looted", looted))
