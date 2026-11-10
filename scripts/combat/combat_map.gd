extends Node2D
class_name CombatMap
# The battlefield as the designer paints it, one TileMapLayer per kind of thing:
#   Ground   : the terrain of each tile (custom data "terrain", see TerrainTypes)
#   Objects  : crates, containers... standing on a tile (custom data "object_type")
#   WallsX   : walls, fences, windows and doors between a tile and its x+1 neighbor
#              (custom data "edge_type", "edge_open"). Drawn on the east side of the tile
#              (south-east on an isometric map).
#   WallsY   : the same between a tile and its y+1 neighbor. Drawn on the south side of the tile
#              (south-west on an isometric map).
#   Roads    : optional. Road tiles over the ground (custom data "terrain", see TerrainTypes)
#   Buildings: optional. Placeholders: one tile per building, painted on its first tile (the north
#              corner, the one with the smallest x and y). Which building a tile is comes from
#              data/combat_tiles.json (BuildingTypes has its size: 1 x 1 up to 4 x 4). At run time
#              CombatMapManager hides this layer and puts a GenericBuilding where each tile is.
#   Spawns   : markers where units start. Which unit (and which way it faces) a tile is comes from
#              data/combat_tiles.json too.
#   Fog      : drawn by FogManager over everything (unexplored, explored; visible = no tile)
# Each border between two tiles belongs to exactly one wall layer cell, so a tile can have walls on
# all its sides. To put a wall on the north or west side of a tile, paint it in the neighbor.
#
# This node only reads and draws: it never creates services or soldiers. CombatMapManager reads it
# and fills the services. All layers share the same tile size. The map can be ISOMETRIC (diamond
# down) or SQUARE (cartesian): it is the TileSet's tile shape that says which, and nothing else
# changes. combat_map.tscn is the isometric one, combat_map_square.tscn the square one.
#
# The map is Y-sorted, so a unit that is added as a child of this node (a UnitContainer) is drawn
# behind the walls and objects in front of it, and in front of those behind it.

@onready var ground: TileMapLayer = $Ground
@onready var objects: TileMapLayer = $Objects
@onready var walls_x: TileMapLayer = $WallsX
@onready var walls_y: TileMapLayer = $WallsY
@onready var roads: TileMapLayer = get_node_or_null("Roads") # optional
@onready var buildings: TileMapLayer = get_node_or_null("Buildings") # optional
@onready var spawns: TileMapLayer = $Spawns
@onready var fog: TileMapLayer = $Fog

const ROAD_STEPS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)] # N E S W

# (edge_type, open) -> atlas coords in the wall tilesets, built once
var _wall_tiles := {}


func _ready() -> void:
    _wall_tiles = _index_wall_tiles(walls_x)


func get_tile_size() -> Vector2i:
    return ground.tile_set.tile_size

## How the tiles are drawn, from the ground TileSet: isometric or square.
func get_projection() -> GridService.TileProjection:
    if ground.tile_set.tile_shape == TileSet.TILE_SHAPE_SQUARE:
        return GridService.TileProjection.CARTESIAN
    return GridService.TileProjection.ISOMETRIC

## Where the center of tile (0, 0) is drawn, in this node's coordinates.
func get_origin_offset() -> Vector2:
    return ground.map_to_local(Vector2i.ZERO)

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

## One element for each building placeholder:
## {"tile": its first tile, "type": String, "size": Vector2i, "texture": the picture of the placeholder,
##  "texture_origin": Vector2, "y_sort_origin": int}. It covers size.x * size.y tiles from `tile`.
func read_buildings() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    if buildings == null:
        return result
    var tileset_path := buildings.tile_set.resource_path
    for cell in buildings.get_used_cells():
        var source_id := buildings.get_cell_source_id(cell)
        var coords := buildings.get_cell_atlas_coords(cell)
        var building_type := str(CombatTiles.lookup(tileset_path, source_id, coords).get("building_type", ""))
        if not BuildingTypes.exists(building_type):
            push_warning("CombatMap: tile %s of the Buildings layer (atlas %d, %s) is not a known building in %s" % [cell, source_id, coords, CombatTiles.PATH])
            continue
        result.append(_building_data(source_id, coords, building_type, cell))
    return result

