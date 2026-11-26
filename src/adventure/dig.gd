class_name Dig
extends RefCounted

## The DIG action that closes the obelisk -> puzzle-map -> dig -> Ultimate
## Artifact chain (PlayerState.puzzle_pieces/puzzle_solved hold the progress;
## MapData.ultimate_artifact holds the buried-tile metadata).
##
## Dig-mechanic quote (data/knowledge_base/artifacts.md:11): "The treasure
## can be dug up only when the hero spends the night at the dig site and spends all
## his movement points the next day digging. Thus, after digging up the treasure,
## the hero automatically loses all movement points until the start of the next day."
##
## "Spent the night" proxy: this project has no separate "camped overnight" flag on
## HeroModel, so we approximate it with hero_model.move_points == hero_model.
## max_move_points — full movement means the hero has not taken a single step yet
## today, i.e. every day starts with the hero wherever it ended the PREVIOUS day
## (turn_controller.gd:59-60 resets move_points = max_move_points at day rollover,
## in place, without moving the hero) — so "full movement, standing on the dig
## tile" is exactly "spent last night at the dig site, first action this morning
## is to dig". Any movement already spent this day invalidates the proxy.

## Total obelisks on the map (puzzle_solved()'s denominator).
static func count_obelisks(map: MapData) -> int:
	if map == null:
		return 0
	var total := 0
	for o: MapObject in map.objects:
		if o.type == "obelisk":
			total += 1
	return total

## Executes dig for a hero (node + model + player state + map).
## Handles movement sync, try_dig call, movement zeroing on commit/wait,
## dialog/defeat notifications, and returns the result dictionary.
static func perform_dig(hero_node: Hero, active_model: HeroModel, player: PlayerState,
		map: MapData, root_node: Node2D = null, audio: Node = null) -> Dictionary:
	if active_model != null and hero_node != null:
		active_model.move_points = hero_node.move_points
		active_model.max_move_points = hero_node.max_move_points

	if player != null and player.is_ai:
		if active_model == null or active_model.move_points < active_model.max_move_points:
			# 0x6bb2e: arriving with less than a full day, the hero
			# waits on the tile and digs tomorrow.
			if hero_node != null:
				hero_node.move_points = 0
			if active_model != null:
				active_model.move_points = 0
			return {"ok": false, "waiting": true}

	var g := _game()
	var campaign_cb: Callable = g.notify_campaign_event if (g != null and g.has_method("notify_campaign_event")) else Callable()
	var res: Dictionary = try_dig(active_model, player, map, -1, campaign_cb)
	if bool(res.get("ok", false)):
		if hero_node != null:
			hero_node.move_points = 0
		if audio != null and audio.has_method("play_dig"):
			audio.play_dig(String(res.get("artifact", "")) != "")

	var found := String(res.get("artifact", ""))
	if found != "":
		if g != null and g.state != null:
			g.state.ultimate_artifact = {}

	if root_node != null:
		if player != null and player.is_ai:
			if bool(res.get("ok", false)) and found != "":
				MapDialogs.info(root_node, {"text": String(res.get("message", ""))})
		else:
			if found != "":
				MapDialogs.info(root_node, {"lines": [String(res.get("message", ""))],
						"on_close": (func(): MapDialogs.artifact_info(root_node, found))
								if bool(res.get("show_info", false)) else Callable()})
			else:
				MapDialogs.info(root_node, {"lines": [String(res.get("message", ""))]})

	if player != null and player.is_ai and bool(res.get("ok", false)) and found != "":
		if g != null and g.game_mode == &"campaign" and g.campaign != null \
				and g.campaign.mission().objective == &"dig_eye":
			g.pending_defeat = true
			g.pending_defeat_message = "A great tragedy - the enemy has found the Eye of Goros!!!  The people abandon you, all is lost."

	return res

