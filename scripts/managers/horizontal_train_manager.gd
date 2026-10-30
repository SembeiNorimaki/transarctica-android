extends Node
class_name HorizontalTrainManager
# Spawns and controls the horizontal trains: the player train in the trade scene,
# and a player train plus enemy trains in combat.
# One manager per scene. Like NavigationTrainManager, it ticks every train, so pausing the
# manager (set_process(false)) pauses all of them.

enum Team {PLAYER, ENEMY}

const HORIZONTAL_TRAIN_SCENE: PackedScene = preload("res://scenes/trains/horizontal_train.tscn")

# Injected by the scene that uses the manager (trade or combat)
var train_container: Node2D

var player_train: HorizontalTrain = null
var enemy_trains: Array[HorizontalTrain] = []


#region spawning
# Adopts a train that already exists in the scene (placed in the editor): builds its wagons
# and registers it. Returns false (with an error) if the data is invalid.
func setup_train(train: HorizontalTrain, train_data: Dictionary, team: Team) -> bool:
    if team == Team.PLAYER and is_instance_valid(player_train):
        push_error("HorizontalTrainManager: a player train already exists")
        return false
    var wagons_data: Array = train_data.get("wagons", [])
    if wagons_data.is_empty():
        push_error("HorizontalTrainManager: train data has no wagons")
        return false
    
    for wagon_data in wagons_data:
        train.add_wagon(wagon_data)
    # Forget the train if it is freed (e.g. destroyed in combat)
    train.tree_exiting.connect(_on_train_tree_exiting.bind(train))

    if team == Team.PLAYER:
        player_train = train
    else:
        enemy_trains.append(train)
    return true

# train_data has the structure of GameState.get_player_train() (a "wagons" array with one entry per wagon).
# The manager adds the train to train_container. Returns null if the data is invalid.
func spawn_train(initial_pos: Vector2, train_data: Dictionary, team: Team) -> HorizontalTrain:
    if train_container == null:
        push_error("HorizontalTrainManager: train_container not injected")
        return null
    if team == Team.PLAYER and is_instance_valid(player_train):
        push_error("HorizontalTrainManager: a player train already exists")
        return null

    var train := HORIZONTAL_TRAIN_SCENE.instantiate() as HorizontalTrain
    train.position = initial_pos
    train_container.add_child(train) # in the tree BEFORE the wagons are added
    if not setup_train(train, train_data, team):
        train.queue_free()
        return null
    return train


func clear_trains() -> void:
    for train in enemy_trains:
        if is_instance_valid(train):
            train.queue_free()
    enemy_trains.clear()
    if is_instance_valid(player_train):
        player_train.queue_free()
    player_train = null


func _on_train_tree_exiting(train: HorizontalTrain) -> void:
    if train == player_train:
        player_train = null
    else:
        enemy_trains.erase(train)
#endregion


#region player controls
func player_train_gear_up() -> void:
    if is_instance_valid(player_train):
        player_train.gear_up()


func player_train_gear_down() -> void:
    if is_instance_valid(player_train):
        player_train.gear_down()


# Same as in the navigation scene: one button starts and stops the train, the other reverses it
func player_train_gear_toggle() -> void:
    if is_instance_valid(player_train):
        player_train.gear_toggle()


func player_train_reverse() -> void:
    if is_instance_valid(player_train):
        player_train.reverse_train()
#endregion


func _process(delta: float) -> void:
    if is_instance_valid(player_train):
        player_train.update(delta)
    for train in enemy_trains:
        if is_instance_valid(train):
            train.update(delta)
    # TODO: enemy AI (gear changes) goes here, or in its own EnemyTrainController
