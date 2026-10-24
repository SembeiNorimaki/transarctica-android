extends Node
class_name NavigationTrainManager

signal train_reached_city(city_name: String)
signal trains_collided(player_train: NavigationTrain, enemy_train: NavigationTrain)
signal player_tile_changed(tile: Vector2i)

enum Team {PLAYER, ENEMY}

const TRAIN_SCENE: PackedScene = preload("res://scenes/trains/navigation_train.tscn")
const MAX_DELTA := 0.1 # seconds; avoids tile-skipping after hitches

# Injected
var cities_manager: CitiesManager
var camera_service: CameraService
var grid_service: GridService
var rail_service: RailService
var exploration_service: ExplorationService
var train_container: Node2D
var fuel_manager: FuelManager


var player_train: NavigationTrain
var enemy_trains: Array[NavigationTrain] = []
var camera_lock_to_engine := false

var _next_train_id := 0
var _transitioning := false


func _ready() -> void:
    GameState.game_saving.connect(save_player_position)
    GameState.game_saving.connect(save_enemy_positions)


#region train spawning
# `tile_pos` and `ori` are the locomotive's. `train_data` has the structure of
# GameState.get_player_train() (stats and wagons). `is_reversed`: the locomotive pushes from the rear.
func spawn_train(tile_pos: Vector2i, ori: String, team: Team, train_data := {}, is_reversed := false) -> NavigationTrain:
    assert(train_container != null, "NavigationTrainManager: train_container not injected")
    var train: NavigationTrain = TRAIN_SCENE.instantiate()
    train.grid_service = grid_service
    train.rail_service = rail_service
    train.train_tile_changed.connect(_on_train_tile_changed)
    train.train_collided.connect(_on_train_collided)

    train_container.add_child(train) # manager owns placement
    var train_id := str(train_data.get("id", ""))
    if train_id.is_empty():
        train_id = _make_id(team)
    train.initialize(train_id, team, tile_pos, ori, train_data, is_reversed)


    if team == Team.PLAYER:
        player_train = train
    else:
        enemy_trains.append(train)
        _add_ai(train)
    return train

func remove_train(train: NavigationTrain) -> void:
    if train == player_train:
        return
    enemy_trains.erase(train)
    train.process_mode = Node.PROCESS_MODE_DISABLED # also disables its collision area right away
    GameState.remove_enemy_train(train.id)
    train.queue_free()

# Writes where the player train is into GameState (it also happens before every save)
func save_player_position() -> void:
    if not is_instance_valid(player_train) or player_train.wagons.is_empty():
        return
    var locomotive := player_train.wagons[0]
    GameState.set_player_position(locomotive.current_tile, locomotive.orientation, player_train.reversed)

# Writes where the enemy trains are into GameState (it also happens before every save)
func save_enemy_positions() -> void:
    for train in enemy_trains:
        if is_instance_valid(train) and not train.wagons.is_empty():
            var locomotive := train.wagons[0]
            GameState.set_enemy_position(train.id, locomotive.current_tile, locomotive.orientation, train.reversed)

# Builds the player train again from GameState, where it is now. For when the wagons may have
# changed while the navigation scene was suspended (trade, depot, combat). The train stops.
func rebuild_player_train() -> void:
    if not is_instance_valid(player_train) or player_train.wagons.is_empty():
        return
    save_player_position()
    var saved := GameState.get_player_position()
    player_train.process_mode = Node.PROCESS_MODE_DISABLED # also disables its collision areas right away
    player_train.queue_free()
    player_train = null
    spawn_train(saved["tile"], saved["ori"], Team.PLAYER, GameState.get_player_train(), saved["reversed"])

# Freezes every train, e.g. while a pop-up is open. resume() unfreezes them.
func pause() -> void:
    set_process(false)

func resume() -> void:
    _transitioning = false
    set_process(true)
    
func _add_ai(train: NavigationTrain) -> void:
    var ai := NavigationTrainAI.new()
    ai.cities_manager = cities_manager # set before add_child, the AI uses it in _ready
    train.add_child(ai)
    
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
    if not is_instance_valid(player_train):
        return
    if not player_train.is_driving() and fuel_manager != null and not fuel_manager.has_fuel():
        fuel_manager.notify_empty() # the HUD can tell the player
        return
    player_train.gear_toggle()

func recenter_player_train() -> void:
    if not is_instance_valid(player_train) or player_train.wagons.is_empty():
        return
    camera_service.set_pos(player_train.wagons[0].global_position)
#endregion


func _process(delta: float) -> void:
    delta = minf(delta, MAX_DELTA)
    if is_instance_valid(player_train):
        player_train.update(delta)
        _burn_fuel(delta)
    for train in enemy_trains:
        if is_instance_valid(train):
            train.update(delta)

    if camera_lock_to_engine and is_instance_valid(player_train) and not player_train.wagons.is_empty():
        camera_service.set_pos(player_train.wagons[0].global_position)
    _update_exploration()


func _burn_fuel(delta: float) -> void:
    if fuel_manager == null:
        return
    fuel_manager.consume_distance(player_train.move_speed * delta)
    if not fuel_manager.has_fuel() and player_train.is_driving():
        player_train.coast() # out of coal: the train brakes by itself
        
#region tile events
func _on_train_tile_changed(train: NavigationTrain, _old_tile: Vector2i, new_tile: Vector2i) -> void:
    if _transitioning:
        return
    if train == player_train:
        player_tile_changed.emit(new_tile)
        _check_city_entry(new_tile)
    # else:
    #     _update_enemy_visibility(train)

func _check_city_entry(tile: Vector2i) -> void:
    if not cities_manager.is_entry_tile(tile):
        return
    var city = cities_manager.get_city_by_entry_tile(tile)
    _transitioning = true
    player_train.immediate_stop()
    player_train.reverse_train()
    set_process(false) # freeze all trains; call clear_trains() or resume() on return
    train_reached_city.emit.call_deferred(city.name)
#endregion

func _on_train_collided(train: NavigationTrain, other_wagon: NavigationWagon) -> void:
    if _transitioning or train != player_train:
        return
    for enemy in enemy_trains:
        if is_instance_valid(enemy) and enemy.wagons.has(other_wagon):
            _transitioning = true
            _emit_collision.call_deferred(enemy)
            return

func _emit_collision(enemy: NavigationTrain) -> void:
    trains_collided.emit(player_train, enemy)


# Enemies are only drawn while they are on a visible tile
# func update_enemy_visibility() -> void:
#     for train in enemy_trains:
#         if is_instance_valid(train):
#             _update_enemy_visibility(train)

# func _update_enemy_visibility(train: NavigationTrain) -> void:
#     if exploration_service != null and not train.wagons.is_empty():
#         train.visible = exploration_service.is_tile_visible(train.wagons[0].current_tile)

# Reveals the map around the player, and shows enemies only while they are on a visible tile.
# Done every frame, because a rail tile is much bigger than a fog tile.
func _update_exploration() -> void:
    if exploration_service == null:
        return
    if is_instance_valid(player_train) and not player_train.wagons.is_empty():
        exploration_service.update_position(player_train.wagons[0].global_position)
    for train in enemy_trains:
        if is_instance_valid(train) and not train.wagons.is_empty():
            train.visible = exploration_service.is_visible_at(train.wagons[0].global_position)