extends RefCounted

## Bake pipeline for derived assets and atlases produced offline by tools/extract.gd.
##
## Offline baking replaces runtime builders that would otherwise rebuild atlases
## on game startup (Map chunk P4, perf audit finding 10).

const SpecLoaderRef := preload("res://src/importer/spec_loader.gd")
const TileSetBuilderRef := preload("res://src/adventure/map/tileset_builder.gd")
const Homm1FontRef := preload("res://src/ui/homm1_font.gd")

const DEFAULT_OBJECT_DIRS: Array[String] = [
	"mtn32", "obj32-00", "obj32-01", "obj32-02", "obj32-03",
	"obj32-04", "obj32-05", "obj32-06", "obj32-07", "rsrc32",
	"town32", "tree32"
]


static func run(out_dir: String, rules: Dictionary, writer: RefCounted) -> void:
	var atlases: Dictionary = rules.get("atlases", {})
	if atlases.is_empty():
		bake_objects_atlas(out_dir, rules, writer)
	else:
		for atlas_name in atlases:
			var atlas_rule: Dictionary = atlases[atlas_name]
			var default_dirs: Array[String] = []
			if atlas_name == "objects":
				default_dirs = DEFAULT_OBJECT_DIRS
			bake_atlas(out_dir, atlas_rule, default_dirs, writer)
	bake_derived(out_dir, rules, writer)


## Packs map scenery and object sprites into a single atlas image and JSON spec.
static func bake_objects_atlas(out_dir: String, rules: Dictionary, writer: RefCounted) -> void:
	var atlas_rule: Dictionary = rules.get("atlases", {}).get("objects", {})
	if not atlas_rule.has("output"):
		atlas_rule["output"] = "objects_atlas"
	bake_atlas(out_dir, atlas_rule, DEFAULT_OBJECT_DIRS, writer)


## Packs sprites from specified directories into an atlas using grid or shelf packing.
static func bake_atlas(out_dir: String, atlas_rule: Dictionary, default_dirs: Array[String], writer: RefCounted) -> void:
	var output_name: String = String(atlas_rule.get("output", ""))
	if output_name.is_empty():
		return
	var dirs: Array = atlas_rule.get("dirs", default_dirs)
	var atlas_w: int = int(atlas_rule.get("width", 1024))
	var atlas_h: int = int(atlas_rule.get("height", 2048))
	var cell_size: int = int(atlas_rule.get("cell_size", 0))
	var padding: int = int(atlas_rule.get("padding", 1))

	if bool(writer.get("dry_run")):
		writer.image("%s.png" % output_name, Image.new())
		writer.json("%s.json" % output_name, {})
		return

	var atlas_img := Image.create(atlas_w, atlas_h, false, Image.FORMAT_RGBA8)
	atlas_img.fill(Color(0, 0, 0, 0))

	var regions := {}

	if cell_size > 0:
		var cols := atlas_w / cell_size
		var cur_col := 0
		var cur_row := 0

		for dir_name_variant in dirs:
			var dir_name := String(dir_name_variant)
			var abs_spec := _abs_path(out_dir, "%s/spec.json" % dir_name)
			if not FileAccess.file_exists(abs_spec):
				continue
			var spec := SpecLoaderRef.load_spec(abs_spec)
			for sprite: Dictionary in spec.get("sprites", []):
				var file: String = sprite.get("file", "")
				if file.is_empty():
					continue
				var abs_file := _abs_path(out_dir, "%s/%s" % [dir_name, file])
				if not FileAccess.file_exists(abs_file):
					continue
				var img := Image.load_from_file(abs_file)
				if img == null:
					continue
				if img.get_format() != Image.FORMAT_RGBA8:
					img.convert(Image.FORMAT_RGBA8)

				var dst_pos := Vector2i(cur_col * cell_size + padding, cur_row * cell_size + padding)
				var w := img.get_width()
				var h := img.get_height()
				atlas_img.blit_rect(img, Rect2i(0, 0, w, h), dst_pos)

				var key := "%s/%s" % [dir_name, file]
				regions[key] = [dst_pos.x, dst_pos.y, w, h]

				cur_col += 1
				if cur_col >= cols:
					cur_col = 0
					cur_row += 1
	else:
		var cur_x := padding
		var cur_y := padding
		var shelf_h := 0

		for dir_name_variant in dirs:
			var dir_name := String(dir_name_variant)
			var abs_spec := _abs_path(out_dir, "%s/spec.json" % dir_name)
			if not FileAccess.file_exists(abs_spec):
				continue
			var spec := SpecLoaderRef.load_spec(abs_spec)
			for sprite: Dictionary in spec.get("sprites", []):
				var file: String = sprite.get("file", "")
				if file.is_empty():
					continue
				var abs_file := _abs_path(out_dir, "%s/%s" % [dir_name, file])
				if not FileAccess.file_exists(abs_file):
					continue
				var img := Image.load_from_file(abs_file)
				if img == null:
					continue
				if img.get_format() != Image.FORMAT_RGBA8:
					img.convert(Image.FORMAT_RGBA8)

				var w := img.get_width()
				var h := img.get_height()
				if cur_x + w + padding > atlas_w:
					cur_x = padding
					cur_y += shelf_h + padding
					shelf_h = 0

				var dst_pos := Vector2i(cur_x, cur_y)
				atlas_img.blit_rect(img, Rect2i(0, 0, w, h), dst_pos)

				var key := "%s/%s" % [dir_name, file]
				regions[key] = [dst_pos.x, dst_pos.y, w, h]

				cur_x += w + padding
				if h > shelf_h:
					shelf_h = h

	writer.image("%s.png" % output_name, atlas_img)
	writer.json("%s.json" % output_name, {
		"width": atlas_w,
		"height": atlas_h,
		"cell_size": cell_size,
		"padding": padding,
		"regions": regions
	})


