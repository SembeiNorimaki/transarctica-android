class_name MoveProfile
extends RefCounted
# How one mover sees the map when pathfinding: what blocks it and what it may do.
# Build one per mover (or per kind of mover) and pass it to PathfindingService.

## Allow the 8 directions (false = 4).
var diagonals := true
## Occupancy layers that stop this mover from entering a tile.
var blocked_by := TileOccupancyService.LAYER_UNIT | TileOccupancyService.LAYER_STRUCTURE | TileOccupancyService.LAYER_OBSTACLE
## Occupancy layers that make a diagonal step impossible when they stand on a tile it passes by
## (so nobody cuts around the corner of a building).
var corner_blocked_by := TileOccupancyService.LAYER_STRUCTURE | TileOccupancyService.LAYER_OBSTACLE
## The mover itself: its own tiles never block it.
var ignore: Object = null
## Highest elevation difference a single step can climb or drop.
var max_step_height := 1
## A diagonal step costs this much times the cost of the tile entered.
var diagonal_factor := 1.4142135
## Optional extra rule: func(tile: Vector2i) -> bool. Return false to forbid entering the tile.
var can_enter: Callable
## Optional extra cost: func(tile: Vector2i) -> float (>= 0), added to entering the tile.
var extra_cost: Callable
## The goal tile may be occupied (to walk up to an enemy, then path[-2] is where to stop).
var goal_may_be_occupied := false
