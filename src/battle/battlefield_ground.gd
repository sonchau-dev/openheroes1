class_name BattlefieldGround
extends RefCounted

## Paints the visible terrain independently from the invisible 7x5 rules grid.
## The original fills the whole battlefield; grid cells are never exposed as a
## board silhouette.

const ART := "res://assets/art/"
const SHIP_BG := ART + "boat_bkg.png"

# A siege uses the mountain horizon rather than the field one: three DOS siege
# captures on the cleared grass arena all show mtnwgrsf while a field battle
# five tiles away on the same grass shows frstwgrs (2026-09-17). Sieges are
# always fought on grass (see Battle._ground_terrain).
## Battle terrain name -> [ground tile dir, field horizon, siege horizon]. The
## ground and obstacle sets share the terrain's name (dirt uses the dgrass set,
## as its obstacles do); siege strips exist only for grass, dirt and snow, so
## the other terrains keep their one strip.
const TERRAIN_ART := {
	"grass": ["grass", "frstwgrs", "mtnwgrsf"],
	"dirt": ["dgrass", "frstwdrt", "mtnwdrtf"],
	"snow": ["snow", "snowfrst", "snowmtnf"],
	"swamp": ["swamp", "swamp", "swamp"],
	"lava": ["lava", "lava", "lava"],
	"desert": ["desert", "desert", "desert"],
}
const GROUND_OFFSET := Vector2(-39, -79)   # grass.xtl/spec.json, full tiles 4-10
const FIELD_TOP := 102
const FIELD_BOTTOM := 460

## The logical combat board is only 7x5, but terrain extends beyond its cells.
## Two extra left columns cover shifted odd rows; the sixth painted row fills
## the lower tips of row 4 down to the status bar.
const GROUND_COL_MIN := -2
const GROUND_COL_MAX := 7
const GROUND_ROW_MIN := 0
const GROUND_ROW_MAX := 5

## Plain tiles are deliberately weighted more heavily than decorated variants.
const GROUND_VARIANTS := [4, 4, 5, 5, 6, 6, 7, 7, 8, 9, 10]

## Which horizon strip a battlefield gets.
static func background_path(battlefield_kind: StringName, siege: bool,
		terrain: String = "grass") -> String:
	if battlefield_kind == &"ship":
		return SHIP_BG
	var art: Array = TERRAIN_ART.get(terrain.to_lower(), TERRAIN_ART["grass"])
	return ART + "%s_bkg.png" % art[2 if siege else 1]

static func ground_dir(terrain: String) -> String:
	var art: Array = TERRAIN_ART.get(terrain.to_lower(), TERRAIN_ART["grass"])
	return ART + "%s.xtl/" % art[0]

static func paint(parent: Node, origin: Vector2, step: Vector2,
		terrain: String = "grass") -> Control:
	var ground := ground_dir(terrain)
	# Clip terrain to the flat horizon seam and the top of the status bar.
	var field := Control.new()
	field.name = "PaintedGround"
	field.position = Vector2(0, FIELD_TOP)
	field.size = Vector2(640, FIELD_BOTTOM - FIELD_TOP)
	field.clip_contents = true
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(field)

	for row in range(GROUND_ROW_MIN, GROUND_ROW_MAX + 1):
		for col in range(GROUND_COL_MIN, GROUND_COL_MAX + 1):
			var id := variant_id(col, row)
			var tex := load(ground + "%04d.png" % id) as Texture2D
			if tex == null:
				continue
			var feet := Hex.to_pixel(col, row, origin, step)
			var sprite := Sprite2D.new()
			sprite.texture = tex
			sprite.centered = false
			sprite.position = feet + GROUND_OFFSET - field.position
			sprite.z_index = row
			field.add_child(sprite)
	return field

## Stable per-cell art choice: deterministic screenshots without a visibly
## repeated single tile.
static func variant_id(col: int, row: int) -> int:
	var mixed := posmod(col * 37 + row * 61 + col * row * 17 + 5, GROUND_VARIANTS.size())
	return GROUND_VARIANTS[mixed]
