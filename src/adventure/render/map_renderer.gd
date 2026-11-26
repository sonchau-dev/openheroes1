class_name MapRenderer
extends TileMapLayer

## Paints a MapData onto this TileMapLayer using a TileSetBuilder tileset.

func render(map: MapData) -> void:
	clear()
	if map == null:
		push_error("MapRenderer: null map")
		return
	tile_set = TileSetBuilder.build()
	var at := Autotiler.create()
	if at == null:
		push_error("MapRenderer: autotiler unavailable")
		return
	for y in map.height:
		for x in map.width:
			var pos := Vector2i(x, y)
			var ov: Variant = map.tile_overrides.get(pos, null)
			if ov is Dictionary:
				# Manual per-cell control wins.
				var tile_id := int((ov as Dictionary).get("tile", map.get_tile(x, y)))
				var coords := TileSetBuilder.tile_to_atlas_coords(tile_id)
				var alt := TileSetBuilder.alt_id(bool((ov as Dictionary).get("flipH", false)), bool((ov as Dictionary).get("flipV", false)))
				set_cell(pos, TileSetBuilder.TERRAIN_SOURCE_ID, coords, alt)
				continue
			var r := at.resolve(map, x, y)
			var coords := TileSetBuilder.tile_to_atlas_coords(r.tile)
			var alt := TileSetBuilder.alt_id(r.flip_h, r.flip_v)
			set_cell(pos, TileSetBuilder.TERRAIN_SOURCE_ID, coords, alt)

func get_rendered_tile(pos: Vector2i) -> int:
	var coords := get_cell_atlas_coords(pos)
	return TileSetBuilder.atlas_coords_to_tile(coords)
