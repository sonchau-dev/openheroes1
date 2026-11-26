class_name Creature
extends Node2D

## Renders a HOMM1 creature's battle animations from extracted sprites.
## Two child Sprite2D layers: shadow (behind) + body (front). Frame->anim
## mapping comes from data/creatures/anim_table.json because the extractor's
## spec.json role labels are unreliable.

signal animation_finished(anim: StringName)

const ART := "res://assets/art/"
const TABLE_PATH := "res://data/creatures/anim_table.json"
const CreatureCatalogScript := preload("res://src/battle/creature_catalog.gd")

## Standard 18-frame composite -> component sprite ids (base F5 + overlay).
## ATK ranged composites use base F0 + overlay F1-F4.
const _COMPOSITE_PARTS := {
	"composite_atk_up.png": [5, 6],
	"composite_atk_across.png": [5, 7],
	"composite_atk_down.png": [5, 8],
	"composite_atk_F1.png": [0, 1],
	"composite_atk_F2.png": [0, 2],
	"composite_atk_F3.png": [0, 3],
	"composite_atk_F4.png": [0, 4],
	"composite_atk0_up.png": [5, 6],
	"composite_atk0_across.png": [5, 7],
	"composite_atk0_down.png": [5, 8],
	"composite_atk1_up.png": [5, 9],
	"composite_atk1_across.png": [5, 10],
	"composite_atk1_down.png": [5, 11],
	"composite_atk2_up.png": [5, 12],
	"composite_atk2_across.png": [5, 13],
	"composite_atk2_down.png": [5, 14],
}

## ATK frames 5-9 are the missile at five fixed angles, steep up to steep
## down; BattleView.missile_frame picks one, HOMM1 never rotates it.
const PROJECTILE_FRAMES := [5, 6, 7, 8, 9]

## Suffix of the attack variant that stops before the long reach (the third
## frame of a three-frame strike), used when nothing stands behind the target.
const SHORT_SUFFIX := "_short"

var _shadow: Sprite2D
var _body: Sprite2D
var _anims: Dictionary = {}          # StringName -> Array[Frame]
# Frame := { body_tex, body_off:Vector2i, shadow_tex, shadow_off:Vector2i,
#            fps:float, loop:bool, hold_last:bool, return_to:StringName }

var _projectiles: Dictionary = {}    # ATK frame id -> { tex: Texture2D, off: Vector2i }

var _current: StringName = &""
var _frame_idx: int = 0
var _elapsed: float = 0.0
var _finished: bool = false
var _hold: bool = false   # when set, freeze on last frame (ignore return_to)
var _custom_fps: float = -1.0

func set_custom_fps(fps: float) -> void:
	_custom_fps = fps

## The DOS game draws a shadow frame by darkening what lies under it, not by
## painting black: grass under a shadow keeps its texture at about half its
## brightness (0.46 to 0.58 per channel, measured beside the Goblins and
## Paladins of the 2026-09-24 Arena Spells recording). The extracted shadow
## frames are solid black, so half opacity reproduces that.
const SHADOW_ALPHA := 0.5

func _init() -> void:
	_shadow = Sprite2D.new()
	_shadow.centered = false
	_shadow.self_modulate = Color(1, 1, 1, SHADOW_ALPHA)
	_shadow.z_index = -1
	add_child(_shadow)
	_body = Sprite2D.new()
	_body.centered = false
	add_child(_body)

static var _anim_table: Dictionary = {}

static func anim_table() -> Dictionary:
	if _anim_table.is_empty():
		_anim_table = JsonFile.read_dict(TABLE_PATH)
	return _anim_table

