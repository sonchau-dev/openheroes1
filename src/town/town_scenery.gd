class_name TownScenery
extends RefCounted

## Scenery rendering, building placement, animations, and hit tests for the town screen.

const ART := "res://assets/art/"
const MAGEGLD := ART + "magegld/"
const GUILD_SPRITE_IDS := {
	1: [0, 1],
	2: [0, 2, 3],
	3: [0, 2, 4, 5],
	4: [0, 2, 4, 6, 7],
}
const ANIMATED_BUILDINGS := [
	"farmcast", "farm_d1", "farm_d2", "farm_d3", "farm_d4", "farm_d5",
	"plnscast", "plnstent", "plns_d1", "plns_d2", "plns_d3", "plns_d5", "plns_e0",
	"frstcast", "frst_d0", "frst_d1", "frst_d2", "frst_d4", "frst_d5",
	"mtn_d1", "mtn_d2", "mtn_d3", "mtn_d4", "mtn_d5",
	"tavern", "dock",
]
const BUILDING_ANIM_FPS := 6.32
const CONSTRUCTION_REVEAL_DELAY := 0.26
const CONSTRUCTION_REVEAL_DISSOLVE := 0.24
const CONSTRUCTION_REVEAL_DURATION := CONSTRUCTION_REVEAL_DELAY + CONSTRUCTION_REVEAL_DISSOLVE
const CONSTRUCTION_REVEAL_SHADER := preload("res://src/town/building_reveal.gdshader")
const WATER_CYCLE_SHADER := preload("res://src/town/town_water_cycle.gdshader")

var dwellings: Array = []       # [{ rect: Rect2, unit: String, tex: Texture2D, depth: int, id: String }]
var guild_hits: Array = []      # [{ rect: Rect2, tex: Texture2D, pos: Vector2 }]
var castle_hit: Dictionary = {} # { rect: Rect2, pos: Vector2, tex: Texture2D, dir: String }
var common_hits: Array = []     # [{ rect: Rect2, pos: Vector2, tex: Texture2D, id: String, depth: int }]

var building_anims: Array = []  # [{ sprites, index, elapsed, building_id, paused }]
var construction_parts: Array = []
var construction_elapsed := 0.0
var construction_active := false

var water_material: ShaderMaterial = null
var water_cycle_elapsed := 0.0
var water_cycle_step := 0

static var _mask_cache: Dictionary = {}

static func clear_mask_cache() -> void:
	_mask_cache.clear()

static func get_mask(d: Dictionary) -> BitMap:
	if d.has("mask"):
		return d["mask"] as BitMap
	var tex: Texture2D = d.get("tex", null)
	if tex != null:
		var path: String = tex.resource_path
		if path != "" and _mask_cache.has(path):
			var cached: BitMap = _mask_cache[path]
			d["mask"] = cached
			return cached
		var img: Image = tex.get_image()
		if img == null:
			return null
		var bm := BitMap.new()
		bm.create_from_image_alpha(img, 0.1)
		if path != "":
			_mask_cache[path] = bm
		d["mask"] = bm
		return bm
	var img: Image = d.get("img", null)
	if img != null:
		var bm := BitMap.new()
		bm.create_from_image_alpha(img, 0.1)
		d["mask"] = bm
		return bm
	return null

func ensure_water_material() -> ShaderMaterial:
	if water_material == null:
		water_material = ShaderMaterial.new()
		water_material.shader = WATER_CYCLE_SHADER
		water_material.set_shader_parameter("cycle_step", 0)
	return water_material

func draw_bg(root: Node2D, town_data: Dictionary) -> void:
	var t := load(ART + String(town_data.get("background", "townbkg0.png"))) as Texture2D
	if t != null:
		var s := Sprite2D.new()
		s.texture = t
		s.centered = false
		s.material = ensure_water_material()
		root.add_child(s)

