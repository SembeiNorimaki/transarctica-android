extends Node2D
class_name PathOverlay
# Draws where the soldiers are going: a line along the path they are following, a marker on the
# tile they are walking to, and a red line to whoever they are about to shoot or are shooting.
# The selected soldier's path is drawn stronger. Soldiers that are hidden (by the fog) draw nothing.
# It only reads; it never changes a soldier.

const PLAYER_COLOR := Color(0.3, 0.75, 1.0)
const ENEMY_COLOR := Color(1.0, 0.4, 0.35)
const TARGET_COLOR := Color(1.0, 0.15, 0.15)

## false: only the selected soldier's path is drawn.
@export var show_all_paths := true

# Injected by the scene
var grid_service: GridService
var battle_unit_manager: BattleUnitManager

var _was_drawing := false


func _process(_delta: float) -> void:
    # Soldiers move every frame, so redraw while anything is going on, and once more to clear
    var active := false
    if battle_unit_manager != null:
        for soldier in battle_unit_manager.soldiers:
            if soldier.get_action() == &"move" or soldier.get_action() == &"attack":
                active = true
                break
    if active or _was_drawing:
        queue_redraw()
    _was_drawing = active


func _draw() -> void:
    if battle_unit_manager == null or grid_service == null:
        return
    for soldier in battle_unit_manager.soldiers:
        if not soldier.is_alive() or not soldier.visible:
            continue
        var selected := soldier == battle_unit_manager.selected
        if not show_all_paths and not selected:
            continue
        var color := ENEMY_COLOR if soldier.team == Soldier.TEAM_ENEMY else PLAYER_COLOR
        color.a = 0.95 if selected else 0.55
        _draw_path(soldier, color, 4.0 if selected else 2.0)
        _draw_target(soldier, selected)


func _draw_path(soldier: Soldier, color: Color, width: float) -> void:
    var ahead := soldier.get_path_ahead()
    if ahead.is_empty():
        return
    var points := PackedVector2Array([soldier.position])
    for tile in ahead:
        points.append(grid_service.tile_to_world(Vector2(tile)))
    draw_polyline(points, color, width, true)
    for i in range(1, points.size() - 1):
        draw_circle(points[i], width, color)
    _draw_tile_marker(ahead[-1], color, width)

# The outline of a tile's diamond
func _draw_tile_marker(tile: Vector2i, color: Color, width: float) -> void:
    var center := grid_service.tile_to_world(Vector2(tile))
    var half := grid_service.tile_half_size * 0.8
    var corners := PackedVector2Array([
        center + Vector2(0, -half.y), center + Vector2(half.x, 0),
        center + Vector2(0, half.y), center + Vector2(-half.x, 0), center + Vector2(0, -half.y),
    ])
    draw_polyline(corners, color, width * 0.6, true)

func _draw_target(soldier: Soldier, selected: bool) -> void:
    var target := soldier.get_attack_target()
    if target == null or not target.visible:
        return
    var from := soldier.position
    var ahead := soldier.get_path_ahead()
    if not ahead.is_empty():
        from = grid_service.tile_to_world(Vector2(ahead[-1]))
    var to := target.position
    var color := TARGET_COLOR
    color.a = 0.9 if selected else 0.6
    draw_dashed_line(from, to, color, 2.0, 8.0)
    draw_circle(to, 5.0, color)