func setup(unit: StringName) -> void:
	_anims.clear()
	var units: Dictionary = CreatureCatalogScript.all_units()
	var table: Dictionary = anim_table()
	var u := String(unit)
	if not units.has(u):
		push_error("Creature: unknown unit %s" % u)
		return
	var dirs: Dictionary = units[u]

	# Parse the specs we have (std/wlk/wip/atk).
	var specs: Dictionary = {}
	for key in ["std", "wlk", "wip", "atk"]:
		if dirs.has(key):
			specs[key] = SpecLoader.load_spec(ART + dirs[key] + "/spec.json")

	# Ranged units: collect the angled missile sprites and their anchor offsets.
	_projectiles.clear()
	if specs.has("atk"):
		for sp in (specs["atk"] as Dictionary).get("sprites", []):
			if int(sp.id) in PROJECTILE_FRAMES:
				var tex := load(ART + dirs["atk"] + "/" + String(sp.file)) as Texture2D
				if tex != null:
					_projectiles[int(sp.id)] = {"tex": tex, "off": sp.offset}

	# Merge default profile with any per-unit override.
	var profile: Dictionary = (table.get("default", {}) as Dictionary).duplicate(true)
	if dirs.has("atk"):
		for k in (table.get("ranged_default", {}) as Dictionary):
			profile[k] = table.ranged_default[k]
	var overrides: Dictionary = table.get("overrides", {})
	if overrides.has(u):
		for k in (overrides[u] as Dictionary):
			profile[k] = overrides[u][k]

	for anim_name in profile:
		var entry: Dictionary = profile[anim_name]
		var src: String = String(entry.get("source", "std"))
		if dirs.has(src):
			_anims[StringName(anim_name)] = _build_frames(entry, dirs, specs)
		elif src == "wip" and dirs.has("wlk"):
			var fallback_entry: Dictionary = entry.duplicate(true)
			fallback_entry["source"] = "wlk"
			_anims[StringName(anim_name)] = _build_frames(fallback_entry, dirs, specs)

	# Cyclops, Phoenix and Dragon end their strike on a long reach that only
	# makes sense with a second unit in line; keep a short cut without it.
	for anim_name: StringName in _anims.keys():
		var frames: Array = _anims[anim_name]
		if String(anim_name).begins_with("attack_") and frames.size() == 3:
			_anims[StringName(String(anim_name) + SHORT_SUFFIX)] = frames.slice(0, 2)

	if _anims.has(&"idle"):
		play(&"idle")

func get_anim_frames(anim: StringName) -> Array:
	return _anims.get(anim, [])

func has_anim(anim: StringName) -> bool:
	return _anims.has(anim) and not (_anims[anim] as Array).is_empty()

## Missile sprite for ATK frame `frame` (5-9) as { tex, off }, `off` placing
## the texture's top-left against the missile's position. Empty for units
## without ranged art.
func projectile(frame: int) -> Dictionary:
	return _projectiles.get(frame, {})

## When `hold` is true the anim freezes on its last frame instead of following
## return_to — used to keep a unit in its pain pose while a hit splash plays out.
func play(anim: StringName, hold: bool = false) -> void:
	if not _anims.has(anim) or (_anims[anim] as Array).is_empty():
		push_warning("Creature: cannot play '%s'" % anim)
		return
	if anim == _current and (_anims[anim][0].loop):
		return  # don't restart a looping anim already playing
	_current = anim
	_frame_idx = 0
	_elapsed = 0.0
	_finished = false
	_hold = hold
	_apply_frame()

func current_anim() -> StringName:
	return _current

func body_sprite() -> Sprite2D:
	return _body

const _OUTLINE_SHADER := "res://src/battle/outline.gdshader"
# COMBAT.PAL indices 228-231, advanced by the original selected-unit timer.
const _GLOW_COLORS := [
	Color8(252, 252, 0),
	Color8(252, 204, 0),
	Color8(192, 140, 0),
	Color8(140, 72, 0),
]
# A stack under a lasting spell is outlined too, red for a hostile effect
# (COMBAT.PAL 224-227) and blue for a friendly one (247-250), cycling at the
# same pace; the active stack's yellow takes precedence (DOS Arena Spells
# recordings, 2026-09-26).
const _HOSTILE_COLORS := [
	Color8(252, 88, 12),
	Color8(220, 52, 4),
	Color8(192, 20, 0),
	Color8(164, 0, 0),
]
const _FRIENDLY_COLORS := [
	Color8(132, 224, 252),
	Color8(0, 152, 252),
	Color8(0, 80, 228),
	Color8(0, 0, 164),
]
const _GLOW_STEP_SECONDS := 0.16
var _outline_mat: ShaderMaterial = null
var _outline_enabled := false
var _outline_elapsed := 0.0
var _outline_step := 0
var _outline_colors: Array = []
var _active_glow := false
var _status_outline: StringName = &""   # &"", &"hostile" or &"friendly"