## The same for a building of this type that is not painted: its picture is that of its placeholder
## tile. Empty if the Buildings layer has no tile for this type (see data/combat_tiles.json).
func make_building_data(building_type: String, tile: Vector2i) -> Dictionary:
    if buildings == null:
        return {}
    for entry in CombatTiles.get_entries(buildings.tile_set.resource_path):
        if str(entry.get("building_type", "")) == building_type:
            return _building_data(int(entry["atlas_id"]), entry["coords"], building_type, tile)
    return {}

## [{"a": Vector2i, "b": Vector2i, "type": String, "open": bool}] for each wall, fence, window or door.
func read_edges() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    _read_wall_layer(walls_x, Vector2i(1, 0), result)
    _read_wall_layer(walls_y, Vector2i(0, 1), result)
    return result

## [{"tile": Vector2i, "team": String, "unit_type": String, "facing": String}] for each spawn
## marker. "facing" is only there for the markers that say it (the vehicle markers: one per facing).
func read_spawns() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var tileset_path := spawns.tile_set.resource_path
    for cell in spawns.get_used_cells():
        var entry := CombatTiles.lookup(tileset_path, spawns.get_cell_source_id(cell), spawns.get_cell_atlas_coords(cell))
        if not entry.has("unit_type"):
            push_warning("CombatMap: tile %s of the Spawns layer is not a known unit in %s" % [cell, CombatTiles.PATH])
            continue
        var spawn := {"tile": cell, "team": str(entry["team"]), "unit_type": str(entry["unit_type"])}
        if entry.has("facing"):
            spawn["facing"] = str(entry["facing"])
        result.append(spawn)
    return result
#endregion


#region roads
## Is there a road tile (of the Roads layer) here?
func has_road(tile: Vector2i) -> bool:
    return roads != null and roads.get_cell_source_id(tile) != -1

## Draws a road on the tile. The roads join: this tile and its road neighbors are drawn with the
## piece that has an arm towards each neighbor (the atlas column is a bit mask: north 1, east 2,
## south 4, west 8, as the tiles are drawn).
func set_road(tile: Vector2i) -> void:
    if roads == null:
        return
    _draw_road(tile)
    for step in ROAD_STEPS:
        if has_road(tile + step):
            _draw_road(tile + step)

func _draw_road(tile: Vector2i) -> void:
    var mask := 0
    for i in ROAD_STEPS.size():
        if has_road(tile + ROAD_STEPS[i]):
            mask |= 1 << i
    roads.set_cell(tile, 0, Vector2i(mask, 0))
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

## The placeholder tiles of the Buildings layer (GenericBuildings are drawn instead).
func set_building_placeholders_visible(value: bool) -> void:
    if buildings != null:
        buildings.visible = value
#endregion


func _building_data(source_id: int, coords: Vector2i, building_type: String, cell: Vector2i) -> Dictionary:
    var source := buildings.tile_set.get_source(source_id) as TileSetAtlasSource
    var tile_data := source.get_tile_data(coords, 0)
    var texture := AtlasTexture.new()
    texture.atlas = source.texture
    texture.region = source.get_tile_texture_region(coords)
    return {
        "tile": cell, "type": building_type, "size": BuildingTypes.get_size(building_type),
        "texture": texture, "texture_origin": Vector2(tile_data.texture_origin), "y_sort_origin": tile_data.y_sort_origin,
    }

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
        return {"layer": walls_x, "cell": a}
    if d == Vector2i(-1, 0):
        return {"layer": walls_x, "cell": b}
    if d == Vector2i(0, 1):
        return {"layer": walls_y, "cell": a}
    if d == Vector2i(0, -1):
        return {"layer": walls_y, "cell": b}
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
