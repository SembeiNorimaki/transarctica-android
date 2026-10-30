extends Node2D
class_name CombatSceneBase
# What every tile based combat scene shares: the services, the managers, the map, the overlays and
# the HUD are nodes of the scene file; this script injects their dependencies, starts the battle and
# runs the HUD. It works with an isometric or a square CombatMap, and turn based or real time.
# A scene extends it and overrides the hooks at the end (_setup_scene, _spawn_units...).
#
# TURN BASED OR REAL TIME: the Managers node must have exactly ONE child that is a TurnManager
# (turn based) or an RtsManager (real time). To change the mode, delete one and add the other.
#
# Controls: tap a soldier of yours to select it, tap an empty tile to walk there, tap an enemy to
# attack it (it walks into range first if it has to). Drag to move the camera, wheel to zoom.

# Services
@onready var grid_service: GridService = $Services/GridService
@onready var terrain_service: TerrainService = $Services/TerrainService
@onready var edge_service: EdgeOccupancyService = $Services/EdgeOccupancyService
@onready var occupancy_service: TileOccupancyService = $Services/TileOccupancyService
@onready var vision_service: VisionService = $Services/VisionService
@onready var visibility_service: VisibilityService = $Services/VisibilityService
@onready var pathfinding_service: PathfindingService = $Services/PathfindingService
@onready var cover_service: CoverService = $Services/CoverService
@onready var camera_service: CameraService = $Services/CameraService

# Managers
@onready var managers: Node = $Managers
@onready var combat_map_manager: CombatMapManager = $Managers/CombatMapManager
@onready var battle_unit_manager: BattleUnitManager = $Managers/BattleUnitManager
@onready var combat_input_manager: CombatInputManager = $Managers/CombatInputManager
@onready var fog_manager: FogManager = $Managers/FogManager

# Map, containers and overlays
@onready var combat_map: CombatMap = $CombatMap
@onready var unit_container: Node2D = $CombatMap/UnitContainer
@onready var path_overlay: PathOverlay = $CombatMap/Overlays/PathOverlay
@onready var vision_overlay: VisionOverlay = $CombatMap/Overlays/VisionOverlay
@onready var nav_graph_overlay: NavGraphOverlay = $CombatMap/Overlays/NavGraphOverlay

# UI
@onready var info_label: Label = $HUD/InfoLabel
@onready var mode_label: Label = $HUD/ModeLabel
@onready var doors_button: Button = $HUD/Buttons/DoorsButton
@onready var fog_button: Button = $HUD/Buttons/FogButton
@onready var paths_button: Button = $HUD/Buttons/PathsButton
@onready var sight_button: Button = $HUD/Buttons/SightButton
@onready var graph_button: Button = $HUD/Buttons/GraphButton
@onready var end_turn_button: Button = $HUD/Buttons/EndTurnButton
@onready var pause_button: Button = $HUD/Buttons/PauseButton

## The one TurnManager or RtsManager of the Managers node.
var flow_manager: CombatFlowManager


## QuestManager asks (by the name of this method) when the scene runs on its own, for debugging:
## a battle has no use for quests, so none are loaded and no quest dialog pauses the game.
func skips_quests_when_debugging() -> bool:
    return true


func _ready() -> void:
    _hide_quest_ui_when_standalone.call_deferred() # deferred: current_scene is set after _ready
    flow_manager = _find_flow_manager()
    _inject()
    combat_map_manager.setup()
    battle_unit_manager.setup()
    fog_manager.setup() # before the soldiers are deployed: it watches them arrive
    flow_manager.setup()

    _setup_scene()
    camera_service.set_world_bounds(_get_camera_bounds())
    camera_service.center_at_tile(grid_service.map_rect.get_center())

    combat_input_manager.tile_tapped.connect(battle_unit_manager.handle_tile_tap)
    combat_input_manager.tile_hovered.connect(_on_tile_hovered)
    battle_unit_manager.selection_changed.connect(_on_selection_changed)
    battle_unit_manager.shot_resolved.connect(_on_shot_resolved)
    flow_manager.status_changed.connect(_update_mode_ui)
    doors_button.pressed.connect(combat_map_manager.toggle_all_doors)
    fog_button.pressed.connect(func() -> void: fog_manager.enabled = not fog_manager.enabled)
    paths_button.pressed.connect(func() -> void: path_overlay.show_all_paths = not path_overlay.show_all_paths)
    sight_button.pressed.connect(func() -> void: vision_overlay.visible = not vision_overlay.visible)
    graph_button.pressed.connect(func() -> void: nav_graph_overlay.visible = not nav_graph_overlay.visible)
    end_turn_button.pressed.connect(_on_end_turn_pressed)
    pause_button.pressed.connect(_on_pause_pressed)

    _spawn_units()
    flow_manager.start()
    _update_mode_ui()
    _start_scene()
    info_label.text = "Tap one of your soldiers (blue) to select it"


#region hooks for the scenes that extend this one
# Extra dependencies and nodes, after the managers are set up and before the soldiers are deployed
func _setup_scene() -> void:
    pass

# Where the camera may go (world coordinates)
func _get_camera_bounds() -> Rect2:
    return grid_service.get_world_bounds().grow(200.0)

# Puts the first soldiers on the battlefield. By default those of the map's Spawns layer.
func _spawn_units() -> void:
    battle_unit_manager.spawn_all(combat_map_manager.get_spawns())

# The battle has started (the flow manager is running)
func _start_scene() -> void:
    pass
#endregion


