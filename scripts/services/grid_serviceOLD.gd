extends Node
class_name GridService

# ─────────────────────────────────────────────
#  GridService
#
#    set_tile_size(tile_size_: Vector2i)              → sets the tile size
#    tile_to_world(tile: Vector2) -> Vector2          → converts tile coordinates to world coordinates
#    world_to_tile(world_pos: Vector2) -> Vector2i    → rounds to nearest tile
#    world_to_tilef(world_pos: Vector2) -> Vector2    → doesn't round
#    tile_delta_to_world_delta(delta_tile: Vector2i)  → Vector2 → converts tile delta to world delta
#    get_neighbors(tile: Vector2i) -> Array[Vector2i] → gets neighbors of a tile
#    get_orientation(from_tile: Vector2i, to_tile: Vector2i) -> String → gets orientation of a tile relative to another tile
#    get_tiles_in_vision_cone(origin: Vector2i, orientation: String, view_angle: float, view_range: int) -> Array[Vector2i] → gets tiles in a vision cone
#    is_inside_map(tile: Vector2i) -> bool → checks if a tile is inside the map
# ─────────────────────────────────────────────

var tile_size: Vector2i
var tile_half_size: Vector2i
var map_origin: Vector2 # is basically half the tile_size
var map_size: Vector2i

# Precomputed vision cone offsets.
# Key: "%d_%d_%s" % [view_range, view_angle_deg, orientation]
# Value: Array[Vector2i] of offsets relative to origin (0,0)
var _cone_cache: Dictionary = {}


var ORIENTATION_VECTORS := {
    "N": Vector2(0, -1),
    "NE": Vector2(1, -1).normalized(),
    "E": Vector2(1, 0),
    "SE": Vector2(1, 1).normalized(),
    "S": Vector2(0, 1),
    "SW": Vector2(-1, 1).normalized(),
    "W": Vector2(-1, 0),
    "NW": Vector2(-1, -1).normalized()
}

var DELTA_TO_ORI = {
    Vector2i(1, 0): "E",
    Vector2i(-1, 0): "W",
    Vector2i(0, 1): "S",
    Vector2i(0, -1): "N",
    Vector2i(1, 1): "SE",
    Vector2i(-1, 1): "SW",
    Vector2i(1, -1): "NE",
    Vector2i(-1, -1): "NW"
}

# clockwise orientations
var ORIENTATIONS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

func set_tile_size(tile_size_: Vector2i):
    tile_size = tile_size_
    tile_half_size = Vector2i(tile_size_.x / 2, tile_size_.y / 2)
    map_origin = tile_half_size

#region tile to world conversions
#this doesn't use map_origin. Useful for relative positions of tiles
func tile_delta_to_world_delta(delta_tile: Vector2i) -> Vector2:
    return Vector2(
        (delta_tile.x - delta_tile.y) * tile_half_size.x,
        (delta_tile.x + delta_tile.y) * tile_half_size.y
    )

# Tile(0,0) -> World(16,8) 
func tile_to_world(tile: Vector2) -> Vector2:
    return map_origin + tile_delta_to_world_delta(tile)

func world_to_tile(world_pos: Vector2) -> Vector2i:
    var p = world_pos - map_origin
    var tile_x = (p.x / tile_size.x) + (p.y / tile_size.y)
    var tile_y = (p.y / tile_size.y) - (p.x / tile_size.x)
    return Vector2i(round(tile_x), round(tile_y))

func world_to_tilef(world_pos: Vector2) -> Vector2:
    var p = world_pos - map_origin
    var tile_x = (p.x / tile_size.x) + (p.y / tile_size.y)
    var tile_y = (p.y / tile_size.y) - (p.x / tile_size.x)
    return Vector2(tile_x, tile_y)
#endregion


func get_neighbors(tile: Vector2i) -> Array[Vector2i]:
    var neighbors: Array[Vector2i] = []
    for x in [-1, 0, 1]:
        for y in [-1, 0, 1]:
            if x == 0 and y == 0:
                continue
            neighbors.append(tile + Vector2i(x, y))

        #neighbors = [tile + Vector2i(1, 0), tile + Vector2i(-1, 0), tile + Vector2i(0, 1), tile + Vector2i(0, -1)]
    return neighbors

