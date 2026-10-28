extends Node2D
class_name RailsOverlay

# Dependencies
var grid_service: GridService
var rail_service: RailService

const OFFSETS := {
    "N": Vector2(60, -30),
    "E": Vector2(60, 30),
    "S": Vector2(-60, 30),
    "W": Vector2(-60, -30),
    "X": Vector2(0, 0)
}

# Debug view of the rail graph. Call update() after the rails changed.
func update() -> void:
    queue_redraw()


func _draw() -> void:
    if rail_service == null or grid_service == null:
        return
    for tile: Vector2i in rail_service.edges:
        var world_pos := grid_service.tile_to_world(tile)
        for edge: RailEdge in rail_service.edges[tile]:
            draw_line(world_pos + OFFSETS[edge.a], world_pos + OFFSETS[edge.b], Color.RED, 2)
