extends Node
class_name FogManager
# Fog of war for one team (the one the player commands). It works out what each soldier sees with
# VisionService (its cone, plus a small circle all around), reports it to VisibilityService, and
# shows the result on the Fog tile layer:
#   unexplored : never seen, opaque
#   explored   : seen before, not visible now, half transparent
#   visible    : no fog
# Soldiers of other teams are hidden while they stand on a tile the local team can't see.
# The truth is in VisibilityService; the tile layer is only a view of it.

const FOG_SOURCE := 0
const UNEXPLORED_ATLAS := Vector2i(0, 0)
const EXPLORED_ATLAS := Vector2i(1, 0)

@export var local_team := Soldier.TEAM_PLAYER
## Soldiers also see this many tiles all around them, whichever way they face.
@export var awareness_range := 2
@export var enabled := true:
    set(value):
        enabled = value
        if is_node_ready() and fog_layer != null:
            _apply_enabled()

# Injected by the scene
var fog_layer: TileMapLayer
var grid_service: GridService
var vision_service: VisionService
var visibility_service: VisibilityService
var battle_unit_manager: BattleUnitManager
var edge_service: EdgeOccupancyService
var terrain_service: TerrainService

var _dirty := false # something that changes what soldiers see happened: recompute next frame


# Call once, after the injection and after the map is loaded
func setup() -> void:
    assert(fog_layer != null and grid_service != null and vision_service != null and visibility_service != null \
            and battle_unit_manager != null, "FogManager: not injected")
    fog_layer.clear()
    var rect := grid_service.map_rect
    for y in range(rect.position.y, rect.end.y):
        for x in range(rect.position.x, rect.end.x):
            fog_layer.set_cell(Vector2i(x, y), FOG_SOURCE, UNEXPLORED_ATLAS)
    visibility_service.visibility_changed.connect(_on_visibility_changed)
    battle_unit_manager.soldier_spawned.connect(_watch)
    battle_unit_manager.soldier_died.connect(_on_soldier_died)
    if edge_service != null:
        edge_service.edge_changed.connect(func(_a: Vector2i, _b: Vector2i) -> void: _dirty = true)
    if terrain_service != null:
        terrain_service.terrain_changed.connect(func(_tiles: Array[Vector2i]) -> void: _dirty = true)
    for soldier in battle_unit_manager.soldiers:
        _watch(soldier)
    _apply_enabled()


func _process(_delta: float) -> void:
    if _dirty:
        _dirty = false
        for soldier in battle_unit_manager.soldiers:
            update_viewer(soldier)
    _update_soldier_visibility()


## Works out again what this soldier sees.
func update_viewer(soldier: Soldier) -> void:
    if not soldier.is_alive():
        visibility_service.remove_viewer(soldier)
        return
    var tiles := vision_service.get_visible_tiles(soldier.tile, soldier.facing, soldier.view_angle, soldier.view_range)
    for tile in vision_service.get_visible_tiles(soldier.tile, "N", 360.0, awareness_range):
        if tile not in tiles:
            tiles.append(tile)
    visibility_service.set_viewer(soldier, soldier.team, tiles)


func _watch(soldier: Soldier) -> void:
    soldier.step_finished.connect(func(_s: Soldier, _tile: Vector2i) -> void: update_viewer(soldier))
    soldier.facing_changed.connect(func(_s: Soldier) -> void: update_viewer(soldier))
    update_viewer(soldier)

func _on_soldier_died(soldier: Soldier) -> void:
    visibility_service.remove_viewer(soldier)

func _on_visibility_changed(team: String, shown: Array[Vector2i], hidden: Array[Vector2i]) -> void:
    if team != local_team:
        return
    for tile in hidden:
        fog_layer.set_cell(tile, FOG_SOURCE, EXPLORED_ATLAS)
    for tile in shown:
        fog_layer.erase_cell(tile)

func _apply_enabled() -> void:
    fog_layer.visible = enabled
    _update_soldier_visibility()

# Enemies show only on tiles the local team sees. A soldier on the move counts from either the
# tile it is walking to or the one it is on.
func _update_soldier_visibility() -> void:
    for soldier in battle_unit_manager.soldiers:
        var shown := true
        if enabled and soldier.team != local_team:
            shown = visibility_service.is_visible(local_team, soldier.tile) \
                    or visibility_service.is_visible(local_team, grid_service.world_to_tile(soldier.position))
        if soldier.visible != shown:
            soldier.visible = shown