# given an orientation "N" turns left a discrete amount of orientations. Ex: N,1 -> NW,  N,2 -> W 
func turn_left(ori: String, amount: int):
    var index = ORIENTATIONS.find(ori)
    index -= amount
    while index < 0:
        index += ORIENTATIONS.size()
    return ORIENTATIONS[index]

func turn_right(ori: String, amount: int):
    var index = ORIENTATIONS.find(ori)
    index += amount
    while index >= ORIENTATIONS.size():
        index -= ORIENTATIONS.size()
    return ORIENTATIONS[index]


func get_orientation(from_tile: Vector2i, to_tile: Vector2i) -> String:
    var delta = to_tile - from_tile
    var dx = delta.x
    var dy = delta.y
    # Boundaries between cardinal and diagonal directions
    var k = 0.4142 # tan(22.5°)
    var ori := ""
    if abs(dx) > abs(dy):
        # Horizontal dominant
        if dx > 0:
            if dy > dx * k:
                ori = "SE"
            elif dy < -dx * k:
                ori = "NE"
            else:
                ori = "E"
        else:
            if dy > -dx * k:
                ori = "SW"
            elif dy < dx * k:
                ori = "NW"
            else:
                ori = "W"
    else:
        # Vertical dominant
        if dy > 0:
            if dx > dy * k:
                ori = "SE"
            elif dx < -dy * k:
                ori = "SW"
            else:
                ori = "S"
        else:
            if dx > -dy * k:
                ori = "NE"
            elif dx < dy * k:
                ori = "NW"
            else:
                ori = "N"

    
    #print("From tile: %s, to tile: %s, orientation: %s" % [from_tile, to_tile, ori])

    return ori

# Precomputes cone offsets for all 8 orientations for the given (view_range, view_angle) pair.
# Call this once at startup (or whenever unit vision parameters are known).
func precompute_vision_cones(view_range: int, view_angle: float) -> void:
    for orientation in ORIENTATIONS:
        var key := _cone_key(view_range, view_angle, orientation)
        if _cone_cache.has(key):
            continue # already computed for this parameter set

        var offsets: Array[Vector2i] = []
        var forward = ORIENTATION_VECTORS[orientation]
        var half_angle := deg_to_rad(view_angle / 2.0)

        for x in range(-view_range, view_range + 1):
            for y in range(-view_range, view_range + 1):
                var offset := Vector2i(x, y)
                if offset == Vector2i.ZERO:
                    continue
                if offset.length() > view_range:
                    continue
                var dir := Vector2(offset).normalized()
                if abs(forward.angle_to(dir)) <= half_angle + 0.01:
                    offsets.append(offset)

        _cone_cache[key] = offsets
        #print("[GridService] Precomputed cone '%s': %d tiles" % [key, offsets.size()])


func get_tiles_in_vision_cone(origin: Vector2i, orientation: String, view_angle: float, view_range: int) -> Array[Vector2i]:
    var key := _cone_key(view_range, view_angle, orientation)

    # Cache miss: precompute all 8 orientations for this (range, angle) pair on first use.
    # Subsequent calls with the same parameters pay only the cheap offset-apply cost below.
    if not _cone_cache.has(key):
        precompute_vision_cones(view_range, view_angle)

    var offsets: Array[Vector2i] = _cone_cache[key]
    var result: Array[Vector2i] = []
    result.resize(offsets.size())
    for i in offsets.size():
        result[i] = origin + offsets[i]
    return result


func _cone_key(view_range: int, view_angle: float, orientation: String) -> String:
    return "%d_%d_%s" % [view_range, int(view_angle), orientation]

func is_inside_map(tile: Vector2i) -> bool:
    return tile.x >= 0 and tile.x < map_size.x and tile.y >= 0 and tile.y < map_size.y
