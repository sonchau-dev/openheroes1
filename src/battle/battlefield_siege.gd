extends Node2D

## Native HOMM1 siege dressing. Every sprite keeps the anchor offset extracted
## in its spec.json; no castle art is scaled.

const ART := "res://assets/art/"
# castle%02d sprite ids, read off the DOS original (siege captures 2026-09-17
# and 2026-09-18, reference-capture-playbook 9). Each wall section is a
# crenellated round tower with wooden hoardings and an arrow slit, tall enough that
# consecutive rows overlap into one continuous face. Straight connecting wall
# segments (id9) link adjacent towers together in a zig-zag: even-to-odd rows (0->1, 2->3)
# slant down-right, and odd-to-even rows (1->2, 3->4) slant down-left (flipped horizontally).
# A destroyed section simply stops drawing its tower, leaving an opening in the wall
# for attackers to enter through. id7 is the wall that closes the top of the castle
# floor behind row 0.
const WALL_SECTION := 8
# id10 is the same tower with its top blown off and its hoardings smashed: the
# half-destroyed state a section shows after one catapult hit. Without it a
# section that had taken damage still drew intact stone, so the catapult read
# as doing nothing until the second hit.
const WALL_DAMAGED := 10
# Authentic HOMM1 ground rubble patches from castle%02d.icn (heroes.exe 0xc37ff..0xc3853).
# Because odd rows are staggered right by half a cell, authentic HOMM1 draws
# frame 5 on odd rows (1, 3) and frame 6 on even rows (0, 2, 4).
const WALL_RUBBLE_ODD := 5
const WALL_RUBBLE_EVEN := 6
# id9 is the connecting wall segment linking adjacent towers. Even-to-odd rows
# slant down-right (unflipped), while odd-to-even rows slant down-left (flipped
# horizontally).
const WALL_SEGMENT := 9
const KEEP := 7
const FLOOR_TILE := 4
# Half-hex fillers. The floor hexes follow the row stagger, so an odd row starts
# half a column further right and leaves a bare wedge against the wall; id3 is
# the left-edge strip that fills it (and id1 the right-edge one).
const FLOOR_EDGE_LEFT := 3
const FLOOR_EDGE_RIGHT := 1
# DOS animation tick for the catapult, measured on a 60 fps DOSBox recording
# (2026-10-11): the arm advances every 0.079 s on the way up (eight changes in
# 0.55 s) and every 0.083 s on the reload, the same ~12.8 Hz the impact cloud
# uses. One shot runs frame 0 at 6.37 s to the cloud's first frame at 8.62 s.
const CATAPULT_FRAME_TIME := 0.08
# DOS holds frame 8 (the arm swung through) while the rock flies, then reloads
# as the impact cloud clears, stepping frames 9 to 13 and back to the loaded
# pose 0 (frame 14 never shows).
const CATAPULT_RELOAD_LAST := 13
# The arm carries the rock through frame 6 and swings empty from frame 7, so
# that is where the boulder leaves the bucket, measured against the catapult
# frames themselves.
const CATAPULT_RELEASE_FRAME := 7
# Where the rock leaves the arm, relative to the catapult's own anchor (30, 380).
# Measured against the bucket at frame 7 in the native sprite: screen (88, 276).
const CATAPULT_LAUNCH := Vector2(58, -104)
# boulder.icn is the rock in flight: three rotation frames, cycled while it
# travels in an arc to the targeted wall section. In the DOS recording the rock
# is first visible 0.11 s after the arm reaches frame 8 and is gone 1.52 s later,
# when the impact cloud starts.
const BOULDER_FRAMES := 3
const BOULDER_SPIN_TIME := 0.09
const BOULDER_FLIGHT_TIME := 1.5
const BOULDER_ARC := 150.0
# cloud.icn is the impact explosion on the wall section: ten frames of dust/smoke,
# sharing the same 12 FPS cadence as Effect's hit splashes (physical blood, etc.).
const CLOUD_FRAMES := 10
const CLOUD_FRAME_TIME := 1.0 / 12.0
# The DOS impact (heroes.exe 0xc2ccd, driven from 0x8ba00) is three cloud puffs
# when breached, but only one puff when damaged. For a breach, each frame draws up to
# three cloud sprites down the section: the first above the tower's feet, the
# second and third (one frame behind) below them, so the blast spans about 230 px.
# When only damaging the top of the wall (breached == false), DOS heroes.exe
# checks 0x664 != -1 at 0xc2dbb; when -1, it skips the second and third puffs,
# drawing only the single impact puff at the top.
# Frame 5 is where the new look takes over in both cases: a destroyed tower is cleared
# at frame 5, and a damaged tower swaps from intact to damaged at frame 5 behind the cloud.
const CLOUD_BREAK_FRAME := 5
# The scene is redrawn inside a window while the cloud plays (x 300..490,
# y row*80-30 .. row*80+190), and the cloud is cut off at its edge.
const CLOUD_WINDOW_X := Vector2(300.0, 490.0)
const CLOUD_WINDOW_TOP := -30.0
const CLOUD_WINDOW_BOTTOM := 190.0
const CLOUD_WINDOW_MAX_Y := 459.0
# The rock strikes the section mid-height rather than at the cell's feet.
const WALL_IMPACT := Vector2(0, -62)
# keep%02d is the arrow tower: id0 the tower itself, id1-3 the shot it fires at
# the three fixed angles HOMM1 draws (flat, diagonal, steep). One dir per
# faction in the same ART order as castle%02d, and each faction shoots its own
# missile - a plain arrow for the Knight, a red bolt for the Sorceress, a
# flaming arrow for the Barbarian, lightning for the Warlock. The tower used to
# be drawn as another wall section, which has no shot art at all.
const TOWER_SPRITE := 0
const TOWER_SHOT_FLAT := 1
const TOWER_SHOT_DIAGONAL := 2
const TOWER_SHOT_STEEP := 3
# keep%02d carries no meaningful spec.json anchor, so the tower is placed by
# screen position: flush with the arena's right edge and the top of the screen.
# A sprite match against the DOS sorceress siege (2026-10-11) puts it at y=0;
# the earlier y=5 (read off the first capture) left a strip of sky and hills
# above the tower.
const TOWER_TOP := 0.0
# Centre of the tower's arrow slit, measured in the sprite: the shot starts there.
const TOWER_SLIT := Vector2(33, 24)
# The flaming arrow crosses the field at about 1400 px/s in the DOS recording
# (568 px to 303 px in 0.2 s), not the 2500 px/s used before.
const TOWER_SHOT_SPEED := 1400.0
# The tower's missile lands on the target's chest.
const CHEST_HEIGHT := Vector2(0, -35)
# Ground tiles paint at z = row and units at 100 + row, so the castle floor
# belongs between them.
const FLOOR_Z := 50
# Wall pieces paint by row like the units do (units sit at 100 + row), not on a
# layer of their own. A DOS capture (2026-10-11) shows a stack standing in a
# breach in front of the tower and hoarding above it and behind the tower on the
# row below, whose crenellated top hides its feet. A wall piece shares its row's
# depth and the battle view is added after this node, so a unit wins the tie.
const WALL_Z := 100
# The catapult stands outside the active cells, level with the fourth row (KB
# battle.md 12.3). Matching the sprite against the DOS siege capture puts it at
# 7,304 on screen, i.e. this anchor once spec.json's -23,-76 is applied; the
# column-based guess had it 91px too far right, inside the field.
const CATAPULT_ANCHOR := Vector2(30, 380)
# catapult.icn embeds two monochromatic ground shadow frames (id15 and id16).
# In DOS heroes.exe (0xc3f0b..0xc3f20), catapult frame 7 (release) draws shadow
# frame 16 while all other catapult frames draw shadow frame 15.
const CATAPULT_SHADOW_REST := 15
const CATAPULT_SHADOW_RELEASE := 16
const SHADOW_ALPHA := 0.5
# The DOS routine that paints the castle ground (heroes.exe 0xc376d) draws row
# 0's floor hexes and rubble, then blits the whole 640x102 sky strip at (0,0),
# so nothing in row 0 shows above y=102. Left of the wall that is where the
# rubble hex's top third would poke out over the sky and grass.
const SKY_STRIP_HEIGHT := 102.0
# The castle%02d dirs are stored in ART order (Knight, Sorceress, Barbarian,
# Warlock) while a town's faction id runs Knight, Barbarian, Sorceress, Warlock.
# Without this hop a barbarian siege drew the sorceress castle, water moat and
# all, and a sorceress siege drew brown brick (DOS captures, 2026-09-17).
const CASTLE_DIR_BY_FACTION := [0, 2, 1, 3]

