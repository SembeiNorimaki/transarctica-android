extends CombatSceneBase
class_name CombatScene3
# Combat scene 3: trains face each other across a SQUARE tile map (soldiers move in 8 directions).
# The player's train is below the map, the enemy's above it. Each has a barracks wagon with
# soldiers. They start aboard: the player lets them off by tapping them in the barracks menu, the
# enemy's are managed by the AI (see CombatAI, TrainAI and UnitAI).
#
# Real time by default. Like in CombatSceneTest, the Managers node has exactly one
# TurnManager (turn based) or RtsManager (real time). The AI plays either way.
#
# Controls, besides those of CombatSceneBase: tap a soldier in the barracks menu to get it off the
# train; select a soldier and press Board to send it back (it walks to the door first).
# The battle ends when a team has nobody left (on the battlefield or aboard), or the enemy train
# flees.

signal battle_finished(result: String) # "victory" or "defeat"

## Soldiers that start in each barracks when the campaign (GameState) has none for the player, and
## always for the enemy: unit types.
@export var debug_player_units: Array[String] = ["liquidator", "liquidator", "pioneer", "redops", "liquidator"]
@export var debug_enemy_units: Array[String] = ["liquidator", "liquidator", "redops", "pioneer", "liquidator"]

@onready var horizontal_train_manager: HorizontalTrainManager = $Managers/HorizontalTrainManager
@onready var deployment_manager: DeploymentManager = $Managers/DeploymentManager
@onready var train_container: Node2D = $TrainContainer
@onready var player_train: HorizontalTrain = $TrainContainer/PlayerTrain
@onready var enemy_train: HorizontalTrain = $TrainContainer/EnemyTrain
@onready var combat_ai: CombatAI = $AI/CombatAI
@onready var barracks_menu: BarracksMenu = $HUD/BarracksMenu
@onready var board_button: Button = $HUD/Buttons/BoardButton
@onready var ai_label: Label = $HUD/AiLabel
@onready var outcome_label: Label = $HUD/OutcomeLabel

## "" while the battle goes on, then "victory" or "defeat".
var outcome := ""


func _process(_delta: float) -> void:
    ai_label.text = combat_ai.get_status_text() if combat_ai.enabled else "AI off"


#region the hooks of CombatSceneBase
func _setup_scene() -> void:
    horizontal_train_manager.train_container = train_container
    _load_train(Soldier.TEAM_PLAYER, player_train, HorizontalTrainManager.Team.PLAYER)
    _load_train(Soldier.TEAM_ENEMY, enemy_train, HorizontalTrainManager.Team.ENEMY)

    deployment_manager.battle_unit_manager = battle_unit_manager
    deployment_manager.grid_service = grid_service
    deployment_manager.occupancy_service = occupancy_service
    deployment_manager.terrain_service = terrain_service
    deployment_manager.pathfinding_service = pathfinding_service
    deployment_manager.combat_map = combat_map
    deployment_manager.flow_manager = flow_manager
    deployment_manager.setup()
    # Registered after the setup: the wagons' places in the world are known
    _register_train(Soldier.TEAM_PLAYER, player_train, _player_units, false)
    _register_train(Soldier.TEAM_ENEMY, enemy_train, _enemy_units, true)

    _setup_ai()

    barracks_menu.unit_clicked.connect(_on_menu_unit_clicked)
    board_button.pressed.connect(_on_board_pressed)
    deployment_manager.soldier_deployed.connect(_on_soldier_deployed)
    deployment_manager.soldier_boarded.connect(_on_soldier_boarded)
    battle_unit_manager.soldier_died.connect(func(_s: Soldier) -> void: _check_outcome())
    combat_ai.fled.connect(func() -> void: _finish("victory", "VICTORY - the enemy train fled"))
    outcome_label.visible = false

func _get_camera_bounds() -> Rect2:
    return grid_service.get_world_bounds().grow_individual(300.0, 260.0, 300.0, 260.0)

# The soldiers start aboard their trains: nobody is on the battlefield yet
func _spawn_units() -> void:
    pass

func _start_scene() -> void:
    _refresh_barracks_menu()
    info_label.text = "Tap a soldier in the barracks to get him off the train"
#endregion


#region trains
var _player_units := {} # unit id -> data
var _enemy_units := {}

# Builds the train of a team from its data, and the soldiers' data
func _load_train(team: String, train: HorizontalTrain, manager_team: HorizontalTrainManager.Team) -> void:
    var train_data := {}
    var units := {}
    if team == Soldier.TEAM_PLAYER:
        train_data = _player_train_from_game_state(units)
    if train_data.is_empty():
        train_data = _debug_train(debug_player_units if team == Soldier.TEAM_PLAYER else debug_enemy_units, team, units)
    horizontal_train_manager.setup_train(train, train_data, manager_team)
    if team == Soldier.TEAM_PLAYER:
        _player_units = units
    else:
        _enemy_units = units

