extends Node
class_name ExplorationService
# Keeps track of which parts of the map the player has explored and which are visible right now,
# and shows it on a fog TileMapLayer placed above the map. Each fog tile is in one of three states:
#   UNEXPLORED: never seen. Opaque black tile.
#   EXPLORED:   seen before, not visible now. Half transparent tile.
#   VISIBLE:    inside the vision of the player train. No fog (the cell is erased).
# The two sets below are the truth. The tilemap is only a view of them.
#
# The fog grid is FINER than the rails grid (e.g. 64x32 fog tiles over 256x128 rail tiles), so the
# service works with WORLD POSITIONS and converts them with the fog layer's own grid. The trains
# only know the rails grid and are not involved. Each rail tile is covered by subdivision x
# subdivision fog tiles; the subdivision is derived from the two tile sizes.
#
# The fog TileSet must have the same tile shape and layout as the terrain, and the fog layer must be
# offset so its blocks line up with the rail tiles (setup() warns with the exact position to use).

signal tiles_explored(tiles: Array[Vector2i]) # fog tiles seen for the FIRST time (e.g. to discover a city)
signal visibility_changed # the set of visible tiles changed

enum State {UNEXPLORED, EXPLORED, VISIBLE}

@export var vision_radius := 2.0 # in RAIL tiles (can be fractional)
@export var fog_source_id := 0 # source of the fog TileSet
@export var unexplored_atlas := Vector2i(0, 0)
@export var explored_atlas := Vector2i(1, 0)

# Injected by NavigationScene
var fog_layer: TileMapLayer
var grid_service: GridService # the rails grid

var _map_name := ""
var _rail_tiles: Array = []
var _subdivision := 1 # fog tiles per rail tile, along each axis
var _map_tiles := {} # fog tile -> true: every fog tile of the map (the land)
var _explored := {} # fog tile -> true
var _visible := {} # fog tile -> true
var _center := Vector2i.ZERO # fog tile of the last update
var _radius := -1.0 # radius of the last update, in rail tiles
var _has_center := false
var _offsets := {} # fog radius -> Array[Vector2i] (cached disc offsets)


func _ready() -> void:
    GameState.game_saving.connect(_on_game_saving)
    GameState.game_loaded.connect(_on_game_loaded)


#region setup
# Call when a map is loaded, with the cells of its terrain (rail tiles). Everything starts
# unexplored, except what GameState says was explored before in this map.
@warning_ignore("integer_division")
func setup(map_name: String, rail_tiles: Array, on_progress := Callable()) -> void:
    if fog_layer == null or fog_layer.tile_set == null or grid_service == null:
        push_error("ExplorationService: fog_layer (with a TileSet) and grid_service must be injected")
        return
    var fog_size := fog_layer.tile_set.tile_size
    var rail_size := grid_service.tile_size
    var ratio_x := float(rail_size.x) / fog_size.x
    var ratio_y := float(rail_size.y) / fog_size.y
    if rail_size.x % fog_size.x != 0 or rail_size.y % fog_size.y != 0 or not is_equal_approx(ratio_x, ratio_y):
        push_error("ExplorationService: the rails tile size %s must be a whole multiple of the fog tile size %s, the same in x and y" % [rail_size, fog_size])
        return
        

    _subdivision = roundi(ratio_x)
    _map_name = map_name
    _rail_tiles = rail_tiles
    _check_alignment()

    fog_layer.clear()
    _map_tiles.clear()
    _explored.clear()
    _visible.clear()
    _has_center = false

    var s := _subdivision
    var done := 0
    for rail_tile: Vector2i in rail_tiles:
        for i in s:
            for j in s:
                var tile := Vector2i(rail_tile.x * s + i, rail_tile.y * s + j)
                _map_tiles[tile] = true
                fog_layer.set_cell(tile, fog_source_id, unexplored_atlas)
        done += 1
        if on_progress.is_valid() and done % 200 == 0:
            await on_progress.call(float(done) / rail_tiles.size())

    for tile in _decode_explored(GameState.get_explored(map_name)):
        if _map_tiles.has(tile):
            _explored[tile] = true
            fog_layer.set_cell(tile, fog_source_id, explored_atlas)


# The fog block of rail tile (0,0) must be centered on that rail tile
func _check_alignment() -> void:
    var s := _subdivision
    var first := fog_layer.to_global(fog_layer.map_to_local(Vector2i(0, 0)))
    var last := fog_layer.to_global(fog_layer.map_to_local(Vector2i(s - 1, s - 1)))
    var block_center := (first + last) * 0.5
    var rail_center := grid_service.tile_to_world(Vector2.ZERO)
    if block_center.distance_to(rail_center) > 0.5:
        var fixed := fog_layer.position + rail_center - block_center
        push_warning("ExplorationService: the fog layer is not aligned with the rails grid. Set FogLayer.position to %s" % fixed)
#endregion


#region vision
# Call every frame with the world position of the player train (cheap: it only acts when the
# fog tile or the radius changes). `radius` is in rail tiles, e.g. larger with an observatory wagon.
func update_position(world_pos: Vector2, radius := -1.0) -> void:
    if fog_layer == null:
        return
    if radius < 0.0:
        radius = vision_radius
    var tile := _fog_tile_at(world_pos)
    if _has_center and tile == _center and is_equal_approx(radius, _radius):
        return
    _update_vision(tile, radius)


