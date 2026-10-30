class_name PathfindingService
extends Node
# Shortest paths and reachable tiles on the tile grid. It keeps no graph: every query asks the
# terrain, edge and occupancy services directly, so it can never be out of date when a wall is
# destroyed or a unit moves.
#
# Every service is optional (null = no rule of that kind). Costs: entering a tile costs the
# terrain cost of that tile (x diagonal_factor for a diagonal step) plus the profile's extra cost.

var grid_service: GridService
var terrain_service: TerrainService
var edge_service: EdgeOccupancyService
var occupancy_service: TileOccupancyService

## A search that has expanded this many tiles gives up. Protects against unreachable goals on
## big or unbounded maps.
var max_expanded_tiles := 20000


#region rules
## Is the single step between two neighboring tiles allowed for this mover?
func can_step(from: Vector2i, to: Vector2i, profile: MoveProfile, is_goal := false) -> bool:
    if not _can_stand(to, profile, is_goal):
        return false
    if terrain_service != null and profile.max_step_height >= 0:
        if absi(terrain_service.get_elevation(to) - terrain_service.get_elevation(from)) > profile.max_step_height:
            return false
    var d := to - from
    if edge_service != null and edge_service.is_move_blocked(from, to):
        return false
    if d.x != 0 and d.y != 0: # diagonal: the two tiles it passes by must be open ground
        for corner in [from + Vector2i(d.x, 0), from + Vector2i(0, d.y)]:
            if terrain_service != null and not terrain_service.is_walkable(corner):
                return false
            if occupancy_service != null and occupancy_service.is_occupied(corner, profile.corner_blocked_by, profile.ignore):
                return false
    return true

## Why a step is not allowed, for debugging overlays. "" if it is (the same answer as can_step).
##   "tile"   : the tile entered is outside the map, not walkable, or occupied
##   "height" : too steep
##   "wall"   : an edge (wall, closed door, window, fence...) on the border crossed
##   "corner" : a diagonal step that would cut the corner of something
func get_step_block_reason(from: Vector2i, to: Vector2i, profile: MoveProfile, is_goal := false) -> String:
    if not _can_stand(to, profile, is_goal):
        return "tile"
    if terrain_service != null and profile.max_step_height >= 0:
        if absi(terrain_service.get_elevation(to) - terrain_service.get_elevation(from)) > profile.max_step_height:
            return "height"
    if edge_service != null and edge_service.is_move_blocked(from, to):
        return "wall"
    var d := to - from
    if d.x != 0 and d.y != 0:
        for corner in [from + Vector2i(d.x, 0), from + Vector2i(0, d.y)]:
            if terrain_service != null and not terrain_service.is_walkable(corner):
                return "corner"
            if occupancy_service != null and occupancy_service.is_occupied(corner, profile.corner_blocked_by, profile.ignore):
                return "corner"
    return ""

## Cost of the step (assumes can_step is true).
func step_cost(from: Vector2i, to: Vector2i, profile: MoveProfile) -> float:
    var cost := 1.0 if terrain_service == null else terrain_service.get_cost(to)
    if to.x != from.x and to.y != from.y:
        cost *= profile.diagonal_factor
    if profile.extra_cost.is_valid():
        cost += float(profile.extra_cost.call(to))
    return cost
#endregion


#region searches
## Cheapest path from `from` to `to`, both included. Empty if there is none. [from] if they are equal.
func find_path(from: Vector2i, to: Vector2i, profile: MoveProfile = null) -> Array[Vector2i]:
    if profile == null:
        profile = MoveProfile.new()
    var path: Array[Vector2i] = []
    if from == to:
        path.append(from)
        return path
    if not _can_stand(to, profile, true):
        return path

    var min_cost := 1.0 if terrain_service == null else minf(terrain_service.get_min_cost(), 1.0)
    var best := {from: 0.0}
    var prev := {}
    var closed := {}
    var open := MinHeap.new()
    open.push(from, 0.0)
    var expanded := 0
    while not open.is_empty():
        var current: Vector2i = open.pop()
        if closed.has(current):
            continue # stale heap entry
        if current == to:
            return _build_path(prev, from, to)
        closed[current] = true
        expanded += 1
        if expanded > max_expanded_tiles:
            push_warning("PathfindingService: gave up after %d tiles" % expanded)
            return path
        for next in _neighbors(current, profile):
            if closed.has(next) or not can_step(current, next, profile, next == to):
                continue
            var cost: float = best[current] + step_cost(current, next, profile)
            if cost < best.get(next, INF):
                best[next] = cost
                prev[next] = current
                open.push(next, cost + min_cost * _distance(next, to, profile))
    return path

