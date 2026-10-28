extends Node2D
class_name CombatScene
# The combat between the player's train and an enemy train. For now it only shows the player's
# train; the enemy and the combat itself come next.

# Managers
@onready var horizontal_train_manager: HorizontalTrainManager = $Managers/HorizontalTrainManager
@onready var combat_unit_manager: CombatUnitManager = $Managers/CombatUnitManager

# Containers
@onready var train_container: Node2D = $TrainContainer
@onready var unit_container: Node2D = $UnitContainer

# Trains
@onready var player_train: HorizontalTrain = $TrainContainer/PlayerTrain
@onready var enemy_train: HorizontalTrain = $TrainContainer/EnemyTrain

# UI
@onready var barracks_menu: BarracksMenu = $CanvasLayer/BarracksMenu


# Only used when this scene is run on its own (F6), where SceneService is not calling initialize()
const DEBUG_ENEMY_ID := "e0"

var enemy_id := ""
var _initialized := false
var _open_barracks: BarracksWagon # the one whose soldiers the menu shows

func _ready() -> void:
    # dependency injection
    horizontal_train_manager.train_container = train_container
    combat_unit_manager.unit_container = unit_container
    combat_unit_manager.barracks_menu = barracks_menu
    
    combat_unit_manager.setup()
    _load_player_train()
    var wagons: Array = GameState.get_player_train().get("wagons", [])
    for wagon in wagons:
        if not wagon.get("unit_ids", []).is_empty():
            barracks_menu.show_units(wagon["unit_ids"])
            break
    
    # connect signals
    player_train.wagon_clicked.connect(_on_player_wagon_clicked)
    
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

# Tapping a barracks shows its soldiers
func _on_player_wagon_clicked(wagon: GenericWagon) -> void:
    var barracks := wagon as BarracksWagon
    if barracks == null:
        return
    var wagons_data: Array = GameState.get_player_train().get("wagons", [])
    combat_unit_manager.open_barracks(barracks, wagons_data[player_train.wagons.find(wagon)].get("unit_ids", []))


# TEMPORARY, until the combat has an end: without it the game stays here for good
func _add_temporary_exit_button() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    var button := Button.new()
    button.text = "Leave combat (temporary)"
    button.position = Vector2(32.0, 32.0)
    button.pressed.connect(SceneService.leave_combat)
    layer.add_child(button)
