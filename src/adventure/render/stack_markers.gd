class_name StackMarkers
extends RefCounted

## Manages neutral creature stack markers on the adventure map: minimon frame animation,
## centralized clock idle loops, attack flourishes, and marker state cleanup.
## Moved out of object_layer.gd.

var layer: DynamicObjectProvider
var markers: Dictionary = {}   # obj.id -> {sprite, frames, idle_frames, attack_indices, is_idling}
var _stack_elapsed: float = 0.0
var _last_stack_tick: int = 0

func _init(p_layer: DynamicObjectProvider = null) -> void:
	layer = p_layer

func setup() -> void:
	markers.clear()
	_stack_elapsed = 0.0
	_last_stack_tick = 0

## Animated minimon stack marker for a neutral guard. Cycles 7 frames in place.
func spawn_stack_marker(stack: NeutralStack) -> void:
	if stack.army == null or stack.army.slots.is_empty():
		push_error("DynamicObjectProvider: unresolved neutral stack at %s" % str(stack.tile))
		return
	var unit := "peasant"
	var army: ArmyData = stack.army
	if army != null and not army.slots.is_empty():
		unit = String(army.slots[0].unit)
	var idx: int = ObjectArtData.MONS32_INDEX.get(unit, 0)

	var spec: Dictionary = layer._shared_spec(ObjectArtData.MINIMON + "spec.json") if layer != null else {}
	var tile_size: int = layer._map.tile_size if (layer != null and layer._map != null) else 32
	var origin := Vector2(stack.tile.x * tile_size, stack.tile.y * tile_size)
	var spr := Sprite2D.new()
	spr.centered = false
	spr.set_meta("depth_tile", stack.tile)
	var parent: Node2D = (layer._actor_parent if (layer != null and layer._actor_parent != null) else layer)
	if parent != null:
		parent.add_child(spr)

	var frames: Array = []
	var base := idx * ObjectArtData.MINIMON_FRAMES
	var spec_sprites: Array = spec.get("sprites", [])
	for i in ObjectArtData.MINIMON_FRAMES:
		if base + i >= spec_sprites.size():
			break
		var sp = spec_sprites[base + i]
		var tex: Texture2D = layer._texture(ObjectArtData.MINIMON + sp.file) if layer != null else null
		var off := Vector2(sp.offset)
		var width := float(tex.get_width()) if tex != null else 0.0
		# heroes.exe 0x9aab5 paints a stack frame at (cell x, cell y - 5); the
		# mirrored attack frame (0x9aa5b) runs leftward from cell x + 36 - ox.
		frames.append({"tex": tex,
				"pos": origin + Vector2(off.x, off.y + ObjectArtData.STACK_ANCHOR_Y),
				"flip_pos": origin + Vector2(ObjectArtData.STACK_MIRROR_X + 1 - off.x - width, off.y + ObjectArtData.STACK_ANCHOR_Y)})
	if frames.is_empty():
		return
	var attack_indices: Array = ObjectArtData.MINIMON_ATTACK_FRAMES.get(unit, [])
	var idle_frames: Array = []
	for i: int in ObjectArtData.minimon_idle_frame_indices(unit, frames.size()):
		idle_frames.append(frames[i])
	if idle_frames.is_empty():
		idle_frames = frames
	apply_stack_frame(spr, idle_frames[0])

	var marker: Dictionary = {"sprite": spr, "frames": frames, "attack_indices": attack_indices,
			"idle_frames": idle_frames, "is_idling": true}
	markers[stack.id] = marker

func is_stack_idling(stack: NeutralStack) -> bool:
	return bool(markers.get(stack.id, {}).get("is_idling", false))

## Puts a guard back on its idle loop after play_attack_flourish. A stack that
## survives a fight with no battle screen (a computer hero dying to it) never
## gets its marker rebuilt, so it would otherwise stay frozen in its swing pose.
func resume_stack_idle(stack: NeutralStack) -> void:
	var marker: Dictionary = markers.get(stack.id, {})
	var idle_frames: Array = marker.get("idle_frames", [])
	if marker.is_empty() or idle_frames.is_empty():
		return
	var spr: Sprite2D = marker.sprite
	apply_stack_frame(spr, idle_frames[0])
	marker["is_idling"] = true

func apply_stack_frame(spr: Sprite2D, fr: Dictionary) -> void:
	spr.texture = fr.tex
	spr.position = fr.flip_pos if spr.flip_h else fr.pos

## Stops the idle loop the instant the hero reaches the adjacent tile, snaps
## the stack to face the hero, and plays a fast one-shot weapon-swing/thrust
## flourish for creatures whose 7 minimon frames have one (see
## MINIMON_ATTACK_FRAMES) — creatures without a distinct attack pose just freeze,
## facing the hero. Either way, battle starts a brief beat later.
func play_attack_flourish(stack: NeutralStack, hero_tile: Vector2i) -> void:
	var marker: Dictionary = markers.get(stack.id, {})
	if marker.is_empty():
		return
	marker["is_idling"] = false
	var spr: Sprite2D = marker.sprite
	spr.flip_h = hero_tile.x < stack.tile.x
	for fr: Dictionary in marker.frames:
		if fr.tex == spr.texture:
			apply_stack_frame(spr, fr)   # re-place the current pose for the flip
			break

	var frames: Array = marker.frames
	var attack_indices: Array = marker.attack_indices
	var attack_frames: Array = attack_indices.map(func(i): return frames[i])
	if attack_frames.is_empty():
		if layer != null and layer.is_inside_tree():
			await layer.get_tree().create_timer(ObjectArtData.ATTACK_BATTLE_DELAY).timeout
		return
	apply_stack_frame(spr, attack_frames[0])
	# Most creatures only have one distinct attack pose. Do not create a Tween
	# until there is another frame to animate: an empty Tween emits
	# "started with no Tweeners" when the scene tree advances it.
	if attack_frames.size() > 1 and layer != null and layer.is_inside_tree():
		var tw := layer.create_tween()
		for fr: Dictionary in attack_frames.slice(1):
			tw.tween_callback(apply_stack_frame.bind(spr, fr))
			tw.tween_interval(ObjectArtData.ATTACK_FLOURISH_FPS)
		await tw.finished
	if layer != null and layer.is_inside_tree():
		await layer.get_tree().create_timer(ObjectArtData.ATTACK_BATTLE_DELAY).timeout

func process(delta: float) -> void:
	_stack_elapsed += delta
	var stack_frame_index: int = int(_stack_elapsed / ObjectArtData.MINIMON_FRAME_S)
	if stack_frame_index != _last_stack_tick:
		_last_stack_tick = stack_frame_index
		for id in markers:
			var marker: Dictionary = markers[id]
			if not marker.get("is_idling", true):
				continue
			var idle_frames: Array = marker.get("idle_frames", [])
			if idle_frames.is_empty():
				continue
			var spr: Sprite2D = marker.get("sprite")
			if spr == null or not is_instance_valid(spr):
				continue
			var idx: int = stack_frame_index % idle_frames.size()
			apply_stack_frame(spr, idle_frames[idx])

func clear_marker(object_id: int) -> void:
	var marker: Dictionary = markers.get(object_id, {})
	if not marker.is_empty():
		var marker_sprite: Node = marker.get("sprite")
		if marker_sprite != null:
			marker_sprite.queue_free()
		markers.erase(object_id)
