extends Node
class_name RailService

# Emitted when a junction switches. The scene (not this service) updates the tilemap.
signal rail_changed(tile: Vector2i)

# Injected by NavigationScene
var rails_tilemap: TileMapLayer
var grid_service: GridService

#region Constants
const ATLAS_TO_RAILNAME = {
    Vector2i(0, 0): "WE",
    Vector2i(1, 0): "NS",
    Vector2i(2, 0): "NW",
    Vector2i(3, 0): "NSW",

    Vector2i(0, 1): "SE",
    Vector2i(1, 1): "NE",
    Vector2i(2, 1): "SW",
    Vector2i(3, 1): "NSE",

    Vector2i(0, 2): "NSWE",
    Vector2i(1, 2): "",
    Vector2i(2, 2): "",
    Vector2i(3, 2): "NEW",

    Vector2i(0, 3): "",
    Vector2i(1, 3): "",
    Vector2i(2, 3): "",
    Vector2i(3, 3): "NES",

    Vector2i(0, 4): "NWSE",
    Vector2i(1, 4): "NESW",
    Vector2i(2, 4): "",
    Vector2i(3, 4): "SEW",

    Vector2i(0, 5): "NWS",
    Vector2i(1, 5): "NWE",
    Vector2i(2, 5): "SWN",
    Vector2i(3, 5): "SEN",

    Vector2i(0, 6): "SWE",
    Vector2i(1, 6): "WEN",
    Vector2i(2, 6): "WES",
    Vector2i(3, 6): "NX",

    Vector2i(0, 7): "WX",
    Vector2i(1, 7): "EX",
    Vector2i(2, 7): "SX",
    Vector2i(3, 7): ""
}

const RAILNAME_TO_ATLAS = {
    "WE": Vector2i(0, 0),
    "NS": Vector2i(1, 0),
    "NW": Vector2i(2, 0),
    "NSW": Vector2i(3, 0),
    "SE": Vector2i(0, 1),
    "NE": Vector2i(1, 1),
    "SW": Vector2i(2, 1),
    "NSE": Vector2i(3, 1),
    "NSWE": Vector2i(0, 2),
    "NEW": Vector2i(3, 2),
    "NES": Vector2i(3, 3),
    "NWSE": Vector2i(0, 4),
    "NESW": Vector2i(1, 4),
    "SEW": Vector2i(3, 4),
    "NWS": Vector2i(0, 5),
    "NWE": Vector2i(1, 5),
    "SWN": Vector2i(2, 5),
    "SEN": Vector2i(3, 5),
    "SWE": Vector2i(0, 6),
    "WEN": Vector2i(1, 6),
    "WES": Vector2i(2, 6),
    "NX": Vector2i(3, 6),
    "WX": Vector2i(0, 7),
    "EX": Vector2i(1, 7),
    "SX": Vector2i(2, 7)
}

const ATLAS_TO_BRIDGENAME = {
    Vector2i(0, 0): "WE",
    Vector2i(1, 0): "NS"
}

const BRIDGENAME_TO_ATLAS = {
    "WE": Vector2i(0, 0),
    "NS": Vector2i(1, 0)
}

# Edge letter -> tile delta (tile space)
const DIRS = {
    "N": Vector2i(0, -1),
    "E": Vector2i(1, 0),
    "S": Vector2i(0, 1),
    "W": Vector2i(-1, 0)
}

# Edge midpoints in half-tile units. Not used here; kept in case RailsOverlay reads it.
const EDGE_POS = {
    "N": Vector2(0.5, -0.5),
    "E": Vector2(0.5, 0.5),
    "S": Vector2(-0.5, 0.5),
    "W": Vector2(-0.5, -0.5)
}

# Moving by `delta` into a tile means entering it through this edge.
const DELTA_TO_ENTRY_EDGE = {
    Vector2i(1, 0): "W",
    Vector2i(-1, 0): "E",
    Vector2i(0, 1): "N",
    Vector2i(0, -1): "S"
}

const OPPOSITE_EDGE = {
    "N": "S",
    "S": "N",
    "E": "W",
    "W": "E"
}

# Tile-space delta -> orientation (same convention as GridService).
# Only used with single-step cardinal or diagonal deltas.
const DELTA_TO_ORI = {
    Vector2i(0, -1): "N",
    Vector2i(1, -1): "NE",
    Vector2i(1, 0): "E",
    Vector2i(1, 1): "SE",
    Vector2i(0, 1): "S",
    Vector2i(-1, 1): "SW",
    Vector2i(-1, 0): "W",
    Vector2i(-1, -1): "NW"
}