var instant: bool = false
var defender_side: int = 1
var faction: int = 0
var origin := Vector2.ZERO
var step := Vector2.ZERO

var _castle_dir := ""
var _keep_dir := ""
var _castle_spec: Dictionary = {}
var _keep_spec: Dictionary = {}
var _catapult_spec: Dictionary = {}
var _cloud_spec: Dictionary = {}
var _boulder_textures: Array[Texture2D] = []
var _walls: Array[Sprite2D] = []
var _wall_segments: Array[Sprite2D] = []
var _wall_patches: Array[Sprite2D] = []
var _wall_hps: Array[int] = [2, 2, 2, 2, 2]
var _floor: Array[Sprite2D] = []
var _keep: Sprite2D = null
var _tower: Sprite2D = null
var _catapult: Sprite2D = null
var _catapult_shadow: Sprite2D = null
var _boulder: Sprite2D = null
var _boulder_from := Vector2.ZERO
var _boulder_to := Vector2.ZERO
var _catapult_audio: AudioStreamPlayer = null
var _impact_audio: AudioStreamPlayer = null
var _tower_audio: AudioStreamPlayer = null

func setup(p_faction: int, p_defender_side: int,
		p_origin: Vector2, p_step: Vector2) -> void:
	faction = clampi(p_faction, 0, 3)
	defender_side = p_defender_side if p_defender_side in [0, 1] else 1
	origin = p_origin
	step = p_step
	_castle_dir = ART + "castle%02d/" % CASTLE_DIR_BY_FACTION[faction]
	_castle_spec = SpecLoader.load_spec(_castle_dir + "spec.json")
	_keep_dir = ART + "keep%02d/" % CASTLE_DIR_BY_FACTION[faction]
	_keep_spec = SpecLoader.load_spec(_keep_dir + "spec.json")
	_catapult_spec = SpecLoader.load_spec(ART + "catapult/spec.json")
	_cloud_spec = SpecLoader.load_spec(ART + "cloud/spec.json")
	_boulder_textures.clear()
	for i in BOULDER_FRAMES:
		var tex := load(ART + "boulder/%04d.png" % i) as Texture2D
		if tex != null:
			_boulder_textures.append(tex)
	name = "BattlefieldSiege"
	_paint_floor()
	_paint_keep()
	_paint_walls()
	_paint_tower()
	_paint_catapult()
	_catapult_audio = _audio("CatapultFire", ART + "CATSND00.wav")
	_impact_audio = _audio("CatapultImpact", ART + "CATSND02.wav")
	if ResourceLoader.exists(ART + "SHOOT01.wav"):
		_tower_audio = _audio("TowerFire", ART + "SHOOT01.wav")

