class_name MapArtResolver
extends RefCounted

## Overworld scenery assets (mtn32, tree32, obj32-*, rsrc32, town32) are packed
## into a unified single-sheet atlas, allowing WorldStaticCanvas to batch all
## static map decor into a single GPU draw call.

const DIR_TO_ATLAS: Dictionary = {
	"mtn32": "objects",
	"obj32-00": "objects",
	"obj32-01": "objects",
	"obj32-02": "objects",
	"obj32-03": "objects",
	"obj32-04": "objects",
	"obj32-05": "objects",
	"obj32-06": "objects",
	"obj32-07": "objects",
	"rsrc32": "objects",
	"town32": "objects",
	"tree32": "objects",
	"mons32": "mons32",
	"minimon": "minimon",
	"flag32": "flag32",
	"art32": "art32",
	"kngt32": "heroes",
	"barb32": "heroes",
	"sorc32": "heroes",
	"wrlk32": "heroes",
	"boat32": "heroes",
	"b-flag32": "heroes",
	"g-flag32": "heroes",
	"r-flag32": "heroes",
	"y-flag32": "heroes",
	"b-bflg32": "heroes",
	"g-bflg32": "heroes",
	"r-bflg32": "heroes",
	"y-bflg32": "heroes",
	"route": "route",
	"clop32": "clop32",
}

const CELL_SIZE := 34 # 32px max sprite + 2px padding
const ATLAS_W := 1024
const ATLAS_H := 2048

static var _atlas_tex: Texture2D = null
static var _atlas_regions: Dictionary = {} # "tree32/0000.png" -> Rect2
static var _atlas_textures: Dictionary = {} # atlas_name -> Texture2D
static var _all_atlas_regions: Dictionary = {} # atlas_name -> Dictionary
static var _atlas_texture_instances: Dictionary = {} # clean_art -> AtlasTexture
static var _attempted_atlases: Dictionary = {} # atlas_name -> bool

# Shared by every resolver and kept across scene changes: the map scene is
# rebuilt after each town, battle or hero screen, and the art never changes.
static var _texture_cache: Dictionary = {}

static func _get_atlas_name(clean_art: String) -> String:
	var slash := clean_art.find("/")
	if slash == -1:
		return ""
	var dir := clean_art.substr(0, slash)
	return String(DIR_TO_ATLAS.get(dir, ""))

static func has_atlas_entry(art: String) -> bool:
	var clean := art.trim_prefix("res://assets/art/")
	var atlas_name := _get_atlas_name(clean)
	if atlas_name.is_empty():
		return false
	if not _attempted_atlases.has(atlas_name):
		_ensure_atlas_loaded(atlas_name)
	return _all_atlas_regions.get(atlas_name, {}).has(clean)

static func get_atlas_texture(art: String) -> AtlasTexture:
	var clean := art.trim_prefix("res://assets/art/")
	if _atlas_texture_instances.has(clean):
		return _atlas_texture_instances[clean]
	var atlas_name := _get_atlas_name(clean)
	if atlas_name.is_empty():
		return null
	if not _attempted_atlases.has(atlas_name):
		_ensure_atlas_loaded(atlas_name)
	var regions: Dictionary = _all_atlas_regions.get(atlas_name, {})
	if not regions.has(clean):
		return null
	var tex: Texture2D = _atlas_textures.get(atlas_name)
	if tex == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = regions[clean]
	at.resource_path = "res://assets/art/" + clean
	_atlas_texture_instances[clean] = at
	return at

static func _ensure_atlas_loaded(atlas_name: String = "objects") -> void:
	if _attempted_atlases.has(atlas_name):
		return
	_attempted_atlases[atlas_name] = true

	var png_path := "res://assets/art/%s_atlas.png" % atlas_name
	var spec_path := "res://assets/art/%s_atlas.json" % atlas_name

	var tex: Texture2D = null
	if ResourceLoader.exists(png_path):
		tex = load(png_path) as Texture2D
	if tex == null and FileAccess.file_exists(png_path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(png_path))
		if img != null:
			tex = ImageTexture.create_from_image(img)
	if tex != null:
		_atlas_textures[atlas_name] = tex
		if atlas_name == "objects":
			_atlas_tex = tex

	var regions := {}
	var parsed := JsonFile.read_dict(spec_path)
	if not parsed.is_empty():
		var raw_regions: Dictionary = parsed.get("regions", parsed)
		for key: String in raw_regions:
			var r: Array = raw_regions[key]
			if r.size() >= 4:
				regions[key] = Rect2(r[0], r[1], r[2], r[3])
	_all_atlas_regions[atlas_name] = regions
	if atlas_name == "objects":
		_atlas_regions = regions

func texture(art: String) -> Texture2D:
	if not _texture_cache.has(art):
		var at := get_atlas_texture(art)
		if at != null:
			_texture_cache[art] = at
		else:
			_texture_cache[art] = load("res://assets/art/" + art) as Texture2D
	return _texture_cache[art]

func offset(art: String) -> Vector2:
	return Vector2(sprite_spec(art).get("offset", Vector2.ZERO))

func sprite_spec(art: String) -> Dictionary:
	var parts := art.split("/")
	if parts.size() != 2:
		return {}
	return SpecLoader.sprite_by_file("res://assets/art/" + parts[0], parts[1])
