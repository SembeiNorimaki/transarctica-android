extends Node2D
class_name BuildOverlay
# Draws what the BuildManager would build: the tiles of the building or road under the pointer
# (green if it can be built there, red if not), and for a wall the tile it starts from and the
# border it would go on. It only reads.

const OK_COLOR := Color(0.25, 0.95, 0.3, 0.45)
const BAD_COLOR := Color(1.0, 0.2, 0.2, 0.45)
const START_COLOR := Color(1.0, 0.85, 0.15, 0.5)

# Injected by the scene
var grid_service: GridService
var build_manager: BuildManager


func setup() -> void:
    build_manager.preview_changed.connect(queue_redraw)
    build_manager.tool_changed.connect(func(_tool: int) -> void: queue_redraw())


func _draw() -> void:
    if build_manager == null or build_manager.tool == BuildManager.Tool.NONE:
        return
    var color := BAD_COLOR if build_manager.get_problem() != "" else OK_COLOR
    for tile in build_manager.get_ghost_tiles():
        _draw_tile(tile, OK_COLOR if build_manager.is_ghost_ok(tile) else BAD_COLOR)
    if build_manager.tool != BuildManager.Tool.WALL:
        return
    if build_manager.has_wall_start:
        _draw_tile(build_manager.wall_start, START_COLOR)
    if build_manager.has_wall_start and build_manager.has_hover:
        var a := build_manager.wall_start
        var b := build_manager.hover_tile
        if absi(a.x - b.x) + absi(a.y - b.y) == 1:
            var middle := (Vector2(a) + Vector2(b)) / 2.0
            var along := Vector2(absi(a.y - b.y), absi(a.x - b.x)) * 0.5 # the border runs across a -> b
            draw_line(grid_service.tile_to_world(middle - along), grid_service.tile_to_world(middle + along),
                    color.lightened(0.3), 5.0)

func _draw_tile(tile: Vector2i, color: Color) -> void:
    var centre := Vector2(tile)
    draw_colored_polygon(PackedVector2Array([
        grid_service.tile_to_world(centre + Vector2(-0.5, -0.5)), grid_service.tile_to_world(centre + Vector2(0.5, -0.5)),
        grid_service.tile_to_world(centre + Vector2(0.5, 0.5)), grid_service.tile_to_world(centre + Vector2(-0.5, 0.5))]), color)
