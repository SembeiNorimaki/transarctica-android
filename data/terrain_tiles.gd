extends RefCounted
class_name TerrainTiles
# The tiles of the terrain TileSet, by the height of their four vertices.
#
# A tile is named with 4 letters, always in this order: n w e s (the four vertices of the diamond).
#   lowercase = the vertex is at the level of the current terrain
#   UPPERCASE = the vertex is at the level of the next terrain
# "nwes" is flat, "NWES" is flat one level up, "NWes" is a ramp: N and W are up, e and s are down.
#
# The atlas coordinates below are PLACEHOLDERS (row = how many vertices are up). Put the real ones.
# NONE means "this tile is not drawn yet".

const NONE := Vector2i(-1, -1)

const TILES := {
    # no vertex up
    "nwes": Vector2i(0, 0), # flat
    # one vertex up (a corner)
    "Nwes": Vector2i(2, 0),
    "nWes": Vector2i(4, 0),
    "nwEs": Vector2i(1, 0),
    "nweS": Vector2i(3, 0),
    # two vertices up that touch (a ramp)
    "NWes": Vector2i(2, 1),
    "NwEs": Vector2i(3, 1),
    "nWeS": Vector2i(0, 1),
    "nwES": Vector2i(1, 1),
    # two opposite vertices up (a saddle)
    "NweS": Vector2i(4, 1),
    "nWEs": Vector2i(0, 2),
    # three vertices up (one corner down)
    "NWEs": Vector2i(5, 2),
    "NWeS": Vector2i(5, 0),
    "NwES": Vector2i(5, 3),
    "nWES": Vector2i(5, 1),
    # all up: flat, one level higher. Normally not needed, the next level's "nwes" is used instead.
    "NWES": Vector2i(3, 6)
}

# The same 5 tiles as in TILES (flat and the four corners), for the lowest level (Terrain-1),
# which is the water level. Only these 5 have a water version: the other tiles are used as they are.
# NONE: the normal tile is used until the water tile is set.
const WATER_TILES := {
    "nwes": Vector2i(5, 4),
    "Nwes": Vector2i(1, 6),
    "nWes": Vector2i(5, 5),
    "nwEs": Vector2i(2, 6),
    "nweS": Vector2i(0, 6)
}

static var _by_coords: Dictionary = {} # Vector2i -> name. Built the first time it is needed


# The atlas coordinates of a tile name, or NONE if the name is unknown.
# `water`: the tile is for the lowest level (Terrain-1). It uses WATER_TILES where there is one.
static func coords_for(tile_name: String, water := false) -> Vector2i:
    if water:
        var water_coords: Vector2i = WATER_TILES.get(tile_name, NONE)
        if water_coords != NONE:
            return water_coords
    return TILES.get(tile_name, NONE)


# The tile name of the four vertices. `up_*` is true when that vertex is in the next level.
static func name_for(up_n: bool, up_w: bool, up_e: bool, up_s: bool) -> String:
    return ("N" if up_n else "n") + ("W" if up_w else "w") + ("E" if up_e else "e") + ("S" if up_s else "s")


# The name of the tile at these atlas coordinates, or "" if there is none.
static func name_at(coords: Vector2i) -> String:
    if _by_coords.is_empty():
        for tile_name in TILES:
            if TILES[tile_name] != NONE:
                _by_coords[TILES[tile_name]] = tile_name
    return _by_coords.get(coords, "")


# Names that are not valid or share the same coordinates (a typo here gives a wrong tile).
static func find_problems() -> Array[String]:
    var result: Array[String] = []
    var seen := {}
    for tile_name in TILES:
        if tile_name != name_for(tile_name[0] == "N", tile_name[1] == "W", tile_name[2] == "E", tile_name[3] == "S"):
            result.append("'%s' is not a valid tile name (use n w e s, in that order)" % tile_name)
        var coords: Vector2i = TILES[tile_name]
        if coords == NONE:
            continue
        if seen.has(coords):
            result.append("'%s' and '%s' have the same coordinates %s" % [seen[coords], tile_name, coords])
        seen[coords] = tile_name
    for tile_name in WATER_TILES:
        if not TILES.has(tile_name):
            result.append("'%s' in WATER_TILES is not in TILES" % tile_name)
    return result