class_name StormRainOverlay
extends Node2D

## Full-field rain overlay for the Storm (meteor_shower) combat spell.
## Reconstructed from heroes.exe (0xc7338-0xc7431):
## Tiled in a 10 col x 7 row grid of 64x64 cells spanning 640x448 px.
## Runs 5 cycles across 10 frames of storm.icn at 12 FPS (~4.16s),
## exactly matching the 4.12s duration of SPELL16.wav.

const ART_DIR := "res://assets/art/storm/"
const COLS := 10
const ROWS := 7
const CELL_SIZE := 64
const CYCLES := 5
const FPS := 12.0
const Z_INDEX := 240

signal finished

var cycles: int = CYCLES
var fps: float = FPS

var _frames: Array[Dictionary] = [] # [{ tex: Texture2D, offset: Vector2i }]
var _current_frame_idx: int = -1

func _init() -> void:
	z_index = Z_INDEX
	_load_frames()

func _load_frames() -> void:
	var spec := SpecLoader.load_spec(ART_DIR + "spec.json")
	for sp: Dictionary in spec.sprites:
		var file_str := String(sp.get("file", ""))
		var path := ART_DIR + file_str
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			if tex != null:
				var off: Vector2i = sp.get("offset", Vector2i.ZERO)
				_frames.append({"tex": tex, "offset": off})

func frame_count() -> int:
	return _frames.size()

func current_frame_idx() -> int:
	return _current_frame_idx

func set_frame(idx: int) -> void:
	_current_frame_idx = clampi(idx, 0, _frames.size() - 1) if not _frames.is_empty() else -1
	queue_redraw()

func play() -> void:
	if _frames.is_empty() or cycles <= 0 or fps <= 0.0 or not is_inside_tree():
		finished.emit()
		return
	var frame_delay := 1.0 / fps
	for cycle in range(cycles):
		for f in range(_frames.size()):
			_current_frame_idx = f
			queue_redraw()
			await get_tree().create_timer(frame_delay).timeout
			if not is_inside_tree():
				return
	_current_frame_idx = -1
	queue_redraw()
	finished.emit()

func _draw() -> void:
	if _current_frame_idx < 0 or _current_frame_idx >= _frames.size():
		return
	var frame: Dictionary = _frames[_current_frame_idx]
	var tex: Texture2D = frame.tex
	var off: Vector2i = frame.offset
	for r in range(ROWS):
		var y := r * CELL_SIZE + off.y
		for c in range(COLS):
			var x := c * CELL_SIZE + off.x
			draw_texture(tex, Vector2(x, y))
