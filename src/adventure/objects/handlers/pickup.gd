extends RefCounted
## Resource pile: grants `amount` of `res` once, then marks the pile consumed.
## Generic catalog-driven pickups (artifact/chest/campfire/etc.)
## read `obj.params` instead — see data/objects/catalog.json for their defaults
## and data/knowledge_base/adventure-object-catalog.md for the value tables those
## defaults transcribe (Artifact/Treasure Chest/Campfire rows).

const SKELETON_GOLD := 1000
## heroes.exe message 0x0e; the window title "Campfire" is drawn separately.
const CAMPFIRE_MESSAGE := "Ransacking an enemy camp, you discover a hidden cache of treasures."
## heroes.exe message 0x4c, followed by the artifact name.
const SKELETON_FIND := "Skeleton\n\nYou come upon the remains of an unfortunate adventurer.  Searching through the tattered clothing, you find %s"
## heroes.exe message 0x4b.
const SKELETON_NOTHING := "Skeleton\n\nYou come upon the remains of an unfortunate adventurer.  Searching through the tattered clothing, you find nothing."

func visit(obj: MapObject, ctx: VisitContext) -> VisitResult:
	var pile := obj as ResourcePile
	if pile != null:
		return _visit_resource_pile(pile)
	return _visit_generic(obj, ctx)

func _visit_resource_pile(pile: ResourcePile) -> VisitResult:
	var r := VisitResult.new()
	if pile.consumed:
		return r
	pile.consumed = true
	r.consumed = true
	r.granted = {pile.res: pile.amount}
	r.message = "+%d %s" % [pile.amount, pile.res]
	return r

## Generic dispatch for any catalog type with no dedicated MapObject subclass.
## `chest`/`campfire` roll a random tier from their catalog params
## (data/knowledge_base/adventure-object-catalog.md's Treasure Chest / Campfire
## rows); everything else
## reads a flat params shape: {"artifact": id} / {"exp": N} / {"grant": {res: amt}}.
func _visit_generic(obj: MapObject, ctx: VisitContext) -> VisitResult:
	var r := VisitResult.new()
	if obj.consumed:
		return r
	match obj.type:
		"chest":
			return _visit_chest(obj)
		"campfire":
			return _visit_campfire(obj)
		"skeleton":
			return _visit_skeleton(obj, ctx)
	var p: Dictionary = obj.params
	if p.has("artifact"):
		r.grant_artifact = String(p["artifact"])
		r.message = String(p.get("message", "You have found the %s!" % r.grant_artifact.capitalize()))
	elif p.has("exp"):
		r.grant_exp = int(p["exp"])
		r.message = String(p.get("message", "+%d experience" % r.grant_exp))
	elif p.has("grant"):
		r.granted = _int_normalized(p["grant"] as Dictionary)
		r.message = String(p.get("message", _compose_grant_message(r.granted)))
	else:
		return r   # unrecognized generic pickup shape: nothing to grant, leave unconsumed
	obj.consumed = true
	r.consumed = true
	return r

## Treasure Chest (note: 1000g/500xp, 1500g/1000xp, 2000g/1500xp — tier rolled,
## then the player picks gold or experience). The tier is rolled immediately
## (Game's seeded live RNG, same "roll once with the live RNG" pattern Shrine
## uses for its spell — see shrine.gd/object_layer.gd); the chest always
## disappears on this visit, independent of which option gets picked later.
func _visit_chest(obj: MapObject) -> VisitResult:
	var r := VisitResult.new()
	var tiers: Array = obj.params.get("tiers", [])
	if tiers.is_empty():
		return r
	var tier: Array = tiers[Game.rng.randi_range(0, tiers.size() - 1)]
	var gold := int(tier[0])
	var exp := int(tier[1])
	obj.consumed = true
	r.consumed = true
	r.choice = {
		"type": "chest",
		"prompt": "You found a treasure chest. Take the gold, or the experience?",
		"options": [
			{"label": "%d Gold" % gold, "granted": {"gold": gold}},
			{"label": "%d Experience" % exp, "exp": exp},
		],
		"gold": gold,
		"exp": exp,
	}
	return r

## Campfire (note: 400g+4, 500g+5, 600g+6 of a random resource — tier AND
## resource both rolled, both grants land at once, no choice). heroes.exe message
## 0x0e in a titled window with both icons (DOS campaign recording), drawn by
## the resolver.
func _visit_campfire(obj: MapObject) -> VisitResult:
	var r := VisitResult.new()
	var tiers: Array = obj.params.get("tiers", [])
	var pool: Array = obj.params.get("resources", [])
	if tiers.is_empty() or pool.is_empty():
		return r
	var tier: Array = tiers[Game.rng.randi_range(0, tiers.size() - 1)]
	var gold := int(tier[0])
	var amount := int(tier[1])
	var res := String(pool[Game.rng.randi_range(0, pool.size() - 1)])
	obj.consumed = true
	r.consumed = true
	r.granted = {"gold": gold, res: amount}
	r.message = CAMPFIRE_MESSAGE
	return r

## Skeleton, as heroes.exe 0xb2e80-0xb2f8b plays it. The map-start pass has
## already decided whether it holds a find (10%, ArtifactAllocator). The first
## search by any hero drops that flag: the skeleton stays on the map and every
## later visit shows the find-nothing message. `visited_by` records the first
## search, so a revisit never re-rolls and `consumed` stays false.
## A find is a random artifact from the world's remaining pool, or 1000 gold
## when none is left (0xb4ea4, 0xb4f85). A hero already carrying a full load
## gets the full-load message and the artifact is lost, flag dropped anyway.
## Objects built outside the allocator (hand-authored maps, tests) roll here
## from `params.chance`, so they behave the same on the first visit.
func _visit_skeleton(obj: MapObject, ctx: VisitContext) -> VisitResult:
	var r := VisitResult.new()
	r.show_dialog = true
	r.message = SKELETON_NOTHING
	if not obj.visited_by.is_empty():
		return r
	obj.mark_visited(ctx.hero_id)
	var found := obj.has_find
	var artifact := obj.resolved_artifact_id
	if not obj.artifact_assignment_resolved:
		found = Game.rng.randf() < float(obj.params.get("chance", 0.10))
		var pool: Array = obj.params.get("artifact_pool", [])
		if found and not pool.is_empty():
			artifact = String(pool[Game.rng.randi_range(0, pool.size() - 1)])
	if not found:
		return r
	var hero := ctx.hero_model
	if hero != null and hero.artifacts.size() >= hero.artifact_capacity():
		r.message = ArtifactPickup.FULL_LOAD_MESSAGE
		return r
	if artifact == "":
		r.granted = {"gold": SKELETON_GOLD}
		r.message = SKELETON_FIND % ("%d gold" % SKELETON_GOLD)
		return r
	r.grant_artifact = artifact
	# heroes.exe 0xb2f41: "%s %s" of message 0x4c and the name, no period.
	r.message = SKELETON_FIND % ArtifactCatalog.shared().display_name(artifact)
	return r

## Copy of a grant dict with whole-valued floats coerced to int — mirrors
## MapLoaderJson._normalize_params, so objects built outside the loader (tests,
## tooling) can't leak 300.0 into resource math.
static func _int_normalized(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src.keys():
		var v: Variant = src[k]
		out[k] = int(v) if (v is float and v == floorf(v)) else v
	return out

static func _compose_grant_message(granted: Dictionary) -> String:
	var parts: Array = []
	for k: String in granted.keys():
		parts.append("+%d %s" % [int(granted[k]), k])
	return ", ".join(parts)