func _paint_floor() -> void:
	## The defenders stand on castle stone. The original paves the courtyard
	## columns behind the wall with the castle's hex floor tile.
	_floor.clear()
	var wall := Hex.wall_col(defender_side)
	var outer := Hex.COLS if defender_side == 1 else -1
	for row in Hex.ROWS:
		for col in _floor_cols():
			_add_floor("Floor%d_%d" % [col, row], FLOOR_TILE, col, row)
		# The stagger pushes odd rows half a column away from the wall; fill the
		# wedge it leaves so no grass shows through the castle floor.
		var staggered := (row & 1) == 1
		if defender_side == 1:
			_add_floor("FloorEdge%d" % row, FLOOR_EDGE_LEFT, wall + 1, row, not staggered)
			_add_floor("FloorOuter%d" % row, FLOOR_EDGE_RIGHT, outer, row, staggered)
		else:
			_add_floor("FloorEdge%d" % row, FLOOR_EDGE_RIGHT, wall - 1, row, not staggered)
			_add_floor("FloorOuter%d" % row, FLOOR_EDGE_LEFT, outer, row, staggered)

func _add_floor(sprite_name: String, frame: int, col: int, row: int,
		skip: bool = false) -> void:
	if skip:
		return
	var sprite := Sprite2D.new()
	sprite.name = sprite_name
	sprite.centered = false
	sprite.z_index = FLOOR_Z + row
	add_child(sprite)
	_floor.append(sprite)
	_set_sprite(sprite, _castle_dir, _castle_spec, frame,
			Hex.to_pixel(col, row, origin, step), defender_side == 0)
	_clip_below_sky(sprite)

