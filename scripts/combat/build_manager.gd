extends Node
class_name BuildManager
# What the player builds on the battlefield, with the tool chosen in the BuildBar:
#   BUILDING: a tap builds the chosen building type with its first (north) tile there
#   ROAD    : a tap builds a road tile (the roads join their neighbors); press and drag builds a
#             straight line of them in one of the four directions (N, E, S, W), as far as the pointer
#             went along it
#   WALL    : tap a tile, then a neighbor of it: a wall between the two (it goes on from the neighbor,
#             so a row of taps builds a row of wall); tap the same tile again to stop
# With no tool (NONE) taps are not for building: the scene lets the units have them. CombatMapManager
# does the building (and knows why something can't be built); this only chooses what and where.
# It reports the preview (hover_tile, wall_start...) for the BuildOverlay to draw.

enum Tool { NONE, BUILDING, ROAD, WALL }

signal tool_changed(tool: int)
signal building_type_changed(building_type: String)
## The ghost to draw changed.
signal preview_changed
## Something to tell the player: it was built, or why it was not.
signal message(text: String)

# Injected by the scene
var combat_map_manager: CombatMapManager

var tool := Tool.NONE
var building_type := "house"
var wall_type := "wall"
## The tile under the pointer; valid when has_hover.
var hover_tile := Vector2i.ZERO
var has_hover := false
## The tile the wall being built starts from; valid when has_wall_start.
var wall_start := Vector2i.ZERO
var has_wall_start := false
## The road being dragged: where it started (valid when is_dragging) and the tile it goes to.
var is_dragging := false
var drag_start := Vector2i.ZERO
var drag_end := Vector2i.ZERO


func setup() -> void:
    assert(combat_map_manager != null, "BuildManager: not injected")


func set_tool(new_tool: int) -> void:
    if new_tool == tool:
        return
    tool = new_tool
    has_wall_start = false
    is_dragging = false
    tool_changed.emit(tool)
    preview_changed.emit()

func set_building_type(new_type: String) -> void:
    if not BuildingTypes.exists(new_type) or new_type == building_type:
        return
    building_type = new_type
    building_type_changed.emit(building_type)
    preview_changed.emit()

func set_hover(tile: Vector2i) -> void:
    has_hover = combat_map_manager.grid_service.is_inside_map(tile)
    hover_tile = tile
    if tool != Tool.NONE:
        preview_changed.emit()


## A tap on the map. Returns true if it was used for building (so it is not for the units).
func handle_tile_tap(tile: Vector2i) -> bool:
    match tool:
        Tool.BUILDING:
            _tap_building(tile)
        Tool.ROAD:
            _tap_road(tile)
        Tool.WALL:
            _tap_wall(tile)
        _:
            return false
    preview_changed.emit()
    return true


## A press on the map with the road tool starts a line (see the drag signals of CombatInputManager).
func begin_drag(tile: Vector2i) -> void:
    if tool != Tool.ROAD:
        return
    is_dragging = true
    drag_start = tile
    drag_end = tile
    preview_changed.emit()

## The pointer is over this tile: the line goes there (along the direction it is furthest in).
func drag_to(tile: Vector2i) -> void:
    if not is_dragging:
        return
    drag_end = _snap_to_line(drag_start, tile)
    preview_changed.emit()

## The pointer is let go: the line is built. Returns how many road tiles were built.
func end_drag(tile: Vector2i) -> int:
    if not is_dragging:
        return 0
    drag_to(tile)
    is_dragging = false
    var built := 0
    for t in get_road_line(drag_start, drag_end):
        if combat_map_manager.build_road(t):
            built += 1
    message.emit("built %d road tiles" % built if built != 1 else "built a road")
    preview_changed.emit()
    return built

## The tiles from `from` to `to`, which must be on a line in one of the four directions.
func get_road_line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
    var line: Array[Vector2i] = []
    var step := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
    var count := maxi(absi(to.x - from.x), absi(to.y - from.y))
    for i in count + 1:
        line.append(from + step * i)
    return line

# `to`, moved onto the horizontal or vertical line through `from` (the one it is nearer to)
func _snap_to_line(from: Vector2i, to: Vector2i) -> Vector2i:
    if absi(to.x - from.x) >= absi(to.y - from.y):
        return Vector2i(to.x, from.y)
    return Vector2i(from.x, to.y)

## The tiles the building being placed would cover with the pointer where it is.
func get_ghost_tiles() -> Array[Vector2i]:
    var tiles: Array[Vector2i] = []
    if not has_hover:
        return tiles
    match tool:
        Tool.BUILDING:
            var size := BuildingTypes.get_size(building_type)
            return Footprint.rect(size.x, size.y).tiles_at(hover_tile)
        Tool.ROAD:
            if is_dragging:
                return get_road_line(drag_start, drag_end)
            tiles.append(hover_tile)
    return tiles

## Can what is drawn on this tile of the ghost be built? (A road over a road is fine.)
func is_ghost_ok(tile: Vector2i) -> bool:
    if tool == Tool.ROAD:
        var reason := combat_map_manager.why_not_road(tile)
        return reason == "" or reason == "there is a road already"
    return get_problem() == ""

## Why what the pointer shows can't be built there ("" if it can).
func get_problem() -> String:
    if not has_hover:
        return ""
    match tool:
        Tool.BUILDING:
            return combat_map_manager.why_not_building(building_type, hover_tile)
        Tool.ROAD:
            return "" if is_dragging else combat_map_manager.why_not_road(hover_tile)
        Tool.WALL:
            if has_wall_start and hover_tile != wall_start:
                return combat_map_manager.why_not_wall(wall_start, hover_tile, wall_type)
    return ""


func _tap_building(tile: Vector2i) -> void:
    var building := combat_map_manager.build_building(building_type, tile)
    if building != null:
        message.emit("built a %s" % building_type)
    else:
        message.emit("can't build a %s here: %s" % [building_type, combat_map_manager.why_not_building(building_type, tile)])

func _tap_road(tile: Vector2i) -> void:
    if combat_map_manager.build_road(tile):
        message.emit("built a road")
    else:
        message.emit("can't build a road here: %s" % combat_map_manager.why_not_road(tile))

func _tap_wall(tile: Vector2i) -> void:
    if not has_wall_start or tile == wall_start:
        has_wall_start = not (has_wall_start and tile == wall_start)
        wall_start = tile
        message.emit("tap the next tile of the wall" if has_wall_start else "wall finished")
        return
    var problem := combat_map_manager.why_not_wall(wall_start, tile, wall_type)
    if problem == "the tiles must be neighbors":
        wall_start = tile # not next to it: start again from here
        message.emit("tap the next tile of the wall")
    elif problem == "":
        combat_map_manager.build_wall(wall_start, tile, wall_type)
        message.emit("built a wall")
        wall_start = tile
    else:
        message.emit("can't build a wall here: %s" % problem)
