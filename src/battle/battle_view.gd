class_name BattleView
extends Node2D

## Owns the visual node (Creature + count Label) for each BattleStack and plays
## its animations. When `instant` is true (headless), animations resolve immediately.

# Measured from DOS HOMM1 (DOSBox video capture, rogue walks 155-167 px/s,
# dwarf walks ~158 px/s; gargoyle/sprite flight measured ~177-185 px/s in combat):
# units glide at a constant speed, so diagonal steps take longer than straight ones.
# A straight 77px hex takes ~0.48s walking and ~0.43s flying.
# A 30 fps DOSBox recording (2026-10-11) of a cavalry walking shows the same
# 160 px/s along a row (162 over nine hexes), but the two row-changing steps it
# took crossed their ~84 px in 0.3 to 0.4 s, which a constant 160 px/s would take
# 0.53 s for. Walking therefore moves at 160 px/s across and about 215 px/s down
# or up, and a step lasts as long as the slower axis needs.
const WALK_SPEED := 160.0   # logical px/sec along a row while walking
const WALK_SPEED_Y := 215.0 # logical px/sec between rows while walking
const FLY_SPEED := 180.0    # logical px/sec while flying
const BattleAudioScript := preload("res://src/battle/battle_audio.gd")

static func step_duration(from_px: Vector2, to_px: Vector2, is_flying: bool = false) -> float:
	if is_flying:
		return from_px.distance_to(to_px) / FLY_SPEED
	var delta := (to_px - from_px).abs()
	return maxf(delta.x / WALK_SPEED, delta.y / WALK_SPEED_Y)

var instant: bool = false
var audio: BattleAudio = null
var _audio: BattleAudio = null

const COUNT_BOX_TEXTURE := UiKit.ART + "textbar/0005.png"
const COUNT_BOX_SIZE := Vector2(20, 11)
const COUNT_X := [8.0, -39.0]        # single-cell stack, indexed by side
const COUNT_X_WIDE := [75.0, -95.0]  # two-cell stack, from its anchor
const COUNT_ROW_TOP := [128, 208, 288, 368, 448]

var _origin: Vector2
var _step: Vector2
var _nodes: Dictionary = {}   # BattleStack -> creature/count/status visual nodes

func _init() -> void:
	audio = BattleAudioScript.new()
	audio.name = "BattleAudio"
	add_child(audio)
	_audio = audio

func setup(stacks: Array, origin: Vector2, step: Vector2) -> void:
	_origin = origin
	_step = step
	for s: BattleStack in stacks:
		var feet := Hex.to_pixel(s.hex.x, s.hex.y, origin, step)
		var c := Creature.new()
		c.z_index = 100 + s.hex.y
		add_child(c)
		c.setup(StringName(s.unit))
		c.play(&"idle")
		var badge := _make_count_badge()
		badge.z_index = c.z_index
		badge.position = count_position(s, feet)
		add_child(badge)
		var lbl: Label = badge.get_node("Count")
		lbl.text = str(s.count)
		var status := _make_status_icon()
		status.z_index = c.z_index
		add_child(status)
		_nodes[s] = {
			"creature": c,
			"badge": badge,
			"label": lbl,
			"status": status,
			"status_id": "",
			"status_suppressed": false,
		}
		_apply_facing(s, s.side == 1)
		_sync_status_icon(s)

func _make_count_badge() -> Node2D:
	var badge := Node2D.new()
	UiKit.add_sprite(badge, COUNT_BOX_TEXTURE, Vector2.ZERO)
	var font := UiKit.font_small()
	var lbl := UiKit.add_label(badge, "", Vector2(-2, 2), COUNT_BOX_SIZE + Vector2(4, 0), font, Color.WHITE,
			HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, "Count")
	if font != null:
		# SMALFONT digits ink 7px tall, rising 6px above the baseline. Center
		# that ink in the 11px box: ink top at y=2 -> baseline at y=8. A Label
		# puts the first baseline one ascent below its top edge.
		lbl.position.y = 8.0 - font.get_cache_ascent(0, font.fixed_size)
	return badge

