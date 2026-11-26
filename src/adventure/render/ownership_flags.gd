class_name OwnershipFlags
extends RefCounted

## Manages adventure map player-color ownership flags and mine carts for towns,
## mines, dragon cities, and lighthouses.
## Moved out of object_layer.gd.

var layer: DynamicObjectProvider
var flag_spec: Dictionary = {}
var mine_cart_sprites: Dictionary = {} # action tile -> resource cart overlay

func _init(p_layer: DynamicObjectProvider = null) -> void:
	layer = p_layer

func setup(p_flag_spec: Dictionary = {}) -> void:
	flag_spec = p_flag_spec
	mine_cart_sprites.clear()

## flag32 color index (0 blue, 1 green, 2 red, 3 yellow) of the kingdom on
## `side`. A side is not a color: the campaign seats its ruler on side 0 in
## the ruler's own color, so the flag must follow the player's crest.
func flag_color(side: int) -> int:
	if side < 0:
		return side
	var tree := Engine.get_main_loop() as SceneTree
	var game := tree.root.get_node_or_null("Game") if tree != null else null
	if game != null and game.state != null:
		var player: PlayerState = game.state.player_of(side)
		if player != null and player.crest_idx >= 0:
			return clampi(player.crest_idx / 4, 0, 3)
	return side

func spawn_mine_ownership(action_tile: Vector2i, res: String, side: int = 0) -> void:
	side = flag_color(side)
	clear_mine_ownership_elements(action_tile)

	# The resource cart is always present, including while the mine is neutral.
	# Ownership adds only the flag; ensuring the cart here also covers callers that
	# capture a mine before spawn_all() runs during post-battle restoration.
	spawn_mine_cart(action_tile, res)
	spawn_flag(action_tile, side, res)

func spawn_mine_cart(action_tile: Vector2i, res: String) -> Sprite2D:
	var pieces: Array = ObjectArtData.MINE_PIECES.get(res, ObjectArtData.MINE_PIECES["ore"])
	if pieces.size() < 5:
		return null
	var existing: Variant = mine_cart_sprites.get(action_tile, null)
	if existing is Sprite2D and is_instance_valid(existing):
		return existing as Sprite2D
	var cart_id: int = pieces[4]
	var offset := Vector2.ZERO
	var sp_file := "%04d.png" % cart_id
	var rsrc_spec: Dictionary = layer.rsrc_spec if layer != null else {}
	for s in rsrc_spec.get("sprites", []):
		if s.id == cart_id:
			offset = Vector2(s.offset)
			sp_file = s.file
			break
	# HOMM1's cart sits on the bottom-right mine cell, one tile east of the
	# entrance/action tile. Placing it on action_tile covers the doorway.
	var cart_tile := action_tile + Vector2i(1, 0)
	var cart: Sprite2D = layer._spawn_object_sprite(ObjectArtData.RESOURCE + sp_file, cart_tile, AdventureDepth.LAYER_1, offset) if layer != null else null
	if cart != null:
		cart.set_meta("mine_cart", action_tile)
		mine_cart_sprites[action_tile] = cart
	return cart

func clear_mine_ownership_elements(action_tile: Vector2i) -> void:
	clear_flag(action_tile)

## Generic building-ownership tell for objects with no per-resource cart art
## (Dragon City): the side-tinted flag on the roof cell, frame and tile from
## FLAG_BY_RES["dragon_city"].
func spawn_building_ownership(action_tile: Vector2i, side: int = 0) -> void:
	side = flag_color(side)
	clear_flag(action_tile)
	spawn_flag(action_tile, side, "dragon_city")

func clear_lighthouse_ownership(action_tile: Vector2i) -> void:
	clear_flag(action_tile)

## heroes.exe 0x7dc28: the owner's flag (flag32 24+color) flies two cells west
## of the Lighthouse door.
func spawn_lighthouse_ownership(action_tile: Vector2i, side: int = 0) -> void:
	clear_flag(action_tile)
	spawn_flag(action_tile, flag_color(side), "lighthouse")

