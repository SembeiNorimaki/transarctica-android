extends Node
class_name CombatMapManager
# Turns a painted CombatMap into the state of the services: it sets up the grid, the terrain, the
# walls and doors and the objects. After that it keeps the drawing of the doors up to date when
# an edge changes. The map itself never knows about the services.

# Injected by the scene
var combat_map: CombatMap
var grid_service: GridService
var terrain_service: TerrainService
var edge_service: EdgeOccupancyService
var occupancy_service: TileOccupancyService

var objects: Array[MapObject] = []


# Call once, after the injection
func setup() -> void:
    assert(combat_map != null and grid_service != null and terrain_service != null \
            and edge_service != null and occupancy_service != null, "CombatMapManager: not injected")
    _setup_grid()
    terrain_service.load_from_layer(combat_map.ground)
    _load_edges()
    _load_objects()
    combat_map.set_spawns_visible(false)
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

func _on_edge_changed(a: Vector2i, b: Vector2i) -> void:
    var edge := edge_service.get_edge(a, b)
    if edge == null:
        combat_map.clear_edge_visual(a, b)
    else:
        combat_map.set_edge_visual(a, b, edge.type, edge.is_open)