const DARKEN_MAP: Dictionary = {
	Color8(252, 252, 228): Color8(248, 248, 100),
	Color8(252, 252, 176): Color8(244, 232, 52),
	Color8(248, 248, 148): Color8(240, 224, 36),
	Color8(248, 248, 124): Color8(232, 212, 28),
	Color8(248, 248, 100): Color8(224, 200, 20),
	Color8(248, 240, 72): Color8(216, 184, 16),
	Color8(244, 232, 52): Color8(208, 172, 8),
	Color8(240, 224, 36): Color8(200, 156, 4),
	Color8(232, 212, 28): Color8(192, 144, 0),
	Color8(224, 200, 20): Color8(184, 132, 0),
	Color8(216, 184, 16): Color8(176, 120, 0),
	Color8(208, 172, 8): Color8(164, 108, 0),
	Color8(200, 156, 4): Color8(152, 92, 0),
	Color8(192, 144, 0): Color8(136, 80, 0),
	Color8(184, 132, 0): Color8(124, 68, 0),
	Color8(176, 120, 0): Color8(112, 56, 0),
	Color8(164, 108, 0): Color8(100, 44, 0),
	Color8(152, 92, 0): Color8(88, 36, 0),
	Color8(136, 80, 0): Color8(88, 36, 0),
	Color8(124, 68, 0): Color8(88, 36, 0),
	Color8(112, 56, 0): Color8(88, 36, 0),
	Color8(100, 44, 0): Color8(88, 36, 0),
	Color8(88, 36, 0): Color8(88, 36, 0),
}


static func bake_derived(out_dir: String, _rules: Dictionary, writer: RefCounted) -> void:
	bake_hud_frame(out_dir, writer)
	bake_roster_panel(out_dir, writer)
	bake_button_bar(out_dir, writer)
	bake_white_fonts(out_dir, writer)
	bake_terrain_atlas(out_dir, writer)
	bake_fog_atlas(out_dir, writer)
	bake_font_atlases(out_dir, writer)


## Bakes the punched-out adventure HUD frame border from bord.png.
static func bake_hud_frame(out_dir: String, writer: RefCounted) -> void:
	if bool(writer.get("dry_run")):
		writer.image("hud_frame.png", Image.new())
		return
	var abs_bord := _abs_path(out_dir, "bord.png")
	if not FileAccess.file_exists(abs_bord):
		return
	var img := Image.load_from_file(abs_bord)
	if img == null:
		return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var regions: Array[Rect2i] = [Rect2i(16, 16, 448, 448), Rect2i(466, 0, 174, 480)]
	for reg in regions:
		for y in range(reg.position.y, reg.position.y + reg.size.y):
			for x in range(reg.position.x, reg.position.x + reg.size.x):
				var c := img.get_pixel(x, y)
				if c.r == 0.0 and c.g == 0.0 and c.b == 0.0:
					img.set_pixel(x, y, Color(0, 0, 0, 0))
	writer.image("hud_frame.png", img)


## Bakes the horizontally flipped roster locator background from portxtra/0000.png.
static func bake_roster_panel(out_dir: String, writer: RefCounted) -> void:
	if bool(writer.get("dry_run")):
		writer.image("portxtra/0000_flipped.png", Image.new())
		return
	var abs_port := _abs_path(out_dir, "portxtra/0000.png")
	if not FileAccess.file_exists(abs_port):
		return
	var img := Image.load_from_file(abs_port)
	if img == null:
		return
	img.flip_x()
	writer.image("portxtra/0000_flipped.png", img)


## Bakes disabled button states for advbtns.
static func bake_button_bar(out_dir: String, writer: RefCounted) -> void:
	for slot in 6:
		var frame_idx := slot * 2
		var out_name := "advbtns/%04d_disabled.png" % frame_idx
		if bool(writer.get("dry_run")):
			writer.image(out_name, Image.new())
			continue
		var abs_btn := _abs_path(out_dir, "advbtns/%04d.png" % frame_idx)
		if not FileAccess.file_exists(abs_btn):
			continue
		var img := Image.load_from_file(abs_btn)
		if img == null:
			continue
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a > 0.0 and DARKEN_MAP.has(c):
					var dark: Color = DARKEN_MAP[c]
					img.set_pixel(x, y, Color(dark.r, dark.g, dark.b, c.a))
		writer.image(out_name, img)