## Toggle the cycling silhouette glow on the body (active-unit marker).
func set_outline(on: bool) -> void:
	_active_glow = on
	_refresh_outline()

## Outline for a lasting spell effect: &"hostile", &"friendly" or &"" for none.
func set_status_outline(kind: StringName) -> void:
	if kind == _status_outline:
		return
	_status_outline = kind
	_refresh_outline()

func _refresh_outline() -> void:
	var colors: Array = []
	if _active_glow:
		colors = _GLOW_COLORS
	elif _status_outline == &"hostile":
		colors = _HOSTILE_COLORS
	elif _status_outline == &"friendly":
		colors = _FRIENDLY_COLORS
	if colors.is_empty():
		_outline_enabled = false
		_outline_colors = []
		_body.material = null
		return
	if _outline_mat == null:
		_outline_mat = ShaderMaterial.new()
		_outline_mat.shader = load(_OUTLINE_SHADER)
		_outline_mat.set_shader_parameter("outline_width", 1.0)
	if colors != _outline_colors or not _outline_enabled:
		_outline_elapsed = 0.0
		_outline_step = 0
	_outline_colors = colors
	_outline_enabled = true
	_outline_mat.set_shader_parameter("outline_color", _outline_colors[_outline_step])
	_body.material = _outline_mat

func set_facing(left: bool) -> void:
	scale.x = -1.0 if left else 1.0

func _process(delta: float) -> void:
	advance(delta)

## Deterministic frame stepper (called by _process; tests call directly).
func advance(dt: float) -> void:
	if _outline_enabled:
		_outline_elapsed += dt
		while _outline_elapsed >= _GLOW_STEP_SECONDS:
			_outline_elapsed -= _GLOW_STEP_SECONDS
			_outline_step = (_outline_step + 1) % _outline_colors.size()
			_outline_mat.set_shader_parameter("outline_color", _outline_colors[_outline_step])
	if _current == &"":
		return
	var frames: Array = _anims[_current]
	var fps: float = _custom_fps if _custom_fps > 0.0 else float(frames[0].fps)
	if fps <= 0.0:
		return
	_elapsed += dt
	var step := 1.0 / fps
	while _elapsed >= step:
		_elapsed -= step
		_advance_one(frames)

func _advance_one(frames: Array) -> void:
	var last := frames.size() - 1
	if _frame_idx < last:
		_frame_idx += 1
		_apply_frame()
		return
	# at last frame
	var f: Dictionary = frames[_frame_idx]
	if f.loop:
		_frame_idx = 0
		_apply_frame()
		return
	# non-looping: fire finished once, then hold or return
	if not _finished:
		_finished = true
		var at_emit := _current
		emit_signal("animation_finished", _current)
		# Awaiters resume synchronously inside the emit and may start another
		# anim (battle code can even advance whole turns before suspending on a
		# tween); only follow return_to if this anim is still the current one.
		if _current == at_emit and not _hold and not f.hold_last and f.return_to != &"":
			play(f.return_to)

func _apply_frame() -> void:
	var f: Dictionary = _anims[_current][_frame_idx]
	_body.texture = f.body_tex
	_body.position = Vector2(f.body_off)
	_shadow.texture = f.shadow_tex
	_shadow.position = Vector2(f.shadow_off)
	_shadow.visible = f.shadow_tex != null

