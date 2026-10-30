extends Node2D
class_name VisionOverlay
# Debug overlay: the lines of sight that decide what the selected soldier sees. For every tile of
# its field of view (the cone, plus the circle of awareness all around) it draws the Bresenham line
# VisionService traces from the soldier to the tile:
#   green : the part of the line that is seen
#   red   : the part hidden behind a wall, a closed door, a window or something that blocks sight
#   X     : the place where the line is cut
# Tiles that are seen are tinted green, tiles in the field of view that are hidden red.
# Also: the line to the tile under the pointer (`probe`) is drawn thick, with the tiles it crosses.
# It only reads: it is the same VisionService call that the fog of war uses.

const SEEN := Color(0.25, 1.0, 0.35)
const HIDDEN := Color(1.0, 0.25, 0.2)
const AWARE := Color(0.4, 0.8, 1.0)
const PROBE := Color(1.0, 0.9, 0.2)

# Injected by the scene
var grid_service: GridService
var vision_service: VisionService
var battle_unit_manager: BattleUnitManager
var edge_service: EdgeOccupancyService
## The soldiers also see this far all around (see FogManager.awareness_range).
var awareness_range := 2

## A tile to ask about (the one under the pointer), when has_probe.
var probe := Vector2i.ZERO
var has_probe := false

var _signature := ""
var _dirty := true


func setup() -> void:
    assert(grid_service != null and vision_service != null and battle_unit_manager != null, "VisionOverlay: not injected")
    if edge_service != null:
        edge_service.edge_changed.connect(func(_a: Vector2i, _b: Vector2i) -> void: _dirty = true)
    visibility_changed.connect(func() -> void: _dirty = true)

func set_probe(tile: Vector2i) -> void:
    if not has_probe or probe != tile:
        probe = tile
        has_probe = true
        _dirty = true

func clear_probe() -> void:
    if has_probe:
        has_probe = false
        _dirty = true

## What the line to the probe tile says, for the info label. "" if there is nothing to say.
func get_probe_text() -> String:
    var soldier := battle_unit_manager.selected
    if soldier == null or not has_probe or not grid_service.is_inside_map(probe):
        return ""
    var cut := vision_service.get_line_block_index(soldier.tile, probe)
    if cut == -1:
        return "line of sight to %s: clear" % probe
    var line := vision_service.get_line(soldier.tile, probe)
    return "line of sight to %s: cut before %s" % [probe, line[cut]]


func _process(_delta: float) -> void:
    if not visible:
        return
    var soldier := battle_unit_manager.selected
    var signature := "" if soldier == null else "%s|%s|%s|%s" % [soldier.unit_id, soldier.tile, soldier.facing, soldier.view_range]
    if _dirty or signature != _signature:
        _signature = signature
        _dirty = false
        queue_redraw()


func _draw() -> void:
    var soldier := battle_unit_manager.selected
    if soldier == null or not soldier.is_alive():
        return
    var origin := soldier.tile
    var cone := vision_service.get_cone_tiles(origin, soldier.facing, soldier.view_angle, soldier.view_range)
    var around := vision_service.get_cone_tiles(origin, "N", 360.0, awareness_range)
    var drawn := {}
    for tile in cone + around:
        if tile == origin or drawn.has(tile) or not grid_service.is_inside_map(tile):
            continue
        drawn[tile] = true
        _draw_line_of_sight(origin, tile, tile in around and tile not in cone)
    draw_polyline(grid_service.get_tile_outline(origin, 0.9), Color.WHITE, 2.0)
    if has_probe and grid_service.is_inside_map(probe) and probe != origin:
        _draw_probe(origin)

func _draw_line_of_sight(origin: Vector2i, target: Vector2i, awareness_only: bool) -> void:
    var line := vision_service.get_line(origin, target)
    var cut := vision_service.get_line_block_index(origin, target)
    var seen_count := line.size() if cut == -1 else cut
    var tint := SEEN if cut == -1 else HIDDEN
    tint.a = 0.10
    draw_colored_polygon(grid_service.get_tile_outline(target, 0.96).slice(0, 4), tint)
    var seen_color := AWARE if awareness_only else SEEN
    seen_color.a = 0.45
    var hidden_color := HIDDEN
    hidden_color.a = 0.45
    var points := PackedVector2Array()
    for i in line.size():
        points.append(grid_service.tile_to_world(Vector2(line[i])))
    if seen_count >= 2:
        draw_polyline(points.slice(0, seen_count), seen_color, 1.5, true)
    if cut != -1:
        draw_polyline(points.slice(cut - 1), hidden_color, 1.5, true)
        _draw_cross(points[cut - 1].lerp(points[cut], 0.5), hidden_color)

func _draw_probe(origin: Vector2i) -> void:
    var line := vision_service.get_line(origin, probe)
    var cut := vision_service.get_line_block_index(origin, probe)
    for i in line.size():
        var seen := cut == -1 or i < cut
        var color := PROBE if seen else HIDDEN
        color.a = 0.9
        draw_polyline(grid_service.get_tile_outline(line[i], 0.5), color, 2.0)
    var points := PackedVector2Array()
    for tile in line:
        points.append(grid_service.tile_to_world(Vector2(tile)))
    var limit := points.size() if cut == -1 else cut
    if limit >= 2:
        draw_polyline(points.slice(0, limit), PROBE, 4.0, true)
    if cut != -1:
        draw_polyline(points.slice(cut - 1), HIDDEN, 4.0, true)
        _draw_cross(points[cut - 1].lerp(points[cut], 0.5), HIDDEN, 8.0)

func _draw_cross(at: Vector2, color: Color, size := 5.0) -> void:
    draw_line(at + Vector2(-size, -size), at + Vector2(size, size), color, 2.0)
    draw_line(at + Vector2(-size, size), at + Vector2(size, -size), color, 2.0)