func _paint_keep() -> void:
	## The castle closes off above the first row with a darker crenellated wall.
	## Two pieces are drawn: Keep1 flush with the outer screen edge, and Keep0
	## adjacent to Tower 0. Keep0 is drawn on top of Keep1 so its body covers
	## Keep1's broken-wall left cutout, while Tower 0 covers Keep0's cutout.
	var mirror := defender_side == 0
	var anchors := ([Vector2(529, 139), Vector2(639, 139)] if not mirror
			else [Vector2(111, 139), Vector2(1, 139)])
	for i in [1, 0]:
		var sprite := Sprite2D.new()
		sprite.name = "Keep%d" % i
		sprite.centered = false
		sprite.z_index = FLOOR_Z + Hex.ROWS
		add_child(sprite)
		if _keep == null or i == 0:
			_keep = sprite
		_set_sprite(sprite, _castle_dir, _castle_spec, KEEP,
				anchors[i], mirror)

func _paint_walls() -> void:
	_walls.clear()
	_wall_segments.clear()
	_wall_patches.clear()
	_wall_hps = [2, 2, 2, 2, 2]
	var mirror := defender_side == 0
	var wall_col := Hex.wall_col(defender_side)
	var w_entry := _spec_entry(_castle_spec, WALL_SEGMENT)
	var base_x: float = Hex.to_pixel(wall_col, 0, origin, step).x + display_offset(w_entry, mirror).x

	for row in Hex.ROWS:
		# 0. Destroyed wall ground patch at this row (visible when tower is destroyed)
		var patch := Sprite2D.new()
		patch.name = "WallPatch%d" % row
		patch.centered = false
		patch.z_index = FLOOR_Z + row
		patch.visible = false
		add_child(patch)
		_wall_patches.append(patch)
		var patch_frame := WALL_RUBBLE_ODD if (row & 1) == 1 else WALL_RUBBLE_EVEN
		_set_sprite(patch, _castle_dir, _castle_spec, patch_frame,
				_wall_anchor(row), mirror)
		_clip_below_sky(patch)

		# 1. Tower at this row
		var tower := Sprite2D.new()
		tower.name = "Wall%d" % row
		tower.centered = false
		tower.z_index = WALL_Z + row
		add_child(tower)
		_walls.append(tower)
		_set_sprite(tower, _castle_dir, _castle_spec, WALL_SECTION,
				_wall_anchor(row), mirror)

		# 2. Connecting wall segment to the next row
		if row < Hex.ROWS - 1:
			var segment := Sprite2D.new()
			segment.name = "WallSegment%d" % row
			segment.centered = false
			segment.z_index = WALL_Z + row
			if not w_entry.is_empty():
				segment.texture = load(_castle_dir + String(w_entry.file)) as Texture2D
				segment.flip_h = ((row & 1) == 1) != mirror
				var anchor_y := Hex.to_pixel(wall_col, row, origin, step).y
				var pos_y: float = anchor_y + display_offset(w_entry, mirror).y
				segment.position = Vector2(base_x, pos_y)
			add_child(segment)
			_wall_segments.append(segment)

