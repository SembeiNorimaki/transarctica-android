extends Node2D
class_name HorizontalTrainOLD


@onready var wagons_container: Node2D = $WagonsContainer


var gear := "N"
var speed := 0.0
var max_speed := 1000.0
var acceleration := 100.0
var deceleration := 300.0

var wagons = []

var last_wagon_position = Vector2.ZERO

# const WAGON_SCENES = {
#     "merchandise": preload("res://scenes/trains/merchandise_wagon.tscn"),
#     "generic": preload("res://scenes/trains/generic_wagon.tscn")
# }


#region initialization
func _ready() -> void:
    pass

#endregion

func add_wagon(wagon_data: Dictionary):
    var wagon_name = wagon_data.type
    var wagon_info = WagonTypes.TYPES[wagon_name]

    var wagon = wagon_info.horizontal_scene.instantiate()
    wagon.set_wagon_type(wagon_name)

    var resource_name = wagon_data.get("cargo_name", "")
    var resource_qty = wagon_data.get("cargo_qty", 0)

    wagon.call_deferred("set_resource_type", resource_name)
    wagon.call_deferred("set_resource_qty", resource_qty)
    

    var wagon_dim = wagon.wagon_dim
    wagon.set_position(last_wagon_position - Vector2(WagonTypes.TYPES[wagon_name].horizontal_size.x / 2, 0))
    last_wagon_position -= Vector2(WagonTypes.TYPES[wagon_name].horizontal_size.x, 0)
    
    # Position the wagon at the end of the train
    # var wagon_pos = position
    # if wagons:
    #     var prev_wagon_name = wagons[-1].get_script().get_global_name()
    #     wagon_pos = wagons[-1].position
    #     wagon_pos.x -= WagonTypes.TYPES[prev_wagon_name].horizontal_size.x / 2
    #     wagon_pos.x -= WagonTypes.TYPES[wagon_name].horizontal_size.x / 2
    #     wagon_pos.x -= 2

    # wagon.position = wagon_pos

    #train_inventory.add_wagon(wagon_name, resource_name, resource_qty)
    add_child(wagon)
    wagons.append(wagon)

#region Movement
func set_speed(speed_: float):
    if speed_ > 0:
        gear = "D"
    elif speed_ < 0:
        gear = "R"
    elif speed_ == 0:
        gear = "N"
    speed = speed_
    

func gear_up():
    if gear == "R":
        gear = "N"
    elif gear == "N":
        gear = "D"
    

func gear_down():
    if gear == "D":
        gear = "N"
    elif gear == "N":
        gear = "R"

func _process(delta: float) -> void:
    if gear == "D":
        speed = speed + acceleration * delta
    elif gear == "R":
        speed -= acceleration * delta
    elif gear == "N":
        if speed > 0.0:
            speed -= deceleration * delta
            if speed < 0.0:
                speed = 0.0
        elif speed < 0.0:
            speed += deceleration * delta
            if speed > 0.0:
                speed = 0.0
            
            
        # if speed > 0:
        #     speed -= deceleration * delta
        #     if speed < 0:
        #         speed = 0
        #         _on_train_just_stopped()
        # elif speed < 0:
        #     speed += deceleration * delta
        #     if speed > 0:
        #         speed = 0
        #         _on_train_just_stopped()

    speed = clamp(speed, -max_speed, max_speed)

    position.x += speed * delta
#endregion