func _make_status_icon() -> TextureRect:
	var status := TextureRect.new()
	status.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	status.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	status.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.visible = false
	return status

## Top-left corner of a stack's count badge, from its anchor cell's feet.
static func count_position(stack: BattleStack, feet: Vector2) -> Vector2:
	var dx: float = COUNT_X_WIDE[stack.side] if stack.wide else COUNT_X[stack.side]
	var row := clampi(stack.hex.y, 0, COUNT_ROW_TOP.size() - 1)
	return Vector2(round(feet.x + dx), COUNT_ROW_TOP[row])

## Place the native-size status art beside the count badge, bottom-aligned one
## pixel above the stack's feet: before the badge on the attacker's side,
## after it on the defender's.
static func status_position(badge: Vector2, feet: Vector2, side: int,
		icon_size: Vector2) -> Vector2:
	var x: float
	if side == 0:
		x = badge.x - icon_size.x - 1.0
	else:
		x = badge.x + COUNT_BOX_SIZE.x + 1.0
	return Vector2(x, feet.y - icon_size.y - 1.0).round()

## Count tags and spell icons stay hidden while this is set; Armageddon hides
## them for the whole spell in the DOS original.
var tags_hidden := false

func set_tags_hidden(on: bool) -> void:
	tags_hidden = on
	for stack: BattleStack in _nodes:
		_nodes[stack].badge.visible = not on and stack.is_alive()
		_sync_status_icon(stack)

func node_for(stack: BattleStack) -> Dictionary:
	return _nodes.get(stack, {})

func _process(_delta: float) -> void:
	for stack: BattleStack in _nodes:
		_sync_status_icon(stack)

## Which outline a stack's lasting effect draws: red for a debuff, blue for a
## buff, none without one or once the stack is dead.
static func status_outline_kind(stack: BattleStack) -> StringName:
	var id := String(stack.active_effect.get("id", ""))
	if id.is_empty() or not stack.is_alive():
		return &""
	return &"hostile" if id in SpellCast.DEBUFFS else &"friendly"

## Mirror the stack's single duration-effect slot as a persistent native spell
## icon beside its count badge. Replacements and removals update automatically.
func _sync_status_icon(stack: BattleStack) -> void:
	if not _nodes.has(stack):
		return
	var n: Dictionary = _nodes[stack]
	var status: TextureRect = n.status
	(n.creature as Creature).set_status_outline(status_outline_kind(stack))
	if bool(n.status_suppressed) or tags_hidden:
		status.visible = false
		return
	var id := String(stack.active_effect.get("id", ""))
	if id.is_empty():
		status.visible = false
		n.status_id = ""
		return
	if String(n.status_id) != id:
		var spell := SpellData.get_spell(id)
		var icon_id := int(spell.get("icon", -1))
		status.texture = UiKit.load_texture(UiKit.ART + "spells/%04d.png" % icon_id) \
				if icon_id >= 0 else null
		n.status_id = id
		if status.texture != null:
			status.size = status.texture.get_size()
	if status.texture != null:
		var feet := Hex.to_pixel(stack.hex.x, stack.hex.y, _origin, _step)
		status.position = status_position(count_position(stack, feet), feet,
				stack.side, status.size)
	status.visible = status.texture != null

## Where a wide stack's sprite origin sits relative to its anchor cell's feet.
## Facing its home side the art spans the anchor and the body cell; facing away
## it is mirrored, so the origin moves to the body cell to cover the same two.
func _wide_shift(stack: BattleStack, left: bool) -> Vector2:
	if stack.wide and left != (stack.side == 1):
		return Vector2(stack.body_dx() * _step.x, 0.0)
	return Vector2.ZERO

