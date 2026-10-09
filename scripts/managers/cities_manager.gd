extends Node
class_name CitiesManager

# Dependencies (injected by NavigationScene)
var rail_service: RailService
var city_labels_container: Node2D
var grid_service: GridService

const NO_ENTRY := Vector2i(-999999, -999999) # sentinel: no entry tile found
const LABEL_OFFSET := Vector2(0, -128) # world px above the city tile
const LABEL_WIDTH := 200.0 # fixed width so the text can be centered

# Candidate entry tiles around a city tile, in priority order (first match wins).
# Each pair is [candidate, outward]. BOTH offsets are relative to the city tile.
# A candidate is accepted when it has rail and the outward tile does not.
const ENTRY_CANDIDATES := [
    [Vector2i(1, 2), Vector2i(2, 2)],
    [Vector2i(-1, 2), Vector2i(-2, 2)],

    [Vector2i(1, -2), Vector2i(2, -2)],
    [Vector2i(-1, -2), Vector2i(-2, -2)],

    [Vector2i(2, 1), Vector2i(2, 2)],
    [Vector2i(2, -1), Vector2i(2, -2)],

    [Vector2i(-2, 1), Vector2i(-2, 2)],
    [Vector2i(-2, -1), Vector2i(-2, -2)],
]

# entry_tile (Vector2i) -> {name: String, city_id: int, city_tile: Vector2i}
var cities: Dictionary = {}
var _labels: Array[Label] = []


# Call when a map is (re)loaded, before spawning cities.
func clear() -> void:
    for label in _labels:
        if is_instance_valid(label):
            label.queue_free()
    _labels.clear()
    cities.clear()


# Must run AFTER the rails of the map are registered in RailService,
# because the entry tile is found by looking at the rails around the city.
func spawn_city(city_id: int, city_tile: Vector2i) -> void:
    var city_data = GameState.get_city_by_id(city_id)
    if not city_data: # null or empty
        push_error("CitiesManager: unknown city id %d at tile %s" % [city_id, city_tile])
        return
    var city_name: String = city_data.Name

    var entry_tile := _find_entry_tile(city_tile)
    if entry_tile == NO_ENTRY:
        push_warning("CitiesManager: no entry tile found for city '%s' at %s (it can't be entered)" % [city_name, city_tile])
    else:
        if cities.has(entry_tile):
            push_warning("CitiesManager: '%s' and '%s' share entry tile %s" % [cities[entry_tile].name, city_name, entry_tile])
        cities[entry_tile] = {"name": city_name, "city_id": city_id, "city_tile": city_tile}

    create_label(city_name, city_tile)


func create_label(city_name: String, city_tile: Vector2i) -> void:
    var label := Label.new()
    label.text = city_name
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.custom_minimum_size = Vector2(LABEL_WIDTH, 0.0)
    city_labels_container.add_child(label)
    # position is the top-left corner, so shift left by half the width to center it
    label.position = grid_service.tile_to_world(Vector2(city_tile)) + LABEL_OFFSET - Vector2(LABEL_WIDTH * 0.5, 0.0)
    _labels.append(label)


func _find_entry_tile(city_tile: Vector2i) -> Vector2i:
    var matches: Array[Vector2i] = []
    for pair in ENTRY_CANDIDATES:
        var candidate: Vector2i = city_tile + pair[0]
        var outward: Vector2i = city_tile + pair[1]
        if rail_service.has_rail(candidate) and not rail_service.has_rail(outward):
            matches.append(candidate)

    if matches.is_empty():
        return NO_ENTRY
    if matches.size() > 1:
        push_warning("CitiesManager: city at %s has several possible entry tiles %s, using %s" % [city_tile, matches, matches[0]])
    return matches[0]


# Returns {} when the tile is not an entry tile.
func get_city_by_entry_tile(tile: Vector2i) -> Dictionary:
    return cities.get(tile, {})


func is_entry_tile(tile: Vector2i) -> bool:
    return cities.has(tile)