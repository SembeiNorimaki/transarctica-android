extends Node
class_name NavigationTrainAI
# Very simple AI for enemy navigation trains. NavigationTrainManager adds it as a child of the
# train (the player train has none). It:
#  - drives forward from the start,
#  - turns around when the train enters a city,
#  - turns around and drives on when the train stops by itself (it reached the end of the rail).

# Injected by NavigationTrainManager BEFORE the node is added to the tree
var cities_manager: CitiesManager

var _train: NavigationTrain
var _turning := false   # a turn-around is already scheduled


func _ready() -> void:
    _train = get_parent() as NavigationTrain
    if _train == null:
        push_error("NavigationTrainAI must be a child of a NavigationTrain")
        return
    _train.train_tile_changed.connect(_on_train_tile_changed)
    _train.gear_changed.connect(_on_gear_changed)
    _train.drive()


func _on_train_tile_changed(_navigation_train: NavigationTrain, _old_tile: Vector2i, new_tile: Vector2i) -> void:
    if cities_manager != null and cities_manager.is_entry_tile(new_tile):
        _turn_around()


# The train puts itself in neutral when there is no rail ahead
func _on_gear_changed(_gear) -> void:
    if not _train.is_driving():
        _turn_around()


func _turn_around() -> void:
    # Only one per frame: a city at the end of the rail triggers both reasons at once,
    # and two turns would cancel each other.
    if _turning:
        return
    _turning = true
    # Deferred, because this is called from inside the train's movement update
    _do_turn_around.call_deferred()


func _do_turn_around() -> void:
    _turning = false
    if not is_instance_valid(_train):
        return
    _train.reverse_train()
    _train.drive()