func draw_buildings(root: Node2D, faction: String, town_data: Dictionary,
		game: GameState, player: PlayerState) -> void:
	building_anims.clear()
	common_hits.clear()
	var layout: Array = town_data.get("layout", [])
	var has_castle: bool = game.town.has_castle if (game != null and game.town != null) else false
	for i in layout.size():
		var e: Dictionary = layout[i]
		var dir := String(e.get("dir", ""))
		if dir == String(town_data.get("tent_dir", "")) and has_castle:
			continue
		if dir == String(town_data.get("castle_dir", "")) and not has_castle:
			continue
		var unit := String(e.get("unit", ""))
		if unit != "":
			var dwelling := BuildingCatalog.dwelling_for_unit(unit, faction)
			if dwelling != "" and game != null and game.town != null and not game.town.is_built(dwelling):
				continue
		var building_id := BuildingCatalog.dwelling_for_unit(unit, faction) if unit != "" else ""
		if dir == String(town_data.get("castle_dir", "")):
			building_id = "castle"
		place_building(root, dir, unit, i, building_id, faction, town_data)

	var next_z := layout.size()
	for id: String in ["well", "thieves_guild", "tavern", "shipyard"]:
		if game != null and game.town != null and not game.town.is_built(id):
			continue
		var sdir := String(BuildingCatalog.entry(id, faction).get("scene_dir", ""))
		if sdir == "":
			continue
		place_building(root, sdir, "", next_z, id, faction, town_data)
		next_z += 1
	draw_guild(root, player)

func place_building(root: Node2D, dir: String, unit: String, depth: int,
		building_id := "", faction: String = "knight", town_data: Dictionary = {}) -> void:
	var spec := SpecLoader.load_spec(ART + dir + "/spec.json")
	if spec.sprites.is_empty():
		return
	var sp = spec.sprites[0]                      # frame 0 = built structure
	var pos := Vector2(sp.offset.x, sp.offset.y)
	var tex := load(ART + dir + "/" + sp.file) as Texture2D
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	spr.position = pos
	spr.z_index = depth
	spr.material = ensure_water_material()
	spr.set_meta("building", true)
	spr.set_meta("building_id", building_id)
	spr.set_meta("construction_reveal", building_id != "")
	root.add_child(spr)
	if ANIMATED_BUILDINGS.has(dir):
		add_building_animation(root, dir, spec, depth, building_id)
	var tod_rect := load_tod_rect(dir)
	var hit_rect := tod_rect if tod_rect.size != Vector2.ZERO else Rect2(pos, Vector2(sp.size.x, sp.size.y))
	if dir == String(town_data.get("castle_dir", "")) \
			or dir == String(town_data.get("tent_dir", "")):
		castle_hit = {
			"rect": hit_rect,
			"pos": pos,
			"tex": tex,
			"dir": dir,
		}
	if unit != "":
		dwellings.append({
			"rect": hit_rect,
			"pos": pos,
			"tex": tex,
			"unit": unit, "depth": depth, "id": building_id,
		})
	else:
		for id: String in ["well", "tavern", "thieves_guild", "shipyard"]:
			if dir == String(BuildingCatalog.entry(id, faction).get("scene_dir", "")):
				common_hits.append({
					"rect": hit_rect,
					"pos": pos,
					"tex": tex,
					"id": id, "depth": depth,
				})
				break

func add_building_animation(root: Node2D, dir: String, spec, depth: int, building_id := "") -> void:
	var sprites: Array = []
	for i in range(1, spec.sprites.size()):
		var sp = spec.sprites[i]
		var frame := Sprite2D.new()
		frame.texture = load(ART + dir + "/" + sp.file) as Texture2D
		frame.centered = false
		frame.position = Vector2(sp.offset.x, sp.offset.y)
		frame.z_index = depth
		frame.visible = i == 1
		frame.material = ensure_water_material()
		frame.set_meta("building", true)
		frame.set_meta("building_id", building_id)
		root.add_child(frame)
		sprites.append(frame)
	if not sprites.is_empty():
		building_anims.append({
			"sprites": sprites, "index": 0, "elapsed": 0.0,
			"building_id": building_id, "paused": false,
		})

