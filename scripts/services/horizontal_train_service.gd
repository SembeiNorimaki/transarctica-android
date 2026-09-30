extends Node
class_name HorizontalTrainService

var player_train: HorizontalTrain = null

const HORIZONTAL_TRAIN_SCENE = preload("res://scenes/trains/horizontal_train.tscn")


# check GameState._player_train_state  for an example of train_data
func spawn_train(initial_pos: Vector2i, train_data: Dictionary) -> HorizontalTrain:
    var horizontal_train = HORIZONTAL_TRAIN_SCENE.instantiate()
    horizontal_train.set_position(initial_pos)

    # add wagons to train
    for wagon_data in train_data.wagons:
        horizontal_train.add_wagon(wagon_data)
    
    player_train = horizontal_train
    
    return horizontal_train
