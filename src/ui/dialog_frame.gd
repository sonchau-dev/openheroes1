## Mirrored buybuild frame pieces shared by the evntwin-style dialogs.
## Plain script with static funcs (no class_name): callers preload it.
## The left half of every row is the right half flipped; the two halves
## meet at local x=151 in the TextureRect dialogs and x=143 in the Sprite2D
## town dialogs (buyspell.bin / rcrthero.bin).

const BUYBUILD := UiKit.ART + "buybuild/"

static func add_segment(parent: Control, texture_path: String, y: float, flip: bool) -> void:
	var texture := load(texture_path) as Texture2D
	if texture == null:
		return
	var segment := TextureRect.new()
	segment.texture = texture
	segment.position = Vector2(151 - texture.get_width() if flip else 151, y)
	segment.flip_h = flip
	segment.size = texture.get_size()
	segment.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	segment.stretch_mode = TextureRect.STRETCH_KEEP
	segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(segment)

## Same row, STRETCH_SCALE and no missing-texture guard, as the older dialogs built it.
static func add_segment_scaled(parent: Control, texture_path: String, y: float, flip: bool) -> void:
	var texture := load(texture_path) as Texture2D
	var segment := TextureRect.new()
	segment.texture = texture
	if flip:
		segment.position = Vector2(151 - texture.get_width(), y)
		segment.flip_h = true
	else:
		segment.position = Vector2(151, y)
	segment.size = texture.get_size()
	segment.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	segment.stretch_mode = TextureRect.STRETCH_SCALE
	segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(segment)

## evntwin layouts reserve 78 rows for BUYBUILD frame 0, while the extracted
## PNG contains only rows 0..76. Preserve all source coordinates and duplicate
## its matching final row into y=77 so the shadow cannot show through the seam.
static func add_top_seam_fill(parent: Control) -> void:
	var source := load(BUYBUILD + "0000.png") as Texture2D
	if source == null:
		return
	var final_row := AtlasTexture.new()
	final_row.atlas = source
	final_row.region = Rect2(0, source.get_height() - 1, source.get_width(), 1)
	for flip: bool in [true, false]:
		var segment := TextureRect.new()
		segment.name = "TopSeamFillLeft" if flip else "TopSeamFillRight"
		segment.texture = final_row
		segment.position = Vector2(151 - source.get_width() if flip else 151, 77)
		segment.flip_h = flip
		segment.size = Vector2(source.get_width(), 1)
		segment.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		segment.stretch_mode = TextureRect.STRETCH_KEEP
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(segment)

static func add_middle_continuation(parent: Control, y: float, height: float) -> void:
	var source := load(BUYBUILD + "0001.png") as Texture2D
	if source == null:
		return
	var cropped := AtlasTexture.new()
	cropped.atlas = source
	cropped.region = Rect2(0, 0, source.get_width(), height)
	for flip: bool in [true, false]:
		var segment := TextureRect.new()
		segment.texture = cropped
		segment.position = Vector2(151 - source.get_width() if flip else 151, y)
		segment.flip_h = flip
		segment.size = Vector2(source.get_width(), height)
		segment.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		segment.stretch_mode = TextureRect.STRETCH_KEEP
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(segment)

## One mirrored buybuild row as Sprite2Ds: the right half begins at local x=143 and the
## trim-cropped left half ends there, exactly as encoded by rcrthero.bin.
static func add_piece(root: Node, frame_pos: Vector2, frame: int, local_y: int) -> void:
	var tex := UiKit.load_texture(BUYBUILD + "%04d.png" % frame)
	for mirrored: bool in [true, false]:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.centered = false
		sprite.flip_h = mirrored
		sprite.position = frame_pos + Vector2(143 - tex.get_width() if mirrored else 143, local_y)
		root.add_child(sprite)

static func fill_top_seam(root: Node, frame_pos: Vector2) -> void:
	var tex := UiKit.load_texture(BUYBUILD + "0000.png")
	if tex == null:
		return
	var final_row := AtlasTexture.new()
	final_row.atlas = tex
	final_row.region = Rect2(0, tex.get_height() - 1, tex.get_width(), 1)
	for mirrored: bool in [true, false]:
		var sprite := Sprite2D.new()
		sprite.texture = final_row
		sprite.centered = false
		sprite.flip_h = mirrored
		sprite.position = frame_pos + Vector2(143 - tex.get_width() if mirrored else 143, 77)
		root.add_child(sprite)
