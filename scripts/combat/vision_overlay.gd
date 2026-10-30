extends Node2D
class_name VisionOverlay
# Debug overlay: how line of sight is worked out for the selected soldier. For EVERY tile it
# evaluates (its field of view: the cone plus the circle of awareness all around) it shows the
# Bresenham line VisionService traces from the soldier to the tile (see
# VisionService.trace_line_of_sight):
#   a dot on the centre of each tile of the line (the tiles Bresenham picks),
#   a straight line from the soldier to the tile,
#   green when the line crosses nothing that blocks view and the tile is seen;
#   when it is cut, green up to the cut and red after it, and the place is marked:
#     a thick red bar on the BORDER the line could not cross (wall, closed door, window, fence...),
#     or a red X on the TILE that blocks sight (rock, container...).
# Seen tiles are tinted green, tiles of the field of view that are hidden red.
# The line to the tile under the pointer (`probe`) is drawn thick with its tiles outlined.
# It only reads: it is the same VisionService trace the fog of war uses.

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
    var trace := vision_service.trace_line_of_sight(soldier.tile, probe)
    if trace["cut"] == -1:
        return "line of sight to %s: clear (%d tiles)" % [probe, trace["line"].size()]
    if trace["cause"] == "edge":
        return "line of sight to %s: cut, it crosses a blocking edge between %s and %s" % [probe, trace["crossed_from"], trace["crossed_to"]]
    return "line of sight to %s: cut by the blocking tile %s" % [probe, trace["crossed_from"]]


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
    var trace := vision_service.trace_line_of_sight(origin, target)
    var line: Array[Vector2i] = trace["line"]
    var cut: int = trace["cut"]
    var seen := cut == -1
    var tint := SEEN if seen else HIDDEN
    tint.a = 0.10
    draw_colored_polygon(grid_service.get_tile_outline(target, 0.96).slice(0, 4), tint)
    var seen_color := AWARE if awareness_only else SEEN
    seen_color.a = 0.5
    var hidden_color := HIDDEN
    hidden_color.a = 0.5
    var start := grid_service.tile_to_world(Vector2(origin))
    var end := grid_service.tile_to_world(Vector2(target))
    if seen:
        draw_line(start, end, seen_color, 1.5, true)
    else:
        # The straight line, split where the line of tiles is cut
        var split := start.lerp(end, (float(cut) - 0.5) / float(line.size() - 1))
        draw_line(start, split, seen_color, 1.5, true)
        draw_line(split, end, hidden_color, 1.5, true)
        _draw_cut(trace, HIDDEN, 3.0)
    for i in range(1, line.size() - 1): # the tiles Bresenham picked
        var dot := seen_color if seen or i < cut else hidden_color
        dot.a = 0.9
        draw_circle(grid_service.tile_to_world(Vector2(line[i])), 2.0, dot)


func _draw_probe(origin: Vector2i) -> void:
    var trace := vision_service.trace_line_of_sight(origin, probe)
    var line: Array[Vector2i] = trace["line"]
    var cut: int = trace["cut"]
    for i in line.size():
        var color := PROBE if cut == -1 or i < cut else HIDDEN
        color.a = 0.9
        draw_polyline(grid_service.get_tile_outline(line[i], 0.5), color, 2.0)
    var start := grid_service.tile_to_world(Vector2(origin))
    var end := grid_service.tile_to_world(Vector2(probe))
    if cut == -1:
        draw_line(start, end, PROBE, 4.0, true)
    else:
        var split := start.lerp(end, (float(cut) - 0.5) / float(line.size() - 1))
        draw_line(start, split, PROBE, 4.0, true)
        draw_line(split, end, HIDDEN, 4.0, true)
        _draw_cut(trace, HIDDEN, 6.0)


# Marks what cut the line: the border it could not cross, or the tile that blocks sight
func _draw_cut(trace: Dictionary, color: Color, width: float) -> void:
    var a: Vector2i = trace["crossed_from"]
    var b: Vector2i = trace["crossed_to"]
    if trace["cause"] == "tile":
        _draw_cross(grid_service.tile_to_world(Vector2(a)), color, 6.0)
        return
    var shared := _shared_corners(a, b)
    if shared.size() == 2: # the border between two neighbors: a bar along it
        draw_line(shared[0], shared[1], color, width)
    else: # a diagonal step crosses at the corner
        _draw_cross(grid_service.tile_to_world(Vector2(a)).lerp(grid_service.tile_to_world(Vector2(b)), 0.5), color, 6.0)

# The corners two tiles have in common: two for tiles that share a side, one for diagonal tiles
func _shared_corners(a: Vector2i, b: Vector2i) -> Array[Vector2]:
    var result: Array[Vector2] = []
    var corners_b := grid_service.get_tile_outline(b).slice(0, 4)
    for corner in grid_service.get_tile_outline(a).slice(0, 4):
        for other in corners_b:
            if corner.distance_to(other) < 1.0:
                result.append(corner)
                break
    return result

func _draw_cross(at: Vector2, color: Color, size := 5.0) -> void:
    draw_line(at + Vector2(-size, -size), at + Vector2(size, size), color, 2.0)
    draw_line(at + Vector2(-size, size), at + Vector2(size, -size), color, 2.0)
