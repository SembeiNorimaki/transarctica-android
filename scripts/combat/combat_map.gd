extends Node2D
class_name CombatMap
# The battlefield as the designer paints it, one TileMapLayer per kind of thing:
#   Ground   : the terrain of each tile (custom data "terrain", see TerrainTypes)
#   Objects  : crates, containers... standing on a tile (custom data "object_type")
#   WallsSE  : walls, fences, windows and doors between a tile and its x+1 neighbor,
#              painted on the SE side of the tile (custom data "edge_type", "edge_open")
#   WallsSW  : the same between a tile and its y+1 neighbor, painted on the SW side
#   Spawns   : markers where soldiers start (custom data "spawn_team", "spawn_type")
# Each border between two tiles belongs to exactly one wall layer cell, so a tile can have walls on
# all its sides. To put a wall on the NE or NW side of a tile, paint it in the neighbor.
#
# This node only reads and draws: it never creates services or soldiers. CombatMapManager reads it
# and fills the services. All layers share the same tile size and are isometric (diamond down).
#
# The map is Y-sorted, so a unit that is added as a child of this node (a UnitContainer) is drawn
# behind the walls and objects in front of it, and in front of those behind it.

@onready var ground: TileMapLayer = $Ground
@onready var objects: TileMapLayer = $Objects
@onready var walls_se: TileMapLayer = $WallsSE
@onready var walls_sw: TileMapLayer = $WallsSW
@onready var spawns: TileMapLayer = $Spawns

# (edge_type, open) -> atlas coords in the wall tilesets, built once
var _wall_tiles := {}


func _ready() -> void:
    _wall_tiles = _index_wall_tiles(walls_se)


func get_tile_size() -> Vector2i:
    return ground.tile_set.tile_size

## The tiles of the battlefield: the area the ground covers.
func get_map_rect() -> Rect2i:
    return ground.get_used_rect()


#region reading
## [{"tile": Vector2i, "type": String}] for each painted object.
func read_objects() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for cell in objects.get_used_cells():
        var object_type := _custom(objects, cell, "object_type")
        if object_type != "":
            result.append({"tile": cell, "type": object_type})
    return result

## [{"a": Vector2i, "b": Vector2i, "type": String, "open": bool}] for each wall, fence, window or door.
func read_edges() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    _read_wall_layer(walls_se, Vector2i(1, 0), result)
    _read_wall_layer(walls_sw, Vector2i(0, 1), result)
    return result

## [{"tile": Vector2i, "team": String, "unit_type": String}] for each spawn marker.
func read_spawns() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for cell in spawns.get_used_cells():
        var team := _custom(spawns, cell, "spawn_team")
        if team != "":
            result.append({"tile": cell, "team": team, "unit_type": _custom(spawns, cell, "spawn_type")})
    return result
#endregion


#region drawing
## Redraws the wall between two neighboring tiles for the state of its edge (a door opening or
## closing). Does nothing if there is no such tile painted there.
func set_edge_visual(a: Vector2i, b: Vector2i, edge_type: String, open: bool) -> void:
    var spot := _wall_cell(a, b)
    if spot.is_empty():
        return
    var layer: TileMapLayer = spot["layer"]
    var coords: Variant = _wall_tiles.get([edge_type, open], null)
    if coords != null:
        layer.set_cell(spot["cell"], 0, coords)

## Erases the wall between two neighboring tiles (it was destroyed).
func clear_edge_visual(a: Vector2i, b: Vector2i) -> void:
    var spot := _wall_cell(a, b)
    if not spot.is_empty():
        (spot["layer"] as TileMapLayer).erase_cell(spot["cell"])

func set_spawns_visible(value: bool) -> void:
    spawns.visible = value
#endregion


func _read_wall_layer(layer: TileMapLayer, side: Vector2i, into: Array[Dictionary]) -> void:
    for cell in layer.get_used_cells():
        var edge_type := _custom(layer, cell, "edge_type")
        if edge_type == "":
            continue
        var data := layer.get_cell_tile_data(cell)
        into.append({"a": cell, "b": cell + side, "type": edge_type, "open": bool(data.get_custom_data("edge_open"))})

# Which layer and cell draws the border between two neighbors.
func _wall_cell(a: Vector2i, b: Vector2i) -> Dictionary:
    var d := b - a
    if d == Vector2i(1, 0):
        return {"layer": walls_se, "cell": a}
    if d == Vector2i(-1, 0):
        return {"layer": walls_se, "cell": b}
    if d == Vector2i(0, 1):
        return {"layer": walls_sw, "cell": a}
    if d == Vector2i(0, -1):
        return {"layer": walls_sw, "cell": b}
    return {}

func _index_wall_tiles(layer: TileMapLayer) -> Dictionary:
    var index := {}
    var source := layer.tile_set.get_source(0) as TileSetAtlasSource
    for i in source.get_tiles_count():
        var coords := source.get_tile_id(i)
        var data := source.get_tile_data(coords, 0)
        index[[str(data.get_custom_data("edge_type")), bool(data.get_custom_data("edge_open"))]] = coords
    return index

func _custom(layer: TileMapLayer, cell: Vector2i, key: String) -> String:
    var data := layer.get_cell_tile_data(cell)
    return "" if data == null else str(data.get_custom_data(key))
