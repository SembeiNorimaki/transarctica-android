class_name TerrainService
extends Node
# The gameplay terrain of each tile: how much it costs to enter, how high it is, whether it blocks
# sight, how much cover it gives. All of it is data (TerrainTypes): this service only remembers
# which type each tile has. Tiles nobody set have `default_type`.
#
# Independent of the projection (isometric or cartesian): it only knows tile coordinates.

## Tiles whose terrain changed. Caches (navigation, vision) listen to this.
signal terrain_changed(tiles: Array[Vector2i])

var default_type := TerrainTypes.DEFAULT_TYPE

var _types: Dictionary = {} # Vector2i -> String (only tiles that differ from the default)


#region setting
func set_tile(tile: Vector2i, terrain_type: String) -> void:
    if not _store(tile, terrain_type):
        return
    terrain_changed.emit([tile] as Array[Vector2i])

func set_rect(rect: Rect2i, terrain_type: String) -> void:
    if not TerrainTypes.exists(terrain_type):
        push_error("TerrainService: unknown terrain type '%s'" % terrain_type)
        return
    var changed: Array[Vector2i] = []
    for y in range(rect.position.y, rect.end.y):
        for x in range(rect.position.x, rect.end.x):
            if _store(Vector2i(x, y), terrain_type):
                changed.append(Vector2i(x, y))
    if not changed.is_empty():
        terrain_changed.emit(changed)

## Reads the type of every painted cell from a custom data layer of the TileSet (a String).
## Cells with an empty or unknown value keep the default type. Returns how many tiles were set.
func load_from_layer(layer: TileMapLayer, custom_data_name := "terrain") -> int:
    if layer == null or layer.tile_set == null or not layer.tile_set.has_custom_data_layer_by_name(custom_data_name):
        push_error("TerrainService: the layer has no custom data layer '%s'" % custom_data_name)
        return 0
    var changed: Array[Vector2i] = []
    for cell in layer.get_used_cells():
        var data := layer.get_cell_tile_data(cell)
        var terrain_type := str(data.get_custom_data(custom_data_name)) if data != null else ""
        if terrain_type == "":
            continue
        if not TerrainTypes.exists(terrain_type):
            push_warning("TerrainService: unknown terrain type '%s' at %s" % [terrain_type, cell])
            continue
        if _store(cell, terrain_type):
            changed.append(cell)
    if not changed.is_empty():
        terrain_changed.emit(changed)
    return changed.size()

func clear() -> void:
    var changed: Array[Vector2i] = []
    for tile: Vector2i in _types:
        changed.append(tile)
    _types.clear()
    if not changed.is_empty():
        terrain_changed.emit(changed)
#endregion


#region queries
func get_type(tile: Vector2i) -> String:
    return _types.get(tile, default_type)

func get_def(tile: Vector2i) -> Dictionary:
    return TerrainTypes.get_def(get_type(tile))

func is_walkable(tile: Vector2i) -> bool:
    return bool(get_def(tile).get("walkable", true))

## Movement points to enter the tile. INF if nobody can.
func get_cost(tile: Vector2i) -> float:
    var def := get_def(tile)
    if not def.get("walkable", true):
        return INF
    return float(def.get("cost", 1.0))

func get_elevation(tile: Vector2i) -> int:
    return int(get_def(tile).get("elevation", 0))

func blocks_vision(tile: Vector2i) -> bool:
    return bool(get_def(tile).get("blocks_vision", false))

func get_cover(tile: Vector2i) -> int:
    return int(get_def(tile).get("cover", CoverLevel.NONE))

## Cheapest cost of entering any tile (a lower bound for pathfinding heuristics).
func get_min_cost() -> float:
    return TerrainTypes.min_cost()
#endregion


# Returns true if the tile's type actually changed.
func _store(tile: Vector2i, terrain_type: String) -> bool:
    if not TerrainTypes.exists(terrain_type):
        push_error("TerrainService: unknown terrain type '%s'" % terrain_type)
        return false
    if get_type(tile) == terrain_type:
        return false
    if terrain_type == default_type:
        _types.erase(tile)
    else:
        _types[tile] = terrain_type
    return true