# --- internals ------------------------------------------------------------

func _build_frames(entry: Dictionary, dirs: Dictionary, specs: Dictionary) -> Array:
	var src: String = entry.get("source", "std")
	if not dirs.has(src):
		push_warning("Creature: anim source '%s' missing for unit" % src)
		return []
	var dir: String = ART + dirs[src] + "/"
	var spec: Dictionary = specs.get(src, {"sprites": []})
	var fps: float = float(entry.get("fps", 8.0))
	var loop: bool = bool(entry.get("loop", false))
	var hold_last: bool = bool(entry.get("hold_last", false))
	var return_to := StringName(entry.get("return_to", ""))

	# Shadow: either one shared strip ("shadow") or a per-frame list ("shadows",
	# e.g. the walk-cycle ground shadows). Per-frame takes precedence.
	var shadow_list: Array = entry.get("shadows", [])
	var shared_name: Variant = entry.get("shadow", null)
	var shared_tex: Texture2D = null
	var shared_off := Vector2i.ZERO
	if shared_name != null:
		shared_tex = load(dir + String(shared_name)) as Texture2D
		shared_off = _offset_by_file(spec, String(shared_name))

	var frames: Array = []
	var frame_names: Array = entry.get("frames", [])
	for i in frame_names.size():
		var fname := String(frame_names[i])
		var body_tex: Texture2D = load(dir + fname) as Texture2D
		if body_tex == null:
			push_warning("Creature: missing %s" % (dir + fname))
		var body_off := _frame_offset(spec, fname)
		var sh_tex := shared_tex
		var sh_off := shared_off
		if i < shadow_list.size():
			var sn := String(shadow_list[i])
			sh_tex = load(dir + sn) as Texture2D
			sh_off = _offset_by_file(spec, sn)
		frames.append({
			"body_tex": body_tex,
			"body_off": body_off,
			"shadow_tex": sh_tex,
			"shadow_off": sh_off,
			"fps": fps,
			"loop": loop,
			"hold_last": hold_last,
			"return_to": return_to,
		})

	# Walk frames bake forward root-motion into offsetX; the node tween already
	# moves the creature, so anchor X to the first frame (legs still cycle in
	# place) — otherwise the body drifts forward then snaps back each loop. The
	# ground shadow is anchored the same way so it stays under the feet.
	if bool(entry.get("anchor_x", false)) and not frames.is_empty():
		var ax: int = frames[0].body_off.x
		var sx: int = frames[0].shadow_off.x
		for fr: Dictionary in frames:
			fr.body_off = Vector2i(ax, fr.body_off.y)
			fr.shadow_off = Vector2i(sx, fr.shadow_off.y)
	return frames

## Anchor offset for a frame. Composites have no spec entry, so derive their
## canvas origin from the min offset of their component sprites.
func _frame_offset(spec: Dictionary, fname: String) -> Vector2i:
	if _COMPOSITE_PARTS.has(fname):
		var min_x := 1 << 30
		var min_y := 1 << 30
		for sid in _COMPOSITE_PARTS[fname]:
			var off := _offset_by_id(spec, sid)
			min_x = min(min_x, off.x)
			min_y = min(min_y, off.y)
		return Vector2i(min_x, min_y)
	return _offset_by_file(spec, fname)

func _offset_by_file(spec: Dictionary, fname: String) -> Vector2i:
	if spec.has("by_file") and (spec.by_file as Dictionary).has(fname):
		return (spec.by_file as Dictionary)[fname].offset
	for sp in spec.get("sprites", []):
		if sp.file == fname:
			return sp.offset
	return Vector2i.ZERO

func _offset_by_id(spec: Dictionary, id: int) -> Vector2i:
	if spec.has("by_id") and (spec.by_id as Dictionary).has(id):
		return (spec.by_id as Dictionary)[id].offset
	for sp in spec.get("sprites", []):
		if sp.id == id:
			return sp.offset
	return Vector2i.ZERO