func draw_guild(root: Node2D, player: PlayerState) -> void:
	guild_hits.clear()
	if player == null or player.town == null:
		return
	var lvl: int = player.town.mage_guild_level
	if lvl <= 0:
		return
	var ids: Array = GUILD_SPRITE_IDS.get(lvl, [])
	var spec := SpecLoader.load_spec(MAGEGLD + "spec.json")
	for id in ids:
		if id >= spec.sprites.size():
			continue
		var sp = spec.sprites[id]
		var pos := Vector2(sp.offset.x, sp.offset.y)
		var tex := load(MAGEGLD + sp.file) as Texture2D
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.centered = false
		spr.position = pos
		spr.z_index = 100 + id
		spr.material = ensure_water_material()
		spr.set_meta("building", true)
		spr.set_meta("building_id", "mage_guild")
		spr.set_meta("construction_reveal", lvl == 1 \
				or id == ids[ids.size() - 2] or id == ids[ids.size() - 1])
		root.add_child(spr)
		var tod_rect := load_tod_rect("magegld")
		var hit_rect := tod_rect if tod_rect.size != Vector2.ZERO else Rect2(pos, Vector2(sp.size.x, sp.size.y))
		guild_hits.append({
			"rect": hit_rect,
			"pos": pos,
			"tex": tex,
		})

func redraw_buildings(root: Node2D, faction: String, town_data: Dictionary,
		game: GameState, player: PlayerState) -> void:
	for c in root.get_children():
		if c is Sprite2D and (c.has_meta("building") or (c as Sprite2D).z_index >= 100):
			c.queue_free()
	dwellings.clear()
	castle_hit.clear()
	draw_buildings(root, faction, town_data, game, player)

func draw_guild_refresh(root: Node2D, player: PlayerState) -> void:
	for c in root.get_children():
		if c is Sprite2D and (c as Sprite2D).z_index >= 100:
			c.queue_free()
	draw_guild(root, player)

func start_construction_reveal(root: Node2D, building_id: String, audio: TownAudio = null) -> void:
	finish_construction_reveal()
	if audio != null:
		audio.play_build()
	for child in root.get_children():
		if not (child is Sprite2D):
			continue
		var sprite := child as Sprite2D
		if sprite.is_queued_for_deletion() \
				or String(sprite.get_meta("building_id", "")) != building_id \
				or not bool(sprite.get_meta("construction_reveal", false)) \
				or sprite.texture == null:
			continue
		var reveal_material := ShaderMaterial.new()
		reveal_material.shader = CONSTRUCTION_REVEAL_SHADER
		reveal_material.set_shader_parameter("reveal_progress", 0.0)
		reveal_material.set_shader_parameter("pattern_offset", sprite.position)
		reveal_material.set_shader_parameter("block_size", 2.0)
		construction_parts.append({
			"sprite": sprite,
			"material": sprite.material,
			"visible": sprite.visible,
			"reveal_material": reveal_material,
		})
		sprite.material = reveal_material
	if construction_parts.is_empty():
		return
	for i in building_anims.size():
		var anim: Dictionary = building_anims[i]
		if String(anim.get("building_id", "")) != building_id:
			continue
		anim.paused = true
		for sprite: Sprite2D in anim.sprites:
			sprite.visible = false
		building_anims[i] = anim
	construction_elapsed = 0.0
	construction_active = true
	apply_construction_reveal()

func apply_construction_reveal() -> void:
	var progress := clampf(
			(construction_elapsed - CONSTRUCTION_REVEAL_DELAY) / CONSTRUCTION_REVEAL_DISSOLVE,
			0.0, 1.0)
	for part: Dictionary in construction_parts:
		var sprite: Sprite2D = part.sprite
		sprite.visible = bool(part.visible)
		(part.reveal_material as ShaderMaterial).set_shader_parameter("reveal_progress", progress)