## Every tile the mover can reach spending at most max_cost, from `from` (cost 0).
## Returns a field {"cost": {tile: cost}, "prev": {tile: previous tile}}; read it with
## get_reachable_tiles() and path_in_field().
func compute_field(from: Vector2i, max_cost: float, profile: MoveProfile = null) -> Dictionary:
    if profile == null:
        profile = MoveProfile.new()
    var cost_of := {from: 0.0}
    var prev := {}
    var closed := {}
    var open := MinHeap.new()
    open.push(from, 0.0)
    var expanded := 0
    while not open.is_empty():
        var current: Vector2i = open.pop()
        if closed.has(current):
            continue
        closed[current] = true
        expanded += 1
        if expanded > max_expanded_tiles:
            push_warning("PathfindingService: gave up after %d tiles" % expanded)
            break
        for next in _neighbors(current, profile):
            if closed.has(next) or not can_step(current, next, profile):
                continue
            var cost: float = cost_of[current] + step_cost(current, next, profile)
            if cost > max_cost or cost >= cost_of.get(next, INF):
                continue
            cost_of[next] = cost
            prev[next] = current
            open.push(next, cost)
    return {"cost": cost_of, "prev": prev}

func get_reachable_tiles(field: Dictionary) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    for tile: Vector2i in field["cost"]:
        result.append(tile)
    return result

## Path (start and end included) to a tile of a field. Empty if it is not in the field.
func path_in_field(field: Dictionary, to: Vector2i) -> Array[Vector2i]:
    var cost: Dictionary = field["cost"]
    var path: Array[Vector2i] = []
    if not cost.has(to):
        return path
    var tile := to
    path.append(tile)
    var prev: Dictionary = field["prev"]
    while prev.has(tile):
        tile = prev[tile]
        path.append(tile)
    path.reverse()
    return path

## Total cost of walking a path (0 for an empty or one tile path).
func path_cost(path: Array[Vector2i], profile: MoveProfile = null) -> float:
    if profile == null:
        profile = MoveProfile.new()
    var total := 0.0
    for i in range(1, path.size()):
        total += step_cost(path[i - 1], path[i], profile)
    return total
#endregion


func _can_stand(tile: Vector2i, profile: MoveProfile, is_goal: bool) -> bool:
    if grid_service != null and not grid_service.is_inside_map(tile):
        return false
    if terrain_service != null and not terrain_service.is_walkable(tile):
        return false
    if occupancy_service != null and not (is_goal and profile.goal_may_be_occupied):
        if occupancy_service.is_occupied(tile, profile.blocked_by, profile.ignore):
            return false
    if profile.can_enter.is_valid() and not profile.can_enter.call(tile):
        return false
    return true

func _neighbors(tile: Vector2i, profile: MoveProfile) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    for offset in (GridService.NEIGHBORS_8 if profile.diagonals else GridService.NEIGHBORS_4):
        result.append(tile + offset)
    return result

# Octile distance with 8 directions, Manhattan with 4. Never more than the real cost (see min_cost).
func _distance(a: Vector2i, b: Vector2i, profile: MoveProfile) -> float:
    var dx := absi(a.x - b.x)
    var dy := absi(a.y - b.y)
    if not profile.diagonals:
        return float(dx + dy)
    return float(dx + dy) + (minf(profile.diagonal_factor, 2.0) - 2.0) * minf(dx, dy)

func _build_path(prev: Dictionary, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
    var path: Array[Vector2i] = [to]
    var tile := to
    while tile != from:
        tile = prev[tile]
        path.append(tile)
    path.reverse()
    return path