func _apply_facing(stack: BattleStack, left: bool) -> void:
	if not _nodes.has(stack):
		return
	var n: Dictionary = _nodes[stack]
	var c: Creature = n.creature
	c.set_facing(left)
	var is_home_facing := (left == (stack.side == 1))
	var tail_hex := stack.hex
	if stack.wide and not is_home_facing:
		tail_hex = stack.hex + Vector2i(stack.body_dx(), 0)
	c.position = Hex.to_pixel(tail_hex.x, tail_hex.y, _origin, _step)
	var home_feet := Hex.to_pixel(stack.hex.x, stack.hex.y, _origin, _step)
	n.badge.position = count_position(stack, home_feet)
	c.z_index = 100 + stack.hex.y
	n.badge.z_index = c.z_index
	n.status.z_index = c.z_index

func refresh(stack: BattleStack) -> void:
	if not _nodes.has(stack):
		return
	var n: Dictionary = _nodes[stack]
	n.label.text = str(stack.count)
	var c: Creature = n.creature
	var is_left := c.scale.x < 0.0
	var is_home_facing := (is_left == (stack.side == 1))
	var tail_hex := stack.hex
	if stack.wide and not is_home_facing:
		tail_hex = stack.hex + Vector2i(stack.body_dx(), 0)
	var feet := Hex.to_pixel(tail_hex.x, tail_hex.y, _origin, _step)
	c.position = feet
	var home_feet := Hex.to_pixel(stack.hex.x, stack.hex.y, _origin, _step)
	n.badge.position = count_position(stack, home_feet)
	n.creature.z_index = 100 + stack.hex.y
	n.badge.z_index = n.creature.z_index
	n.status.z_index = n.creature.z_index
	n.badge.visible = not tags_hidden
	_sync_status_icon(stack)

static func attack_dir(from_hex: Vector2i, to_hex: Vector2i) -> StringName:
	if to_hex.y < from_hex.y:
		return &"attack_up"
	if to_hex.y > from_hex.y:
		return &"attack_down"
	return &"attack_across"

## Walk the stack hex-by-hex or fly directly along `path`
## (waypoints after from_hex, ending at dest).
func play_move(stack: BattleStack, from_hex: Vector2i, path: Array) -> void:
	if not _nodes.has(stack):
		return
	var c: Creature = _nodes[stack].creature
	if path.is_empty():
		refresh(stack)
		return
	# The original contour vanishes as soon as the active unit starts moving.
	c.set_outline(false)
	if instant:
		var last: Vector2i = path[path.size() - 1]
		c.position = Hex.to_pixel(last.x, last.y, _origin, _step)
		refresh(stack)
		return
	# HOMM1 hides the count box while the unit is on the move; refresh() at the
	# end of the walk re-shows it at the destination.
	_nodes[stack].badge.visible = false
	_nodes[stack].status_suppressed = true
	_nodes[stack].status.visible = false
	var is_flyer := stack.is_flying()
	if is_flyer:
		c.z_index = 200   # air depth above ground obstacles and units
	# HOMM1 movement is one continuous walk/flight: the cycle loops while the unit
	# glides along the path at WALK_SPEED (or FLY_SPEED for flyers).
	c.play(&"walk")
	var prev := from_hex
	var prev_px := Hex.to_pixel(prev.x, prev.y, _origin, _step)
	var facing_left := c.scale.x < 0.0
	for hex: Vector2i in path:
		var px := Hex.to_pixel(hex.x, hex.y, _origin, _step)
		# A unit turns only on a step along its row. A step to another row also
		# shifts half a cell sideways, and the DOS cavalry keeps its heading
		# through a run of those; turning on each would flip a wide unit a whole
		# cell back and forth over its neighbours. A flyer crosses rows in one glide.
		if (is_flyer or px.y == prev_px.y) and px.x != prev_px.x \
				and (px.x < prev_px.x) != facing_left:
			facing_left = px.x < prev_px.x
			c.set_facing(facing_left)
			c.position = prev_px + _wide_shift(stack, facing_left)
		var dur := step_duration(prev_px, px, is_flyer)
		var tw := create_tween()
		tw.tween_property(c, "position", px + _wide_shift(stack, facing_left), dur)
		var sound_tw: Tween = null
		if is_flyer and dur > 0.0:
			var steps := maxi(1, Hex.distance(prev.x, prev.y, hex.x, hex.y))
			var interval := dur / float(steps)
			sound_tw = create_tween()
			for i in range(steps):
				sound_tw.tween_callback(func(): _audio.play_unit(stack.unit, &"move"))
				if i < steps - 1:
					sound_tw.tween_interval(interval)
		else:
			_audio.play_unit(stack.unit, &"move")
		await tw.finished
		if sound_tw != null:
			sound_tw.kill()
		if not is_flyer:
			# Keep the source row's depth throughout the step. Switching at tween
			# start makes tall units overlap units ahead before their feet arrive.
			c.z_index = 100 + hex.y
		prev = hex
		prev_px = px
	_apply_facing(stack, stack.side == 1)
	c.play(&"idle")
	_nodes[stack].status_suppressed = false
	refresh(stack)