func finish_construction_reveal() -> void:
	if not construction_active and construction_parts.is_empty():
		return
	var building_id := ""
	for part: Dictionary in construction_parts:
		var sprite: Sprite2D = part.sprite
		if not is_instance_valid(sprite):
			continue
		building_id = String(sprite.get_meta("building_id", building_id))
		sprite.material = part.material
		sprite.visible = bool(part.visible)
	for i in building_anims.size():
		var anim: Dictionary = building_anims[i]
		if not bool(anim.get("paused", false)) \
				or String(anim.get("building_id", "")) != building_id:
			continue
		anim.paused = false
		anim.index = 0
		anim.elapsed = 0.0
		var sprites: Array = anim.sprites
		for frame_index in sprites.size():
			(sprites[frame_index] as Sprite2D).visible = frame_index == 0
		building_anims[i] = anim
	construction_parts.clear()
	construction_active = false
	construction_elapsed = 0.0

func process(delta: float) -> void:
	if construction_active:
		construction_elapsed += delta
		if construction_elapsed >= CONSTRUCTION_REVEAL_DURATION:
			finish_construction_reveal()
		else:
			apply_construction_reveal()
	var step := 1.0 / BUILDING_ANIM_FPS
	water_cycle_elapsed += delta
	while water_cycle_elapsed >= step:
		water_cycle_elapsed -= step
		water_cycle_step = (water_cycle_step + 1) % 20
		if water_material != null:
			water_material.set_shader_parameter("cycle_step", water_cycle_step)
	for i in building_anims.size():
		var anim: Dictionary = building_anims[i]
		if bool(anim.get("paused", false)):
			continue
		var sprites: Array = anim.sprites
		if sprites.size() < 2:
			continue
		var elapsed := float(anim.elapsed) + delta
		while elapsed >= step:
			elapsed -= step
			(sprites[int(anim.index)] as Sprite2D).visible = false
			anim.index = (int(anim.index) + 1) % sprites.size()
			(sprites[int(anim.index)] as Sprite2D).visible = true
		anim.elapsed = elapsed
		building_anims[i] = anim

func opaque_at(d: Dictionary, p: Vector2) -> bool:
	var bm := get_mask(d)
	if bm == null:
		if d.get("tex") == null and d.get("img") == null and not d.has("mask"):
			if d.has("rect"):
				return (d.rect as Rect2).has_point(p)
			return true
		return false
	var origin: Vector2 = d.get("pos", (d.rect as Rect2).position)
	var lx := int(p.x - origin.x)
	var ly := int(p.y - origin.y)
	var sz := bm.get_size()
	if lx < 0 or ly < 0 or lx >= int(sz.x) or ly >= int(sz.y):
		return false
	return bm.get_bit(lx, ly)

func castle_at(p: Vector2) -> bool:
	if castle_hit.is_empty() or not (castle_hit.rect as Rect2).has_point(p):
		return false
	return opaque_at(castle_hit, p)

func guild_at(p: Vector2) -> bool:
	for h in guild_hits:
		var rect: Rect2 = h.rect
		if not rect.has_point(p):
			continue
		if opaque_at(h, p):
			return true
	return false

func dwelling_at(p: Vector2) -> Dictionary:
	var best: Dictionary = {}
	for d in dwellings:
		if not d.rect.has_point(p):
			continue
		if not opaque_at(d, p):
			continue
		if best.is_empty() or int(d.depth) > int(best.depth):
			best = d
	return best

func common_at(p: Vector2) -> Dictionary:
	var best: Dictionary = {}
	for hit: Dictionary in common_hits:
		if not (hit.rect as Rect2).has_point(p) or not opaque_at(hit, p):
			continue
		if best.is_empty() or int(hit.depth) > int(best.depth):
			best = hit
	return best

static func load_tod_rect(name: String) -> Rect2:
	var path := ART + "%s.tod" % name
	if not FileAccess.file_exists(path):
		return Rect2()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 9:
		return Rect2()
	f.get_8()
	var x := f.get_16()
	var y := f.get_16()
	var w := f.get_16()
	var h := f.get_16()
	return Rect2(x, y, w, h)
