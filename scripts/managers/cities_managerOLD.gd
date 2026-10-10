extends Node
class_name CitiesManagerOLD

# Dependencies
var rail_service: RailService
var city_labels_container: Node2D
var grid_service: GridService

var cities = {} # EntryTile -> {name, city_tile}

func spawn_city(city_id: int, city_tile: Vector2i) -> void:
    #var city_name = GameState.cities_by_location.get(Vector2i(tile.x, tile.y), "NOOOO")
    var city_data = GameState.get_city_by_id(city_id)
    var city_name = city_data.Name
    var entry_tile = _compute_entry_tile(city_tile)
    cities[entry_tile] = {"name": city_name, "city_tile": city_tile, "city_id": city_id}
    create_label(city_name, city_tile)

func create_label(city_name: String, city_tile: Vector2i) -> void:
    var label = Label.new()
    label.text = city_name
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    city_labels_container.add_child(label)
    label.position = grid_service.tile_to_world(city_tile) + Vector2(0, -128)


func _compute_entry_tile(tile: Vector2i):
    if rail_service.has_rail(tile + Vector2i(1, 2)) and not rail_service.has_rail(tile + Vector2i(2, 2)):
        return tile + Vector2i(1, 2)
    elif rail_service.has_rail(tile + Vector2i(-1, 2)) and not rail_service.has_rail(tile + Vector2i(-2, 2)):
        return tile + Vector2i(-1, 2)
    
    elif rail_service.has_rail(tile + Vector2i(1, -2)) and not rail_service.has_rail(tile + Vector2i(2, -2)):
        return tile + Vector2i(1, -2)
    elif rail_service.has_rail(tile + Vector2i(-1, -2)) and not rail_service.has_rail(tile + Vector2i(-2, -2)):
        return tile + Vector2i(-1, -2)
    
    elif rail_service.has_rail(tile + Vector2i(2, 1)) and not rail_service.has_rail(tile + Vector2i(2, 2)):
        return tile + Vector2i(2, 1)
    elif rail_service.has_rail(tile + Vector2i(2, -1)) and not rail_service.has_rail(tile + Vector2i(2, -2)):
        return tile + Vector2i(2, -1)

    elif rail_service.has_rail(tile + Vector2i(-2, 1)) and not rail_service.has_rail(tile + Vector2i(-2, 2)):
        return tile + Vector2i(-2, 1)
    elif rail_service.has_rail(tile + Vector2i(-2, -1)) and not rail_service.has_rail(tile + Vector2i(-2, -2)):
        return tile + Vector2i(-2, -1)

func _compute_entry_tile_old(tile: Vector2i):
    for offset in [Vector2i(0, 2), Vector2i(0, -2), Vector2i(2, 0), Vector2i(-2, 0)]:
        if rail_service.has_rail(tile + offset):
            return tile + offset
    return tile + Vector2i(0, 2)

func get_city_by_entry_tile(tile: Vector2i) -> Dictionary:
    return cities.get(tile, null)

func is_entry_tile(tile: Vector2i) -> bool:
    return tile in cities
