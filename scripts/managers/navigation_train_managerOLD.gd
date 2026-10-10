extends Node
class_name NavigationTrainManagerOLD


# Dependencies
var cities_manager: CitiesManager
var camera_service: CameraService
var grid_service: GridService
var rail_service: RailService

# Signals
signal train_reached_city(city_name)


var player_train: NavigationTrain
var enemy_trains = []

var camera_lock_to_engine = false
var next_train_id = 0


# This manager controls all navigation trains: Player and Enemies

var TRAIN_SCENE = preload("res://scenes/trains/navigation_train.tscn")


#region train spawning
func spawn_train(tile_pos: Vector2i, ori: String, team: String):
    var id = "t%s%s" % [team[0], next_train_id]
    next_train_id += 1

    var train = TRAIN_SCENE.instantiate()
    # Dependency injection
    train.train_manager = self
    train.grid_service = grid_service
    train.rail_service = rail_service
    
    # connect signals
    train.train_tile_changed.connect(_on_train_tile_changed)

    train.call_deferred("initialize", id, tile_pos, ori)
    if team == "Player":
        player_train = train
    else:
        enemy_trains.append(train)

    return train
#endregion


func player_train_reverse():
    player_train.reverse_train()

func player_train_gear_toggle():
    player_train.gear_toggle()

func _process(delta: float):
    player_train.update(delta)
    for train in enemy_trains:
        train.update(delta)
    if camera_lock_to_engine:
        camera_service.set_pos(player_train.wagons[0].position)


func _on_train_tile_changed(train: NavigationTrain, old_tile: Vector2i, new_tile: Vector2i) -> void:
    _check_tile_events(train, new_tile)

func _check_tile_events(train: NavigationTrain, new_tile: Vector2i) -> void:
    if cities_manager.is_entry_tile(new_tile):
        var city = cities_manager.get_city_by_entry_tile(new_tile)
        # print("Train reached city %s" % city.name)
        train.inmediate_stop()
        train_reached_city.emit(city.name)
