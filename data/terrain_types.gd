class_name TerrainTypes
extends RefCounted
# Static data of the gameplay terrain of a tile (not to be confused with TerrainTiles, which only
# describes how the terrain TileSet is drawn). Used by TerrainService.
#
# Keys of a definition (all optional):
#   cost          : float, movement points needed to enter the tile, default 1.0
#   walkable      : bool, default true (false = nobody can enter, whatever the cost)
#   elevation     : int, default 0
#   blocks_vision : bool, default false
#   cover         : CoverLevel.NONE / HALF / FULL, default NONE
# New types can be added at runtime (a campaign, a mod) with TerrainTypes.register().

const DEFAULT_TYPE := "grass"

const DEFS := {
    "grass": {"cost": 1.0},
    "road": {"cost": 1.0},
    "sand": {"cost": 1.5},
    "snow": {"cost": 1.5},
    "mud": {"cost": 2.0},
    "forest": {"cost": 2.0, "cover": CoverLevel.HALF},
    "shallow_water": {"cost": 3.0},
    "deep_water": {"walkable": false},
    "rock": {"walkable": false, "blocks_vision": true, "cover": CoverLevel.FULL},
}

static var _defs: Dictionary = DEFS.duplicate(true)


static func exists(terrain_type: String) -> bool:
    return _defs.has(terrain_type)

static func get_def(terrain_type: String) -> Dictionary:
    return _defs.get(terrain_type, {})

static func register(terrain_type: String, definition: Dictionary) -> void:
    _defs[terrain_type] = definition.duplicate(true)

static func reset() -> void:
    _defs = DEFS.duplicate(true)

## The cheapest cost to enter any walkable tile. Used by pathfinding to keep its heuristic admissible.
static func min_cost() -> float:
    var best := INF
    for def: Dictionary in _defs.values():
        if def.get("walkable", true):
            best = minf(best, float(def.get("cost", 1.0)))
    return 1.0 if best == INF else best