# Junction switch cycle. In a 3-letter name, the first two letters are the ACTIVE route.
const JUNCTION_CHANGES = {
    "NSW": "NWS",
    "NWS": "SWN",
    "SWN": "NSW",

    "NSE": "NES",
    "NES": "SEN",
    "SEN": "NSE",

    "SEW": "SWE",
    "SWE": "WES",
    "WES": "SEW",

    "NEW": "NWE",
    "NWE": "WEN",
    "WEN": "NEW"
}
#endregion

#region State
var rails := {} # tile -> rail name (e.g. "NS", "NSW")
var edges := {} # tile -> Array[RailEdge]. For junctions, [0] is the ACTIVE route (kept for the overlay)
#var bridges := {} # tile -> bridge name. TODO: bridges need their own routing layer
var _routes := {} # tile -> {entry_edge: exit_edge}, active routes only
#endregion


#region Registration
func clear() -> void:
    rails.clear()
    edges.clear()
    #bridges.clear()
    _routes.clear()

# Registers the rail found at `tile` (nothing is spawned; the tile already exists in the tilemap)
func spawn_rail(tile: Vector2i, atlas_coords: Vector2i) -> void:
    var rail_name: String = ATLAS_TO_RAILNAME.get(atlas_coords, "")
    if rail_name.is_empty():
        push_warning("RailService: no rail for atlas %s at tile %s" % [atlas_coords, tile])
        return
    _rebuild_edges_for_tile(tile, rail_name)

# Bridges are stored separately so they don't overwrite the rail under them.
# TODO: make calculate_new_orientation aware of bridges when you enable them.
# func spawn_bridge(tile: Vector2i, atlas_coords: Vector2i) -> void:
#     var bridge_name: String = ATLAS_TO_BRIDGENAME.get(atlas_coords, "")
#     if bridge_name.is_empty():
#         push_warning("RailService: no bridge for atlas %s at tile %s" % [atlas_coords, tile])
#         return
#     bridges[tile] = bridge_name

func _rebuild_edges_for_tile(tile: Vector2i, rail_name: String) -> void:
    var l := rail_name.split("")
    var list: Array = []

    match l.size():
        2:
            list.append(RailEdge.new(l[0], l[1], 1))
        3: # Junction: [0] is the active route, [1] and [2] are the other switch states
            list.append(RailEdge.new(l[0], l[1], 1))
            list.append(RailEdge.new(l[0], l[2], 1))
            list.append(RailEdge.new(l[1], l[2], 1))
        4: # Crossing or double curve: both pairs are active
            list.append(RailEdge.new(l[0], l[1], 1))
            list.append(RailEdge.new(l[2], l[3], 1))
        _:
            push_warning("RailService: unsupported rail name '%s' at tile %s" % [rail_name, tile])
            return

    rails[tile] = rail_name
    edges[tile] = list

    # Active routes: only the first edge for junctions, every edge otherwise
    var active: Array = list.slice(0, 1) if l.size() == 3 else list
    var route := {}
    for e in active:
        route[e.a] = e.b
        route[e.b] = e.a
    _routes[tile] = route

func get_tile_edges(tile: Vector2i) -> Array:
    return edges.get(tile, [])
#endregion


#region Routing
# Returns the orientation to use after entering `tile` with a move of `delta`,
# or "" if the train can't continue (no rail, inactive side of a junction, unexpected delta).
#
# A tile is a set of edge pairs. From `delta` we know the entry edge, and the route gives
# the exit edge. Straight: keep the delta. Curve: the diagonal between delta and the exit direction.
func calculate_new_orientation(tile: Vector2i, delta: Vector2i) -> String:
    var entry_edge: String = DELTA_TO_ENTRY_EDGE.get(delta, "")
    if entry_edge.is_empty():
        push_warning("RailService: unexpected delta %s entering tile %s" % [delta, tile])
        return ""

    var exit_edge: String = _routes.get(tile, {}).get(entry_edge, "")
    if exit_edge.is_empty():
        return "" # no rail here, or entering a junction from its disconnected side

    if exit_edge == "X" or DIRS[exit_edge] == delta:
        return grid_service.get_orientation(Vector2i.ZERO, delta) # straight
    return grid_service.get_orientation(Vector2i.ZERO, delta + DIRS[exit_edge]) # curve: diagonal

#endregion


#region Junctions
func change_junction(tile: Vector2i) -> void:
    var next_name: String = JUNCTION_CHANGES.get(rails.get(tile, ""), "")
    if next_name.is_empty():
        return
    _rebuild_edges_for_tile(tile, next_name)
    # The scene updates the tilemap:
    # rails_tilemap.set_cell(tile, 0, RAILNAME_TO_ATLAS[rails[tile]])
    rail_changed.emit(tile)

func has_junction(tile: Vector2i) -> bool:
    return rails.has(tile) and rails[tile].length() == 3

func has_rail(tile: Vector2i) -> bool:
    return rails.has(tile)
#endregion