func _paint_tower() -> void:
	## The arrow tower that shoots every round. KB battle.md 12.3 puts it outside
	## the active cells on the defender's side in the first row, and in the DOS
	## capture the castle stone rises to y=5 at the arena's edge. Its art is
	## keep%02d, not a wall section: the keep dir is the only one that carries a
	## missile to fire.
	_tower = Sprite2D.new()
	_tower.name = "Tower"
	_tower.centered = false
	_tower.z_index = FLOOR_Z + Hex.ROWS + 1
	add_child(_tower)
	var entry := _spec_entry(_keep_spec, TOWER_SPRITE)
	if entry.is_empty():
		return
	_tower.texture = load(_keep_dir + String(entry.file)) as Texture2D
	_tower.flip_h = defender_side == 0
	var width := float(Vector2i(entry.get("size", Vector2i.ZERO)).x)
	_tower.position = Vector2(0.0 if defender_side == 0 else 640.0 - width, TOWER_TOP)

func _paint_catapult() -> void:
	_catapult_shadow = Sprite2D.new()
	_catapult_shadow.name = "CatapultShadow"
	_catapult_shadow.centered = false
	_catapult_shadow.self_modulate = Color(1, 1, 1, SHADOW_ALPHA)
	_catapult_shadow.z_index = 97
	add_child(_catapult_shadow)

	_catapult = Sprite2D.new()
	_catapult.name = "Catapult"
	_catapult.centered = false
	_catapult.z_index = 98
	add_child(_catapult)

	_set_catapult_frame(0)

static func catapult_shadow_frame(catapult_frame: int) -> int:
	return CATAPULT_SHADOW_RELEASE if catapult_frame == CATAPULT_RELEASE_FRAME else CATAPULT_SHADOW_REST

func _set_catapult_frame(frame: int) -> void:
	var anchor := _catapult_anchor()
	var mirror := defender_side == 0
	if _catapult != null:
		_set_sprite(_catapult, ART + "catapult/", _catapult_spec, frame,
				anchor, mirror)
	if _catapult_shadow != null:
		var shadow_frame := catapult_shadow_frame(frame)
		_set_sprite(_catapult_shadow, ART + "catapult/", _catapult_spec, shadow_frame,
				anchor, mirror)

func _catapult_anchor() -> Vector2:
	if defender_side == 0:
		return Vector2(640.0 - CATAPULT_ANCHOR.x, CATAPULT_ANCHOR.y)
	return CATAPULT_ANCHOR

func _wall_anchor(row: int) -> Vector2:
	return Hex.to_pixel(Hex.wall_col(defender_side), row, origin, step)

func _floor_cols() -> Array:
	## Pave the courtyard behind the wall: columns beyond the wall column up to
	## one column past the grid edge (since a 78px hex against 77px pitch needs
	## an extra column to cover the screen boundary).
	var wall := Hex.wall_col(defender_side)
	return (range(wall + 1, Hex.COLS + 1) if defender_side == 1 else range(-1, wall))

func wall_sprite(row: int) -> Sprite2D:
	return _walls[row] if row >= 0 and row < _walls.size() else null

func wall_segment_sprite(row: int) -> Sprite2D:
	return _wall_segments[row] if row >= 0 and row < _wall_segments.size() else null

func wall_patch_sprite(row: int) -> Sprite2D:
	return _wall_patches[row] if row >= 0 and row < _wall_patches.size() else null

func catapult_sprite() -> Sprite2D:
	return _catapult

func catapult_shadow_sprite() -> Sprite2D:
	return _catapult_shadow

