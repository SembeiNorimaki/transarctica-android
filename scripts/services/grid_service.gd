extends Node
class_name GridService

const NEIGHBORS_4: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const NEIGHBORS_8: Array[Vector2i] = [
    Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
    Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]
const ORIENTATIONS: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"] # clockwise, tile-space

## How tiles are drawn. Tile coordinates, orientations and neighbors are the same in both:
## only the tile <-> world conversion changes.
enum TileProjection { ISOMETRIC, CARTESIAN }

var projection := TileProjection.ISOMETRIC
var tile_size := Vector2i.ZERO
var tile_half_size := Vector2.ZERO
var tile_center_offset := Vector2.ZERO # world position of tile (0,0)'s center
var map_rect := Rect2i()


func set_tile_size(size: Vector2i) -> void:
    assert(size.x > 0 and size.y > 0, "GridService: invalid tile size")
    tile_size = size
    tile_half_size = Vector2(size) * 0.5
    tile_center_offset = tile_half_size

func set_projection(value: TileProjection) -> void:
    projection = value

func set_map_rect(rect: Rect2i) -> void:
    map_rect = rect

func is_inside_map(tile: Vector2i) -> bool:
    return map_rect.has_point(tile)


#region conversions
func tile_delta_to_world_delta(delta_tile: Vector2) -> Vector2: # Vector2, not Vector2i
    if projection == TileProjection.CARTESIAN:
        return delta_tile * Vector2(tile_size)
    return Vector2(
        (delta_tile.x - delta_tile.y) * tile_half_size.x,
        (delta_tile.x + delta_tile.y) * tile_half_size.y
    )

func tile_to_world(tile: Vector2) -> Vector2:
    return tile_center_offset + tile_delta_to_world_delta(tile)

func world_to_tilef(world_pos: Vector2) -> Vector2:
    assert(tile_size.x > 0 and tile_size.y > 0, "GridService: tile size not set")
    var p := (world_pos - tile_center_offset) / Vector2(tile_size)
    if projection == TileProjection.CARTESIAN:
        return p
    return Vector2(p.x + p.y, p.y - p.x)

func world_to_tile(world_pos: Vector2) -> Vector2i:
    return Vector2i(world_to_tilef(world_pos).round())

func orientation_to_delta(ori: String) -> Vector2i:
    var i := ORIENTATIONS.find(ori)
    assert(i != -1, "GridService: unknown orientation '%s'" % ori)
    return NEIGHBORS_8[i]

func orientation_to_heading(ori: String) -> Vector2:
    return tile_delta_to_world_delta(Vector2(orientation_to_delta(ori))).normalized()

## World-space bounds of the whole map (tile edges, not centers). Feed to CameraService.set_world_bounds().
func get_world_bounds() -> Rect2:
    var a := Vector2(map_rect.position) - Vector2(0.5, 0.5)
    var b := Vector2(map_rect.end) - Vector2(0.5, 0.5)
    var corners: Array[Vector2] = [
        tile_to_world(a), tile_to_world(Vector2(b.x, a.y)),
        tile_to_world(Vector2(a.x, b.y)), tile_to_world(b),
    ]
    var bounds := Rect2(corners[0], Vector2.ZERO)
    for c in corners:
        bounds = bounds.expand(c)
    return bounds
#endregion


func get_neighbors(tile: Vector2i, diagonals := true) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    for offset in (NEIGHBORS_8 if diagonals else NEIGHBORS_4):
        result.append(tile + offset)
    return result


func turn_right(ori: String, steps: int) -> String:
    var i := ORIENTATIONS.find(ori)
    assert(i != -1, "GridService: unknown orientation '%s'" % ori)
    return ORIENTATIONS[posmod(i + steps, ORIENTATIONS.size())]

func turn_left(ori: String, steps: int) -> String:
    return turn_right(ori, -steps)


## Returns "" when from_tile == to_tile.
func get_orientation(from_tile: Vector2i, to_tile: Vector2i) -> String:
    var d := to_tile - from_tile
    if d == Vector2i.ZERO:
        return ""
    # 0 = N, then clockwise in 45° steps, matching ORIENTATIONS
    var step := roundi(atan2(d.x, -d.y) / (TAU / 8.0))
    return ORIENTATIONS[posmod(step, 8)]
