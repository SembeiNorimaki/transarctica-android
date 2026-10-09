extends Node2D
class_name NavigationWagon

signal tile_changed(wagon: NavigationWagon, old_tile: Vector2i, new_tile: Vector2i)

var grid_service: GridService # injected
var speed := 0.0
var orientation := ""
var heading := Vector2.RIGHT
var current_tile := Vector2i.ZERO
var _placed := false # nothing moves or emits before place_at()

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


## Never emits tile_changed.
func place_at(tile: Vector2i, ori: String) -> void:
    position = grid_service.tile_to_world(Vector2(tile))
    current_tile = tile
    set_orientation(ori)
    _placed = true

func set_orientation(ori: String) -> void:
    heading = grid_service.orientation_to_heading(ori) # derived: can't desync
    if ori != orientation:
        orientation = ori
        sprite.play(ori)

func reverse() -> void:
    set_orientation(grid_service.turn_right(orientation, 4))


## Called by the train. Sub-steps so no tile can be skipped.
func advance(delta: float) -> void:
    if not _placed:
        return
    var remaining := speed * delta
    var max_step := grid_service.tile_half_size.y * 0.5 # well below a tile's width
    while remaining > 0.0 and speed > 0.0:
        var step := minf(remaining, max_step)
        position += heading * step
        remaining -= step
        var tile := grid_service.world_to_tile(position)
        if tile != current_tile:
            var old := current_tile
            current_tile = tile
            tile_changed.emit(self, old, tile) # handler may change orientation or stop