## Returns true if `to_stack` is horizontally to the left of `from_stack` in pixel space.
## Uses the centroid of occupied cells for wide or single-cell units.
func _target_is_left(from_stack: BattleStack, to_stack: BattleStack) -> bool:
	var from_x := 0.0
	for c: Vector2i in from_stack.cells():
		from_x += Hex.to_pixel(c.x, c.y, _origin, _step).x
	from_x /= float(from_stack.cells().size())
	var to_x := 0.0
	for c: Vector2i in to_stack.cells():
		to_x += Hex.to_pixel(c.x, c.y, _origin, _step).x
	to_x /= float(to_stack.cells().size())
	return to_x < from_x

## Play the attacker's swing. When `hold` is true the unit freezes on the final
## attack frame (caller releases it with play_idle once the defender's reaction
## has played) so attacker and defender animate together rather than in sequence.
## Line attackers (Cyclops, Phoenix, Dragon) reach a second unit only with the
## last frame, so they play it only when `line_hit` is true.
func play_attack(attacker: BattleStack, defender: BattleStack, hold: bool = false,
		line_hit: bool = true) -> void:
	if not _nodes.has(attacker):
		return
	var c: Creature = _nodes[attacker].creature
	_apply_facing(attacker, _target_is_left(attacker, defender))
	if instant:
		if not hold:
			play_idle(attacker)
		return
	_audio.play_unit(attacker.unit, &"attack")
	var anim := attack_dir(attacker.hex, defender.hex)
	if attacker.two_cell_attack and not line_hit \
			and c.has_anim(StringName(String(anim) + Creature.SHORT_SUFFIX)):
		anim = StringName(String(anim) + Creature.SHORT_SUFFIX)
	c.play(anim, hold)
	await c.animation_finished
	if not hold:
		play_idle(attacker)

# Measured from DOS HOMM1 (DOSBox video capture, two centaur shots on the
# 640x480 battlefield): ~2050-2940 px/s -> a cross-field shot lands in ~0.2s.
# Two Archer shots in the 2026-09-26 Arena Spells recording agree: one ~40 px
# step per 1/60 s tick.
const ARROW_SPEED := 2500.0   # px/sec projectile flight

# Missile geometry from heroes.exe's shot routine (file 0x8e241): the missile
# leaves 80 px in front of the shooter's feet and 90 px up, raised or lowered
# by its sprite's angle (data 0x1e768), and aims 90 px above the feet of the
# target's front cell. Fitted to the two recorded Archer shots to ~1.5 px.
const MISSILE_REACH := 80
const MISSILE_HEIGHT := 90
const MISSILE_LAUNCH_DY := {5: -20, 6: -15, 7: 0, 8: 15, 9: 20}

## Which way a shooter turns for its shot. heroes.exe decides it from the two
## anchor cells (0x8e31e-0x8e348), not from where the sprites sit: right for a
## target at a higher column, or at the same column when the shooter stands on
## an even row; left otherwise.
static func shoot_faces_left(from_hex: Vector2i, to_hex: Vector2i) -> bool:
	return to_hex.x < from_hex.x or (to_hex.x == from_hex.x and (from_hex.y & 1) == 1)

