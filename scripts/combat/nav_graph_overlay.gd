extends Node2D
class_name NavGraphOverlay
# Debug overlay: the graph soldiers walk on. Every walkable tile is a node; two neighboring nodes
# are joined by an edge when PathfindingService lets a soldier step between them, in any of the 8
# directions. What it draws:
#   dot            : a free, walkable tile (a node)
#   line           : a connection. Green for cheap ground, towards yellow and red for costly
#                    (mud, forest, water). Both nodes can step to each other, unless it has an arrow.
#   red stubs      : NO connection although both tiles are free: a wall, fence, window or closed
#                    door is on the border between them. A red cross marks the cut.
#   orange stubs   : no connection for a diagonal step that would cut the corner of a wall,
#                    an object or ground that can't be walked.
#   gray X         : tile that can't be walked on (deep water, rock...)
#   orange square  : tile blocked by an object (crate, container...)
# The soldiers' own bodies are ignored: the graph is the map's, not the situation of the moment.
# It asks PathfindingService.can_step / get_step_block_reason, the same functions the soldiers' paths use.

const WALL_COLOR := Color(1.0, 0.2, 0.2)
const CORNER_COLOR := Color(1.0, 0.6, 0.1)
const BLOCKED_COLOR := Color(0.6, 0.6, 0.6)
const OBJECT_COLOR := Color(1.0, 0.6, 0.1)

## Draw the connections that are missing because of a wall or a corner.
@export var show_missing := true
## Colour the connections by how costly they are.
@export var show_costs := true

# Injected by the scene
var grid_service: GridService
var pathfinding_service: PathfindingService
var terrain_service: TerrainService
var occupancy_service: TileOccupancyService
var edge_service: EdgeOccupancyService

var _profile := MoveProfile.new()


func setup() -> void:
    assert(grid_service != null and pathfinding_service != null, "NavGraphOverlay: not injected")
    # The map's graph: objects and walls count, the soldiers don't
    _profile.blocked_by = TileOccupancyService.LAYER_STRUCTURE | TileOccupancyService.LAYER_OBSTACLE
    if edge_service != null:
        edge_service.edge_changed.connect(func(_a: Vector2i, _b: Vector2i) -> void: queue_redraw())
    if terrain_service != null:
        terrain_service.terrain_changed.connect(func(_tiles: Array[Vector2i]) -> void: queue_redraw())


## The tiles a soldier can step to from this one, by the rules of the graph (not counting soldiers).
func get_connections(tile: Vector2i) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    if not _is_node(tile):
        return result
    for offset in GridService.NEIGHBORS_8:
        if pathfinding_service.can_step(tile, tile + offset, _profile):
            result.append(tile + offset)
    return result

## Why a step is not part of the graph: see PathfindingService.get_step_block_reason. "" if it is.
func get_missing_reason(from: Vector2i, to: Vector2i) -> String:
    return pathfinding_service.get_step_block_reason(from, to, _profile)

func _is_node(tile: Vector2i) -> bool:
    return grid_service.is_inside_map(tile) and (terrain_service == null or terrain_service.is_walkable(tile)) \
            and (occupancy_service == null or not occupancy_service.is_occupied(tile, _profile.blocked_by))


func _draw() -> void:
    if grid_service == null or pathfinding_service == null:
        return
    var rect := grid_service.map_rect
    for y in range(rect.position.y, rect.end.y):
        for x in range(rect.position.x, rect.end.x):
            _draw_node(Vector2i(x, y))

func _draw_node(tile: Vector2i) -> void:
    var center := grid_service.tile_to_world(Vector2(tile))
    if terrain_service != null and not terrain_service.is_walkable(tile):
        _draw_x(center, BLOCKED_COLOR)
        return
    if not _is_node(tile):
        draw_rect(Rect2(center - Vector2(5, 5), Vector2(10, 10)), OBJECT_COLOR, false, 2.0)
        return
    for offset in GridService.NEIGHBORS_8:
        _draw_step(tile, tile + offset, center)
    draw_circle(center, 3.0, Color(0.9, 1.0, 0.9))

func _draw_step(from: Vector2i, to: Vector2i, from_center: Vector2) -> void:
    if not grid_service.is_inside_map(to):
        return
    var to_center := grid_service.tile_to_world(Vector2(to))
    var reason := get_missing_reason(from, to)
    if reason == "":
        # Each connection once; when only one way works, draw it from its start with an arrow
        var back_ok := pathfinding_service.can_step(to, from, _profile)
        if back_ok and (to.y < from.y or (to.y == from.y and to.x < from.x)):
            return
        var color := _cost_color(from, to)
        draw_line(from_center, to_center, color, 2.0, true)
        if not back_ok:
            _draw_arrow(from_center, to_center, color)
        return
    if not show_missing or not _is_node(to):
        return # towards a tile that is not a node there is nothing to connect to
    if reason == "wall" or reason == "corner":
        var color := WALL_COLOR if reason == "wall" else CORNER_COLOR
        draw_line(from_center, from_center.lerp(to_center, 0.3), color, 2.0)
        if to.y > from.y or (to.y == from.y and to.x > from.x):
            _draw_x(from_center.lerp(to_center, 0.5), color, 4.0)

func _cost_color(from: Vector2i, to: Vector2i) -> Color:
    if not show_costs:
        return Color(0.3, 0.9, 0.4, 0.8)
    var cost := pathfinding_service.step_cost(from, to, _profile)
    if from.x != to.x and from.y != to.y:
        cost /= _profile.diagonal_factor
    var k := clampf((cost - 1.0) / 2.0, 0.0, 1.0) # 1 = flat ground, 3 or more = very costly
    var color := Color(0.3, 0.9, 0.4).lerp(Color(1.0, 0.85, 0.2), minf(k * 2.0, 1.0)).lerp(Color(1.0, 0.3, 0.2), maxf(k * 2.0 - 1.0, 0.0))
    color.a = 0.8
    return color

func _draw_x(at: Vector2, color: Color, size := 6.0) -> void:
    draw_line(at + Vector2(-size, -size), at + Vector2(size, size), color, 2.0)
    draw_line(at + Vector2(-size, size), at + Vector2(size, -size), color, 2.0)

func _draw_arrow(from: Vector2, to: Vector2, color: Color) -> void:
    var direction := (to - from).normalized()
    var tip := from.lerp(to, 0.7)
    var side := direction.orthogonal() * 4.0
    draw_colored_polygon(PackedVector2Array([tip + direction * 6.0, tip + side, tip - side]), color)
