extends Node

# Autoload. Single source of truth for persistent game data (cities, player train).
#
# Cities are stored by name. To look cities up by location or id, the correspondence
# dictionaries below are used. Always go through the API:
#   get_city_by_name / get_city_by_location / get_city_by_id
#
# NOTE: the getters return the INTERNAL dictionaries, not copies. Changes made to them are live
# immediately. Use .duplicate(true) if you need to edit and be able to cancel (e.g. a trade preview).
#
# Cities JSON (keyed by city id):
#   "<id>": {
#       "Name": String,
#       "Location": [x, y],
#       "TradeResources": { "<Resource>": {"Quantity": n, "SellPrice": n, "BuyPrice": n} }
#   }
# Player train JSON: see data/newgame/player_train.json
#   (id, owner, position [x, y, ori], fuel, max_fuel, max_speed, acceleration, deceleration, wagons[])
#
# JSON numbers are loaded as floats (3 -> 3.0). Convert with int() where an int is required.
 

const CITIES_PATH := "res://data/newgame/cities_World2.json"
const PLAYER_TRAIN_PATH := "res://data/newgame/player_train.json"

var _cities_state: Dictionary = {} # city name -> city data
var _cities_by_location: Dictionary = {} # Vector2i -> city name
var _cities_by_id: Dictionary = {} # int -> city name
var _player_train_state: Dictionary = {}

var _player_money := 100 # TODO: load the starting value from data

var state := {
    "cities": {},
}

# # this are examples for showing the structure of the data. They are removed when loading data from JSON files
# var _cities_state = {
#     "ËxampleCity": {
#         "TradeResources": {
#             "Oil": {
#                 "Quantity": 3,
#                 "SellPrice": 4,
#                 "BuyPrice": 5
#             },
#             "Alcohol": {
#                 "Quantity": 6,
#                 "SellPrice": 7,
#                 "BuyPrice": 8
#             }
#         }
#     }
# }

# var _player_train_state = {
#     "id": "TP0",
#     "owner": "Player",
#     "position": [2, 4, "E"],
    
#     "fuel": 40,
#     "max_fuel": 100,
#     "max_speed": 100,
#     "acceleration": 10,
#     "deceleration": 20,

#     "wagons": [
#         {
#             "type": "locomotive",
#             "hp": 100,
#             "max_hp": 100,
#             "capacity": 0,
#             "cargo_name": "",
#             "cargo_qty": 0
#         },
#         {
#             "type": "tender",
#             "hp": 60,
#             "max_hp": 60,
#             "capacity": 100,
#             "cargo_name": "coal",
#             "cargo_qty": 40
#         },
#         {
#             "type": "merchandise",
#             "hp": 40,
#             "max_hp": 40,
#             "capacity": 20,
#             "cargo_name": "caviar",
#             "cargo_qty": 3
#         }
#     ]
# }


#region initialization
func _ready() -> void:
    _load_initial_cities(CITIES_PATH)
    _load_initial_player_train(PLAYER_TRAIN_PATH)

# Returns the parsed JSON, or null (with an error) if the file is missing or invalid.
func _read_json(path: String) -> Variant:
    if not FileAccess.file_exists(path):
        push_error("GameState: file not found: %s" % path)
        return null
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("GameState: cannot open %s (error %d)" % [path, FileAccess.get_open_error()])
        return null
    var data = JSON.parse_string(file.get_as_text())
    if data == null:
        push_error("GameState: invalid JSON in %s" % path)
    return data

# Loads cities into _cities_state, _cities_by_location and _cities_by_id.
# Public so a "new game" flow can reload them.
func _load_initial_cities(path: String):
    _cities_state = {}
    _cities_by_location = {}
    _cities_by_id = {}

    var data = _read_json(path)
    if not (data is Dictionary):
        push_error("GameState: %s must contain a JSON object of cities" % path)
        return
 
    for key in data.keys():
        var city = data[key]
        if not str(key).is_valid_int():
            push_error("GameState: city key '%s' in %s is not an integer id" % [key, path])
            continue
        if not (city is Dictionary) or not city.has("Name") or not city.has("Location"):
            push_error("GameState: city '%s' in %s needs Name and Location" % [key, path])
            continue
        var location = city["Location"]
        if not (location is Array) or location.size() < 2:
            push_error("GameState: city '%s' has an invalid Location" % key)
            continue
 
        var city_name: String = city["Name"]
        if _cities_state.has(city_name):
            push_warning("GameState: duplicate city name '%s' (id %s), the later one overwrites the earlier" % [city_name, key])
 
        _cities_by_location[Vector2i(int(location[0]), int(location[1]))] = city_name
        _cities_by_id[int(key)] = city_name
        _cities_state[city_name] = city

    # var file = FileAccess.open(filename, FileAccess.READ)
    # var data = JSON.parse_string(file.get_as_text())
    # for city_id in data.keys():
    #     var city_name = data[city_id].Name
    #     var city_location = Vector2i(data[city_id].Location[0], data[city_id].Location[1])
    #     _cities_by_location[city_location] = city_name
    #     _cities_by_id[int(city_id)] = city_name
    #     _cities_state[city_name] = data[city_id]


# Loads the initial player train into _player_train_state.
func _load_initial_player_train(path: String) -> void:
    _player_train_state = {}
    var data = _read_json(path)
    if not (data is Dictionary):
        push_error("GameState: %s must contain a JSON object" % path)
        return
    _player_train_state = data
#endregion

#region publicAPI

# Player Train State
func get_player_train() -> Dictionary:
    return _player_train_state

func set_player_train(player_train_data: Dictionary) -> void:
    _player_train_state = player_train_data

# TODO: not implemented yet. The data lives in _player_train_state["wagons"][idx] (cargo_name, cargo_qty, capacity).
func set_wagon_cargo(_wagon_idx: int, _resource_name: String, _qty: int) -> void:
    push_warning("GameState.set_wagon_cargo() is not implemented")

func get_wagon_cargo(_wagon_idx: int) -> Dictionary:
    push_warning("GameState.get_wagon_cargo() is not implemented")
    return {}
    
# City State
func get_all_city_names() -> Array:
    return _cities_state.keys()
    
func get_city_by_name(city_name: String) -> Dictionary:
    return _cities_state.get(city_name, {})

func get_city_by_location(loc: Vector2i) -> Dictionary:
    return get_city_by_name(_cities_by_location.get(loc, ""))

func get_city_by_id(id: int) -> Dictionary:
    return get_city_by_name(_cities_by_id.get(id, ""))

func set_city(city_name: String, city_data: Dictionary) -> void:
    if not _cities_state.has(city_name):
        push_warning("GameState: set_city() on unknown city '%s' (it has no id or location mapping)" % city_name)
    _cities_state[city_name] = city_data
#endregion

func change_city_goods(city_name: String, resource_name: String, delta: int) -> bool:
    var trade_resources: Dictionary = _cities_state.get(city_name, {}).get("TradeResources", {})
    if not trade_resources.has(resource_name):
        push_error("GameState: city '%s' has no resource '%s'" % [city_name, resource_name])
        return false
    var entry: Dictionary = trade_resources[resource_name]
    entry["Quantity"] = maxi(int(entry.get("Quantity", 0)) + delta, 0)
    return true

func get_money() -> int:
    return _player_money

func add_money(delta: int) -> bool: # false if the result would be below 0
    if _player_money + delta < 0:
        return false
    _player_money += delta
    return true
