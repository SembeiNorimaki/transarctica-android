class_name CoverService
extends Node
# How well a target is covered against a shooter: the best of the edge crossed by the shot on its
# last step, and the terrain of the target's own tile. Keeps no state, so it never needs refreshing
# when a wall is destroyed or a door opens.
#
# Games can add their own sources (sandbags made of units, crates...) with `extra_cover`.

var vision_service: VisionService # for the line between shooter and target
var edge_service: EdgeOccupancyService
var terrain_service: TerrainService

## Optional: func(shooter: Vector2i, target: Vector2i) -> int (a CoverLevel), combined with the rest.
var extra_cover: Callable


## CoverLevel the target has against a shooter on `shooter_tile`.
func get_cover(shooter_tile: Vector2i, target_tile: Vector2i) -> int:
    if shooter_tile == target_tile:
        return CoverLevel.NONE
    var best := CoverLevel.NONE
    if terrain_service != null:
        best = terrain_service.get_cover(target_tile)
    if edge_service != null and vision_service != null:
        var line := vision_service.get_line(shooter_tile, target_tile)
        best = maxi(best, edge_service.get_cover(line[line.size() - 2], target_tile))
    if extra_cover.is_valid():
        best = maxi(best, int(extra_cover.call(shooter_tile, target_tile)))
    return best

## Cover of a tile against a shooter standing one step away in each of the 8 directions, keyed by
## orientation ("N", "NE"...). For showing cover icons around a unit.
func get_directional_cover(tile: Vector2i) -> Dictionary:
    var result := {}
    for i in GridService.ORIENTATIONS.size():
        result[GridService.ORIENTATIONS[i]] = get_cover(tile + GridService.NEIGHBORS_8[i], tile)
    return result