## Horizontal launch offset from the shooter's feet: 80 px the way the shot
## turned it (heroes.exe 0x8e534-0x8e550 reads the facing byte set just above).
static func missile_reach(left: bool) -> int:
	return -MISSILE_REACH if left else MISSILE_REACH

## ATK missile frame (5 steep up .. 9 steep down) for a shot `dcol` columns and
## `drow` rows away. The original picks it from the cell gaps, not the
## on-screen angle (heroes.exe 0x8e4c1-0x8e522).
static func missile_frame(dcol: int, drow: int) -> int:
	var dc := absi(dcol)
	var dr := absi(drow)
	var dir := signi(drow)
	var frame := 7
	if dr > 1:
		frame += dir
	if dc <= 3:
		if dr > 2:
			frame += dir
		if dr == 1:
			frame += dir
	return frame

## Every position the missile is drawn at, in order: 2 x max(column gap, row
## gap) equal steps, each truncated toward zero, with the path shifted back
## half a step so the draws sit evenly between launch and target. The target
## itself is never drawn. A zero column or row gap holds that axis still,
## halfway between launch and target (heroes.exe 0x8e5c7-0x8e6ab, loop at
## 0x8e782).
static func missile_path(launch: Vector2i, target: Vector2i, dcol: int, drow: int) -> Array[Vector2i]:
	var n := 2 * maxi(absi(dcol), absi(drow))
	var out: Array[Vector2i] = []
	if n == 0:
		return out
	var sx := 0 if dcol == 0 else (target.x - launch.x) / n
	var sy := 0 if drow == 0 else (target.y - launch.y) / n
	var start := Vector2i(_missile_start(launch.x, sx, target.x, n),
			_missile_start(launch.y, sy, target.y, n))
	for i in n:
		out.append(start + Vector2i(sx, sy) * i)
	return out

static func _missile_start(from: int, step: int, to: int, n: int) -> int:
	var first := from + step
	return from + (first + to - n * step) / 2 - first

## Play a ranged attack: the shooter's four ATK frames (reach, nock, draw,
## release for a bow; pick up, raise, throw for a Troll's rock) in that order
## whatever the direction, held on the release pose while the missile flies.
## Units without shoot art fall back to the melee swing so the action still reads.
func play_shoot(attacker: BattleStack, defender: BattleStack) -> void:
	if not _nodes.has(attacker):
		return
	var c: Creature = _nodes[attacker].creature
	var left := shoot_faces_left(attacker.hex, defender.hex)
	_apply_facing(attacker, left)
	if instant:
		return
	if not c.has_anim(&"shoot"):
		await play_attack(attacker, defender, true)
		return
	_audio.play_unit(attacker.unit, &"shoot")
	c.play(&"shoot", true)   # hold the release pose while the missile flies
	await c.animation_finished
	await _fly_projectile(c, attacker, defender, left)

func _fly_projectile(c: Creature, attacker: BattleStack, defender: BattleStack,
		left: bool) -> void:
	# A two-cell target is aimed at its front cell (heroes.exe 0x8e408).
	var aim := defender.hex
	if defender.wide:
		aim = defender.hex + Vector2i(defender.body_dx(), 0)
	var dcol := aim.x - attacker.hex.x
	var drow := aim.y - attacker.hex.y
	var frame := missile_frame(dcol, drow)
	var art := c.projectile(frame)
	if art.is_empty():
		return
	var feet := Vector2i(Hex.to_pixel(attacker.hex.x, attacker.hex.y, _origin, _step))
	var launch := feet + Vector2i(missile_reach(left),
			MISSILE_LAUNCH_DY[frame] - MISSILE_HEIGHT)
	var target := Vector2i(Hex.to_pixel(aim.x, aim.y, _origin, _step)) - Vector2i(0, MISSILE_HEIGHT)
	var path := missile_path(launch, target, dcol, drow)
	if path.is_empty():
		return
	# The art depicts rightward flight; it is mirrored only for a shot at a
	# lower column, as in the original.
	var arrow := Sprite2D.new()
	arrow.texture = art.tex
	arrow.centered = false
	arrow.offset = Vector2(art.off)
	arrow.scale.x = -1.0 if dcol < 0 else 1.0
	arrow.position = Vector2(path[0])
	arrow.z_index = 400
	add_child(arrow)
	var last := Vector2(path[path.size() - 1])
	var tw := create_tween()
	tw.tween_property(arrow, "position", last, arrow.position.distance_to(last) / ARROW_SPEED)
	await tw.finished
	arrow.queue_free()

