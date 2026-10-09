extends Node2D
class_name NavigationTrain

# Dependencies
var train_manager: NavigationTrainManager
var grid_service: GridService
var rail_service: RailService

# Signals
signal train_tile_changed(navigation_train: NavigationTrain, old_tile: Vector2i, new_tile: Vector2i)

@onready var wagon_container: Node2D = $WagonContainer

var id: String = ""
var team_id: String = ""
var move_speed := 0.0
var gear = "N"

const MAX_SPEED := 300.0
const ACCELERATION := 50.0
const DECELERATION := 200.0

var wagons = []

const ORIENTATIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

const OPPOSITE_ORIENTATION = {
    "N": "S",
    "NE": "SW",
    "E": "W",
    "SE": "NW",
    "S": "N",
    "SW": "NE",
    "W": "E",
    "NW": "SE"
}

var ori_to_heading = {
    "N": Vector2(2, -1).normalized(),
    "NE": Vector2(1, 0),
    "E": Vector2(2, 1).normalized(),
    "SE": Vector2(0, 1),
    "S": Vector2(-2, 1).normalized(),
    "SW": Vector2(-1, 0),
    "W": Vector2(-2, -1).normalized(),
    "NW": Vector2(0, -1)
}

const LOCOMOTIVE_SCENE = preload("res://scenes/trains/navigation_locomotive.tscn")

#region initialization
func initialize(id_: String, tile_pos_: Vector2i, ori_: String) -> void:
    _add_locomotive()
    call_deferred("_initialize_wagon_positions", tile_pos_, ori_)
    set_id(id_)

func _initialize_wagon_positions(tile_pos_: Vector2i, ori_: String):
    var offset = Vector2(-32, -16)
    var current_pos = grid_service.tile_to_world(tile_pos_)
    for wagon in wagons:
        wagon.set_pos(current_pos)
        wagon.set_orientation(ori_)
        wagon.set_heading(ori_to_heading[ori_])
        current_pos += offset

func _add_locomotive():
    var locomotive = LOCOMOTIVE_SCENE.instantiate()
    
    # dependency injection
    locomotive.grid_service = grid_service
    
    # connect signals
    locomotive.tile_changed.connect(_on_locomotive_tile_changed)

    # add to container
    wagon_container.add_child(locomotive)
    wagon_container.move_child(locomotive, 0)

    wagons.append(locomotive)

func set_id(id_: String) -> void:
    if id == "":
        id = id_
    else:
        push_error("Unit already has an id")

func set_team(team_id_: String):
    team_id = team_id_

func update(delta):
    _update_speed(delta)

func gear_toggle():
    gear = "N" if gear == "D" else "D"
    #update_gear_label()

func reverse_train():
    var positions = []
    var orientations = []
    var n = wagons.size()
    for wagon in wagons:
        positions.append(wagon.position)
        orientations.append(wagon.orientation)
    for i in range(n):
        wagons[n - i - 1].set_pos(positions[i])
        wagons[n - i - 1].set_orientation(OPPOSITE_ORIENTATION[orientations[i]])
        wagons[n - i - 1].set_heading(ori_to_heading[OPPOSITE_ORIENTATION[orientations[i]]])

func inmediate_stop():
    move_speed = 0
    gear = "N"
    #update_gear_label()
    #update_speed_label()
    for wagon in wagons:
        wagon.speed = move_speed

func _update_speed(delta: float):
    if gear == "D":
        move_speed += ACCELERATION * delta
    elif gear == "N":
        move_speed -= DECELERATION * delta
    
    move_speed = clamp(move_speed, 0, MAX_SPEED)
    for wagon in wagons:
        wagon.speed = move_speed
    #update_speed_label()

func _on_locomotive_tile_changed(locomotive, old_tile: Vector2i, new_tile: Vector2i):
    _handle_tile_change(locomotive, old_tile, new_tile)
    train_tile_changed.emit(self, old_tile, new_tile)

func _handle_tile_change(wagon, old_tile: Vector2i, new_tile: Vector2i):
    # Here we need to check with the rail_service what will be the next orientation for the wagon
    var delta = new_tile - old_tile
    var new_ori = rail_service.calculate_new_orientation(new_tile, delta)
    if new_ori == null:
        inmediate_stop()
        return
    wagon.set_orientation(new_ori)
    wagon.set_heading(ori_to_heading[new_ori])
