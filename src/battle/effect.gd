class_name Effect
extends Node2D

## A one-shot battle hit-splash. Plays a sprite sequence (e.g. physical/ blood,
## redfire/ flame) anchored at a creature's feet — same anchor convention as
## Creature (Sprite2D.centered=false, position = feet + per-frame offset) — then
## frees itself. Used to show damage impact on a struck stack.

const ART := "res://assets/art/"
const FPS := 12.0

## Attack damage type -> native effect sprite dir. Creature data uses the exact
## bank names; the semantic aliases remain for spell/controller callers.
const DIR_FOR := {
	&"physical": "physical",
	&"redfire": "redfire",
	&"bluefire": "bluefire",
	&"electric": "electric",
	&"elecfire": "elecfire",
	&"cloud": "cloud",
	&"fire": "redfire",
	&"cold": "bluefire",
	&"lightning": "elecfire",
	&"rainbluk": "rainbluk",
	&"good_luck": "rainbluk",
}

signal finished
signal body_hide_frame_started
## A later pass of a multi-pass bank begins (1 = the second).
signal pass_started(index: int)

var _sprite: Sprite2D
var _frames: Array = []          # [{ tex:Texture2D, off:Vector2i }]
var _idx: int = 0
var _elapsed: float = 0.0
var _body_hide_frame: int = 0
var _passes_left: int = 1
var _passes_total: int = 1
## Also draw each frame flipped about the anchor. heroes.exe draws Fireball's
## half-ring frames twice, plain and mirrored (0xc6b5f, 0xc6b88), into a ring.
var mirror := false
## Frames per second for this effect; most banks run at FPS.
var fps := FPS
var _mirror_sprite: Sprite2D = null

func _init() -> void:
	z_index = 250
	_sprite = Sprite2D.new()
	_sprite.centered = false
	add_child(_sprite)

## Place at `feet` and play the splash for `kind` (a DIR_FOR key). z above bodies.
## `passes` runs the whole sequence that many times, as the exe does for most
## spell cast banks.
func play(feet: Vector2, kind: StringName = &"physical", passes: int = 1) -> void:
	_passes_left = maxi(passes, 1)
	_passes_total = _passes_left
	position = feet
	if z_index == 0:
		z_index = 250
	var dir_name: String = DIR_FOR.get(kind, String(kind))
	var dir := ART + dir_name + "/"
	var spec := SpecLoader.load_spec(dir + "spec.json")
	_frames.clear()
	for sp in spec.sprites:
		var tex := load(dir + sp.file) as Texture2D
		if tex == null:
			continue
		_frames.append({"tex": tex, "off": sp.offset})
	if _frames.is_empty():
		finished.emit()
		queue_free()
		return
	# The physical bank reaches full coverage on frame 5, then dissolves over
	# frames 6-9. Hiding a defeated body beneath that opaque frame gives the
	# native-looking transition: no early pop, followed by a visible blood tail.
	_body_hide_frame = mini(5, _frames.size() - 1) if kind == &"physical" \
			else _frames.size() - 1
	_idx = 0
	_elapsed = 0.0
	_apply()

func _apply() -> void:
	var f: Dictionary = _frames[_idx]
	_sprite.texture = f.tex
	if mirror:
		if _mirror_sprite == null:
			_mirror_sprite = Sprite2D.new()
			_mirror_sprite.centered = false
			_mirror_sprite.flip_h = true
			add_child(_mirror_sprite)
		_mirror_sprite.texture = f.tex
		_mirror_sprite.position = Vector2(-float(f.off.x) - float(f.tex.get_width()),
				float(f.off.y))
	# Native battle effects clamp to the screen boundary (y >= 0, x >= 0). For
	# top-row units, morale birds (ICN offset y=-176..-200, feet.y=141) would
	# otherwise render off-screen; clamping screen_y to 0 causes the bird's top
	# edge to anchor at the top of the screen, naturally shifting the bird down
	# as its wings spread upwards.
	var target_x := position.x + float(f.off.x)
	var target_y := position.y + float(f.off.y)
	_sprite.position = Vector2(
			maxf(0.0, target_x) - position.x,
			maxf(0.0, target_y) - position.y
	)

func _process(delta: float) -> void:
	if _frames.is_empty():
		return
	_elapsed += delta
	var step := 1.0 / fps
	while _elapsed >= step:
		_elapsed -= step
		_idx += 1
		if _idx >= _frames.size():
			_passes_left -= 1
			if _passes_left > 0:
				_idx = 0
				_apply()
				pass_started.emit(_passes_total - _passes_left)
				continue
			finished.emit()
			queue_free()
			return
		_apply()
		if _idx == _body_hide_frame:
			body_hide_frame_started.emit()

func has_reached_body_hide_frame() -> bool:
	return not _frames.is_empty() and _idx >= _body_hide_frame
