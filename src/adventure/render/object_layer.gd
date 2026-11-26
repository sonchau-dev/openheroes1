class_name DynamicObjectProvider
extends Node2D

## All interactive map-object sprites (towns, mines, resources, dwellings,
## neutral stacks, shrines) + mine idle animations. Sprites are children of
## this node, each painted at the depth of the cell layer heroes.exe paints it
## on (AdventureDepth): a castle's top row and mine flags are layer 2, town
## flags are a layer-1 overlay, and everything else is layer 1. Monster stacks
## are actors and live under the actor parent.
## NOTE: spawn_all() also has game-state side effects (Game.town_tile, fog
## reveal around towns, shrine spell roll persistence).

# --- Forwarded constants from ObjectArtData ---
const MONS32 := ObjectArtData.MONS32
const MONS32_INDEX := ObjectArtData.MONS32_INDEX
const MINIMON := ObjectArtData.MINIMON
const MINIMON_FRAMES := ObjectArtData.MINIMON_FRAMES
const MINIMON_FRAME_S := ObjectArtData.MINIMON_FRAME_S
const MINIMON_ATTACK_FRAMES := ObjectArtData.MINIMON_ATTACK_FRAMES
const ATTACK_FLOURISH_FPS := ObjectArtData.ATTACK_FLOURISH_FPS
const ATTACK_BATTLE_DELAY := ObjectArtData.ATTACK_BATTLE_DELAY
const RESOURCE := ObjectArtData.RESOURCE
const RESOURCE_INDEX := ObjectArtData.RESOURCE_INDEX
const MINE_PIECES := ObjectArtData.MINE_PIECES
const MINE_ANIMATIONS := ObjectArtData.MINE_ANIMATIONS
const STACK_ANCHOR_Y := ObjectArtData.STACK_ANCHOR_Y
const STACK_MIRROR_X := ObjectArtData.STACK_MIRROR_X
const FLAG32 := ObjectArtData.FLAG32
const FLAG_DEFAULT := ObjectArtData.FLAG_DEFAULT
const FLAG_BY_RES := ObjectArtData.FLAG_BY_RES
const SHRINE_SPRITE := ObjectArtData.SHRINE_SPRITE
const DRAGON_CITY_PIECES := ObjectArtData.DRAGON_CITY_PIECES
const TOWN32 := ObjectArtData.TOWN32
const TOWN_BLOCK := ObjectArtData.TOWN_BLOCK
const TOWN_BLOCK_UNWALLED := ObjectArtData.TOWN_BLOCK_UNWALLED
const DISSOLVE_SHADER := ObjectArtData.DISSOLVE_SHADER
const PICKUP_DISSOLVE_DELAY := ObjectArtData.PICKUP_DISSOLVE_DELAY
const PICKUP_DISSOLVE_DURATION := ObjectArtData.PICKUP_DISSOLVE_DURATION
const PICKUP_DISSOLVE_STEPS := ObjectArtData.PICKUP_DISSOLVE_STEPS
const PICKUP_TOTAL_DURATION := ObjectArtData.PICKUP_TOTAL_DURATION

static func town_rows(faction: int, has_castle: bool = true) -> Array:
	return ObjectArtData.town_rows(faction, has_castle)

static func minimon_idle_frame_indices(unit: String, frame_count: int = MINIMON_FRAMES) -> Array:
	return ObjectArtData.minimon_idle_frame_indices(unit, frame_count)

var flags: OwnershipFlags
var stacks: StackMarkers

var _map: MapData
var _fog: FogLayer
var rsrc_spec: Dictionary = {}

var _active_animations: Array = []
var _art_resolver: MapArtResolver
var _actor_parent: Node2D
var _reverse := false

# --- Compatibility properties forwarding to subcomponents ---
var _stack_markers: Dictionary:
	get: return stacks.markers
	set(v): stacks.markers = v

var _mine_cart_sprites: Dictionary:
	get: return flags.mine_cart_sprites
	set(v): flags.mine_cart_sprites = v

var _flag_spec: Dictionary:
	get: return flags.flag_spec
	set(v): flags.flag_spec = v

static var _tex_cache: Dictionary = {}

func _init() -> void:
	flags = OwnershipFlags.new(self)
	stacks = StackMarkers.new(self)

