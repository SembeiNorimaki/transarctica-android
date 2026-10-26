extends Node
class_name CitiesManager

# Dependencies (injected by NavigationScene)
var rail_service: RailService
var city_labels_container: Node2D
var grid_service: GridService


const LABEL_OFFSET := Vector2(0, -128) # world px above the city tile
const LABEL_WIDTH := 200.0 # fixed width so the text can be centered

# entrance tile (Vector2i) -> {name: String, city_id: int}
# The id tile of the map sits ON the entrance, so this is filled straight from the map.
var cities: Dictionary = {}
var _labels: Array[Label] = []


# Call when a map is (re)loaded, before spawning cities.
func clear() -> void:
    for label in _labels:
        if is_instance_valid(label):
            label.queue_free()
    _labels.clear()
    cities.clear()


# `entrance_tile` is the tile where the id was placed on the CitiesIds tilemap.
# It no longer depends on the rails, so the order of the map setup doesn't matter.
func spawn_city(city_id: int, entrance_tile: Vector2i) -> void:
    var city_data = GameState.get_city_by_id(city_id)
    if not city_data: # null or empty
        push_error("CitiesManager: unknown city id %d at tile %s" % [city_id, entrance_tile])
        return
    var city_name: String = city_data.Name

    if not rail_service.has_rail(entrance_tile):
        push_warning("CitiesManager: entrance of '%s' at %s has no rail" % [city_name, entrance_tile])
    if cities.has(entrance_tile):
        push_warning("CitiesManager: '%s' and '%s' share entrance tile %s" % [cities[entrance_tile].name, city_name, entrance_tile])
    cities[entrance_tile] = {"name": city_name, "city_id": city_id}

    create_label(city_name, entrance_tile)


func create_label(city_name: String, entrance_tile: Vector2i) -> void:
    var label := Label.new()
    label.text = city_name
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.custom_minimum_size = Vector2(LABEL_WIDTH, 0.0)
    city_labels_container.add_child(label)
    # position is the top-left corner, so shift left by half the width to center it
    label.position = grid_service.tile_to_world(Vector2(entrance_tile)) + LABEL_OFFSET - Vector2(LABEL_WIDTH * 0.5, 0.0)
    _labels.append(label)


# Returns {} when the tile is not an entry tile.
func get_city_by_entry_tile(tile: Vector2i) -> Dictionary:
    return cities.get(tile, {})


func is_entry_tile(tile: Vector2i) -> bool:
    return cities.has(tile)