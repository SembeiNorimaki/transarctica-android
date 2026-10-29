extends Node2D
class_name CombatSceneTest
# A tile based battle on a CombatMap, to try the grid services and the soldiers' actions.
# Everything it needs is in the scene file (services, managers, containers, map, HUD): this script
# only injects the dependencies, then starts the battle.
#
# Controls: tap a soldier of yours to select it, tap an empty tile to walk there, tap an enemy to
# attack it (it walks into range first if it has to). Drag to move the camera, wheel to zoom.
# The button opens and closes every door.

# Services
@onready var grid_service: GridService = $Services/GridService
@onready var terrain_service: TerrainService = $Services/TerrainService
@onready var edge_service: EdgeOccupancyService = $Services/EdgeOccupancyService
@onready var occupancy_service: TileOccupancyService = $Services/TileOccupancyService
@onready var vision_service: VisionService = $Services/VisionService
@onready var pathfinding_service: PathfindingService = $Services/PathfindingService
@onready var cover_service: CoverService = $Services/CoverService
@onready var camera_service: CameraService = $Services/CameraService

# Managers
@onready var combat_map_manager: CombatMapManager = $Managers/CombatMapManager
@onready var battle_unit_manager: BattleUnitManager = $Managers/BattleUnitManager
@onready var combat_input_manager: CombatInputManager = $Managers/CombatInputManager

# Map and containers
@onready var combat_map: CombatMap = $CombatMap
@onready var unit_container: Node2D = $CombatMap/UnitContainer

# UI
@onready var info_label: Label = $HUD/InfoLabel
@onready var doors_button: Button = $HUD/DoorsButton


func _ready() -> void:
    _inject()
    combat_map_manager.setup()
    battle_unit_manager.setup()

    camera_service.set_world_bounds(grid_service.get_world_bounds().grow(200.0))
    camera_service.center_at_tile(grid_service.map_rect.get_center())

    combat_input_manager.tile_tapped.connect(battle_unit_manager.handle_tile_tap)
    combat_input_manager.tile_hovered.connect(_on_tile_hovered)
    battle_unit_manager.selection_changed.connect(_on_selection_changed)
    battle_unit_manager.shot_resolved.connect(_on_shot_resolved)
    doors_button.pressed.connect(combat_map_manager.toggle_all_doors)

    battle_unit_manager.spawn_all(combat_map_manager.get_spawns())
    info_label.text = "Tap one of your soldiers (blue) to select it"


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

    combat_input_manager.grid_service = grid_service
    combat_input_manager.camera_service = camera_service
    combat_input_manager.world = combat_map


func _on_tile_hovered(tile: Vector2i) -> void:
    if not grid_service.is_inside_map(tile):
        return
    var text := "tile %s  %s (cost %s)" % [tile, terrain_service.get_type(tile), terrain_service.get_cost(tile)]
    for object in occupancy_service.get_entities_at(tile):
        text += "  | %s" % (object.type if object is MapObject else (object as Soldier).unit_id)
    info_label.text = text

func _on_selection_changed(soldier: Soldier) -> void:
    info_label.text = "Nothing selected" if soldier == null \
            else "Selected %s (%s). Tap a tile to walk, an enemy to attack" % [soldier.unit_id, soldier.unit_type]

func _on_shot_resolved(attacker: Soldier, target: Soldier, damage: int, cover: int) -> void:
    var cover_text: String = ["no cover", "half cover", "full cover"][cover]
    info_label.text = "%s hit %s for %d (%s)" % [attacker.unit_id, target.unit_id, damage, cover_text]
