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
const UNITS_PATH := "res://data/newgame/units.json"
const ENEMY_TRAINS_PATH := "res://data/newgame/enemy_trains.json"

# const SAVE_PATH := "user://savegame.json"
const SAVES_DIR := "user://saves"
const SLOT_COUNT := 4
const DEBUG_SLOT := 1 # slot used while debugging scenes, until the main menu sets one
const DEBUG_AUTOLOAD := false # true: every debug run starts from the DEBUG_SLOT save, if it exists
const SAVE_VERSION := 1
const INITIAL_MONEY := 100

const FILE_CITIES := "cities.json"
const FILE_PLAYER := "player.json"
const FILE_ENEMIES := "enemies.json"
const FILE_QUESTS := "quests.json"
const SAVE_FILES := [FILE_CITIES, FILE_PLAYER, FILE_ENEMIES, FILE_QUESTS]


var _cities_state: Dictionary = {} # city name -> city data
var _cities_by_location: Dictionary = {} # Vector2i -> city name
var _cities_by_id: Dictionary = {} # int -> city name
var _player_train_state: Dictionary = {}
var _enemies_state := {} # enemy trains: the navigation scene will fill it on game_saving
var _units_state: Dictionary = {} # unit id -> unit data (see data/newgame/units.json)

var _player_money := INITIAL_MONEY # TODO: load the starting value from data
var _explored := {} # map name -> explored tiles, encoded by ExplorationService
var _quests_state := {}
var _events_state := {} # map name -> {"x,y": true} for the events already done
var _flags := {} # story flags set by events: name -> true

var current_slot := DEBUG_SLOT # the main menu will set this


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
    _load_initial_enemies(ENEMY_TRAINS_PATH)
    _load_initial_units(UNITS_PATH)
    if DEBUG_AUTOLOAD and OS.is_debug_build() and has_save(DEBUG_SLOT):
        load_game(DEBUG_SLOT)

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
    # _cities_by_location = {}
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
        if not (city is Dictionary) or not city.has("Name"):
            push_error("GameState: city '%s' in %s needs Name" % [key, path])
            continue
 
        var city_name: String = city["Name"]
        if _cities_state.has(city_name):
            push_warning("GameState: duplicate city name '%s' (id %s), the later one overwrites the earlier" % [city_name, key])
 
        # _cities_by_location[Vector2i(int(location[0]), int(location[1]))] = city_name
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
    # A new game takes the start of the train from the map (the Trains tilemap), not from the JSON
    _player_train_state.erase("position")
    _player_train_state.erase("reversed")

func _load_initial_units(path: String) -> void:
    _units_state = {}
    var data = _read_json(path)
    if not (data is Dictionary):
        push_error("GameState: %s must contain a JSON object of units" % path)
        return
    _units_state = data
#endregion

#region publicAPI

# Player Train State
func get_player_train() -> Dictionary:
    return _player_train_state

func set_player_train(player_train_data: Dictionary) -> void:
    _player_train_state = player_train_data

# Where the player train is on the navigation map: the locomotive's tile and orientation, and
# whether the train is reversed (the locomotive at the rear, pushing). Stored in the train as
# "position": [x, y, "E"] and "reversed": bool. A new game has none: the scene uses the map's start.
func has_player_position() -> bool:
    var position = _player_train_state.get("position", null)
    return position is Array and position.size() >= 3

func get_player_position() -> Dictionary:
    var position: Array = _player_train_state.get("position", [])
    if position.size() < 3:
        return {}
    return {
        "tile": Vector2i(int(position[0]), int(position[1])),
        "ori": str(position[2]),
        "reversed": bool(_player_train_state.get("reversed", false)),
    }

func set_player_position(tile: Vector2i, ori: String, reversed := false) -> void:
    _player_train_state["position"] = [tile.x, tile.y, ori]
    _player_train_state["reversed"] = reversed

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

# func get_city_by_location(loc: Vector2i) -> Dictionary:
#     return get_city_by_name(_cities_by_location.get(loc, ""))

func get_city_by_id(id: int) -> Dictionary:
    return get_city_by_name(_cities_by_id.get(id, ""))

func set_city(city_name: String, city_data: Dictionary) -> void:
    if not _cities_state.has(city_name):
        push_warning("GameState: set_city() on unknown city '%s' (it has no id or location mapping)" % city_name)
    _cities_state[city_name] = city_data
#endregion

#region units
func get_unit(unit_id: String) -> Dictionary:
    return _units_state.get(unit_id, {})