func set_wall_hp(row: int, hp: int) -> void:
	## A section has two hit points and three looks. Intact it is the hoarded
	## tower; one hit in it swaps to the same tower with its top blown off
	## (id10), so a shot that does not breach still shows on screen; breached it
	## is a hole - the tower stops drawing, leaving an opening in the wall for
	## attackers to pass through (DOS capture 2026-09-18).
	## Breached sections reveal a ground rubble patch (id5) so the opening connects
	## to the castle courtyard floor without leaving clear grass.
	var sprite := wall_sprite(row)
	if sprite == null:
		return
	if row >= 0 and row < _wall_hps.size():
		_wall_hps[row] = hp
	sprite.visible = hp > 0
	var patch := wall_patch_sprite(row)
	if patch != null:
		patch.visible = hp <= 0
	_update_wall_segments()
	if hp <= 0:
		return
	_set_sprite(sprite, _castle_dir, _castle_spec,
			WALL_SECTION if hp >= 2 else WALL_DAMAGED,
			_wall_anchor(row), defender_side == 0)

func _update_wall_segments() -> void:
	## In authentic HOMM1 (heroes.exe 0xc2bce), each surviving tower i (i in 0..3)
	## draws its own downward connecting wall segment to row i+1. When tower i
	## is breached, its downward segment i disappears; the tower above it (i-1)
	## keeps segment i-1 intact.
	for i in range(Hex.ROWS - 1):
		if i < _wall_segments.size() and _wall_segments[i] != null:
			_wall_segments[i].visible = (i < _wall_hps.size() and _wall_hps[i] > 0)

func play_catapult(row: int, wall_remaining_hp: int) -> void:
	## The arm swings, lets the rock go at the release frame, and the boulder
	## flies in an arc to the section it was aimed at. On impact, an explosion
	## cloud blooms and the damaged/rubble wall section is revealed underneath.
	## Finally the catapult arm lowers and reloads with a new rock.
	if _catapult == null:
		set_wall_hp(row, wall_remaining_hp)
		return
	if _catapult_audio != null:
		_catapult_audio.play()
	if not instant:
		await _animate_catapult(0, CATAPULT_RELEASE_FRAME + 1)
		await _fly_boulder(row)
		if _impact_audio != null:
			_impact_audio.play()
		await _play_cloud(row, wall_remaining_hp)
		await _reload_catapult_animated()
	else:
		_reload_catapult()
		set_wall_hp(row, wall_remaining_hp)
		if _impact_audio != null:
			_impact_audio.play()

func _animate_catapult(first: int, last: int, reload: bool = false) -> void:
	for frame in range(first, last + 1):
		if _catapult == null or not is_inside_tree():
			return
		_set_catapult_frame(frame)
		await get_tree().create_timer(CATAPULT_FRAME_TIME).timeout
	if reload:
		_reload_catapult()

func _reload_catapult_animated() -> void:
	for frame in range(CATAPULT_RELEASE_FRAME + 2, CATAPULT_RELOAD_LAST + 1):
		if _catapult == null or not is_inside_tree():
			return
		_set_catapult_frame(frame)
		await get_tree().create_timer(CATAPULT_FRAME_TIME).timeout
	_reload_catapult()

func _reload_catapult() -> void:
	## Frame 0 is the loaded pose, rock in the bucket, ready for next round.
	if _catapult == null or not is_inside_tree():
		return
	_set_catapult_frame(0)

func _play_cloud(row: int, wall_remaining_hp: int) -> void:
	if _cloud_spec.is_empty():
		set_wall_hp(row, wall_remaining_hp)
		return
	var clip := _open_cloud(row)
	var breached := wall_remaining_hp <= 0
	for frame in CLOUD_FRAMES:
		if not is_inside_tree():
			break
		_lay_cloud(clip, row, frame, breached)
		if frame == CLOUD_BREAK_FRAME:
			set_wall_hp(row, wall_remaining_hp)
		await get_tree().create_timer(CLOUD_FRAME_TIME).timeout
	set_wall_hp(row, wall_remaining_hp)
	clip.queue_free()

func _open_cloud(row: int) -> Control:
	## The cropped window the impact draws into, with its three puff sprites.
	var window := cloud_window(row)
	var clip := Control.new()
	clip.name = "ImpactCloud"
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.position = window.position
	clip.size = window.size
	clip.z_index = 450
	add_child(clip)
	for i in 3:
		var puff := Sprite2D.new()
		puff.centered = false
		clip.add_child(puff)
	return clip

