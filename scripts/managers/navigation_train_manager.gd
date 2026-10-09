extends Node
class_name NavigationTrainManager

signal train_reached_city(city_name: String)

enum Team {PLAYER, ENEMY}

const TRAIN_SCENE: PackedScene = preload("res://scenes/trains/navigation_train.tscn")
const MAX_DELTA := 0.1 # seconds; avoids tile-skipping after hitches

# Injected
var cities_manager: CitiesManager
var camera_service: CameraService
var grid_service: GridService
var rail_service: RailService
var train_container: Node2D

var player_train: NavigationTrain
var enemy_trains: Array[NavigationTrain] = []
var camera_lock_to_engine := false

var _next_train_id := 0
var _transitioning := false


#region train spawning
func spawn_train(tile_pos: Vector2i, ori: String, team: Team) -> NavigationTrain:
    assert(train_container != null, "NavigationTrainManager: train_container not injected")
    var train: NavigationTrain = TRAIN_SCENE.instantiate()
    train.grid_service = grid_service
    train.rail_service = rail_service
    train.train_tile_changed.connect(_on_train_tile_changed)

    train_container.add_child(train) # manager owns placement
    train.initialize(_make_id(team), team, tile_pos, ori)

    if team == Team.PLAYER:
        player_train = train
    else:
        enemy_trains.append(train)
    return train

func clear_trains() -> void:
    for train in enemy_trains:
        if is_instance_valid(train):
            train.queue_free()
    enemy_trains.clear()
    if is_instance_valid(player_train):
        player_train.queue_free()
    player_train = null
    _next_train_id = 0
    _transitioning = false
    set_process(true)

func _make_id(team: Team) -> String:
    var id := "t%s%d" % ["P" if team == Team.PLAYER else "E", _next_train_id]
    _next_train_id += 1
    return id
#endregion


#region player controls
func player_train_reverse() -> void:
    if is_instance_valid(player_train):
        player_train.reverse_train()

func player_train_gear_toggle() -> void:
    if is_instance_valid(player_train):
        player_train.gear_toggle()
#endregion


func _process(delta: float) -> void:
    delta = minf(delta, MAX_DELTA)
    if is_instance_valid(player_train):
        player_train.update(delta)
    for train in enemy_trains:
        if is_instance_valid(train):
            train.update(delta)

    if camera_lock_to_engine and is_instance_valid(player_train) and not player_train.wagons.is_empty():
        camera_service.set_pos(player_train.wagons[0].global_position)


#region tile events
func _on_train_tile_changed(train: NavigationTrain, _old_tile: Vector2i, new_tile: Vector2i) -> void:
    if _transitioning:
        return
    if train == player_train:
        _check_city_entry(new_tile)
    # TODO: enemy behaviour at cities / contact with the player

func _check_city_entry(tile: Vector2i) -> void:
    if not cities_manager.is_entry_tile(tile):
        return
    var city = cities_manager.get_city_by_entry_tile(tile)
    _transitioning = true
    player_train.immediate_stop()
    set_process(false) # freeze all trains; call clear_trains() or resume() on return
    train_reached_city.emit.call_deferred(city.name)
#endregion
