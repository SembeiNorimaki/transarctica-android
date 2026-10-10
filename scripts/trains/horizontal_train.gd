extends Node2D
class_name HorizontalTrain
# Train of the trade and combat scenes. It moves left/right.
# The node position is the FRONT of the locomotive. Wagons are added behind it (to the left).
# Driven by HorizontalTrainManager, which calls update(delta) every frame.

signal wagon_clicked(wagon: GenericWagon)
# wagon_index is the index in the "wagons" array of the train data (valid while no wagon was skipped)
signal wagon_cargo_changed(wagon_index: int, wagon: GenericWagon)

var gear := "N" # "D" drive, "R" reverse, "N" neutral (brakes)
var speed := 0.0
var max_speed := 1000.0
var acceleration := 100.0
var deceleration := 300.0

var wagons: Array[GenericWagon] = []
var last_wagon_position := Vector2.ZERO # back end of the last wagon, local to the train

# Optional horizontal limits, in the coordinates of the train's parent. Unbounded by default.
var bounds_left := -INF # limit for the tail of the train
var bounds_right := INF # limit for the front of the train

var train_length: float:
    get:
        return -last_wagon_position.x


#region wagons
# Adds a wagon behind the last one. Returns the wagon, or null if the data is invalid.
func add_wagon(wagon_data: Dictionary) -> GenericWagon:
    var wagon_name: String = wagon_data.get("type", "")
    if not WagonTypes.TYPES.has(wagon_name):
        push_error("HorizontalTrain: unknown wagon type '%s'" % wagon_name)
        return null

    var wagon_info: Dictionary = WagonTypes.TYPES[wagon_name]
    var wagon_width: float = wagon_info.horizontal_size.x

    var node: Node = wagon_info.horizontal_scene.instantiate()
    var wagon := node as GenericWagon
    if wagon == null:
        node.free()
        push_error("HorizontalTrain: the scene of '%s' must use a script that extends GenericWagon" % wagon_name)
        return null

    # Plain data only, so this is safe before the wagon is in the tree
    wagon.apply_data(wagon_data, wagon_info)

    # The wagon is centered on its slot, then the slot is consumed
    wagon.position = last_wagon_position - Vector2(wagon_width / 2.0, 0.0)
    last_wagon_position.x -= wagon_width

    wagon.clicked.connect(_on_wagon_clicked)
    wagon.cargo_changed.connect(_on_wagon_cargo_changed)
    add_child(wagon)
    wagons.append(wagon)
    return wagon


func _on_wagon_clicked(wagon: GenericWagon) -> void:
    wagon_clicked.emit(wagon)


func _on_wagon_cargo_changed(wagon: GenericWagon) -> void:
    wagon_cargo_changed.emit(wagons.find(wagon), wagon)
#endregion


#region Movement
func set_bounds(left: float, right: float) -> void:
    bounds_left = left
    bounds_right = right


func set_speed(speed_: float) -> void:
    if speed_ > 0.0:
        gear = "D"
    elif speed_ < 0.0:
        gear = "R"
    else:
        gear = "N"
    speed = speed_


func gear_up() -> void:
    if gear == "R":
        gear = "N"
    elif gear == "N":
        gear = "D"


func gear_down() -> void:
    if gear == "D":
        gear = "N"
    elif gear == "N":
        gear = "R"


# Called every frame by HorizontalTrainManager
func update(delta: float) -> void:
    var target := 0.0
    if gear == "D":
        target = max_speed
    elif gear == "R":
        target = - max_speed

    # Neutral brakes; drive and reverse accelerate
    var rate := deceleration if gear == "N" else acceleration
    speed = move_toward(speed, target, rate * delta)
    speed = clampf(speed, -max_speed, max_speed)

    var new_x := position.x + speed * delta
    var clamped_x := clampf(new_x, bounds_left + train_length, bounds_right)
    if not is_equal_approx(clamped_x, new_x):
        speed = 0.0 # hit a limit
    position.x = clamped_x
#endregion