# Creates a unit from `unit_data` (see UnitTypes.make_unit) and puts it in a wagon of the player
# train. Returns its new id, or "" (changing nothing) if the wagon doesn't exist.
func add_unit_to_wagon(wagon_idx: int, unit_data: Dictionary) -> String:
    var wagons: Array = _player_train_state.get("wagons", [])
    if wagon_idx < 0 or wagon_idx >= wagons.size():
        push_error("GameState: no wagon %d in the player train" % wagon_idx)
        return ""
    var unit_id := _new_unit_id()
    var unit: Dictionary = unit_data.duplicate(true)
    unit["id"] = unit_id
    _units_state[unit_id] = unit

    var wagon: Dictionary = wagons[wagon_idx]
    if not wagon.has("unit_ids"):
        wagon["unit_ids"] = []
    wagon["unit_ids"].append(unit_id)
    return unit_id


func _new_unit_id() -> String:
    var next := 0
    for key in _units_state:
        var text := str(key)
        if text.begins_with("u") and text.substr(1).is_valid_int():
            next = maxi(next, int(text.substr(1)) + 1)
    return "u%d" % next


# Changes the stock of a soldier type a city recruits (delta can be negative).
func change_city_recruits(city_name: String, unit_type: String, delta: int) -> bool:
    var recruits: Dictionary = _cities_state.get(city_name, {}).get("Recruits", {})
    if not recruits.has(unit_type):
        push_error("GameState: city '%s' has no recruits '%s'" % [city_name, unit_type])
        return false
    var entry: Dictionary = recruits[unit_type]
    entry["Quantity"] = maxi(int(entry.get("Quantity", 0)) + delta, 0)
    return true
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

func get_enemies() -> Dictionary:
    return _enemies_state

func set_enemies(data: Dictionary) -> void:
    _enemies_state = data

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


# The first slot without a save, or 0 if all of them are used
func find_free_slot() -> int:
    for slot in range(1, SLOT_COUNT + 1):
        if not has_save(slot):
            return slot
    return 0

# Sets the game to its initial state, from the newgame folder, in the given slot.
# Nothing is written to disk: the slot only changes when the game is saved.
func start_new_game(slot: int) -> bool:
    if slot < 1 or slot > SLOT_COUNT:
        push_error("GameState: slot %d does not exist (1 to %d)" % [slot, SLOT_COUNT])
        return false
    current_slot = slot
    _player_money = INITIAL_MONEY
    _explored = {}
    _quests_state = {} # empty quest state: QuestManager starts the quest line
    _load_initial_enemies(ENEMY_TRAINS_PATH)
    _load_initial_cities(CITIES_PATH)
    _load_initial_player_train(PLAYER_TRAIN_PATH)
    _events_state = {}
    _flags = {}
    game_loaded.emit() # before money_changed, like in load_game
    money_changed.emit(_player_money)
    return true

# What the slot menu shows
func get_slot_info(slot: int) -> Dictionary:
    if not has_save(slot):
        return {"exists": false}
    var data = _read_json("%s/%s" % [get_slot_dir(slot), FILE_PLAYER])
    if not (data is Dictionary):
        return {"exists": true, "valid": false}
    return {"exists": true, "valid": true, "saved_at": str(data.get("saved_at", "")), "money": int(data.get("money", 0))}

#region enemy trains
# Loads the enemy trains of a new game: id -> train data. The key is the id. The position is not
# in the file: it comes from the map (the Trains tilemap) and is set by set_enemy_position().
func _load_initial_enemies(path: String) -> void:
    _enemies_state = {}
    var data = _read_json(path)
    if not (data is Dictionary):
        push_error("GameState: %s must contain a JSON object of enemy trains" % path)
        return
    for key in data:
        if str(key).begins_with("_"):
            continue # comments
        var train = data[key]
        if not (train is Dictionary) or not (train.get("wagons") is Array):
            push_error("GameState: enemy train '%s' in %s needs a 'wagons' list" % [key, path])
            continue
        train["id"] = str(key)
        train.erase("position")
        train.erase("reversed")
        _enemies_state[str(key)] = train


func get_enemy_train(train_id: String) -> Dictionary:
    return _enemies_state.get(train_id, {})


func has_enemy_position(train_id: String) -> bool:
    var position = _enemies_state.get(train_id, {}).get("position", null)
    return position is Array and position.size() >= 3


