class_name ArtifactAllocator
extends RefCounted

## Resolves a scenario's ordinary-artifact supply once. Authored ground IDs are
## reserved first; all random ground objects and producing sites then draw from
## the remaining pool without replacement.

static func resolve(map: MapData, rng: RandomNumberGenerator,
		already_owned: Array = []) -> Array[MapObject]:
	var changed: Array[MapObject] = []
	if map == null or rng == null:
		return changed
	var pool: Array[String] = ArtifactCatalog.shared().ordinary_pool()
	for owned: Variant in already_owned:
		pool.erase(ArtifactCatalog.shared().normalize(String(owned)))

	# Authored IDs win over all random consumers, independent of map order.
	for object: MapObject in map.objects:
		if object is ArtifactPickup:
			var pickup := object as ArtifactPickup
			if pickup.authored_artifact and pickup.artifact_id != "":
				pool.erase(ArtifactCatalog.shared().normalize(pickup.artifact_id))

	_shuffle(pool, rng)
	for object: MapObject in map.objects:
		if object is ArtifactPickup:
			var pickup := object as ArtifactPickup
			if not pickup.authored_artifact:
				pickup.artifact_id = pool.pop_back() if not pool.is_empty() else ""
			if not pickup.authored_mode:
				pickup.encounter_mode = ArtifactPickup.mode_for_roll(rng.randf())
			pickup.resolved = true
			# A random ground placeholder with no remaining ordinary artifact is
			# absent from play rather than becoming an inert blocking tile.
			if pickup.artifact_id == "":
				pickup.consumed = true
			changed.append(pickup)
		elif object.type == "skeleton":
			# heroes.exe 0x7ac69: 10 rolls in 100 of random(0, 99) / 10 == 3.
			object.has_find = rng.randi_range(0, 99) / 10 == 3
			object.resolved_artifact_id = pool.pop_back() if object.has_find and not pool.is_empty() else ""
			object.artifact_assignment_resolved = true
			changed.append(object)
		elif _produces_artifact(object):
			object.resolved_artifact_id = pool.pop_back() if not pool.is_empty() else ""
			object.artifact_assignment_resolved = true
			changed.append(object)
	# heroes.exe's map-start pass also rolls each Daemon Cave's (0x7ace0) and
	# Graveyard's or Shipwreck's (0x7adee) outcome into cell byte 9, so the
	# computer values the outcome waiting there. After the loop above, so the
	# artifact draws keep their order.
	for object: MapObject in map.objects:
		if object is WeeklyPickup and (object as WeeklyPickup).week_resource == "":
			# The same pass rolls each windmill's resource (0x7b295).
			(object as WeeklyPickup).roll_week_resource(rng)
			if (object as WeeklyPickup).week_resource != "" and not changed.has(object):
				changed.append(object)
		if object is GuardedPickup:
			var gp := object as GuardedPickup
			if gp.rolled_band < 0 and not gp.looted:
				gp.rolled_band = GuardedPickup.roll_band(gp.outcomes, rng)
				if not changed.has(gp):
					changed.append(gp)
	return changed

static func _produces_artifact(object: MapObject) -> bool:
	if object is GuardedPickup:
		for band: Variant in (object as GuardedPickup).outcomes:
			if band is Dictionary and ((band as Dictionary).get("reward", {}) as Dictionary).has("artifact"):
				return true
	return false

static func _shuffle(pool: Array[String], rng: RandomNumberGenerator) -> void:
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
