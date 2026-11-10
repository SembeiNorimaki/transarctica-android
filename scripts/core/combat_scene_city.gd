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


# The debug labels of 12 units on top of each other hide everything: only the selected unit shows its
# labels (hp, action points, tile...)
func _setup_scene() -> void:
    battle_unit_manager.soldier_spawned.connect(func(soldier: Soldier) -> void: soldier.show_debug_labels = false)
    battle_unit_manager.selection_changed.connect(_on_selection_labels)

var _labelled: Soldier = null

func _on_selection_labels(soldier: Soldier) -> void:
    if is_instance_valid(_labelled):
        _labelled.show_debug_labels = false
    _labelled = soldier
    if soldier != null:
        soldier.show_debug_labels = true


# Starts looking at the player's units, not at the middle of the map
func _start_scene() -> void:
    var middle := Vector2.ZERO
    var count := 0
    for soldier in battle_unit_manager.soldiers:
        if soldier.team == Soldier.TEAM_PLAYER:
            middle += soldier.position
            count += 1
    if count > 0:
        camera_service.set_pos(combat_map.to_global(middle / count))