## Release a held pose (e.g. after play_attack(..., hold=true)) back to idle.
## Freeze a stack in its wince pose until play_idle() releases it.
func hold_wince(stack: BattleStack) -> void:
	if instant or not _nodes.has(stack):
		return
	var c: Creature = _nodes[stack].creature
	if c.has_anim(&"wince"):
		c.play(&"wince", true)

func play_idle(stack: BattleStack) -> void:
	if not _nodes.has(stack):
		return
	var c: Creature = _nodes[stack].creature
	_apply_facing(stack, stack.side == 1)
	if not instant:
		c.play(&"idle")

# heroes.exe draws the effect it plays on a stack in the stack's own draw
# routine (0x8d200, state 3: 0x8d7c8 then 0x8d912-0x8d9b8), at the creature's
# anchor but, for a two-cell unit, half a cell toward the way it faces
# (0x8d918-0x8d942). Morale, luck and spells cast on the stack (0x914c1) and
# the hit splash (0x90e9c, banks from data 0x1f0d4) all draw this way. The same block moves the count box to the measured +75 /
# -95 of COUNT_X_WIDE, which ties its x to our creature anchor.
const WIDE_EFFECT_SHIFT := 39.0

## Where an effect played on `stack` is anchored: the creature's feet, moved
## half a cell forward for a two-cell unit so it lands over the middle of the
## body rather than its tail.
func effect_anchor(stack: BattleStack) -> Vector2:
	if not _nodes.has(stack):
		return Hex.to_pixel(stack.hex.x, stack.hex.y, _origin, _step)
	var c: Creature = _nodes[stack].creature
	var pos := c.position
	if stack.wide:
		pos.x += -WIDE_EFFECT_SHIFT if c.scale.x < 0.0 else WIDE_EFFECT_SHIFT
	return pos

## Effect anchor for a stack at an arbitrary hex (e.g. departure/arrival during teleport).
## Same spot as effect_anchor: the middle of a two-cell body, whichever way it faces.
func effect_anchor_for_hex(stack: BattleStack, h: Vector2i) -> Vector2:
	var pos := Hex.to_pixel(h.x, h.y, _origin, _step)
	if stack.wide:
		pos.x += stack.body_dx() * WIDE_EFFECT_SHIFT
	return pos

## Hide or show creature, badge, and status icon together (e.g. during teleport in-transit).
func set_stack_hidden(stack: BattleStack, hidden: bool) -> void:
	if not _nodes.has(stack):
		return
	var n: Dictionary = _nodes[stack]
	n.status_suppressed = hidden
	n.status.visible = not hidden and String(stack.active_effect.get("id", "")) != "" and not tags_hidden
	n.badge.visible = not hidden and not tags_hidden and stack.is_alive()
	(n.creature as Creature).visible = not hidden

## Native morale birds hang from effect_anchor by their ICN offsets (frame
## y=-176..-200). Keep that source geometry intact.
## In heroes.exe (0x8ab26 / 0xd57c4), the engine plays the fanfare and waits
## for the entire audio sample to finish playing before advancing combat.
## The birds run at about 5.3 frames a second: a 30 fps DOSBox recording
## (2026-10-11) shows the good-morale bird's ten frames lasting 1.9 s, one
## sprite change every 0.17 to 0.2 s. The falling bird of bad morale lasts the
## same 1.9 s (second recording, same day).
const MORALE_FPS := 5.3

