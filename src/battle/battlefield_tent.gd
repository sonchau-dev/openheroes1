class_name BattlefieldTent
extends RefCounted

## Renders a hero's authentic class tent and player-color banner. The attacker's
## tent stands at the left edge and is clickable (General's Options); the
## defender's is the same art mirrored about the field centre, which is where the
## DOS siege capture puts it: its banner reads x 560..586 against the attacker
## banner's 48..81 (2026-09-17). Only the letter stays unflipped so it reads.
## HeroModel.crest_idx is color*4 + class, where both values are 0..3.

const TENT := UiKit.ART + "tent/%04d.png"
const BODY_BASE := Vector2(0, 92)
const BANNER_POS := Vector2(48, 155)
const BODY_Y_OFFSETS := [0, 0, 18, 31]   # tent/spec.json ids 0-3
const LETTER_OFFSETS := [Vector2(2, 0), Vector2(4, 0), Vector2(3, 0), Vector2.ZERO]
const LETTER_BASE := Vector2(8, 16)
# The defender's tent is the attacker's layout mirrored about the field centre
# and one row pitch lower. Matched against the DOS siege captures (2026-09-17,
# 2026-10-11): the body sits flush with the right screen edge, so its x is
# 640 minus the sprite's own width (class widths differ, 72..76), and the
# banner lands at 560,235 (the attacker's banner at 48,155 plus one 80 px row).
# The first measurement put them at 562 and 557, which left a 3-6 px strip of
# floor between the tent and the screen edge.
const DEFENDER_BODY_Y := 172
const DEFENDER_BANNER_POS := Vector2(560, 235)
const SCREEN_WIDTH := 640
# The attacker's tent base is at Y ≈ 255 (between Row 1 at 219 and Row 2 at 299).
# It paints above Row 0 and Row 1 (z 100..101) so top units and their shadows
# never draw over the tent, while staying behind foreground creatures in Row 2+ (z >= 102).
const ATTACKER_BODY_Z := 101
const ATTACKER_BANNER_Z := 101

# The defender's tent base is at Y ≈ 335 (between Row 2 at 299 and Row 3 at 379).
# It sits on the castle floor (z 50..54) and paints above Rows 0..2 (z 100..102),
# while staying behind foreground creatures in Row 3+ (z >= 103).
const DEFENDER_BODY_Z := 102
const DEFENDER_BANNER_Z := 102

static func indices(crest_idx: int) -> Dictionary:
	var safe := clampi(crest_idx, 0, 15)
	var hero_class := safe % 4
	var color := safe / 4
	return {
		"class": hero_class,
		"color": color,
		"body": hero_class,
		"banner": 4 + color,
		"letter": 8 + hero_class,
	}

static func paint(parent: Node, crest_idx: int, pressed: Callable,
		hovered: Callable = Callable(), exited: Callable = Callable()) -> void:
	var ids := indices(crest_idx)
	var hero_class: int = ids["class"]
	var body_pos := BODY_BASE + Vector2(0, BODY_Y_OFFSETS[hero_class])
	_add_clickable(parent, ids["body"], body_pos, ATTACKER_BODY_Z, pressed, hovered, exited)
	# Battlefield creatures depth-sort at z=100+row. Keep the banner in front of
	# row 0/1 background units but behind row 2+ foreground units.
	_add_clickable(parent, ids["banner"], BANNER_POS, ATTACKER_BANNER_Z, pressed, hovered, exited)
	_add_sprite(parent, ids["letter"],
			BANNER_POS + LETTER_BASE + LETTER_OFFSETS[hero_class], ATTACKER_BANNER_Z)

static func paint_defender(parent: Node, crest_idx: int, pressed: Callable = Callable(),
		hovered: Callable = Callable(), exited: Callable = Callable()) -> void:
	var ids := indices(crest_idx)
	var hero_class: int = ids["class"]
	var body_tex := UiKit.load_texture(TENT % ids["body"])
	var body_x := SCREEN_WIDTH - (body_tex.get_width() if body_tex != null else 0)
	var body_pos := Vector2(body_x, DEFENDER_BODY_Y + BODY_Y_OFFSETS[hero_class])
	if pressed.is_valid():
		_add_clickable(parent, ids["body"], body_pos, DEFENDER_BODY_Z, pressed, hovered, exited, true)
		_add_clickable(parent, ids["banner"], DEFENDER_BANNER_POS, DEFENDER_BANNER_Z, pressed, hovered, exited, true)
	else:
		_add_sprite(parent, ids["body"], body_pos, DEFENDER_BODY_Z, true)
		_add_sprite(parent, ids["banner"], DEFENDER_BANNER_POS, DEFENDER_BANNER_Z, true)
	# The class letter is mirrored back so it still reads, and the banner is
	# symmetric, so the same inset works from either edge.
	var inset: Vector2 = LETTER_BASE + LETTER_OFFSETS[hero_class]
	_add_sprite(parent, ids["letter"], DEFENDER_BANNER_POS + inset,
			DEFENDER_BANNER_Z)

static func _add_clickable(parent: Node, id: int, pos: Vector2, z: int,
		pressed: Callable, hovered: Callable, exited: Callable,
		mirrored: bool = false) -> void:
	var tex := UiKit.load_texture(TENT % id)
	if tex == null:
		return
	var button := TextureButton.new()
	button.name = "TentPart%d%s" % [id, "Mirrored" if mirrored else ""]
	button.texture_normal = tex
	button.position = pos
	button.z_index = z
	button.focus_mode = Control.FOCUS_NONE
	button.flip_h = mirrored
	var image := tex.get_image()
	if image != null:
		if mirrored:
			image = image.duplicate()
			image.flip_x()
		var mask := BitMap.new()
		mask.create_from_image_alpha(image)
		button.texture_click_mask = mask
	if pressed.is_valid():
		button.pressed.connect(pressed)
	if hovered.is_valid():
		button.mouse_entered.connect(hovered)
	if exited.is_valid():
		button.mouse_exited.connect(exited)
	parent.add_child(button)

static func _add_sprite(parent: Node, id: int, pos: Vector2, z: int,
		mirrored: bool = false) -> void:
	var sprite := UiKit.add_sprite(parent, TENT % id, pos, z, "TentPart%d%s" % [id, "Mirrored" if mirrored else ""])
	if sprite != null and mirrored:
		sprite.flip_h = true
