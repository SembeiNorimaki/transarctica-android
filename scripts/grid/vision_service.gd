class_name VisionService
extends Node
# What a unit can see: vision cones and line of sight on the tile grid. It keeps no map state
# except a cache of cone shapes, so it is always up to date with walls, doors, terrain and units.
#
# A cone is the set of tiles within `view_range` of the origin and within half of `view_angle` of
# the facing. Orientations are the tile-space ones of GridService ("N", "NE"...).
# Line of sight is symmetric: A sees B exactly when B sees A. Tiles that block sight (terrain,
# or entities on the vision-blocking layers) hide what is behind them but are themselves visible.
#
# Every service is optional (null = nothing of that kind blocks sight).

var grid_service: GridService
var terrain_service: TerrainService
var edge_service: EdgeOccupancyService
var occupancy_service: TileOccupancyService

## Entities on these occupancy layers block sight.
var vision_blocking_layers := TileOccupancyService.LAYER_STRUCTURE

const _ANGLE_EPSILON := 0.0001

var _cone_cache: Dictionary = {} # "range_angle_orientation" -> {"list": Array[Vector2i], "set": Dictionary}


#region cones
## Offsets (relative to the origin) of the tiles of a cone. Cached per range, angle and facing.
func get_cone_offsets(orientation: String, view_angle: float, view_range: int) -> Array[Vector2i]:
    return _cone(orientation, view_angle, view_range)["list"]

## Tiles of the cone placed on the map, ignoring walls and the map edge. Origin included.
func get_cone_tiles(origin: Vector2i, orientation: String, view_angle: float, view_range: int) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    for o in get_cone_offsets(orientation, view_angle, view_range):
        result.append(origin + o)
    return result

func is_in_cone(origin: Vector2i, orientation: String, view_angle: float, view_range: int, tile: Vector2i) -> bool:
    return _cone(orientation, view_angle, view_range)["set"].has(tile - origin)

## Builds the cones of every facing for these parameters ahead of time (e.g. at loading).
func precompute(view_angle: float, view_range: int) -> void:
    for orientation in GridService.ORIENTATIONS:
        _cone(orientation, view_angle, view_range)

func clear_cache() -> void:
    _cone_cache.clear()
#endregion


#region line of sight
## Tiles on the straight line from a to b, both included, in that order.
## The line is the same whichever way it is drawn (it is always traced from the smaller tile).
func get_line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
    var swapped := b.x < a.x or (b.x == a.x and b.y < a.y)
    var start := b if swapped else a
    var end := a if swapped else b
    var line: Array[Vector2i] = []
    var dx := absi(end.x - start.x)
    var dy := absi(end.y - start.y)
    var sx := 1 if start.x < end.x else -1
    var sy := 1 if start.y < end.y else -1
    var err := dx - dy
    var p := start
    while true:
        line.append(p)
        if p == end:
            break
        var e2 := 2 * err
        if e2 > -dy:
            err -= dy
            p.x += sx
        if e2 < dx:
            err += dx
            p.y += sy
    if swapped:
        line.reverse()
    return line

## Can `from` see `to`? Walls, doors, terrain and entities in between are checked; the two end
## tiles never block themselves. Does not look at range or facing.
func has_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
    if from == to:
        return true
    var line := get_line(from, to)
    for i in range(1, line.size()):
        if i < line.size() - 1 and _tile_blocks_vision(line[i]):
            return false
        if edge_service != null and edge_service.is_view_blocked(line[i - 1], line[i]):
            return false
    return true

## Tiles a unit at `origin` sees: inside the cone, inside the map, with line of sight.
func get_visible_tiles(origin: Vector2i, orientation: String, view_angle: float, view_range: int) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    for tile in get_cone_tiles(origin, orientation, view_angle, view_range):
        if grid_service != null and not grid_service.is_inside_map(tile):
            continue
        if has_line_of_sight(origin, tile):
            result.append(tile)
    return result

func can_see(origin: Vector2i, orientation: String, view_angle: float, view_range: int, target: Vector2i) -> bool:
    if grid_service != null and not grid_service.is_inside_map(target):
        return false
    return is_in_cone(origin, orientation, view_angle, view_range, target) and has_line_of_sight(origin, target)
#endregion


func _tile_blocks_vision(tile: Vector2i) -> bool:
    if terrain_service != null and terrain_service.blocks_vision(tile):
        return true
    return occupancy_service != null and occupancy_service.is_occupied(tile, vision_blocking_layers)

func _cone(orientation: String, view_angle: float, view_range: int) -> Dictionary:
    var key := "%d_%d_%s" % [view_range, roundi(view_angle * 100.0), orientation]
    if _cone_cache.has(key):
        return _cone_cache[key]
    var list: Array[Vector2i] = []
    var set := {}
    var index := GridService.ORIENTATIONS.find(orientation)
    assert(index != -1, "VisionService: unknown orientation '%s'" % orientation)
    var facing := Vector2(GridService.NEIGHBORS_8[index]).normalized()
    var half := deg_to_rad(view_angle) * 0.5
    for y in range(-view_range, view_range + 1):
        for x in range(-view_range, view_range + 1):
            var offset := Vector2i(x, y)
            if x * x + y * y > view_range * view_range:
                continue
            if offset != Vector2i.ZERO and view_angle < 360.0 \
                    and absf(Vector2(offset).normalized().angle_to(facing)) > half + _ANGLE_EPSILON:
                continue
            list.append(offset)
            set[offset] = true
    var entry := {"list": list, "set": set}
    _cone_cache[key] = entry
    return entry