## Remove town flag sprites for the given action tile.
func clear_town_ownership(action_tile: Vector2i) -> void:
	if layer == null:
		return
	for child in layer.get_children():
		if child is Sprite2D and child.has_meta("town_flag") \
				and child.get_meta("town_flag") == action_tile:
			layer.remove_child(child)
			child.queue_free()

## Spawn town/castle owner flags flanking the entrance (left and right of gate tile).
## In authentic HOMM1, flags use flag32: left = side*2, right = side*2 + 1.
func spawn_town_ownership(action_tile: Vector2i, side: int = 0) -> void:
	side = flag_color(side)
	clear_town_ownership(action_tile)
	if side < 0 or side > 3:
		return
	if flag_spec.is_empty() and layer != null:
		flag_spec = layer._shared_spec(ObjectArtData.FLAG32 + "spec.json")

	# Left flag: frame side * 2 on action_tile + Vector2i(-1, 0)
	var left_frame := side * 2
	var left_file := "%04d.png" % left_frame
	var left_offset := Vector2(0, 11)
	for s in flag_spec.get("sprites", []):
		if int(s.id) == left_frame:
			left_offset = Vector2(s.offset)
			left_file = String(s.file)
			break
	var left_tile := action_tile + Vector2i(-1, 0)
	# heroes.exe 0x7da4e hangs town flags as the layer-1 overlay of the cells
	# either side of the gate, so a hero on those cells covers them.
	var left_spr: Sprite2D = layer._spawn_object_sprite(ObjectArtData.FLAG32 + left_file, left_tile, AdventureDepth.LAYER_1, left_offset) if layer != null else null
	if left_spr != null:
		left_spr.set_meta("town_flag", action_tile)

	# Right flag: frame side * 2 + 1 on action_tile + Vector2i(1, 0)
	var right_frame := side * 2 + 1
	var right_file := "%04d.png" % right_frame
	var right_offset := Vector2(14, 11)
	for s in flag_spec.get("sprites", []):
		if int(s.id) == right_frame:
			right_offset = Vector2(s.offset)
			right_file = String(s.file)
			break
	var right_tile := action_tile + Vector2i(1, 0)
	var right_spr: Sprite2D = layer._spawn_object_sprite(ObjectArtData.FLAG32 + right_file, right_tile, AdventureDepth.LAYER_1, right_offset) if layer != null else null
	if right_spr != null:
		right_spr.set_meta("town_flag", action_tile)

func spawn_flag(t: Vector2i, side: int = 0, res: String = "") -> Sprite2D:
	if flag_spec.is_empty() and layer != null:
		flag_spec = layer._shared_spec(ObjectArtData.FLAG32 + "spec.json")
	var style: Dictionary = ObjectArtData.FLAG_BY_RES.get(res, ObjectArtData.FLAG_DEFAULT)
	var frame_id := int(style["frame"]) + clampi(side, 0, 3)
	var sp_file := "%04d.png" % frame_id
	var offset := Vector2(13, 6)
	for s in flag_spec.get("sprites", []):
		if int(s.id) == frame_id:
			offset = Vector2(s.offset)
			sp_file = String(s.file)
			break
	var target_tile := t + (style["tile"] as Vector2i)
	# heroes.exe 0x7dcc1 hangs a mine's flag as the layer-2 overlay of its cell.
	var spr: Sprite2D = layer._spawn_object_sprite(ObjectArtData.FLAG32 + sp_file, target_tile, AdventureDepth.LAYER_2, offset) if layer != null else null
	if spr != null:
		spr.set_meta("ownership_flag", true)
		spr.set_meta("flag_owner_tile", t)
	return spr

## Free every owner flag hung on the building whose action tile is `t`.
func clear_flag(t: Vector2i) -> void:
	if layer == null:
		return
	for c in layer.get_children():
		if c is Sprite2D and c.has_meta("flag_owner_tile") and c.get_meta("flag_owner_tile") == t:
			layer.remove_child(c)
			c.queue_free()
