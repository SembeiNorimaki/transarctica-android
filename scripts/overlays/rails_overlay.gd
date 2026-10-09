extends Node2D
class_name RailsOverlay

# Dependencies
var grid_service: GridService
var rail_service: RailService

const OFFSETS = {
    "N": Vector2(60, -30),
    "E": Vector2(60, 30),
    "S": Vector2(-60, 30),
    "W": Vector2(-60, -30),
    "X": Vector2(0, 0)
}

func _ready():
    set_process(false)

func update():
    #print("Updating rails overlay")
    _draw()
    queue_redraw()

func _draw():
    #print("Drawing rails overlay")
    for tile in rail_service.edges:
        var edges = rail_service.edges[tile]
        for edge in edges:
            #print("Tile: %s : %s <-> %s" % [tile, edge.a, edge.b])
            var a = edge.a
            var b = edge.b
            var a_off = OFFSETS[a]
            var b_off = OFFSETS[b]
            var world_pos = grid_service.tile_to_world(tile)
            var a_pos = world_pos + a_off
            var b_pos = world_pos + b_off
            #print("World pos: %s, A pos: %s, B pos: %s" % [world_pos, a_pos, b_pos])
            draw_line(a_pos, b_pos, Color.RED, 2)
            
        # for edge in edges:
        #     #print("%s -> %s" % [edge.from_tile, edge.to_tile])
        #     draw_line(
        #         grid_service.tile_to_world(edge.from_tile),
        #         grid_service.tile_to_world(edge.to_tile),
        #         Color.RED, 2)
        
        #     draw_circle(grid_service.tile_to_world(edge.from_tile), 6, Color.RED)
        #     #draw_circle(grid_service.tile_to_world(edge.to_tile), 4, Color.GREEN)
