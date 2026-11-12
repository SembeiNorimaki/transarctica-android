extends CombatSceneBase
class_name CombatSceneCity
# A turn based battle in an isometric city, on a map bigger than the screen (see combat_map_city.tscn:
# ground, roads, 3x3 and 4x4 buildings, walls and fences, crates). Soldiers (1x1) and tanks (2x2)
# start where the map's Spawns layer says.
#
# Controls, besides those of CombatSceneBase: scroll the camera with the arrow keys or WASD, by
# moving the mouse to the edge of the window, or by dragging; wheel to zoom.
# Left click: select a unit of yours / preview the path to the tile (green: within its action points,
# yellow: beyond), and click the same tile again to walk it / attack an enemy. Right click: turn the
# selected unit towards the tile.
#
# The player's train stands next to the map (below its south corner): it comes in from the left at
# train_initial_speed and brakes when it reaches the TrainBrakeStart marker, as in the trade scene. The
# player's units start aboard it. Tap a wagon of the train to see it in the bottom panel (its hp and
# what it carries); a barracks or a vehicle carrier shows its units, and tapping one gets it off the
# train, on the free tiles of the deploy area nearest to the wagon (see WagonDeployManager).
# If the train has no units, the player's units are those of the map's Spawns layer.
#
# The enemy's units are played by the FieldAI: each guards its post or patrols until it sees one of
# yours; then it is alert and engages. Turn based, the enemy's turn is its thinking; with the AI off
# (AI/FieldAI, enabled) the enemy's turn passes by itself.

## The player's units are the ones aboard the train. Off: they start where the map's Spawns layer says.
@export var player_units_from_train := true
## How fast the train comes in (it keeps this speed until the marker).
@export var train_initial_speed := 700.0

@onready var horizontal_train_manager: HorizontalTrainManager = $Managers/HorizontalTrainManager
@onready var wagon_deploy_manager: WagonDeployManager = $Managers/WagonDeployManager
@onready var train_container: Node2D = $TrainContainer
@onready var player_train: HorizontalTrain = $TrainContainer/PlayerTrain
@onready var brake_marker: Marker2D = $TrainBrakeStart
@onready var field_ai: FieldAI = $AI/FieldAI

var _train_arriving := false
var _shown_wagon: GenericWagon = null # the wagon the bottom panel shows


# The debug labels of 12 units on top of each other hide everything: only the selected unit shows its
# labels (hp, action points, tile...)
func _setup_scene() -> void:
    _setup_field_ai()
    _setup_train()
    battle_unit_manager.soldier_spawned.connect(func(soldier: Soldier) -> void: soldier.show_debug_labels = false)
    battle_unit_manager.selection_changed.connect(_on_selection_labels)

var _labelled: Soldier = null

func _on_selection_labels(soldier: Soldier) -> void:
    if is_instance_valid(_labelled):
        _labelled.show_debug_labels = false
    _labelled = soldier
    if soldier != null:
        soldier.show_debug_labels = true


# The train comes in, and the camera looks at the place where it stops (or at the player's units if
# there is no train)
func _start_scene() -> void:
    if player_train.visible:
        camera_service.set_pos(Vector2(_get_train_stop_x(), brake_marker.global_position.y - 120.0))
        player_train.max_speed = train_initial_speed
        player_train.set_speed(train_initial_speed) # speed > 0: it drives, and keeps this speed
        _train_arriving = true
        return
    var middle := Vector2.ZERO
    var count := 0
    for soldier in battle_unit_manager.soldiers:
        if soldier.team == Soldier.TEAM_PLAYER:
            middle += soldier.position
            count += 1
    if count > 0:
        camera_service.set_pos(combat_map.to_global(middle / count))


func _process(_delta: float) -> void:
    if _train_arriving and player_train.global_position.x >= brake_marker.global_position.x:
        player_train.gear_down() # D -> N: it brakes
        _train_arriving = false


# Where the middle of the train will be when it has stopped: the marker plus the braking distance,
# minus half the train
func _get_train_stop_x() -> float:
    var braking := train_initial_speed * train_initial_speed / (2.0 * player_train.deceleration)
    return brake_marker.global_position.x + braking - player_train.train_length * player_train.global_scale.x * 0.5


# The camera may also go to the train
func _get_camera_bounds() -> Rect2:
    var bounds := super()
    if player_train.visible:
        var train_box := Rect2(brake_marker.global_position + Vector2(-2500.0, -300.0), Vector2(3500.0, 600.0))
        bounds = bounds.merge(train_box)
    return bounds


func _setup_field_ai() -> void:
    field_ai.battle_unit_manager = battle_unit_manager
    field_ai.vision_service = vision_service
    field_ai.pathfinding_service = pathfinding_service
    field_ai.occupancy_service = occupancy_service
    field_ai.grid_service = grid_service
    field_ai.flow_manager = flow_manager
    field_ai.setup()
    field_ai.awareness_range = fog_manager.awareness_range
    var turn_manager := flow_manager as TurnManager
    if turn_manager != null:
        turn_manager.auto_pass_computer_turns = not field_ai.enabled # the AI ends its turns itself