func setup(map: MapData, fog: FogLayer, art_resolver: MapArtResolver = null) -> void:
	_map = map
	_fog = fog
	_art_resolver = art_resolver if art_resolver != null else MapArtResolver.new()
	rsrc_spec = _shared_spec(RESOURCE + "spec.json")
	var flag_spec_data := _shared_spec(FLAG32 + "spec.json")
	flags.setup(flag_spec_data)
	stacks.setup()

func set_fog(fog: FogLayer) -> void:
	_fog = fog

func set_actor_parent(parent: Node2D) -> void:
	_actor_parent = parent

## Paint `node` as part of `layer` on `cell` (AdventureDepth).
func _set_depth(node: CanvasItem, cell: Vector2i, layer: String) -> void:
	node.z_as_relative = false
	node.z_index = AdventureDepth.phase_z(layer, cell, _reverse)
	node.set_meta("depth_cell", cell)
	node.set_meta("depth_layer", layer)

## Flip the order the cells of a row are painted in; only layer 2 moves.
func set_reverse(reverse: bool) -> void:
	_reverse = reverse
	for c: Node in get_children():
		if c is CanvasItem and c.has_meta("depth_layer") \
				and String(c.get_meta("depth_layer")) == AdventureDepth.LAYER_2:
			_set_depth(c, c.get_meta("depth_cell"), AdventureDepth.LAYER_2)

## HOMM1's ship leaves on the exact tile one cell southwest of the gate.
static func sea_near(map: MapData, t: Vector2i) -> bool:
	return map.is_water(t + Vector2i(-1, 1))

static func _shared_spec(path: String) -> Dictionary:
	return SpecLoader.load_spec(path)