func _lay_cloud(clip: Control, row: int, frame: int, breached: bool = true) -> void:
	var layout := cloud_puffs(row, frame, breached)
	for i in clip.get_child_count():
		var puff := clip.get_child(i) as Sprite2D
		puff.visible = i < layout.size()
		if i < layout.size():
			_set_sprite(puff, ART + "cloud/", _cloud_spec, int(layout[i].frame),
					layout[i].anchor - clip.position, defender_side == 0)

func show_cloud_frame(row: int, frame: int, breached: bool = true) -> void:
	## Freeze one frame of the impact on screen, to compare against a capture.
	_lay_cloud(_open_cloud(row), row, frame, breached)

func cloud_window(row: int) -> Rect2:
	## The part of the screen the impact is drawn into, mirrored with the castle.
	var top := maxf(0.0, row * step.y + CLOUD_WINDOW_TOP)
	var bottom := minf(CLOUD_WINDOW_MAX_Y, row * step.y + CLOUD_WINDOW_BOTTOM)
	var left := CLOUD_WINDOW_X.x
	var right := CLOUD_WINDOW_X.y
	if defender_side == 0:
		left = 640.0 - CLOUD_WINDOW_X.y
		right = 640.0 - CLOUD_WINDOW_X.x
	return Rect2(left, top, right - left, bottom - top)

func cloud_puffs(row: int, frame: int, breached: bool = true) -> Array:
	## The sprites DOS draws for one frame of the impact on a section: a list of
	## {frame, anchor}, one to three long. When breached (clearing the section),
	## rows 1 to 3 stack three puffs; row 0 raises the first one and row 4 has only
	## two. When only damaging the top of the wall (not breached), DOS heroes.exe
	## (0xc2ccd, checking 0x664 != -1 at 0xc2dbb) draws only the first puff at the top.
	var mirror := defender_side == 0
	var entry := _wall_anchor(row)
	var puffs: Array = []
	var first_dx := -15.0 if mirror else 15.0
	var first_dy := -20.0 if row == 0 else -36.0
	puffs.append({"frame": frame, "anchor": entry + Vector2(first_dx, first_dy)})
	if not breached:
		return puffs
	if row == Hex.ROWS - 1:
		puffs.append({"frame": frame,
				"anchor": entry + Vector2(0.0 if mirror else 15.0, 8.0)})
		return puffs
	var second_dx: float
	var third_dx: float
	if (row & 1) == 1:
		second_dx = 0.0 if mirror else 8.0
		third_dx = -40.0 if mirror else -32.0
	else:
		second_dx = -28.0 if mirror else -8.0
		third_dx = 20.0 if mirror else 40.0
	puffs.append({"frame": frame, "anchor": entry + Vector2(second_dx, 40.0)})
	if frame > 0:
		puffs.append({"frame": frame - 1, "anchor": entry + Vector2(third_dx, 60.0)})
	return puffs

## Where the rock leaves the arm, and where it lands on a section: a test can
## pin the flight without watching it.
func catapult_launch() -> Vector2:
	var anchor := _catapult_anchor()
	var launch := CATAPULT_LAUNCH
	if defender_side == 0:
		launch.x = -launch.x
	return anchor + launch

func wall_impact(row: int) -> Vector2:
	return _wall_anchor(row) + WALL_IMPACT

func _fly_boulder(row: int) -> void:
	## A thrown rock travels in an arc and spins on the way, which is what the
	## three boulder frames are for.
	var boulder := Sprite2D.new()
	boulder.name = "Boulder"
	boulder.centered = true
	boulder.z_index = 400
	add_child(boulder)
	_boulder = boulder
	_boulder_from = catapult_launch()
	_boulder_to = wall_impact(row)
	_boulder_step(0.0)
	var tween := create_tween()
	tween.tween_method(_boulder_step, 0.0, 1.0, BOULDER_FLIGHT_TIME)
	await tween.finished
	_boulder = null
	boulder.queue_free()

