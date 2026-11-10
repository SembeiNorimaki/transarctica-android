extends Node2D
class_name PathOverlay
# Draws where the soldiers are going: a line along the path they are following, a marker on the
# tile they are walking to, and a red line to whoever they are about to shoot or are shooting.
# The selected soldier's path is drawn stronger. Soldiers that are hidden (by the fog) draw nothing.
# It also draws what is being previewed (see BattleUnitManager): the path (green where the soldier has
# the action points to walk it, yellow beyond), or a shot (a crosshair on the target with the hit
# chance, red if the shot is blocked). It only reads; it never changes a soldier.

const PLAYER_COLOR := Color(0.3, 0.75, 1.0)
const ENEMY_COLOR := Color(1.0, 0.4, 0.35)
const TARGET_COLOR := Color(1.0, 0.15, 0.15)
const PREVIEW_OK_COLOR := Color(0.25, 0.95, 0.3)
const PREVIEW_FAR_COLOR := Color(1.0, 0.85, 0.15)
const CROSSHAIR_COLOR := Color(1.0, 0.9, 0.3)
const CROSSHAIR_BLOCKED_COLOR := Color(1.0, 0.12, 0.12)
## Where a bullet leaves and arrives: above the feet of a unit.
const AIM_OFFSET := Vector2(0, -24)

## false: only the selected soldier's path is drawn.
@export var show_all_paths := true

# Injected by the scene
var grid_service: GridService
var battle_unit_manager: BattleUnitManager

var _was_drawing := false
var _preview_listening := false


func _process(_delta: float) -> void:
    if not _preview_listening and battle_unit_manager != null:
        _preview_listening = true
        battle_unit_manager.preview_changed.connect(queue_redraw)
    # Soldiers move every frame, so redraw while anything is going on, and once more to clear
    var active := false
    if battle_unit_manager != null:
        for soldier in battle_unit_manager.soldiers:
            if soldier.get_action() == &"move" or soldier.get_action() == &"attack":
                active = true
                break
    if battle_unit_manager != null and battle_unit_manager.preview_attack_target != null:
        active = true # the hit chance and the line of sight change while units move
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
    _draw_preview()
    _draw_attack_preview()


# The previewed shot: a line from the shooter to a crosshair on the target, the hit chance beside it
func _draw_attack_preview() -> void:
    var shooter := battle_unit_manager.preview_soldier
    var target := battle_unit_manager.preview_attack_target
    if target == null or not is_instance_valid(shooter) or not is_instance_valid(target):
        return
    var info := battle_unit_manager.get_attack_info(shooter, target)
    var color := CROSSHAIR_BLOCKED_COLOR if info["blocked"] else CROSSHAIR_COLOR
    var from := shooter.position + AIM_OFFSET
    var to := target.position + AIM_OFFSET
    draw_dashed_line(from, to, color, 2.0, 8.0)
    draw_arc(to, 20.0, 0.0, TAU, 32, color, 3.0, true)
    for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
        var direction := Vector2.from_angle(angle)
        draw_line(to + direction * 12.0, to + direction * 30.0, color, 3.0, true)
    draw_circle(to, 2.5, color)
    var font := ThemeDB.fallback_font
    var chance := "%d%%" % roundi(float(info["hit_chance"]) * 100.0)
    var corner := to + Vector2(26.0, -10.0)
    draw_string_outline(font, corner, chance, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 5, Color.BLACK)
    draw_string(font, corner, chance, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, color)
    var note := str(info["reason"])
    if note == "" and int(info["cover"]) != CoverLevel.NONE:
        note = "half cover" if int(info["cover"]) == CoverLevel.HALF else "full cover"
    if note != "":
        var below := corner + Vector2(0.0, 20.0)
        draw_string_outline(font, below, note, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color.BLACK)
        draw_string(font, below, note, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)


# The previewed path: green up to the last tile the soldier can reach now, yellow from there on
func _draw_preview() -> void:
    var path := battle_unit_manager.preview_path
    var soldier := battle_unit_manager.preview_soldier
    if path.size() < 2 or not is_instance_valid(soldier):
        return
    var points := PackedVector2Array()
    for tile in path:
        points.append(soldier.get_world_position(tile))
    var reachable := clampi(battle_unit_manager.preview_reachable, 1, path.size())
    if reachable > 1:
        draw_polyline(points.slice(0, reachable), PREVIEW_OK_COLOR, 5.0, true)
    if reachable < path.size():
        draw_polyline(points.slice(reachable - 1), PREVIEW_FAR_COLOR, 5.0, true)
    for i in range(1, points.size() - 1):
        draw_circle(points[i], 4.0, PREVIEW_OK_COLOR if i < reachable else PREVIEW_FAR_COLOR)
    var goal_color := PREVIEW_OK_COLOR if reachable == path.size() else PREVIEW_FAR_COLOR
    _draw_footprint_marker(soldier, path[-1], goal_color)
    # where the soldier stops if the tile is too far
    if reachable < path.size():
        draw_circle(points[reachable - 1], 7.0, PREVIEW_OK_COLOR)

func _draw_footprint_marker(soldier: Soldier, anchor: Vector2i, color: Color) -> void:
    for offset in soldier.footprint.offsets:
        draw_polyline(grid_service.get_tile_outline(anchor + offset, 0.85), color, 3.0, true)


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

func _draw_tile_marker(tile: Vector2i, color: Color, width: float) -> void:
    draw_polyline(grid_service.get_tile_outline(tile, 0.8), color, width * 0.6, true)

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