#region the train
func _setup_train() -> void:
    var data: Dictionary = GameState.get_player_train()
    if data.get("wagons", []).is_empty():
        player_train.hide()
        return
    horizontal_train_manager.train_container = train_container
    horizontal_train_manager.setup_train(player_train, data, HorizontalTrainManager.Team.PLAYER)

    wagon_deploy_manager.battle_unit_manager = battle_unit_manager
    wagon_deploy_manager.grid_service = grid_service
    wagon_deploy_manager.occupancy_service = occupancy_service
    wagon_deploy_manager.terrain_service = terrain_service
    wagon_deploy_manager.pathfinding_service = pathfinding_service
    wagon_deploy_manager.combat_map = combat_map
    wagon_deploy_manager.flow_manager = flow_manager
    wagon_deploy_manager.setup()
    for wagon in player_train.wagons:
        var units := {}
        for id in wagon.unit_ids:
            units[id] = GameState.get_unit(id).duplicate(true)
        wagon_deploy_manager.add_wagon(wagon, wagon.unit_ids, units)

    player_train.wagon_clicked.connect(_on_wagon_clicked)
    battle_unit_manager.selection_changed.connect(func(soldier: Soldier) -> void:
        if soldier != null:
            _shown_wagon = null) # the panel shows the unit now
    wagon_deploy_manager.aboard_changed.connect(_on_aboard_changed)
    flow_manager.status_changed.connect(_refresh_wagon_panel)
    if unit_hud != null:
        unit_hud.deploy_requested.connect(_on_deploy_requested)


# The player's units are on the train, unless there are none: then the map's spawns
func _spawn_units() -> void:
    var spawns := combat_map_manager.get_spawns()
    if not (player_units_from_train and wagon_deploy_manager.count_aboard() > 0):
        battle_unit_manager.spawn_all(spawns)
        return
    var enemy_spawns: Array[Dictionary] = []
    for spawn in spawns:
        if spawn["team"] != Soldier.TEAM_PLAYER:
            enemy_spawns.append(spawn)
    battle_unit_manager.spawn_all(enemy_spawns)


# Tapping a wagon shows it in the bottom panel (tapping it again closes it), instead of a unit
func _on_wagon_clicked(wagon: GenericWagon) -> void:
    if unit_hud == null:
        return
    if wagon == _shown_wagon:
        _shown_wagon = null
        unit_hud.clear_wagon()
        return
    battle_unit_manager.clear_preview()
    battle_unit_manager.select(null)
    _shown_wagon = wagon
    _refresh_wagon_panel()

func _refresh_wagon_panel() -> void:
    if unit_hud != null and _shown_wagon != null:
        unit_hud.show_wagon(_describe_wagon(_shown_wagon))

func _on_aboard_changed(wagon: GenericWagon) -> void:
    if wagon == _shown_wagon:
        _refresh_wagon_panel()

func _on_deploy_requested(unit_id: String) -> void:
    if _shown_wagon == null:
        return
    if wagon_deploy_manager.deploy(_shown_wagon, unit_id) == null:
        info_label.text = "%s can't get off the train now" % unit_id

# What the bottom panel shows of a wagon (see UnitHud.show_wagon)
func _describe_wagon(wagon: GenericWagon) -> Dictionary:
    var info := {
        "name": wagon.wagon_type.capitalize(), "icon": wagon.get_icon(),
        "hp": wagon.hp, "max_hp": wagon.max_hp, "cargo_text": "", "cargo_icon": null, "units": [],
    }
    if wagon_deploy_manager.carries_units(wagon):
        var aboard := wagon_deploy_manager.get_aboard(wagon)
        info["cargo_text"] = "%s %d / %d" % ["Vehicles" if wagon.stores.has("Vehicles") else "Soldiers", aboard.size(), wagon.max_cargo_amount]
        var units: Array[Dictionary] = []
        for id in aboard:
            var unit_type := str(wagon_deploy_manager.get_unit_data(id).get("unit_type", ""))
            units.append({
                "id": id, "icon": WagonPictures.unit_icon(unit_type), "label": unit_type.replace("_", " ").capitalize(),
                "enabled": wagon_deploy_manager.can_deploy(wagon, id),
            })
        info["units"] = units
    elif wagon.max_cargo_amount > 0:
        if wagon.cargo_type.is_empty() or wagon.cargo_amount <= 0:
            info["cargo_text"] = "Empty (0 / %d)" % wagon.max_cargo_amount
        else:
            info["cargo_text"] = "%s %d / %d" % [wagon.cargo_type.capitalize(), wagon.cargo_amount, wagon.max_cargo_amount]
            info["cargo_icon"] = WagonPictures.resource_icon(wagon.cargo_type)
    return info
#endregion