func _boulder_step(t: float) -> void:
	if _boulder == null:
		return
	var frame := int(t * BOULDER_FLIGHT_TIME / BOULDER_SPIN_TIME) % BOULDER_FRAMES
	if frame < _boulder_textures.size() and _boulder_textures[frame] != null:
		_boulder.texture = _boulder_textures[frame]
	else:
		_boulder.texture = load(ART + "boulder/%04d.png" % frame) as Texture2D
	_boulder.position = _boulder_from.lerp(_boulder_to, t) \
			+ Vector2(0.0, -BOULDER_ARC * sin(PI * t))

## Fire the tower's missile at `target_pos`, the target stack's feet on screen.
## Passing nothing keeps the sound-only behaviour used by headless runs.
func play_tower_shot(target_pos: Vector2 = Vector2.INF) -> void:
	if _tower_audio != null:
		_tower_audio.play()
	if instant or _tower == null or target_pos == Vector2.INF:
		return
	await _fly_tower_shot(target_pos + CHEST_HEIGHT)

func tower_slit() -> Vector2:
	var size := Vector2i(_spec_entry(_keep_spec, TOWER_SPRITE).get("size", Vector2i.ZERO))
	var slit := TOWER_SLIT
	if defender_side == 0:
		slit.x = float(size.x) - TOWER_SLIT.x
	return _tower.position + slit

## Which of the three fixed angles the tower's missile is drawn at. The art is
## drawn for a shot leaving a right-hand tower, so it mirrors with the castle.
static func tower_shot_frame(flight: Vector2) -> int:
	var angle := absf(rad_to_deg(Vector2(absf(flight.x), flight.y).angle()))
	if angle >= 60.0:
		return TOWER_SHOT_STEEP
	if angle >= 25.0:
		return TOWER_SHOT_DIAGONAL
	return TOWER_SHOT_FLAT

func _fly_tower_shot(to: Vector2) -> void:
	var from := tower_slit()
	var flight := to - from
	var entry := _spec_entry(_keep_spec, tower_shot_frame(flight))
	if entry.is_empty():
		return
	var shot := Sprite2D.new()
	shot.name = "TowerShot"
	shot.centered = true
	shot.z_index = 400
	shot.texture = load(_keep_dir + String(entry.file)) as Texture2D
	shot.flip_h = defender_side == 0
	shot.position = from
	add_child(shot)
	var tween := create_tween()
	tween.tween_property(shot, "position", to,
			maxf(0.08, flight.length() / TOWER_SHOT_SPEED))
	await tween.finished
	shot.queue_free()

func _set_sprite(sprite: Sprite2D, dir: String, spec: Dictionary,
		frame: int, anchor: Vector2, mirror: bool) -> void:
	var entry := _spec_entry(spec, frame)
	if entry.is_empty():
		return
	sprite.texture = load(dir + String(entry.file)) as Texture2D
	sprite.flip_h = mirror
	sprite.position = anchor + display_offset(entry, mirror)

func _clip_below_sky(sprite: Sprite2D) -> void:
	## Crop the rows of a ground sprite that DOS leaves under the sky strip.
	var cut := SKY_STRIP_HEIGHT - sprite.position.y
	if sprite.texture == null or cut <= 0.0:
		return
	var size := sprite.texture.get_size()
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0.0, cut, size.x, size.y - cut)
	sprite.position.y += cut

static func display_offset(entry: Dictionary, mirror: bool) -> Vector2:
	var offset := Vector2(entry.get("offset", Vector2i.ZERO))
	if mirror:
		var size: Vector2i = entry.get("size", Vector2i.ZERO)
		offset.x = -offset.x - float(size.x)
	return offset

static func _spec_entry(spec: Dictionary, frame: int) -> Dictionary:
	for entry: Dictionary in spec.get("sprites", []):
		if int(entry.get("id", -1)) == frame:
			return entry
	return {}

func _audio(node_name: String, path: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.stream = load(path) as AudioStream
	add_child(player)
	return player