func get_enemy_position(train_id: String) -> Dictionary:
    var train: Dictionary = _enemies_state.get(train_id, {})
    var position: Array = train.get("position", [])
    if position.size() < 3:
        return {}
    return {
        "tile": Vector2i(int(position[0]), int(position[1])),
        "ori": str(position[2]),
        "reversed": bool(train.get("reversed", false)),
    }


func set_enemy_position(train_id: String, tile: Vector2i, ori: String, reversed := false) -> void:
    if not _enemies_state.has(train_id):
        return
    _enemies_state[train_id]["position"] = [tile.x, tile.y, ori]
    _enemies_state[train_id]["reversed"] = reversed


# The enemy train is gone (destroyed): it, and its soldiers, leave the game state
func remove_enemy_train(train_id: String) -> bool:
    if not _enemies_state.has(train_id):
        return false
    for wagon in _enemies_state[train_id].get("wagons", []):
        for unit_id in wagon.get("unit_ids", []):
            _units_state.erase(unit_id)
    _enemies_state.erase(train_id)
    return true
#endregion

#region save game
# Writes the slot's four files. Returns false (with an error) if it fails.
func save_game(slot := -1) -> bool:
    var target := _resolve_slot(slot)
    if target < 1 or target > SLOT_COUNT:
        push_error("GameState: slot %d does not exist (1 to %d)" % [target, SLOT_COUNT])
        return false
    game_saving.emit()

    var city_ids := {} # JSON keys must be strings
    for id in _cities_by_id:
        city_ids[str(id)] = _cities_by_id[id]

    var files := {
        FILE_CITIES: {"version": SAVE_VERSION, "cities": _cities_state, "city_ids": city_ids},
        FILE_PLAYER: {
            "version": SAVE_VERSION,
            "saved_at": Time.get_datetime_string_from_system(),
            "money": _player_money,
            "train": _player_train_state,
            "explored": _explored,
            "units": _units_state,
            "events": _events_state,
            "flags": _flags,
        },
        FILE_ENEMIES: {"version": SAVE_VERSION, "enemies": _enemies_state},
        FILE_QUESTS: {"version": SAVE_VERSION, "quests": _quests_state},
    }

    var dir_path := get_slot_dir(target)
    var error := DirAccess.make_dir_recursive_absolute(dir_path)
    if error != OK:
        push_error("GameState: cannot create %s (error %d)" % [dir_path, error])
        return false

    # Everything goes to temporary files first: if a write fails, the previous save is untouched
    for file_name in files:
        if not _write_json("%s/%s.tmp" % [dir_path, file_name], files[file_name]):
            _remove_temp_files(dir_path)
            return false
    for file_name in files:
        var final_path := "%s/%s" % [dir_path, file_name]
        if FileAccess.file_exists(final_path):
            DirAccess.remove_absolute(final_path)
        error = DirAccess.rename_absolute(final_path + ".tmp", final_path)
        if error != OK:
            push_error("GameState: cannot finish saving %s (error %d); the new data is in %s.tmp" % [final_path, error, final_path])
            return false

    print("GameState: saved slot %d to %s" % [target, ProjectSettings.globalize_path(dir_path)])
    return true


func _write_json(path: String, data: Dictionary) -> bool:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        push_error("GameState: cannot write %s (error %d)" % [path, FileAccess.get_open_error()])
        return false
    file.store_string(JSON.stringify(data, "\t")) # keys are sorted, so files are stable and easy to diff
    file.close()
    return true


func _remove_temp_files(dir_path: String) -> void:
    for file_name in SAVE_FILES:
        DirAccess.remove_absolute("%s/%s.tmp" % [dir_path, file_name])

#endregion