func play_morale(stack: BattleStack, good: bool) -> void:
	var sound_path := UiKit.ART + ("GOODMRLE.wav" if good else "BADMRLE.wav")
	var voice := _play_one_shot(sound_path)
	if instant or not _nodes.has(stack):
		return
	var c: Creature = _nodes[stack].creature
	# Native bad morale holds the creature's wince pose while the falling bird
	# plays, then lowers it back to idle. This is a visual reaction only:
	# BADMRLE.wav already supplies the event sound.
	if not good:
		c.play(&"wince", true)
	var effect := Effect.new()
	add_child(effect)
	effect.fps = MORALE_FPS
	effect.play(effect_anchor(stack), &"moraleg" if good else &"moraleb")
	await effect.finished
	if not good and is_instance_valid(c):
		c.play(&"idle")
	if voice != null and is_instance_valid(voice) and voice.playing:
		await voice.finished

## Luck animation anchored to creature feet: the rainbow (rainbluk) with
## GOODLUCK for good luck, the cloud (cloudluk) with BADLUCK for bad
## (heroes.exe 0x907f2, banks 0x16 and 0x17 of the table at data 0x1f114).
## The engine awaits the audio sample (0xd57c4).
## The rainbow runs at about 5 frames a second, not the 12 of the hit splashes:
## two DOS recordings (30 fps, 2026-10-11) show its ten frames lasting 2.0 s
## and 2.07 s, from the status line to the last frame. The cloud is assumed to
## share the rate; no bad luck was caught.
const LUCK_FPS := 5.0

func play_luck(stack: BattleStack = null, good: bool = true) -> void:
	var voice := _play_one_shot(UiKit.ART + ("GOODLUCK.wav" if good else "BADLUCK.wav"))
	if instant or stack == null or not _nodes.has(stack):
		return
	var effect := Effect.new()
	add_child(effect)
	effect.fps = LUCK_FPS
	effect.play(effect_anchor(stack), &"rainbluk" if good else &"cloudluk")
	await effect.finished
	if voice != null and is_instance_valid(voice) and voice.playing:
		await voice.finished

func _play_one_shot(path: String) -> AudioStreamPlayer:
	if instant or _audio == null or not _audio.enabled:
		return null
	return _audio.play_one_shot(path)

## Authentic duration for the struck creature's wince reaction when no splash
## effect plays, matching retail heroes.exe (0x8c88b..0x8c8f5 / 0xd57c4) where
## the engine plays WINCE%02d.82M (averaging ~0.46s) and holds the wince pose
## for ~35 frames at 70 FPS (~0.50s) before restoring idle stance.
const WINCE_DURATION := 0.45