static func _texture(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		var tex := UiKit.load_texture(path)
		if tex == null:
			return null
		_tex_cache[path] = tex
	return _tex_cache[path]

func spawn_all() -> void:
	# Some render harnesses attach this node during SceneTree._initialize(),
	# before absolute NodePaths are legal. Side zero remains the standalone
	# fallback; a live scene reads the seated hot-seat side from the autoload.
	var tree := get_tree() if is_inside_tree() else null
	var game := tree.root.get_node_or_null("Game") if tree != null else null
	var local_side: int = game.state.active_player_side \
			if game != null and game.state != null else 0
	for o: MapObject in _map.objects:
		if o is TownObject:
			if game != null:
				game.register_town_gate(o.id, o.action_tile)
			# action_tile IS the gate tile (bottom row, col 2): the hero rides into the
			# gate and stands inside the arch, HOMM1-style. _spawn_town anchors on it.
			_spawn_town(o.action_tile, (o as TownObject).town_type,
					town_has_castle(o as TownObject))
			if o.owner >= 0:
				spawn_town_ownership(o.action_tile, o.owner)
			var owner = game.state.player_of(o.owner) if game != null and game.state != null else null
			var town_model: TownModel = owner.town_by_object_id(o.id) if owner != null else null
			if town_model != null:
				town_model.ship_launch_tile = o.action_tile + Vector2i(-1, 1)
				town_model.sea_access = sea_near(_map, o.action_tile)
				if town_model.town_type != (o as TownObject).town_type:
					town_model.town_type = (o as TownObject).town_type
					town_model.init_start_buildings(game.rng, owner.is_ai)
			if o.owner == local_side:
				if _fog != null:
					_fog.reveal(o.action_tile, 5)
				# Preserve the selected town's gate as the legacy/save position. With
				# multiple towns, assigning every owned gate made the last map object win.
				if game != null and owner != null and owner.town != null \
						and owner.town.object_id == o.id:
					game.town_tile = o.action_tile
		elif o is ArtifactPickup:
			var pickup := o as ArtifactPickup
			if not pickup.consumed and pickup.resolved and pickup.artifact_id != "":
				_spawn_artifact_marker(pickup)
		elif o is NeutralStack:
			if not (o as NeutralStack).consumed:
				_spawn_stack_marker(o as NeutralStack)
		elif o is ResourcePile:
			if not (o as ResourcePile).consumed:
				if not o.has_map_art():
					var rid: int = RESOURCE_INDEX.get((o as ResourcePile).res, 67)
					var offset := Vector2.ZERO
					var sp_file := "%04d.png" % rid
					for s in rsrc_spec.get("sprites", []):
						if s.id == rid:
							offset = Vector2(s.offset)
							sp_file = s.file
							break
					_spawn_body(RESOURCE + sp_file, o.tile, offset)
		elif o is Mine:
			if o.has_map_art():
				pass # v3 native body, cart, and animation are explicit render_parts.
			else:
				_spawn_mine_building((o as Mine).tile, (o as Mine).action_tile, (o as Mine).res)
			if o.owner >= 0:
				spawn_mine_ownership((o as Mine).action_tile, (o as Mine).res, o.owner)
		elif o is DragonCity:
			_spawn_dragon_city((o as DragonCity).action_tile)
			if o.owner >= 0:
				spawn_building_ownership((o as DragonCity).action_tile, o.owner)
		elif o is Lighthouse:
			if not o.has_map_art():
				_spawn_catalog_art(o, ObjectCatalog.shared().art(o.type))
			if o.owner >= 0:
				spawn_lighthouse_ownership(o.action_tile, o.owner)
		elif o is Dwelling:
			# The .map paints a real building here (a thatched hut, a cave mouth…);
			# the mons32 creature icon below is only the hand-authored fallback.
			if o.has_map_art() or o.consumed:
				pass
			else:
				var dwelling_art := ObjectCatalog.shared().art(o.type)
				if dwelling_art.has("dir"):
					_spawn_catalog_art(o, dwelling_art)
				else:
					_spawn_body(MONS32 + "%04d.png" % int(MONS32_INDEX.get((o as Dwelling).unit, 0)), o.tile)
		elif o is Shrine:
			var shrine := o as Shrine
			if shrine.spell_id == "":
				# First time this object is spawned this session (a fresh map, or
				# apply_object_states() found no saved roll yet): roll for real
				# with the game's live RNG, then persist immediately so a later
				# scene reload restores the same spell instead of re-rolling.
				if game != null:
					shrine.roll_spell(game.rng)
					game.record_object_state(shrine)
			if not o.has_map_art():
				_spawn_body(SHRINE_SPRITE, o.tile)
		else:
			# Generic catalog-driven object:
			# any type with no dedicated spawn arm above renders from its catalog
			# "art" entry (dir + sprite id resolved via that dir's spec.json) instead
			# of a hardcoded table here. Types with no "art" entry draw nothing yet.
			# Consumed guard: saved state is applied BEFORE
			# spawn_all(), so without it a spent chest/campfire/artifact would
			# ghost-respawn its sprite on scene reload (typed arms above already guard).
			if not o.consumed:
				if not o.has_map_art():
					var art := ObjectCatalog.shared().art(o.type)
					if art.has("dir"):
						_spawn_catalog_art(o, art)

func _spawn_artifact_marker(pickup: ArtifactPickup) -> void:
	var definition := ArtifactCatalog.shared().get_artifact(pickup.artifact_id)
	var frame := int(definition.get("art32_frame", -1))
	if frame < 0:
		return
	var dir := "res://assets/art/art32/"
	var spec := _shared_spec(dir + "spec.json")
	for sprite: Dictionary in spec.get("sprites", []):
		if int(sprite.id) == frame:
			_spawn_body(dir + String(sprite.file), pickup.tile, Vector2(sprite.offset))
			return

func _spawn_catalog_art(o: MapObject, art: Dictionary) -> void:
	var dir := "res://assets/art/%s/" % String(art.get("dir", ""))
	var spec := _shared_spec(dir + "spec.json")
	if art.has("layers"):
		for layer: Dictionary in art["layers"]:
			var tile_off: Array = layer.get("tile", [0, 0])
			var layer_tile: Vector2i = o.tile + Vector2i(int(tile_off[0]), int(tile_off[1]))
			for entry in layer.get("ids", []):
				var sprite_id: int = int(entry["id"]) if entry is Dictionary else int(entry)
				var offset_override = Vector2(entry["offset"][0], entry["offset"][1]) if entry is Dictionary and entry.has("offset") else null
				for s in spec.get("sprites", []):
					if s.id == sprite_id:
						_spawn_body(dir + s.file, layer_tile, offset_override if offset_override != null else Vector2(s.offset))
						break
			for group: Dictionary in layer.get("anim_groups", []):
				_spawn_catalog_animation(layer_tile, dir, spec, group)
	else:
		var sprite_id: int = int(art.get("sprite", -1))
		for s in spec.get("sprites", []):
			if s.id == sprite_id:
				_spawn_body(dir + s.file, o.tile, Vector2(s.offset))
				break
	if art.has("anim"):
		_spawn_catalog_animation(o.tile, dir, spec, art["anim"])

func _spawn_catalog_animation(tile: Vector2i, dir: String, spec: Dictionary, anim: Dictionary) -> void:
	var frames: Array = anim.get("frames", [])
	var shift_arr: Array = anim.get("shift", [0, 0])
	var shift := Vector2(shift_arr[0], shift_arr[1])
	var textures: Array = []
	var offsets: Array = []
	for sid in frames:
		var offset := Vector2.ZERO
		var sp_file := "%04d.png" % int(sid)
		for s in spec.get("sprites", []):
			if s.id == int(sid):
				offset = Vector2(s.offset) + shift
				sp_file = s.file
				break
		textures.append(_texture(dir + sp_file))
		offsets.append(offset)
	if textures.is_empty():
		return
	var spr := Sprite2D.new()
	spr.centered = false
	_set_depth(spr, tile, AdventureDepth.LAYER_1)
	add_child(spr)
	spr.texture = textures[0]
	spr.position = Vector2(tile.x * _map.tile_size, tile.y * _map.tile_size) + offsets[0]
	_active_animations.append({
		"sprite": spr,
		"tile": tile,
		"frames": frames,
		"textures": textures,
		"offsets": offsets,
		"fps": float(anim.get("fps", 6.0)),
		"elapsed": 0.0,
		"frame_index": 0,
	})

func _spawn_object_sprite(path: String, t: Vector2i, layer: String, offset := Vector2.ZERO,
		sprite_scale := Vector2.ONE) -> Sprite2D:
	var tex := _texture(path)
	if tex == null:
		return null
	var spr := Sprite2D.new()
	spr.centered = false
	_set_depth(spr, t, layer)
	spr.texture = tex
	spr.position = Vector2(t.x * _map.tile_size, t.y * _map.tile_size) + offset
	spr.scale = sprite_scale
	spr.set_meta("tile", t)
	add_child(spr)
	return spr

func _spawn_body(path: String, t: Vector2i, offset := Vector2.ZERO) -> Sprite2D:
	var spr := _spawn_object_sprite(path, t, AdventureDepth.LAYER_1, offset)
	if spr != null:
		spr.set_meta("object_art", true)
	return spr

func _spawn_dragon_city(action_tile: Vector2i) -> void:
	for piece: Array in DRAGON_CITY_PIECES:
		var sid: int = int(piece[0])
		var target_tile: Vector2i = action_tile + (piece[1] as Vector2i)
		var sp_file := "%04d.png" % sid
		var offset := Vector2.ZERO
		for s in rsrc_spec.get("sprites", []):
			if int(s.id) == sid:
				sp_file = String(s.file)
				offset = Vector2(s.offset)
				break
		_spawn_body(RESOURCE + sp_file, target_tile, offset)

# --- Ownership Flags Forwarding ---
func _clear_flag(t: Vector2i) -> void:
	flags.clear_flag(t)

func spawn_mine_ownership(action_tile: Vector2i, res: String, side: int = 0) -> void:
	flags.spawn_mine_ownership(action_tile, res, side)

func _spawn_mine_cart(action_tile: Vector2i, res: String) -> Sprite2D:
	return flags.spawn_mine_cart(action_tile, res)

func _clear_mine_ownership_elements(action_tile: Vector2i) -> void:
	flags.clear_mine_ownership_elements(action_tile)

func spawn_building_ownership(action_tile: Vector2i, side: int = 0) -> void:
	flags.spawn_building_ownership(action_tile, side)

func clear_lighthouse_ownership(action_tile: Vector2i) -> void:
	flags.clear_lighthouse_ownership(action_tile)

func spawn_lighthouse_ownership(action_tile: Vector2i, side: int = 0) -> void:
	flags.spawn_lighthouse_ownership(action_tile, side)

func clear_town_ownership(action_tile: Vector2i) -> void:
	flags.clear_town_ownership(action_tile)

func spawn_town_ownership(action_tile: Vector2i, side: int = 0) -> void:
	flags.spawn_town_ownership(action_tile, side)

func _get_mercury_bottom_pieces(action_tile: Vector2i) -> Array:
	var tile_index: int = _map.get_tile(action_tile.x, action_tile.y)
	if tile_index >= 116 and tile_index <= 139:
		return [27, 28] # Desert
	elif tile_index >= 76 and tile_index <= 91:
		return [35, 36] # Lava
	else:
		return [43, 44] # Rest

func _spawn_mine_building(art_tile: Vector2i, action_tile: Vector2i, res: String) -> void:
	var pieces: Array = MINE_PIECES.get(res, MINE_PIECES["ore"])
	var tl_id: int = pieces[0]
	var tr_id: int = pieces[1]
	var bl_id: int = pieces[2]
	var br_id: int = pieces[3]

	if res == "mercury":
		var bottom_pieces := _get_mercury_bottom_pieces(action_tile)
		bl_id = bottom_pieces[0]
		br_id = bottom_pieces[1]

	var spec_sprites: Array = rsrc_spec.get("sprites", [])

	var tile_defs := [
		[tl_id, art_tile],                        # top-left (art tile)
		[tr_id, art_tile + Vector2i(1, 0)],       # top-right
		[bl_id, action_tile],                     # bottom-left (action tile)
		[br_id, action_tile + Vector2i(1, 0)],    # bottom-right
	]
	for tile_def in tile_defs:
		var sid: int = tile_def[0]
		var world_tile: Vector2i = tile_def[1]
		var offset := Vector2.ZERO
		var sp_file := "%04d.png" % sid
		for s in spec_sprites:
			if s.id == sid:
				offset = Vector2(s.offset)
				sp_file = s.file
				break
		_spawn_body(RESOURCE + sp_file, world_tile, offset)

	var cart := flags.spawn_mine_cart(action_tile, res)
	if cart != null:
		move_child(cart, -1)

	if MINE_ANIMATIONS.has(res):
		_spawn_mine_building_animation(art_tile, action_tile, res)

func _spawn_mine_building_animation(art_tile: Vector2i, action_tile: Vector2i, res: String) -> void:
	var anim: Dictionary = MINE_ANIMATIONS[res]
	var base_tile: Vector2i = action_tile if anim.rel_tile == "action_tile" else art_tile
	var target_tile: Vector2i = base_tile + anim.offset_tile

	var anim_textures: Array = []
	var anim_offsets: Array = []
	var spec_sprites: Array = rsrc_spec.get("sprites", [])

	var frames: Array = anim.frames
	if res == "mercury":
		var tile_index: int = _map.get_tile(action_tile.x, action_tile.y)
		if tile_index >= 116 and tile_index <= 139:
			frames = [29, 30, 31, 32, 33, 34] # Desert
		elif tile_index >= 76 and tile_index <= 91:
			frames = [37, 38, 39, 40, 41, 42] # Lava
		else:
			frames = [45, 46, 47, 48, 49, 50] # Rest

	for sid in frames:
		var offset := Vector2.ZERO
		var sp_file := "%04d.png" % sid
		for s in spec_sprites:
			if s.id == sid:
				offset = Vector2(s.offset)
				sp_file = s.file
				break
		var tex := _texture(RESOURCE + sp_file)
		anim_textures.append(tex)
		anim_offsets.append(offset)

	var spr := Sprite2D.new()
	spr.centered = false
	_set_depth(spr, target_tile, AdventureDepth.LAYER_1)
	add_child(spr)

	if not anim_textures.is_empty():
		spr.texture = anim_textures[0]
		spr.position = Vector2(target_tile.x * _map.tile_size, target_tile.y * _map.tile_size) + anim_offsets[0]

	_active_animations.append({
		"sprite": spr,
		"tile": target_tile,
		"frames": frames,
		"textures": anim_textures,
		"offsets": anim_offsets,
		"fps": anim.fps,
		"elapsed": 0.0,
		"frame_index": 0,
	})

func town_has_castle(town: TownObject) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var game := tree.root.get_node_or_null("Game") if tree != null else null
	if game != null:
		return game.town_has_castle(town)
	return bool(town.params.get("has_castle", true))

func _spawn_town(t: Vector2i, faction: int, has_castle: bool = true) -> void:
	# Idempotent: a town can be redrawn (a capture changes its owner flags and
	# may change town <-> castle), and spawn_all() draws every town again when
	# the map is rebuilt. Drop the previous art for this gate first.
	_clear_town_art(t)
	var rows: Array = town_rows(faction, has_castle)
	var spec := _shared_spec(TOWN32 + "spec.json")
	for r in rows.size():
		var ids: Array = rows[r]
		var map_row := t.y - (rows.size() - 1 - r)   # last row = gate row (t.y)
		for i in ids.size():
			var sid: int = ids[i]
			if sid < 0 or sid >= spec.sprites.size():
				continue
			var sp = spec.sprites[sid]
			var col := t.x - 2 + i
			var origin := Vector2(col * _map.tile_size, map_row * _map.tile_size)
			var spr := Sprite2D.new()
			spr.centered = false
			_set_depth(spr, Vector2i(col, map_row),
					AdventureDepth.LAYER_2 if r == 0 else AdventureDepth.LAYER_1)
			var at := MapArtResolver.get_atlas_texture("town32/" + sp.file)
			spr.texture = at if at != null else _texture(TOWN32 + sp.file)
			spr.position = origin + Vector2(sp.offset)
			spr.set_meta("town_art", t)
			spr.set_meta("town_castle", has_castle)
			add_child(spr)

## Drop the town art sprites drawn for the gate tile `t`.
func _clear_town_art(t: Vector2i) -> void:
	for c in get_children():
		if c.has_meta("town_art") and c.get_meta("town_art") == t:
			remove_child(c)
			c.queue_free()

func _refresh_town_art(town: TownObject) -> void:
	var has_castle := town_has_castle(town)
	var drawn: Array[Node] = []
	for c in get_children():
		if c.has_meta("town_art") and c.get_meta("town_art") == town.action_tile \
				and not c.is_queued_for_deletion():
			drawn.append(c)
	if not drawn.is_empty() and bool(drawn[0].get_meta("town_castle")) == has_castle:
		return
	for c in drawn:
		c.queue_free()
	_spawn_town(town.action_tile, town.town_type, has_castle)

# --- Stack Markers Forwarding ---
func _spawn_stack_marker(stack: NeutralStack) -> void:
	stacks.spawn_stack_marker(stack)

func is_stack_idling(stack: NeutralStack) -> bool:
	return stacks.is_stack_idling(stack)

func resume_stack_idle(stack: NeutralStack) -> void:
	stacks.resume_stack_idle(stack)

func play_attack_flourish(stack: NeutralStack, hero_tile: Vector2i) -> void:
	await stacks.play_attack_flourish(stack, hero_tile)

func _process(delta: float) -> void:
	# Update active mine animations
	for anim in _active_animations:
		anim.elapsed += delta
		if not anim.frames.is_empty():
			var frame_index: int = int(anim.elapsed * anim.fps) % anim.frames.size()
			if frame_index != anim.get("frame_index", -1):
				anim["frame_index"] = frame_index
				var tex: Texture2D = anim.textures[frame_index]
				var offset: Vector2 = anim.offsets[frame_index]
				anim.sprite.texture = tex
				anim.sprite.position = Vector2(anim.tile.x * _map.tile_size, anim.tile.y * _map.tile_size) + offset

	# Update neutral stack idle animations off centralized clock
	stacks.process(delta)

func remove_object_sprites(obj: MapObject) -> void:
	for c in get_children():
		if not (c is Sprite2D) or not c.has_meta("object_art"):
			continue
		if c.has_meta("dissolving"):
			continue
		if c.has_meta("obj_id") and int(c.get_meta("obj_id")) == obj.id:
			c.queue_free()
		elif not c.has_meta("obj_id") and c.has_meta("tile") and c.get_meta("tile") == obj.tile:
			c.queue_free()
	for i in range(_active_animations.size() - 1, -1, -1):
		if _active_animations[i].get("tile", null) == obj.tile:
			var spr: Node = _active_animations[i].get("sprite", null)
			if spr != null:
				spr.queue_free()
			_active_animations.remove_at(i)

func dissolve_object(obj: MapObject, delay: float = PICKUP_DISSOLVE_DELAY, duration: float = PICKUP_DISSOLVE_DURATION, tree: SceneTree = null) -> Tween:
	var targets: Array[Sprite2D] = []

	for c in get_children():
		if not (c is Sprite2D) or not c.has_meta("object_art"):
			continue
		if (c.has_meta("obj_id") and int(c.get_meta("obj_id")) == obj.id) \
				or (not c.has_meta("obj_id") and c.has_meta("tile") and c.get_meta("tile") == obj.tile):
			targets.append(c as Sprite2D)

	if targets.is_empty() and _map != null:
		for part: Dictionary in _map.render_parts:
			if int(part.get("object_id", -1)) == obj.id:
				var art := String(part.get("art", ""))
				if art == "":
					var frames: Array = part.get("frames", [])
					if not frames.is_empty():
						art = String(frames[0])
				if art == "":
					continue
				if _art_resolver == null:
					_art_resolver = MapArtResolver.new()
				var tex := _art_resolver.texture(art)
				if tex == null:
					continue
				var tile: Array = part.get("tile", [0, 0])
				var origin := Vector2(int(tile[0]) * _map.tile_size, int(tile[1]) * _map.tile_size)
				var offset := _art_resolver.offset(art)
				var spr := Sprite2D.new()
				spr.texture = tex
				spr.centered = false
				spr.position = origin + offset
				_set_depth(spr, Vector2i(int(tile[0]), int(tile[1])),
						String(part.get("phase", AdventureDepth.LAYER_1)))
				spr.set_meta("obj_id", obj.id)
				add_child(spr)
				targets.append(spr)

	for i in range(_active_animations.size() - 1, -1, -1):
		if _active_animations[i].get("tile", null) == obj.tile:
			var spr: Node = _active_animations[i].get("sprite", null)
			if spr != null:
				spr.queue_free()
			_active_animations.remove_at(i)

	if targets.is_empty():
		return null

	for spr in targets:
		spr.set_meta("dissolving", true)
		var mat := ShaderMaterial.new()
		mat.shader = DISSOLVE_SHADER
		mat.set_shader_parameter("pattern_offset", spr.position)
		mat.set_shader_parameter("reveal_progress", 1.0)
		mat.set_shader_parameter("block_size", 1.0)
		mat.set_shader_parameter("noise_steps", PICKUP_DISSOLVE_STEPS)
		spr.material = mat

	var target_tree := tree if tree != null else get_tree()
	var tween: Tween = create_tween() if is_inside_tree() else (target_tree.create_tween() if target_tree != null else null)
	if tween == null:
		return null

	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_method(func(val: float):
		for spr in targets:
			if is_instance_valid(spr) and spr.material is ShaderMaterial:
				(spr.material as ShaderMaterial).set_shader_parameter("reveal_progress", val)
	, 1.0, 0.0, duration)
	tween.tween_callback(func():
		for spr in targets:
			if is_instance_valid(spr):
				spr.queue_free()
	)
	return tween

func refresh_object(object_id: int) -> void:
	var obj := _map.object_by_id(object_id) if _map != null else null
	if obj == null:
		return
	if obj.consumed:
		remove_object_sprites(obj)
		stacks.clear_marker(object_id)
		return
	if obj is NeutralStack:
		stacks.clear_marker(object_id)
		stacks.spawn_stack_marker(obj as NeutralStack)
		return
	if obj is Mine:
		if obj.owner >= 0:
			spawn_mine_ownership(obj.action_tile, (obj as Mine).res, obj.owner)
		else:
			_clear_mine_ownership_elements(obj.action_tile)
	elif obj is DragonCity:
		if obj.owner >= 0:
			spawn_building_ownership(obj.action_tile, obj.owner)
		else:
			_clear_mine_ownership_elements(obj.action_tile)
	elif obj is TownObject:
		_refresh_town_art(obj as TownObject)
		if obj.owner >= 0:
			spawn_town_ownership(obj.action_tile, obj.owner)
		else:
			clear_town_ownership(obj.action_tile)
	elif obj is Lighthouse:
		if obj.owner >= 0:
			spawn_lighthouse_ownership(obj.action_tile, obj.owner)
		else:
			clear_lighthouse_ownership(obj.action_tile)