#region load game
func load_game(slot := -1) -> bool:
    var target := _resolve_slot(slot)
    if not has_save(target):
        push_warning("GameState: slot %d has no save" % target)
        return false

    var dir_path := get_slot_dir(target)
    var player = _read_slot_file(dir_path, FILE_PLAYER)
    var cities = _read_slot_file(dir_path, FILE_CITIES)
    var enemies = _read_slot_file(dir_path, FILE_ENEMIES)
    var quests = _read_slot_file(dir_path, FILE_QUESTS)
    if player == null or cities == null or enemies == null or quests == null:
        return false # a file exists but is invalid: the Debugger says which

    var problem := _validate_player(player)
    if problem == "" and not cities.is_empty():
        problem = _validate_cities(cities)
    if problem == "" and not enemies.is_empty():
        problem = _validate_enemies(enemies)
    if problem != "":
        push_error("GameState: invalid save in slot %d: %s" % [target, problem])
        return false
    

    current_slot = target # saving now goes to the slot you loaded

    _player_money = int(player["money"])
    _player_train_state = player["train"]
    _explored = player.get("explored", {})
    _events_state = player.get("events", {})
    _flags = player.get("flags", {})

    if player.get("units") is Dictionary:
        _units_state = player["units"]
    else:
        _load_initial_units(UNITS_PATH) # an older save has no units: start with the initial ones

    if cities.is_empty():
        _load_initial_cities(CITIES_PATH) # no cities.json: the cities start as in a new game
    else:
        _cities_state = cities["cities"]
        _cities_by_id = {}
        for id in cities["city_ids"]:
            _cities_by_id[int(id)] = cities["city_ids"][id]

    _enemies_state = enemies.get("enemies", {}) # missing files give {}: no enemies, no quests...
    _quests_state = quests.get("quests", {}) # ...and an empty quest state starts the quest line

    game_loaded.emit() # before money_changed, so quests are rebuilt before they react to the money
    money_changed.emit(_player_money)
    return true


# The parsed file, {} if it doesn't exist, or null (with an error) if it is invalid
func _read_slot_file(dir_path: String, file_name: String) -> Variant:
    var path := "%s/%s" % [dir_path, file_name]
    if not FileAccess.file_exists(path):
        return {}
    var data = _read_json(path)
    if not (data is Dictionary):
        push_error("GameState: %s is not a valid JSON object" % path)
        return null
    if int(data.get("version", 0)) != SAVE_VERSION:
        push_error("GameState: %s has version %s, expected %d" % [path, data.get("version"), SAVE_VERSION])
        return null
    return data


func _validate_player(data: Dictionary) -> String:
    if not data.has("money") or not (data.get("train") is Dictionary):
        return "player.json needs 'money' and a 'train' object"
    if not (data["train"].get("wagons") is Array):
        return "'train' needs a 'wagons' list"
    return ""


func _validate_cities(data: Dictionary) -> String:
    if not (data.get("cities") is Dictionary and data.get("city_ids") is Dictionary):
        return "cities.json needs 'cities' and 'city_ids' objects"
    for id in data["city_ids"]:
        if not str(id).is_valid_int():
            return "city id '%s' is not a number" % id
        if not data["cities"].has(data["city_ids"][id]):
            return "city id %s points to '%s', which is not in 'cities'" % [id, data["city_ids"][id]]
    return ""

func _validate_enemies(data: Dictionary) -> String:
    if not (data.get("enemies") is Dictionary):
        return "enemies.json needs an 'enemies' object"
    for train_id in data["enemies"]:
        var train = data["enemies"][train_id]
        if not (train is Dictionary) or not (train.get("wagons") is Array):
            return "enemy train '%s' needs a 'wagons' list" % train_id
    return ""
#endregion

#region slots
func get_slot_dir(slot := -1) -> String:
    return "%s/slot_%d" % [SAVES_DIR, _resolve_slot(slot)]


func has_save(slot := -1) -> bool:
    return FileAccess.file_exists("%s/%s" % [get_slot_dir(slot), FILE_PLAYER])


func delete_slot(slot := -1) -> void:
    var dir_path := get_slot_dir(slot)
    for file_name in SAVE_FILES:
        DirAccess.remove_absolute("%s/%s" % [dir_path, file_name])
    DirAccess.remove_absolute(dir_path) # only works once it is empty, which it now is


func _resolve_slot(slot: int) -> int:
    return current_slot if slot < 1 else slot
#endregion

#region events
func is_event_done(map_name: String, tile: Vector2i) -> bool:
    return _events_state.get(map_name, {}).has(_tile_key(tile))


func set_event_done(map_name: String, tile: Vector2i) -> void:
    if not _events_state.has(map_name):
        _events_state[map_name] = {}
    _events_state[map_name][_tile_key(tile)] = true


func _tile_key(tile: Vector2i) -> String:
    return "%d,%d" % [tile.x, tile.y]


func has_flag(flag: String) -> bool:
    return bool(_flags.get(flag, false))


func set_flag(flag: String, value := true) -> void:
    _flags[flag] = value
#endregion

func _unhandled_key_input(event: InputEvent) -> void: # TEMPORARY: quick save / load while developing
    var key := event as InputEventKey
    if key == null or not key.pressed or key.echo or not OS.is_debug_build():
        return
    match key.keycode:
        KEY_F5:
            save_game()
        KEY_F9:
            load_game()