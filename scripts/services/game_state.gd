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
const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1

var _cities_state: Dictionary = {} # city name -> city data
var _cities_by_location: Dictionary = {} # Vector2i -> city name
var _cities_by_id: Dictionary = {} # int -> city name
var _player_train_state: Dictionary = {}

var _player_money := 100 # TODO: load the starting value from data
var _explored := {} # map name -> explored tiles, encoded by ExplorationService
var _quests_state := {}

var state := {
    "cities": {},
}

# Signals
signal money_changed(money: int)
signal player_wagon_added(index: int, wagon_data: Dictionary)
signal player_cargo_changed
signal game_saving # emitted before the state is written: scenes should flush their runtime state into GameState
signal game_loaded # emitted after a load: scenes should rebuild themselves from GameState


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

func set_wagon_cargo(wagon_idx: int, resource_name: String, qty: int) -> void:
    var wagons: Array = _player_train_state.get("wagons", [])
    if wagon_idx < 0 or wagon_idx >= wagons.size():
        push_error("GameState: no wagon %d in the player train" % wagon_idx)
        return
    wagons[wagon_idx]["cargo_name"] = resource_name
    wagons[wagon_idx]["cargo_qty"] = qty
    player_cargo_changed.emit()

# TODO: not implemented yet. The data lives in _player_train_state["wagons"][idx] (cargo_name, cargo_qty, capacity).
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

# Changes the stock of a wagon type a city sells (delta can be negative).
func change_city_wagons(city_name: String, wagon_type: String, delta: int) -> bool:
    var trade_wagons: Dictionary = _cities_state.get(city_name, {}).get("TradeWagons", {})
    if not trade_wagons.has(wagon_type):
        push_error("GameState: city '%s' has no wagon '%s'" % [city_name, wagon_type])
        return false
    var entry: Dictionary = trade_wagons[wagon_type]
    entry["Quantity"] = maxi(int(entry.get("Quantity", 0)) + delta, 0)
    return true


# Appends a wagon at the rear of the player train. Returns its index, or -1 on error.
func add_wagon_to_player_train(wagon_data: Dictionary) -> int:
    if not _player_train_state.has("wagons"):
        push_error("GameState: the player train has no wagons list")
        return -1
    var wagons: Array = _player_train_state["wagons"]
    wagons.append(wagon_data)
    var index := wagons.size() - 1
    player_wagon_added.emit(index, wagon_data)
    player_cargo_changed.emit()
    return index

# Removes a wagon from the player train's list. The wagons behind it move up one index.
func remove_wagon_from_player_train(wagon_idx: int) -> bool:
    var wagons: Array = _player_train_state.get("wagons", [])
    if wagon_idx < 0 or wagon_idx >= wagons.size():
        push_error("GameState: no wagon %d in the player train" % wagon_idx)
        return false
    wagons.remove_at(wagon_idx)
    player_cargo_changed.emit()
    return true

func get_money() -> int:
    return _player_money

func add_money(delta: int) -> bool: # false if the result would be below 0
    if _player_money + delta < 0:
        return false
    _player_money += delta
    money_changed.emit(_player_money)
    return true

func get_explored(map_name: String) -> Dictionary:
    return _explored.get(map_name, {})

func set_explored(map_name: String, data: Dictionary) -> void:
    _explored[map_name] = data

func get_quests() -> Dictionary:
    return _quests_state

func set_quests(data: Dictionary) -> void:
    _quests_state = data

# Moves a wagon of the player train. Index 0 is the locomotive and can't move.
func move_wagon_in_player_train(from_idx: int, to_idx: int) -> bool:
    var wagons: Array = _player_train_state.get("wagons", [])
    if from_idx < 1 or to_idx < 1 or from_idx >= wagons.size() or to_idx >= wagons.size() or from_idx == to_idx:
        push_error("GameState: cannot move wagon %d to %d" % [from_idx, to_idx])
        return false
    wagons.insert(to_idx, wagons.pop_at(from_idx))
    return true

#region save game
func has_save() -> bool:
    return FileAccess.file_exists(SAVE_PATH)


# Writes the whole state to SAVE_PATH as readable JSON. Returns false (with an error) on failure.
func save_game() -> bool:
    game_saving.emit()

    var city_ids := {} # JSON keys must be strings
    for id in _cities_by_id:
        city_ids[str(id)] = _cities_by_id[id]

    var data := {
        "version": SAVE_VERSION,
        "saved_at": Time.get_datetime_string_from_system(),
        "money": _player_money,
        "player_train": _player_train_state,
        "cities": _cities_state,
        "city_ids": city_ids,
        "quests": _quests_state,
        "explored": _explored
    }
    var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file == null:
        push_error("GameState: cannot write %s (error %d)" % [SAVE_PATH, FileAccess.get_open_error()])
        return false
    file.store_string(JSON.stringify(data, "\t")) # keys are sorted, so the file is stable and easy to diff
    file.close()
    print("GameState: saved to %s" % ProjectSettings.globalize_path(SAVE_PATH))
    return true


# Replaces the current state with the saved one. Returns false, changing nothing, if the file is
# missing or invalid. Everything is checked before anything is replaced.
func load_game() -> bool:
    if not has_save():
        push_warning("GameState: there is no save at %s" % SAVE_PATH)
        return false
    var data = _read_json(SAVE_PATH)
    var problem := _validate_save(data)
    if problem != "":
        push_error("GameState: invalid save: %s" % problem)
        return false

    _player_money = int(data["money"])
    _player_train_state = data["player_train"]
    _cities_state = data["cities"]
    _quests_state = data.get("quests", {})
    _explored = data.get("explored", {})

    _cities_by_id = {}
    for id in data["city_ids"]:
        _cities_by_id[int(id)] = data["city_ids"][id]
    _cities_by_location = {}
    for city_name in _cities_state:
        var location: Array = _cities_state[city_name]["Location"]
        _cities_by_location[Vector2i(int(location[0]), int(location[1]))] = city_name

    game_loaded.emit()
    money_changed.emit(_player_money)
    return true


# Returns "" if the data looks like a valid save, or a description of what is wrong.
func _validate_save(data) -> String:
    if not (data is Dictionary):
        return "the file is not a JSON object"
    if int(data.get("version", 0)) != SAVE_VERSION:
        return "version %s, expected %d" % [data.get("version"), SAVE_VERSION]
    for key in ["money", "player_train", "cities", "city_ids"]:
        if not data.has(key):
            return "missing '%s'" % key
    if not (data["player_train"] is Dictionary and data["cities"] is Dictionary and data["city_ids"] is Dictionary):
        return "'player_train', 'cities' and 'city_ids' must be objects"

    for city_name in data["cities"]:
        var city = data["cities"][city_name]
        if not (city is Dictionary) or not (city.get("Location") is Array) or city["Location"].size() < 2:
            return "city '%s' needs a Location [x, y]" % city_name
    for id in data["city_ids"]:
        if not str(id).is_valid_int():
            return "city id '%s' is not a number" % id
        if not data["cities"].has(data["city_ids"][id]):
            return "city id %s points to '%s', which is not in 'cities'" % [id, data["city_ids"][id]]
    return ""


func _unhandled_key_input(event: InputEvent) -> void: # TEMPORARY: quick save / load while developing
    var key := event as InputEventKey
    if key == null or not key.pressed or key.echo or not OS.is_debug_build():
        return
    match key.keycode:
        KEY_F5:
            save_game()
        KEY_F9:
            load_game()
#endregion
