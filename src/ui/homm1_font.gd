class_name Homm1Font
extends RefCounted

## Builds a Godot FontFile from an extracted HOMM1 bitmap-font sprite dir
## (e.g. res://assets/art/font or .../smalfont) and its baked glyph strip.
##
## The two HOMM1 fonts are ICN sprite files of 96 glyphs = ASCII 32..127,
## glyph id i -> char (32 + i). Each glyph is a mono PNG (white ink + alpha)
## so it tints to any color via a Label's font color. spec.json gives, per
## glyph: offsetX (left bearing), offsetY (top relative to baseline, negative
## = above), and width/height (ink box).
##
## Usage:
##   var font := Homm1Font.load_font("res://assets/art/font/")
##   label.add_theme_font_override("font", font)
##   label.add_theme_font_size_override("font_size", font.fixed_size)
##
## Results are cached per directory.

const GAP := 1  ## extra pixels of advance between glyphs (HOMM1 is tight)

static var _cache: Dictionary = {}


static func load_font(font_dir: String) -> FontFile:
	if not font_dir.ends_with("/"):
		font_dir += "/"
	if _cache.has(font_dir):
		return _cache[font_dir]

	var spec := SpecLoader.load_spec(font_dir + "spec.json")
	if spec.sprites.is_empty():
		push_error("Homm1Font: no glyphs in %s" % font_dir)
		return null
	# The extractor bakes the glyph strip (tools/extract/bake.gd).
	var atlas_path := atlas_path_for(font_dir)
	# Fresh from the extractor the atlas has only its stub .import and no uid
	# until Godot imports it, as in the tool processes tools/setup.gd runs.
	# Exports carry no raw PNG, so this never hides the font in a build.
	if FileAccess.file_exists(atlas_path) and ResourceLoader.get_resource_uid(atlas_path) == ResourceUID.INVALID_ID:
		return null
	var atlas :=load(atlas_path) as Image if ResourceLoader.exists(atlas_path) else null
	if atlas == null:
		push_error("Homm1Font: %s is missing; rerun tools/extract.gd" % atlas_path)
		return null
	# LA8 makes Godot treat the font as monochrome, so a Label's font_color
	# tints it; an RGBA8 atlas reads as a fixed-color (emoji-style) font.
	if atlas.get_format() != Image.FORMAT_LA8:
		atlas.convert(Image.FORMAT_LA8)
	var lay := layout(spec, func(file: String) -> bool: return ResourceLoader.exists(font_dir + file))
	var line_h: int = lay.ascent + lay.descent

	# Assemble the FontFile.
	var font := FontFile.new()
	font.fixed_size = line_h
	var sz := Vector2i(line_h, 0)
	font.set_texture_image(0, sz, 0, atlas)

	for g: Dictionary in lay.glyphs:
		var ch: int = g.char
		var advance: int = g.ox + g.w + GAP
		font.set_glyph_advance(0, line_h, ch, Vector2(advance, 0))
		# Only blank glyphs (space) have no ink: give them advance only, or
		# TextServer draws a ".notdef" box where the space should be.
		if g.ink:
			font.set_glyph_offset(0, sz, ch, Vector2(g.ox, g.oy))
			font.set_glyph_size(0, sz, ch, Vector2(g.w, g.h))
			font.set_glyph_texture_idx(0, sz, ch, 0)
			font.set_glyph_uv_rect(0, sz, ch, Rect2(g.x, 0, g.w, g.h))

	font.set_cache_ascent(0, line_h, lay.ascent)
	font.set_cache_descent(0, line_h, lay.descent)

	_cache[font_dir] = font
	return font


## The baked glyph strip of a font directory: art/font/ -> art/font_atlas.png.
static func atlas_path_for(font_dir: String) -> String:
	return font_dir.trim_suffix("/") + "_atlas.png"


## Where each glyph sits in the atlas strip, and the line metrics:
## {glyphs: [{char, file, w, h, ox, oy, x, ink}], width, height, ascent, descent}.
## Glyphs with ink sit side by side with a 1 px gap. `has_file.call(file)`
## says whether a glyph's PNG exists.
static func layout(spec: Dictionary, has_file: Callable) -> Dictionary:
	var glyphs: Array = []
	var atlas_w := 0
	var atlas_h := 1
	var ascent := 0   # max pixels above baseline (= max -offsetY)
	var descent := 0  # max pixels below baseline (= max offsetY + height)
	for sp in spec.sprites:
		var w: int = sp.size.x
		var h: int = sp.size.y
		var ox: int = sp.offset.x
		var oy: int = sp.offset.y
		var ch := 32 + int(sp.id)
		ascent = max(ascent, -oy)
		descent = max(descent, oy + h)
		# Char 32 (glyph id 0) is the space: the extractor emits a stray box
		# for it, so never draw it; it contributes advance only.
		var ink: bool = w > 0 and h > 0 and ch != 32 and bool(has_file.call(sp.file))
		glyphs.append({"char": ch, "file": String(sp.file), "w": w, "h": h, "ox": ox, "oy": oy, "x": atlas_w, "ink": ink})
		if ink:
			atlas_w += w + 1
			atlas_h = max(atlas_h, h)
	return {"glyphs": glyphs, "width": maxi(atlas_w, 1), "height": atlas_h,
			"ascent": ascent, "descent": descent}


## Greedy word wrap on measured width, the way the original fits text into a
## .bin box: a word stays on the line while the line is no wider than
## max_width. A Label's own autowrap needs about 5 px more than that, so it
## breaks lines the original keeps whole. Explicit newlines are kept.
static func wrap(font: Font, text: String, max_width: float) -> String:
	var lines: Array[String] = []
	for paragraph in text.split("\n"):
		var current := ""
		# Keep empty tokens: the catalog texts put two spaces after a sentence.
		for word in paragraph.split(" "):
			var candidate := word if current == "" else current + " " + word
			if current != "" and font.get_string_size(candidate).x > max_width:
				lines.append(current)
				current = word
			else:
				current = candidate
		lines.append(current)
	return "\n".join(lines)