## Pure seam (headless-testable, no UI/signals). Returns:
##   {"ok": bool, "message": String, "artifact": String}
## - ok == false: dig REFUSED (not full movement) — hero_model is untouched,
##   nothing committed, the hero keeps its movement to do something else instead.
## - ok == true: the hero committed to digging (full day spent, see below),
##   whether or not anything was buried under its feet.
static func try_dig(hero_model: HeroModel, player: PlayerState, map: MapData,
		total_obelisks: int = -1, campaign_event: Callable = Callable()) -> Dictionary:
	if total_obelisks < 0:
		total_obelisks = count_obelisks(map)
	if hero_model == null or player == null or map == null:
		return {"ok": false, "message": "There is nothing to dig here.", "artifact": ""}

	if hero_model.move_points < hero_model.max_move_points:
		# Refused: the hero already moved today, so it can't have spent the whole
		# NEXT day digging (the note's rule). Movement is NOT touched — the hero
		# hasn't committed to anything, it's free to keep moving/acting instead.
		return {"ok": false, "message": "Digging for artifacts requires a whole day, try again tomorrow.", "artifact": ""}

	# heroes.exe 0x98a7c: a sprite on the cell, a hole included, is checked
	# before water (0x98ab7).
	if has_sprite(map, hero_model.tile) or _dug(hero_model.tile):
		return {"ok": false, "message": "Try searching on clear ground.", "artifact": ""}

	if hero_model.travel_mode == &"sea" or map.is_water(hero_model.tile):
		return {"ok": false, "message": "Try looking on land!!!", "artifact": ""}

	if not is_clear_ground(map, hero_model.tile):
		return {"ok": false, "message": "Try searching on clear ground.", "artifact": ""}

	var dig_tile := _buried_tile(map)
	if dig_tile != Vector2i(-1, -1) and hero_model.tile == dig_tile:
		var buried_id := String(map.ultimate_artifact.get("artifact", ""))
		if buried_id != "" and not hero_model.can_add_artifact(buried_id):
			return {"ok": false, "message": "You have no room to carry another artifact!", "artifact": ""}

	# Committed: digging consumes the entire day regardless of what (if anything)
	# turns up, per the note ("loses all movement points until the start of the
	# next day").
	hero_model.move_points = 0

	if dig_tile != Vector2i(-1, -1) and hero_model.tile == dig_tile:
		var artifact := String(map.ultimate_artifact.get("artifact", ""))
		hero_model.add_artifact(artifact)
		# Consume the buried site so a second dig here (or after a reload) finds
		# nothing — clearing to {} is the simplest "dug" flag: MapData.ultimate_artifact
		# defaults to {} anyway, and PuzzleMap.cross_tile()/a future dig both already
		# treat {} as "no buried tile", so no other reader needs to change.
		map.ultimate_artifact = {}
		_after_dig(hero_model.tile, map)
		if campaign_event.is_valid():
			if player.is_ai:
				campaign_event.call(&"ai_dug_eye")
			else:
				campaign_event.call(&"dig_eye")
		var uncover_msg := ""
		var show_info := false
		var g := _game()
		var is_campaign_eye: bool = g != null and g.game_mode == &"campaign" and g.campaign != null \
				and g.campaign.mission().objective == &"dig_eye"
		if player.is_ai:
			if is_campaign_eye:
				uncover_msg = "A great tragedy - the enemy has found the Eye of Goros!!!  The people abandon you, all is lost."
			else:
				uncover_msg = "The enemy has captured the ultimate artifact!!"
		else:
			if is_campaign_eye:
				uncover_msg = "After spending many hours digging here, you have uncovered the Eye of Goros!!!!"
			else:
				# heroes.exe 0x98c2f: the full name, no full stop, in a box
				# without an icon, then the artifact's info box (0x98cc0).
				uncover_msg = "Congratulations! After spending many hours digging here, you have uncovered the %s" \
						% ArtifactCatalog.shared().display_name(artifact)
				show_info = true
		return {
			"ok": true,
			"message": uncover_msg,
			"artifact": artifact,
			"show_info": show_info,
		}

	_after_dig(hero_model.tile, map)
	return {"ok": true, "message": "Nothing here.\nWhere could it be?", "artifact": ""}

## Whether `tile` was dug before this run.
static func _dug(tile: Vector2i) -> bool:
	var g := _game()
	return g != null and g.state != null and g.state.dug_tiles.has(tile)

## heroes.exe 0x98b0e..0x98d9e: the hole is marked, then every computer
## player guesses again where the Ultimate Artifact lies.
static func _after_dig(tile: Vector2i, map: MapData) -> void:
	var g := _game()
	if g == null or g.state == null:
		return
	if not g.state.dug_tiles.has(tile):
		g.state.dug_tiles.append(tile)
	for p: PlayerState in g.state.players:
		AIPlanner.refresh_dig_guess(p, map, g.rng, g.state.dug_tiles)

static func _game() -> Node:
	var ml := Engine.get_main_loop() as SceneTree
	return ml.root.get_node_or_null("Game") if ml != null and ml.root != null else null

## MapData.ultimate_artifact.tile round-trips as an Array[int, int] (see
## map_loader_json.gd), not a Vector2i — normalize here so callers/tests can hand
## either shape in and try_dig always compares against a real Vector2i.
static func _buried_tile(map: MapData) -> Vector2i:
	if map.ultimate_artifact.is_empty():
		return Vector2i(-1, -1)
	var tile_v: Variant = map.ultimate_artifact.get("tile", null)
	if tile_v is Vector2i:
		return tile_v
	if tile_v is Array and (tile_v as Array).size() == 2:
		return Vector2i(int(tile_v[0]), int(tile_v[1]))
	return Vector2i(-1, -1)

## Whether the cell holds a layer-1 or layer-2 sprite (cell bytes B2, B4 not
## 0xff; heroes.exe 0x98a7c). A taken object's sprite is gone from the map.
static func has_sprite(map: MapData, tile: Vector2i) -> bool:
	for part: Dictionary in map.parts_at(tile):
		var object_id := int(part.get("object_id", -1))
		if object_id < 0:
			return true
		var owner := map.object_by_id(object_id)
		if owner != null and not owner.consumed:
			return true
	return false

static func is_clear_ground(map: MapData, tile: Vector2i) -> bool:
	if map == null:
		return false
	if not map.passable.is_empty() and not map.is_passable(tile.x, tile.y):
		return false
	if map.is_water(tile) or has_sprite(map, tile):
		return false
	if map.active_object_at_action(tile) != null:
		return false
	for o: MapObject in map.objects:
		if (o.type == "town" or o is TownObject) and tile.x >= o.tile.x - 2 and tile.x <= o.tile.x + 1 \
				and tile.y >= o.tile.y - 2 and tile.y <= o.tile.y:
			return false
		if not o.consumed and (o.tile == tile or o.action_tile == tile or o.interaction_tiles().has(tile)):
			return false
	return true

