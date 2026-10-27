extends Node2D
class_name CombatScene
# The combat between the player's train and an enemy train. For now it only shows the player's
# train; the enemy and the combat itself come next.

@onready var horizontal_train_manager: HorizontalTrainManager = $Managers/HorizontalTrainManager
@onready var train_container: Node2D = $TrainContainer
@onready var player_train: HorizontalTrain = $TrainContainer/PlayerTrain
@onready var enemy_train: HorizontalTrain = $TrainContainer/EnemyTrain

# Only used when this scene is run on its own (F6), where SceneService is not calling initialize()
const DEBUG_ENEMY_ID := "e0"
const TRAIN_SCALE := Vector2(2.0, 2.0) # like in the trade scene
# Where the FRONT of the player's locomotive is, as a fraction of the screen size.
# The wagons go to the left of it.
const PLAYER_TRAIN_POSITION := Vector2(0.45, 0.7)

var enemy_id := ""
var _initialized := false

func _ready() -> void:
    horizontal_train_manager.train_container = train_container
    _load_player_train()
    _add_temporary_exit_button()

    if get_tree().current_scene == self:
        initialize(DEBUG_ENEMY_ID)

# Called by SceneService right after the scene is added to the tree (so the @onready vars exist).
# `enemy_id_` is the id of the enemy train in GameState ("e0"...). Must be called only once.
func initialize(enemy_id_: String) -> void:
    if _initialized:
        push_error("CombatScene: already initialized")
        return
    _initialized = true
    enemy_id = enemy_id_
    _load_enemy_train()

# The train is already in the scene: the manager only builds its wagons and registers it
func _load_player_train() -> void:
    horizontal_train_manager.setup_train(
            player_train,
            GameState.get_player_train(),
            HorizontalTrainManager.Team.PLAYER)

func _load_enemy_train() -> void:
    horizontal_train_manager.setup_train(
            enemy_train,
            GameState.get_enemy_train(enemy_id),
            HorizontalTrainManager.Team.ENEMY)
            
# TEMPORARY, until the combat has an end: without it the game stays here for good
func _add_temporary_exit_button() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    var button := Button.new()
    button.text = "Leave combat (temporary)"
    button.position = Vector2(32.0, 32.0)
    button.pressed.connect(SceneService.leave_combat)
    layer.add_child(button)
