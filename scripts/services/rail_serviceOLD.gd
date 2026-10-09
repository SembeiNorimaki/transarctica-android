extends Node
class_name RailService

# Injected by NavigationScene
var rails_tilemap: TileMapLayer


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

const DIRS = {
    "N": Vector2i(0, -1),
    "E": Vector2i(1, 0),
    "S": Vector2i(0, 1),
    "W": Vector2i(-1, 0)
}

const EDGE_POS = {
    "N": Vector2(0.5, -0.5),
    "E": Vector2(0.5, 0.5),
    "S": Vector2(-0.5, 0.5),
    "W": Vector2(-0.5, -0.5)
}

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

const RAIL_TO_ORI = {
    "NW": "SW",
    "NE": "SE",
    "NS": "S",
    "NX": "S",

    "WN": "NE",
    "WE": "E",
    "WX": "E",
    "WS": "SE",

    "EN": "WN",
    "EW": "W",
    "EX": "W",
    "ES": "WS",

    "SN": "N",
    "SX": "N",
    "SW": "NW",
    "SE": "NE"
}

const junction_changes = {
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

const orientations = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]


#var rail_graph := {}
var rails = {} # tile -> rail_code (e.g. "NS", "EW", "NSe")
var edges = {} # tile -> Array[RailEdge]

func spawn_rail(tile: Vector2i, atlas_coords: Vector2i) -> void:
    var rail_name = ATLAS_TO_RAILNAME[atlas_coords]
    #print("Spawning rail %s at %s" % [rail_name, tile])
    # Place the simplest rail, atlascoords (0, 0)
    #rails_tilemap.set_cell(tile, 0, Vector2i(0, 0))
    # update internal graph
    #_add_to_graph(tile)
    _rebuild_edges_for_tile(tile, rail_name)

func spawn_bridge(tile: Vector2i, atlas_coords: Vector2i) -> void:
    var bridge_name = ATLAS_TO_RAILNAME[atlas_coords]
    #print("Spawning rail %s at %s" % [rail_name, tile])
    # Place the simplest rail, atlascoords (0, 0)
    #rails_tilemap.set_cell(tile, 0, Vector2i(0, 0))
    # update internal graph
    #_add_to_graph(tile)
    _rebuild_edges_for_tile(tile, bridge_name)

func _rebuild_edges_for_tile(tile: Vector2i, rail_name: String) -> void:
    edges[tile] = []
    var letters = rail_name.split("") # eg: ["N", "S"]

    rails[tile] = rail_name

    if letters.size() == 2:
        var a = letters[0]
        var b = letters[1]
        edges[tile].append(RailEdge.new(a, b, 1))

    elif letters.size() == 3: # Junctions
        var a = letters[0]
        var b = letters[1]
        var c = letters[2]
        edges[tile].append(RailEdge.new(a, b, 1))
        edges[tile].append(RailEdge.new(a, c, 1))
        edges[tile].append(RailEdge.new(b, c, 1))

    elif letters.size() == 4:
        var a = letters[0]
        var b = letters[1]
        var c = letters[2]
        var d = letters[3]
        edges[tile].append(RailEdge.new(a, b, 1))
        edges[tile].append(RailEdge.new(c, d, 1))
        

func get_tile_edges(tile: Vector2i) -> Array:
    return edges.get(tile, [])
    

# A tile has an array of edges, for example (1) NS for a single rail, or (3) NS, SE, NE for a junction
# When arriving to a tile, we need to know which edge we are using to arrive there
# We know old tile and new tile, so can compute delta. From delta we can get the entry edge
func calculate_new_orientation(tile: Vector2i, delta: Vector2i):
    var entry_edge = DELTA_TO_ENTRY_EDGE[delta]
    # We enter tile (1,1) from W
    # We need to know if this tile has an edge connecting W to somewhere
    var exit_edge = null
    # print("Calculating new orientation. Available edges:")
    for edge in edges[tile]:
        # print(" %s, %s " % [edge.a, edge.b])
        pass
    var edge = edges[tile][0]
    
    if edge.a == entry_edge:
        exit_edge = edge.b
    elif edge.b == entry_edge:
        exit_edge = edge.a
    else:
        # this is reached if the edge does not have the entry edge
        # which happens in junctions if we enter from the disconnected side
        pass
        
    
    if exit_edge:
        var edge_str = "%s%s" % [entry_edge, exit_edge]
        var new_ori = RAIL_TO_ORI[edge_str]
        # print("New orientation: %s" % new_ori)
        if new_ori in orientations:
            return new_ori
        else:
            new_ori = new_ori.reverse()
            return new_ori
    return null


func change_junction(tile: Vector2i) -> void:
    var rail_name = rails[tile]
    if junction_changes.has(rail_name):
        var new_tilename = junction_changes[rail_name]
        
        rails[tile] = new_tilename
        var letters = new_tilename.split("")
        var a = letters[0]
        var b = letters[1]
        var c = letters[2]
        edges[tile] = []
        edges[tile].append(RailEdge.new(a, b, 1))
        edges[tile].append(RailEdge.new(a, c, 1))
        edges[tile].append(RailEdge.new(b, c, 1))

        # print("changing junction from %s to %s" % [rail_name, new_tilename])
        var new_atlas_coords = RAILNAME_TO_ATLAS[new_tilename]
        rails_tilemap.set_cell(tile, 0, new_atlas_coords)

func has_junction(tile: Vector2i) -> bool:
    # print("Checking if tile %s is a junction: %s " % [tile, rails[tile]])
    return rails.has(tile) and rails[tile].length() == 3

func has_rail(tile: Vector2i) -> bool:
    return rails.has(tile)
#     return rail_graph.has(tile)

# func _add_to_graph(tile: Vector2i) -> void:
#     rail_graph[tile] = []
