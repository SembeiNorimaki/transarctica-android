extends Node
class_name CombatMapManager
# Turns a painted CombatMap into the state of the services: it sets up the grid, the terrain, the
# walls and doors, the objects and the buildings. After that it keeps the drawing of the doors up to
# date when an edge changes, and frees the tiles of a building that is destroyed. The map itself
# never knows about the services.

# Injected by the scene
var combat_map: CombatMap
var grid_service: GridService
var terrain_service: TerrainService
var edge_service: EdgeOccupancyService
var occupancy_service: TileOccupancyService
## Where the GenericBuildings are put: a Y-sorted node, a sibling of the units' container. Needed
## only if the map has a Buildings layer.
var building_container: Node2D

const BUILDING_SCENE: PackedScene = preload("res://scenes/buildings/generic_building.tscn")

signal building_destroyed(building: GenericBuilding)

var objects: Array[MapObject] = []
var buildings: Array[GenericBuilding] = []


# Call once, after the injection
func setup() -> void:
    assert(combat_map != null and grid_service != null and terrain_service != null \
            and edge_service != null and occupancy_service != null, "CombatMapManager: not injected")
    _setup_grid()
    terrain_service.load_from_layer(combat_map.ground)
    if combat_map.roads != null:
        terrain_service.load_from_layer(combat_map.roads) # roads over the ground
    _load_edges()
    _load_objects()
    _load_buildings()
    combat_map.set_spawns_visible(false)
    combat_map.set_building_placeholders_visible(false)
    edge_service.edge_changed.connect(_on_edge_changed)


## The soldiers to deploy: [{"tile", "team", "unit_type"}]
func get_spawns() -> Array[Dictionary]:
    return combat_map.read_spawns()

## Opens or closes every door of the map. Returns how many there are.
func set_all_doors_open(open: bool) -> int:
    var count := 0
    for door in combat_map.read_edges():
        if door["type"] == "door" and edge_service.set_open(door["a"], door["b"], open):
            count += 1
    return count

func toggle_all_doors() -> void:
    var any_closed := false
    for door in combat_map.read_edges():
        var edge := edge_service.get_edge(door["a"], door["b"])
        if edge != null and edge.can_toggle() and not edge.is_open:
            any_closed = true
    set_all_doors_open(any_closed)


func _setup_grid() -> void:
    grid_service.set_projection(combat_map.get_projection())
    grid_service.set_tile_size(combat_map.get_tile_size())
    grid_service.tile_center_offset = combat_map.get_origin_offset()
    grid_service.set_map_rect(combat_map.get_map_rect())
    occupancy_service.bounds = combat_map.get_map_rect()

func _load_edges() -> void:
    for data in combat_map.read_edges():
        var edge := edge_service.add(data["a"], data["b"], data["type"])
        if edge != null and data["open"]:
            edge_service.set_open(data["a"], data["b"], true)

func _load_objects() -> void:
    for data in combat_map.read_objects():
        if not CombatObjectTypes.exists(data["type"]):
            push_warning("CombatMapManager: unknown object type '%s' at %s" % [data["type"], data["tile"]])
            continue
        var object := MapObject.new(data["type"], data["tile"])
        occupancy_service.place(object, object.tile, Footprint.single(), CombatObjectTypes.get_layer(object.type))
        objects.append(object)

# A GenericBuilding takes the place of each building placeholder of the map. It blocks movement and
# sight on all the tiles it covers, until it is destroyed.
func _load_buildings() -> void:
    var placeholders := combat_map.read_buildings()
    if placeholders.is_empty():
        return
    assert(building_container != null, "CombatMapManager: the map has buildings but no building_container is injected")
    for data in placeholders:
        var building := BUILDING_SCENE.instantiate() as GenericBuilding
        building_container.add_child(building)
        building.setup(data, grid_service.tile_to_world(Vector2(data["tile"])), grid_service.tile_size)
        var size: Vector2i = data["size"]
        occupancy_service.place(building, building.tile, Footprint.rect(size.x, size.y), TileOccupancyService.LAYER_STRUCTURE)
        building.destroyed.connect(_on_building_destroyed)
        buildings.append(building)

## The building that covers this tile (null if there is none, or it is destroyed).
func get_building_at(tile: Vector2i) -> GenericBuilding:
    return occupancy_service.get_first_at(tile, TileOccupancyService.LAYER_STRUCTURE) as GenericBuilding

func _on_building_destroyed(building: GenericBuilding) -> void:
    occupancy_service.remove(building) # units can walk and see through the rubble
    building_destroyed.emit(building)

func _on_edge_changed(a: Vector2i, b: Vector2i) -> void:
    var edge := edge_service.get_edge(a, b)
    if edge == null:
        combat_map.clear_edge_visual(a, b)
    else:
        combat_map.set_edge_visual(a, b, edge.type, edge.is_open)