## Play a struck stack's reaction. Both surviving and destroyed stacks use the
## native STD wince pose. A lethal hit remains visible until the hit effect's
## concealment frame, then disappears beneath the effect while its dissolve
## frames continue. The extracted WIP bank is a walk-in-place cycle, not a death
## animation, and must never play when a unit dies.
func play_losses(stack: BattleStack, hit: StringName = &"physical", splash: bool = true) -> void:
	if not _nodes.has(stack):
		return
	refresh(stack)
	var dead := not stack.is_alive()
	if instant:
		if dead:
			_remove(stack)
		return
	var c: Creature = _nodes[stack].creature
	splash = splash or dead   # a kill always splashes
	var voice: AudioStreamPlayer = null
	if _audio != null:
		voice = _audio.play_unit(stack.unit, &"wince")
	var eff: Effect = null
	if splash:
		eff = _play_hit_splash(stack, hit)
	if dead:
		_nodes[stack].badge.visible = false
		_nodes[stack].status.visible = false
		c.play(&"wince", true)
		await c.animation_finished
		# Let the pain pose linger until the blood fully covers it. Remove it
		# beneath that opaque frame, then preserve the dissolve timing before
		# advancing the battle controller.
		if eff != null and is_instance_valid(eff) and not eff.is_queued_for_deletion():
			if not eff.has_reached_body_hide_frame():
				await eff.body_hide_frame_started
		_remove(stack)
		if eff != null and is_instance_valid(eff) and not eff.is_queued_for_deletion():
			await eff.finished
		if voice != null and is_instance_valid(voice) and voice.playing:
			await voice.finished
		return
	# In heroes.exe (0x8c88b..0x8c8f5 / 0xd57c4), the creature holds its wince pose
	# while the wince audio sample and hit effect play, lasting ~0.45-0.50s before
	# returning to idle.
	c.play(&"wince", true)
	if eff != null:
		await eff.finished
	else:
		var loop := Engine.get_main_loop() as SceneTree
		if loop != null:
			await loop.create_timer(WINCE_DURATION).timeout
		else:
			await c.animation_finished
	if voice != null and is_instance_valid(voice) and voice.playing:
		await voice.finished
	c.play(&"idle")

## React a whole group to one hit in the same rendered frame: Armageddon, area
## spells, and a hydra's bite on every adjacent stack. The rules damage has
## already been applied; this updates every badge, starts every hit effect and
## wince together, and only then waits for the shared reaction to finish. A
## stack splashes only when it loses creatures, as in play_losses; a hit may
## override that with `splash`, and a kill always splashes.
func play_losses_batch(hits: Array, hit: StringName = &"fire") -> void:
	var affected: Array[BattleStack] = []
	var effects: Array[Effect] = []
	var voices: Array[AudioStreamPlayer] = []
	for result: Dictionary in hits:
		var stack: BattleStack = result.stack
		if not _nodes.has(stack):
			continue
		affected.append(stack)
		refresh(stack)
		var dead := not stack.is_alive()
		if instant:
			if dead:
				_remove(stack)
			continue
		var c: Creature = _nodes[stack].creature
		var voice := _audio.play_unit(stack.unit, &"wince")
		if voice != null:
			voices.append(voice)
		if bool(result.get("splash", int(result.get("killed", 0)) > 0)) or dead:
			effects.append(_play_hit_splash(stack, hit))
		if dead:
			_nodes[stack].badge.visible = false
			_nodes[stack].status.visible = false
		c.play(&"wince", true)
	if instant:
		return
	# All effects use the same native frame bank and begin in this loop's first
	# frame. The last-added effect also processes last, so its completion means
	# every stack has finished its reaction.
	var last: Effect = effects.back() if not effects.is_empty() else null
	if last != null and is_instance_valid(last) and not last.is_queued_for_deletion():
		await last.finished
	else:
		var loop := Engine.get_main_loop() as SceneTree
		if loop != null:
			await loop.create_timer(WINCE_DURATION).timeout
	for voice: AudioStreamPlayer in voices:
		if is_instance_valid(voice) and voice.playing:
			await voice.finished
	for stack: BattleStack in affected:
		if not _nodes.has(stack):
			continue
		if not stack.is_alive():
			_remove(stack)
		else:
			var c: Creature = _nodes[stack].creature
			c.play(&"idle")

## Spawn a one-shot damage splash at the struck stack's effect_anchor,
## returning the Effect so the caller can await its `finished` signal. Runs
## alongside the wince reaction and frees itself when its frames finish.
func _play_hit_splash(stack: BattleStack, hit: StringName) -> Effect:
	var eff := Effect.new()
	eff.z_index = 250 + stack.hex.y
	add_child(eff)
	eff.play(effect_anchor(stack), hit)
	return eff

func _remove(stack: BattleStack) -> void:
	if not _nodes.has(stack):
		return
	var n: Dictionary = _nodes[stack]
	n.creature.queue_free()
	n.badge.queue_free()
	n.status.queue_free()
	_nodes.erase(stack)