## Ensures glyphs in font and smalfont are white ink (R=1, G=1, B=1, A=a).
static func bake_white_fonts(out_dir: String, writer: RefCounted) -> void:
	for font_dir in ["font", "smalfont"]:
		var abs_spec := _abs_path(out_dir, "%s/spec.json" % font_dir)
		if not FileAccess.file_exists(abs_spec):
			continue
		var spec := SpecLoaderRef.load_spec(abs_spec)
		for sp: Dictionary in spec.get("sprites", []):
			var file: String = sp.get("file", "")
			if file.is_empty():
				continue
			var abs_file := _abs_path(out_dir, "%s/%s" % [font_dir, file])
			if not FileAccess.file_exists(abs_file):
				continue
			var img := Image.load_from_file(abs_file)
			if img == null:
				continue
			if img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
			var changed := false
			for y in img.get_height():
				for x in img.get_width():
					var c := img.get_pixel(x, y)
					if c.a > 0.0 and (c.r < 1.0 or c.g < 1.0 or c.b < 1.0):
						img.set_pixel(x, y, Color(1, 1, 1, c.a))
						changed = true
			if changed and not bool(writer.get("dry_run")):
				writer.image("%s/%s" % [font_dir, file], img)


## The startup atlases below replace runtime builders that read each tile back
## from its texture; on a phone each readback stalls the GPU.

## ground32 in the TileSetBuilder layout: water strips in columns 0..4, static
## tiles from column 5. Cells with no tile stay opaque black.
static func bake_terrain_atlas(out_dir: String, writer: RefCounted) -> void:
	var tiles := 0
	while FileAccess.file_exists(_abs_path(out_dir, "ground32/%04d.png" % tiles)):
		tiles += 1
	if tiles == 0:
		return
	if bool(writer.get("dry_run")):
		writer.image("ground32_atlas.png", Image.new())
		return
	var atlas := Image.create(TileSetBuilderRef.ATLAS_WIDTH, TileSetBuilderRef.ATLAS_HEIGHT,
			false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 1))
	for id in tiles:
		var img := Image.load_from_file(_abs_path(out_dir, "ground32/%04d.png" % id))
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		var size := Vector2i(TileSetBuilderRef.TILE * (TileSetBuilderRef.WATER_ANIM_FRAMES
				if id < TileSetBuilderRef.WATER_TILE_COUNT else 1), TileSetBuilderRef.TILE)
		atlas.blit_rect(img, Rect2i(Vector2i.ZERO, size),
				TileSetBuilderRef.tile_to_atlas_coords(id) * TileSetBuilderRef.TILE)
	writer.image("ground32_atlas.png", atlas)


## The four clof32 solid fog tiles side by side (FogLayer.SOLID_TILE_IDS).
static func bake_fog_atlas(out_dir: String, writer: RefCounted) -> void:
	if not FileAccess.file_exists(_abs_path(out_dir, "clof32/0000.png")):
		return
	if bool(writer.get("dry_run")):
		writer.image("clof32_atlas.png", Image.new())
		return
	var atlas := Image.create(32 * 4, 32, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 1))
	for id in 4:
		var path := _abs_path(out_dir, "clof32/%04d.png" % id)
		if not FileAccess.file_exists(path):
			continue
		var img := Image.load_from_file(path)
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		atlas.blit_rect(img, Rect2i(0, 0, 32, 32), Vector2i(id * 32, 0))
	writer.image("clof32_atlas.png", atlas)


## Each font's glyphs in one LA8 strip, in the Homm1Font.layout() order,
## imported as an Image because FontFile takes its pixels, not a texture.
static func bake_font_atlases(out_dir: String, writer: RefCounted) -> void:
	for font_dir in ["font", "smalfont"]:
		var abs_spec := _abs_path(out_dir, "%s/spec.json" % font_dir)
		if not FileAccess.file_exists(abs_spec):
			continue
		var out_name := "%s_atlas.png" % font_dir
		if bool(writer.get("dry_run")):
			writer.image(out_name, Image.new(), true)
			continue
		var dir_path := _abs_path(out_dir, font_dir)
		var lay := Homm1FontRef.layout(SpecLoaderRef.load_spec(abs_spec),
				func(file: String) -> bool: return FileAccess.file_exists("%s/%s" % [dir_path, file]))
		var atlas := Image.create(int(lay.width), int(lay.height), false, Image.FORMAT_RGBA8)
		atlas.fill(Color(1, 1, 1, 0))
		for g: Dictionary in lay.glyphs:
			if not g.ink:
				continue
			var img := Image.load_from_file("%s/%s" % [dir_path, g.file])
			if img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
			atlas.blit_rect(img, Rect2i(0, 0, g.w, g.h), Vector2i(g.x, 0))
		atlas.convert(Image.FORMAT_LA8)
		writer.image(out_name, atlas, true)


static func _abs_path(root: String, rel: String) -> String:
	var joined := root if rel == "" else "%s/%s" % [root.trim_suffix("/"), rel]
	return ProjectSettings.globalize_path(joined) if joined.begins_with("res://") \
		or joined.begins_with("user://") else joined
