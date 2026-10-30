extends Node2D
class_name HorizontalTrain
# Train of the trade and combat scenes. It moves left/right.
# The node position is the FRONT of the locomotive. Wagons are added behind it (to the left).
# Driven by HorizontalTrainManager, which calls update(delta) every frame.

signal wagon_clicked(wagon: GenericWagon)

const LAYOUT_TIME := 0.15 # seconds the wagons take to slide into their places

var _layout_tween: Tween
var gear := "N" # "D" drive (to the right), "R" reverse (to the left), "N" neutral (brakes)
## Where the train goes when it drives: 1 to the right, -1 to the left. reverse_train() flips it.
var direction := 1
var speed := 0.0
var max_speed := 1500.0
var acceleration := 1200.0
var deceleration := 1200.0

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

    wagon.clicked.connect(wagon_clicked.emit) # the wagon passes itself
    add_child(wagon)
    wagons.append(wagon)
    return wagon

func remove_wagon(index: int) -> void:
    if index < 0 or index >= wagons.size():
        return
    var wagon := wagons[index]
    wagons.remove_at(index)
    wagon.queue_free()
    _layout_wagons()

func move_wagon(from_index: int, to_index: int) -> void:
    if from_index < 0 or to_index < 0 or from_index >= wagons.size() or to_index >= wagons.size() or from_index == to_index:
        return
    wagons.insert(to_index, wagons.pop_at(from_index))
    _layout_wagons(true)
    
# Slides the wagons into their places (e.g. after a cancelled drag)
func relayout() -> void:
    _layout_wagons(true)

# Local x of the boundary before wagon k. Boundary wagons.size() is the rear end of the train.
func get_boundary_x(k: int) -> float:
    var x := 0.0
    for i in mini(k, wagons.size()):
        x -= float(wagons[i].wagon_dim.x)
    return x

func _layout_wagons(animated := false) -> void:
    if _layout_tween != null and _layout_tween.is_valid():
        _layout_tween.kill()
    var tween: Tween = null
    if animated and not wagons.is_empty():
        tween = create_tween().set_parallel(true)
        _layout_tween = tween

    last_wagon_position = Vector2.ZERO
    for wagon in wagons:
        var width := float(wagon.wagon_dim.x)
        var target := last_wagon_position - Vector2(width / 2.0, 0.0)
        if tween != null:
            tween.tween_property(wagon, "position", target, LAYOUT_TIME)
        else:
            wagon.position = target
        last_wagon_position.x -= width

#endregion


#region Movement
func set_bounds(left: float, right: float) -> void:
    bounds_left = left
    bounds_right = right


func set_speed(speed_: float) -> void:
    if speed_ > 0.0:
        gear = "D"
        direction = 1
    elif speed_ < 0.0:
        gear = "R"
        direction = -1
    else:
        gear = "N"
    speed = speed_


func gear_up() -> void:
    if gear == "R":
        gear = "N"
    elif gear == "N":
        gear = "D"
        direction = 1


func gear_down() -> void:
    if gear == "D":
        gear = "N"
    elif gear == "N":
        gear = "R"
        direction = -1

# Drive to the right, whatever the gear was
func drive() -> void:
    gear = "D"
    direction = 1


func is_driving() -> bool:
    return gear != "N"

# Start or stop: from neutral it drives (the way `direction` says), otherwise it brakes
func gear_toggle() -> void:
    if gear == "N":
        gear = "D" if direction > 0 else "R"
    else:
        gear = "N"

# The other way: left becomes right and the other way round. A train that is driving turns
# round (it brakes and gathers speed the other way); a stopped one will start the other way.
func reverse_train() -> void:
    direction = -direction
    if gear != "N":
        gear = "D" if direction > 0 else "R"

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