# There must be exactly one TurnManager or RtsManager: they are two ways to run the same battle
func _find_flow_manager() -> CombatFlowManager:
    var found: Array[CombatFlowManager] = []
    for child in managers.get_children():
        if child is CombatFlowManager:
            found.append(child)
    if found.is_empty():
        push_error("CombatSceneBase: add a TurnManager (turn based) or an RtsManager (real time) to Managers")
        var fallback := CombatFlowManager.new() # everything allowed, so the scene still works
        fallback.name = "FlowManager"
        managers.add_child(fallback)
        return fallback
    for extra in found.slice(1):
        push_error("CombatSceneBase: only one of TurnManager / RtsManager can be in Managers. '%s' is ignored and removed" % extra.name)
        managers.remove_child(extra)
        extra.queue_free()
    return found[0]


# Dependency injection
func _inject() -> void:
    vision_service.grid_service = grid_service
    vision_service.terrain_service = terrain_service
    vision_service.edge_service = edge_service
    vision_service.occupancy_service = occupancy_service

    pathfinding_service.grid_service = grid_service
    pathfinding_service.terrain_service = terrain_service
    pathfinding_service.edge_service = edge_service
    pathfinding_service.occupancy_service = occupancy_service

    cover_service.vision_service = vision_service
    cover_service.edge_service = edge_service
    cover_service.terrain_service = terrain_service

    camera_service.grid_service = grid_service

    combat_map_manager.combat_map = combat_map
    combat_map_manager.grid_service = grid_service
    combat_map_manager.terrain_service = terrain_service
    combat_map_manager.edge_service = edge_service
    combat_map_manager.occupancy_service = occupancy_service

    battle_unit_manager.unit_container = unit_container
    battle_unit_manager.grid_service = grid_service
    battle_unit_manager.occupancy_service = occupancy_service
    battle_unit_manager.pathfinding_service = pathfinding_service
    battle_unit_manager.vision_service = vision_service
    battle_unit_manager.cover_service = cover_service
    battle_unit_manager.flow_manager = flow_manager

    flow_manager.battle_unit_manager = battle_unit_manager
    flow_manager.pathfinding_service = pathfinding_service
    flow_manager.visibility_service = visibility_service

    fog_manager.fog_layer = combat_map.fog
    fog_manager.grid_service = grid_service
    fog_manager.vision_service = vision_service
    fog_manager.visibility_service = visibility_service
    fog_manager.battle_unit_manager = battle_unit_manager
    fog_manager.edge_service = edge_service
    fog_manager.terrain_service = terrain_service

    path_overlay.grid_service = grid_service
    path_overlay.battle_unit_manager = battle_unit_manager

    vision_overlay.grid_service = grid_service
    vision_overlay.vision_service = vision_service
    vision_overlay.battle_unit_manager = battle_unit_manager
    vision_overlay.edge_service = edge_service
    vision_overlay.awareness_range = fog_manager.awareness_range
    vision_overlay.setup()

    nav_graph_overlay.grid_service = grid_service
    nav_graph_overlay.pathfinding_service = pathfinding_service
    nav_graph_overlay.terrain_service = terrain_service
    nav_graph_overlay.occupancy_service = occupancy_service
    nav_graph_overlay.edge_service = edge_service
    nav_graph_overlay.setup()

    combat_input_manager.grid_service = grid_service
    combat_input_manager.camera_service = camera_service
    combat_input_manager.world = combat_map


# The quest list of the campaign is not wanted when the scene runs by itself
func _hide_quest_ui_when_standalone() -> void:
    if get_tree().current_scene != self:
        return
    var quest_ui := get_node_or_null("/root/QuestUI")
    if quest_ui != null:
        quest_ui.hide()


#region HUD
# What the HUD shows depends on the mode: the End turn button only exists in turn based combat,
# the Pause button in real time.
func _update_mode_ui() -> void:
    mode_label.text = flow_manager.get_status_text()
    end_turn_button.visible = flow_manager is TurnManager
    pause_button.visible = flow_manager is RtsManager
    if flow_manager is TurnManager:
        end_turn_button.disabled = (flow_manager as TurnManager).is_computer_turn()
    if flow_manager is RtsManager:
        pause_button.text = "Resume" if (flow_manager as RtsManager).paused else "Pause"

func _on_end_turn_pressed() -> void:
    if flow_manager is TurnManager:
        (flow_manager as TurnManager).end_turn()

func _on_pause_pressed() -> void:
    if flow_manager is RtsManager:
        (flow_manager as RtsManager).toggle_pause()

func _on_tile_hovered(tile: Vector2i) -> void:
    if not grid_service.is_inside_map(tile):
        return
    vision_overlay.set_probe(tile)
    var text := "tile %s  %s (cost %s)" % [tile, terrain_service.get_type(tile), terrain_service.get_cost(tile)]
    var state: String = ["unexplored", "explored", "visible"][visibility_service.get_state(fog_manager.local_team, tile)]
    text += "  %s" % state
    for object in occupancy_service.get_entities_at(tile):
        if object is MapObject:
            text += "  | %s" % object.type
        elif (object as Soldier).visible:
            text += "  | %s" % (object as Soldier).unit_id
    if vision_overlay.visible and vision_overlay.get_probe_text() != "":
        text += "  | " + vision_overlay.get_probe_text()
    info_label.text = text

func _on_selection_changed(soldier: Soldier) -> void:
    info_label.text = "Nothing selected" if soldier == null \
            else "Selected %s (%s). Tap a tile to walk, an enemy to attack" % [soldier.unit_id, soldier.unit_type]

func _on_shot_resolved(attacker: Soldier, target: Soldier, damage: int, cover: int) -> void:
    var cover_text: String = ["no cover", "half cover", "full cover"][cover]
    info_label.text = "%s hit %s for %d (%s)" % [attacker.unit_id, target.unit_id, damage, cover_text]
#endregion
