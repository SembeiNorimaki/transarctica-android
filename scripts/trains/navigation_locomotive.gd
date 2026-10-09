extends Node2D
class_name NavigationLocomotive

# Dependencies
var grid_service: GridService

# locomotives emit a signal when they change tile, so events can trigger
signal tile_changed(loco, old_tile: Vector2i, new_tile: Vector2i)

@onready var sprite = $AnimatedSprite2D
@onready var label: Label = $Label

var current_tile := Vector2i(-1, -1)
var orientation := ""
var heading = Vector2(1.0, 0.0)
var speed := 0.0


func _ready() -> void:
    pass

func set_pos(new_pos: Vector2):
    position = new_pos
    current_tile = grid_service.world_to_tile(new_pos)

func set_orientation(new_ori: String):
    # print("Setting locomotive orientation to %s" % new_ori)
    if orientation != new_ori:
        orientation = new_ori
        update_animation()
        
func set_heading(new_heading: Vector2):
    heading = new_heading

func update_animation():
    sprite.set_animation(orientation)
    sprite.play(orientation)

func _update_labels():
    label.text = "%s,%s\n%s\n%s\n%s" % [current_tile.x, current_tile.y, orientation, heading, get_parent().get_parent().gear]

func _process(delta):
    _move(delta)
    _check_tile_change()
    _update_labels()

func _move(delta: float):
    position += heading * speed * delta

func _check_tile_change():
    var new_tile = grid_service.world_to_tile(position)
    if current_tile != new_tile:
        emit_signal("tile_changed", self, current_tile, new_tile)
        current_tile = new_tile
