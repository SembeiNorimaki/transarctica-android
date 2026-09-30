extends Node

var state := {
    "cities": {},
}

# this are examples for showing the structure of the data. They are removed when loading data from JSON files
var _cities_state = {
    "ËxampleCity": {
        "TradeResources": {
            "Oil": {
                "Quantity": 3,
                "SellPrice": 4,
                "BuyPrice": 5
            },
            "Alcohol": {
                "Quantity": 6,
                "SellPrice": 7,
                "BuyPrice": 8
            }
        }
    }
}

var _player_train_state = {
    "id": "TP0",
    "owner": "Player",
    "position": [2, 4, "E"],
    
    "fuel": 40,
    "max_fuel": 100,
    "max_speed": 100,
    "acceleration": 10,
    "deceleration": 20,

    "wagons": [
        {
            "type": "locomotive",
            "hp": 100,
            "max_hp": 100,
            "capacity": 0,
            "cargo_name": "",
            "cargo_qty": 0
        },
        {
            "type": "tender",
            "hp": 60,
            "max_hp": 60,
            "capacity": 100,
            "cargo_name": "coal",
            "cargo_qty": 40
        },
        {
            "type": "merchandise",
            "hp": 40,
            "max_hp": 40,
            "capacity": 20,
            "cargo_name": "caviar",
            "cargo_qty": 3
        }
    ]
}


# cities_state stores cities by name. To retrieve cities by location or id, this dictionaries provide a correspondence loc->name and id->name
# in any case, to get cities data, use the API calls get_city_by_name, get_city_by_location, get_city_by_id
var _cities_by_location = {}
var _cities_by_id = {}

#region initialization
func _ready() -> void:
    # print("Game state Ready")
    _load_initial_cities("res://data/newgame/cities_World2.json")
    _load_initial_player_train("res://data/newgame/player_train.json")

# Loads initial cities into _cities_state, _cities_by_location and _cities_by_id 
func _load_initial_cities(filename: String):
    _cities_state = {}
    _cities_by_location = {}
    _cities_by_id = {}

    var file = FileAccess.open(filename, FileAccess.READ)
    var data = JSON.parse_string(file.get_as_text())
    for city_id in data.keys():
        var city_name = data[city_id].Name
        var city_location = Vector2i(data[city_id].Location[0], data[city_id].Location[1])
        _cities_by_location[city_location] = city_name
        _cities_by_id[int(city_id)] = city_name
        _cities_state[city_name] = data[city_id]


# Loads initial player train into _player_train_state
func _load_initial_player_train(filename: String):
    _player_train_state = {}

    var file = FileAccess.open(filename, FileAccess.READ)
    var train_data = JSON.parse_string(file.get_as_text())
    _player_train_state = train_data
#endregion

#region publicAPI

# Player Train State
func get_player_train() -> Dictionary:
    return _player_train_state

func set_player_train(player_train_data: Dictionary) -> void:
    _player_train_state = player_train_data

func set_wagon_cargo(wagon_idx: int, resource_name: String, qty: int) -> void:
    pass
func get_wagon_cargo(wagon_idx: int) -> Dictionary:
    return {}
    
# City State
func get_all_city_names() -> Array:
    return _cities_state.keys()
    
func get_city_by_name(city_name: String) -> Dictionary:
    return _cities_state.get(city_name, {})

func get_city_by_location(loc: Vector2i) -> Dictionary:
    return _cities_state.get(_cities_by_location[loc], {})

func get_city_by_id(id: int) -> Dictionary:
    return _cities_state.get(_cities_by_id[id], {})

func set_city(city_name: String, city_data: Dictionary) -> void:
    _cities_state[city_name] = city_data

#endregion