func _update_vision(center: Vector2i, radius: float) -> void:
    _center = center
    _radius = radius
    _has_center = true

    var new_visible := _tiles_in_radius(center, roundi(radius * _subdivision))
    var changed := false

    # Tiles that stop being visible become "explored"
    for tile in _visible:
        if not new_visible.has(tile):
            fog_layer.set_cell(tile, fog_source_id, explored_atlas)
            changed = true

    # Tiles that become visible lose their fog
    var newly_explored: Array[Vector2i] = []
    for tile in new_visible:
        if not _visible.has(tile):
            fog_layer.erase_cell(tile)
            changed = true
            if not _explored.has(tile):
                _explored[tile] = true
                newly_explored.append(tile)

    _visible = new_visible
    if not newly_explored.is_empty():
        tiles_explored.emit(newly_explored)
    if changed:
        visibility_changed.emit()


func _tiles_in_radius(center: Vector2i, fog_radius: int) -> Dictionary:
    var result := {}
    for offset: Vector2i in _get_offsets(fog_radius):
        var tile := center + offset
        if _map_tiles.has(tile):
            result[tile] = true
    return result


# A disc in tile space (the "+ radius" makes it a little rounder than a plain r*r), computed once per radius
func _get_offsets(fog_radius: int) -> Array:
    if not _offsets.has(fog_radius):
        var list: Array[Vector2i] = []
        var limit := fog_radius * fog_radius + fog_radius
        for dx in range(-fog_radius, fog_radius + 1):
            for dy in range(-fog_radius, fog_radius + 1):
                if dx * dx + dy * dy <= limit:
                    list.append(Vector2i(dx, dy))
        _offsets[fog_radius] = list
    return _offsets[fog_radius]


func _fog_tile_at(world_pos: Vector2) -> Vector2i:
    # Rails run exactly along fog tile boundaries (even subdivision), so float noise would flip
    # the tile every frame. A fixed nudge of a quarter fog tile puts the point inside one tile.
    var bias := Vector2(0, fog_layer.tile_set.tile_size.y * 0.25)
    return fog_layer.local_to_map(fog_layer.to_local(world_pos + bias))
#endregion


#region queries (for gameplay: enemies, clicks, cities...)
func get_state_at(world_pos: Vector2) -> State:
    var tile := _fog_tile_at(world_pos)
    if _visible.has(tile):
        return State.VISIBLE
    if _explored.has(tile):
        return State.EXPLORED
    return State.UNEXPLORED


func is_visible_at(world_pos: Vector2) -> bool:
    return fog_layer != null and _visible.has(_fog_tile_at(world_pos))


func is_explored_at(world_pos: Vector2) -> bool:
    return fog_layer != null and _explored.has(_fog_tile_at(world_pos))


# Same, for a RAIL tile (its center)
func is_tile_visible(rail_tile: Vector2i) -> bool:
    return is_visible_at(grid_service.tile_to_world(Vector2(rail_tile)))


func is_tile_explored(rail_tile: Vector2i) -> bool:
    return is_explored_at(grid_service.tile_to_world(Vector2(rail_tile)))
#endregion


#region saving
# Explored fog tiles as {"subdivision": n, "rows": {"y": "x1..x2,x3"}}: compact and easy to edit
# by hand. The subdivision is saved so a change of the fog tile size is noticed.
func get_explored_data() -> Dictionary:
    var by_row := {} # y -> Array of x
    for tile in _explored:
        if not by_row.has(tile.y):
            by_row[tile.y] = []
        by_row[tile.y].append(tile.x)

    var rows := {}
    for y in by_row:
        var xs: Array = by_row[y]
        xs.sort()
        var parts: Array[String] = []
        var start: int = xs[0]
        var prev: int = start
        for i in range(1, xs.size() + 1):
            if i < xs.size() and xs[i] == prev + 1:
                prev = xs[i]
                continue
            parts.append(str(start) if start == prev else "%d..%d" % [start, prev])
            if i < xs.size():
                start = xs[i]
                prev = start
        rows[str(y)] = ",".join(parts)
    return {"subdivision": _subdivision, "rows": rows}


func _decode_explored(data: Dictionary) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    if data.is_empty():
        return result
    if int(data.get("subdivision", 0)) != _subdivision:
        push_warning("ExplorationService: the saved exploration of '%s' used another fog size, so it is ignored" % _map_name)
        return result

    var rows: Dictionary = data.get("rows", {})
    for y_key in rows:
        var y := int(y_key)
        for part in str(rows[y_key]).split(",", false):
            var bounds := part.split("..")
            var x0 := int(bounds[0])
            var x1 := int(bounds[bounds.size() - 1]) # a single number has one part
            for x in range(x0, x1 + 1):
                result.append(Vector2i(x, y))
    return result


# GameState is about to write the save file: hand over the explored tiles
func _on_game_saving() -> void:
    if _map_name != "":
        GameState.set_explored(_map_name, get_explored_data())


# GameState replaced its data (a load): rebuild the fog from it
func _on_game_loaded() -> void:
    if _map_name == "" or fog_layer == null:
        return
    var center := _center
    var radius := _radius
    var had_center := _has_center
    setup(_map_name, _rail_tiles)
    if had_center:
        _update_vision(center, radius)
#endregion