# The campaign's train, if it has a barracks with soldiers. `units` is filled with the data of the
# soldiers of the first barracks that has any (the others don't take part in this battle).
func _player_train_from_game_state(units: Dictionary) -> Dictionary:
    # Looked up by path, so the scene also runs where the autoload is not there (a test, F6 on the scene)
    var game_state := get_node_or_null("/root/GameState")
    if game_state == null:
        return {}
    var train_data: Dictionary = game_state.get_player_train()
    var found := false
    for wagon_data: Dictionary in train_data.get("wagons", []):
        if wagon_data.get("type", "") != "BarracksWagon":
            continue
        for id: String in wagon_data.get("unit_ids", []):
            var unit: Dictionary = game_state.get_unit(id)
            if not unit.is_empty() and UnitTypes.exists(str(unit.get("unit_type", ""))):
                units[id] = unit.duplicate()
                found = true
        if found:
            break
    return train_data if found else {}

# A locomotive and a barracks wagon with one soldier per type of the list
func _debug_train(unit_types: Array[String], team: String, units: Dictionary) -> Dictionary:
    var ids: Array[String] = []
    for i in unit_types.size():
        var id := "%s_u%d" % [team.left(1), i]
        units[id] = UnitTypes.make_unit(unit_types[i])
        ids.append(id)
    return {"wagons": [
        {"type": "LocomotiveWagon"},
        {"type": "BarracksWagon", "cargo_name": "Soldiers", "cargo_qty": ids.size(), "unit_ids": ids},
    ]}

func _register_train(team: String, train: HorizontalTrain, units: Dictionary, from_top: bool) -> void:
    for wagon in train.wagons:
        if wagon is BarracksWagon:
            # The first barracks wagon is the one that fights
            deployment_manager.register_train(team, wagon, units, from_top)
            return
    push_error("CombatScene3: the %s train has no barracks wagon" % team)
#endregion


#region AI
func _setup_ai() -> void:
    combat_ai.battle_unit_manager = battle_unit_manager
    combat_ai.deployment_manager = deployment_manager
    combat_ai.flow_manager = flow_manager

    var train_ai := combat_ai.train_ai
    train_ai.deployment_manager = deployment_manager
    train_ai.train = enemy_train
    train_ai.exit_x = grid_service.get_world_bounds().end.x + 150.0

    var unit_ai := combat_ai.unit_ai
    unit_ai.battle_unit_manager = battle_unit_manager
    unit_ai.deployment_manager = deployment_manager
    unit_ai.visibility_service = visibility_service
    unit_ai.pathfinding_service = pathfinding_service
    unit_ai.occupancy_service = occupancy_service

    # When an AI plays the enemy's turns, they end when it says so (not after a fixed delay)
    if flow_manager is TurnManager and combat_ai.enabled:
        (flow_manager as TurnManager).auto_pass_computer_turns = false
    combat_ai.setup()
#endregion


#region player controls
func _refresh_barracks_menu() -> void:
    barracks_menu.show_units(deployment_manager.get_aboard(Soldier.TEAM_PLAYER))

func _on_menu_unit_clicked(unit_id: String) -> void:
    var soldier := deployment_manager.deploy(Soldier.TEAM_PLAYER, unit_id)
    if soldier == null:
        info_label.text = "Can't get off the train now"
        return
    battle_unit_manager.select(soldier)

func _on_board_pressed() -> void:
    var soldier := battle_unit_manager.selected
    if soldier == null:
        info_label.text = "Select a soldier to send back to the train"
    elif not deployment_manager.order_board(soldier):
        info_label.text = "%s can't get back on the train" % soldier.unit_id

func _on_soldier_deployed(soldier: Soldier) -> void:
    if soldier.team == Soldier.TEAM_PLAYER:
        _refresh_barracks_menu()

func _on_soldier_boarded(_unit_id: String, team: String) -> void:
    if team == Soldier.TEAM_PLAYER:
        _refresh_barracks_menu()
#endregion


#region the end
func _check_outcome() -> void:
    if outcome != "":
        return
    if deployment_manager.is_team_defeated(Soldier.TEAM_PLAYER):
        _finish("defeat", "DEFEAT - all your soldiers are lost")
    elif deployment_manager.is_team_defeated(Soldier.TEAM_ENEMY):
        _finish("victory", "VICTORY - the enemy is wiped out")

func _finish(result: String, text: String) -> void:
    if outcome != "":
        return
    outcome = result
    outcome_label.text = text
    outcome_label.visible = true
    combat_ai.enabled = false
    flow_manager.end_battle()
    battle_finished.emit(result)
#endregion
