class_name UiKit
extends RefCounted

## Shared UI constants and factory helpers.
##
## Centralizes asset paths, font resolution, TextureRect/Sprite2D instantiation,
## and Label construction across dialogs and screens.

const ART := "res://assets/art/"
const FONT := ART + "font/"
const SMALL_FONT := ART + "smalfont/"

const FONT_BIG := FONT
const FONT_SMALL := SMALL_FONT
const SMALL_FONT_DIR := SMALL_FONT


# --- Fonts -------------------------------------------------------------------

static func font_normal() -> FontFile:
	return Homm1Font.load_font(FONT)


static func font_small() -> FontFile:
	return Homm1Font.load_font(SMALL_FONT)


static func font() -> FontFile:
	return font_normal()


static func font_big() -> FontFile:
	return font_normal()


static func small_font() -> FontFile:
	return font_small()


# --- Textures and Sprites ----------------------------------------------------

static func load_texture(path: String) -> Texture2D:
	var rel := path.trim_prefix(ART)
	if rel != path and MapArtResolver.has_atlas_entry(rel):
		var atlas_tex := MapArtResolver.get_atlas_texture(rel)
		if atlas_tex != null:
			return atlas_tex
	return load(path) as Texture2D


static func texture_rect(path: String, pos: Vector2 = Vector2.ZERO, flip_h: bool = false) -> TextureRect:
	var tr := TextureRect.new()
	var tex := load_texture(path)
	tr.texture = tex
	tr.position = pos
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if flip_h:
		tr.flip_h = true
		if tex != null:
			tr.size = tex.get_size()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
	return tr


static func add_texture(parent: Node, path: String, pos: Vector2 = Vector2.ZERO, flip_h: bool = false) -> TextureRect:
	var tr := texture_rect(path, pos, flip_h)
	if parent != null:
		parent.add_child(tr)
	return tr


static func add_tex(parent: Node, path: String, pos: Vector2 = Vector2.ZERO) -> TextureRect:
	return add_texture(parent, path, pos)


static func sprite(path: String, pos: Vector2 = Vector2.ZERO, z: int = 0) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = load_texture(path)
	s.centered = false
	s.position = pos
	if z != 0:
		s.z_index = z
	return s


static func add_sprite(parent: Node, path: String, pos: Vector2 = Vector2.ZERO, z: int = 0, node_name: String = "") -> Sprite2D:
	var s := sprite(path, pos, z)
	if node_name != "":
		s.name = node_name
	if parent != null:
		parent.add_child(s)
	return s


# --- Labels ------------------------------------------------------------------

static func create_label(
		text: String = "",
		pos: Vector2 = Vector2.ZERO,
		size: Vector2 = Vector2.ZERO,
		font: Font = null,
		color: Color = Color8(240, 240, 240),
		halign: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER,
		valign: VerticalAlignment = VERTICAL_ALIGNMENT_TOP,
		outline_size: int = 0,
		outline_color: Color = Color.BLACK,
		line_spacing: int = -1,
		wrap: bool = false) -> Label:
	var lbl := Label.new()
	# Autowrap has to be on BEFORE the text is assigned. A Label's minimum
	# width is the unwrapped text width, so a size applied afterwards is
	# clamped up to it; turning autowrap on later leaves the label that
	# wide and the copy runs out past its panel.
	if wrap:
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.position = pos
	lbl.horizontal_alignment = halign
	lbl.vertical_alignment = valign
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := font if font != null else font_normal()
	if f != null:
		lbl.add_theme_font_override("font", f)
		if "fixed_size" in f and f.fixed_size > 0:
			lbl.add_theme_font_size_override("font_size", f.fixed_size)
	if size != Vector2.ZERO:
		lbl.size = size
	lbl.add_theme_color_override("font_color", color)
	if outline_size > 0:
		lbl.add_theme_color_override("font_outline_color", outline_color)
		lbl.add_theme_constant_override("outline_size", outline_size)
	if line_spacing >= 0:
		lbl.add_theme_constant_override("line_spacing", line_spacing)
	# The text goes in last: the label's minimum size (and the width a
	# wrapped label wraps at) is measured from the font and the size that
	# are already in place.
	lbl.text = text
	return lbl


static func add_label(
		parent: Node,
		text: String = "",
		pos: Vector2 = Vector2.ZERO,
		size: Vector2 = Vector2.ZERO,
		font: Font = null,
		color: Color = Color8(240, 240, 240),
		halign: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER,
		valign: VerticalAlignment = VERTICAL_ALIGNMENT_TOP,
		node_name: String = "",
		outline_size: int = 0,
		outline_color: Color = Color.BLACK,
		line_spacing: int = -1) -> Label:
	var lbl := create_label(text, pos, size, font, color, halign, valign, outline_size, outline_color, line_spacing)
	if node_name != "":
		lbl.name = node_name
	if parent != null:
		parent.add_child(lbl)
		if size != Vector2.ZERO:
			lbl.size = size
	return lbl


static func add_label_rect(
		parent: Node,
		text: String,
		rect: Rect2,
		font: Font = null,
		color: Color = Color8(240, 240, 240),
		halign: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER,
		valign: VerticalAlignment = VERTICAL_ALIGNMENT_TOP,
		node_name: String = "",
		line_spacing: int = -1) -> Label:
	return add_label(parent, text, rect.position, rect.size, font, color, halign, valign, node_name, 0, Color.BLACK, line_spacing)


static func add_boxed_label(
		parent: Control,
		node_name: String,
		text: String,
		rect: Rect2,
		font: FontFile = null,
		wrap: bool = false,
		line_spacing: int = 0) -> Label:
	var box := Control.new()
	box.name = node_name + "Box"
	box.position = rect.position
	box.size = rect.size
	if parent != null:
		parent.add_child(box)

	var lbl := Label.new()
	lbl.name = node_name
	# Autowrap first: a Label's minimum width is the unwrapped text width, so
	# assigning the text first would clamp the label to that width and the
	# copy would run out past its box.
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	lbl.text = text
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var f := font if font != null else font_normal()
	if f != null:
		lbl.add_theme_font_override("font", f)
		lbl.add_theme_font_size_override("font_size", f.fixed_size)
	if line_spacing != 0:
		lbl.add_theme_constant_override("line_spacing", line_spacing)
	lbl.add_theme_color_override("font_color", Color8(240, 240, 240))
	box.add_child(lbl)
	return lbl
