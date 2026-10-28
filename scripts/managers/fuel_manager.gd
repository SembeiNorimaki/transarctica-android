extends Node
class_name FuelManager
# Fuel of the player train. The fuel is the coal in its tender wagons, which live in GameState's
# wagon list: buying coal in a city fills the tender, and driving burns it.
# NavigationTrainManager tells it how far the train moved. It keeps the HUD informed with signals.
#
# While the navigation scene is running, this is the only code that changes the train's cargo
# (TrainInventory only exists in the trade scene), so the two can't get out of sync.

signal fuel_changed(current: int, maximum: int)
signal out_of_fuel # the coal just ran out, or the player tried to drive without coal

const FUEL_RESOURCE := "coal"

@export var coal_per_tile := 5.0 # coal burned per tile of rail (one step between adjacent rail tiles)
@export var extra_per_wagon := 0.0 # extra consumption per wagon besides the locomotive: 0.1 = +10% each

# Injected by NavigationScene: it measures a rail tile in pixels
var grid_service: GridService

var _fuel := 0
var _max_fuel := 0
var _burn_debt := 0.0 # coal burned but not yet taken from the tender (coal comes in whole units)
var _was_empty := false # out_of_fuel is only sent once per time the coal runs out


func _ready() -> void:
    GameState.player_cargo_changed.connect(refresh) # the trade scene changes the coal too
    GameState.game_loaded.connect(refresh)
    refresh()


#region queries
func get_fuel() -> int:
    return _fuel


func get_max_fuel() -> int:
    return _max_fuel


func has_fuel() -> bool:
    return _fuel > 0

# Coal in the tender wagons of the player train, straight from GameState:
# x = current, y = maximum. Static, so a HUD can use it without a FuelManager.
static func read_fuel() -> Vector2i:
    var fuel := 0
    var maximum := 0
    var fuel_wagon_type: String = ResourceTypes.wagon_type_for(FUEL_RESOURCE)
    var capacity := int(WagonTypes.TYPES.get(fuel_wagon_type, {}).get("capacity", 0))

    for wagon in GameState.get_player_train().get("wagons", []):
        var data: Dictionary = wagon
        if data.get("type", "") != fuel_wagon_type:
            continue
        maximum += capacity
        if ResourceTypes.same(str(data.get("cargo_name", "")), FUEL_RESOURCE):
            fuel += int(data.get("cargo_qty", 0))
    return Vector2i(fuel, maximum)
#endregion


#region burning
# Call every frame with the distance the player train moved (in pixels).
func consume_distance(pixels: float) -> void:
    if pixels <= 0.0 or _fuel <= 0:
        return
    var wagon_count: int = GameState.get_player_train().get("wagons", []).size()
    var per_tile := coal_per_tile * (1.0 + extra_per_wagon * maxi(wagon_count - 1, 0))
    _burn_debt += pixels / _tile_length() * per_tile

    var whole := int(_burn_debt)
    if whole <= 0:
        return
    _burn_debt -= whole
    _take_coal(whole)


# Called when the player tries to drive without coal, so the HUD can say so
func notify_empty() -> void:
    out_of_fuel.emit()


func _tile_length() -> float:
    return maxf(grid_service.tile_delta_to_world_delta(Vector2(1, 0)).length(), 1.0)


# Takes coal from the tender wagons, in order
func _take_coal(amount: int) -> void:
    var remaining := amount
    var fuel_wagon_type = ResourceTypes.wagon_type_for(FUEL_RESOURCE)
    var wagons: Array = GameState.get_player_train().get("wagons", [])

    for i in wagons.size():
        if remaining == 0:
            break
        var data: Dictionary = wagons[i]
        if data.get("type", "") != fuel_wagon_type or not ResourceTypes.same(str(data.get("cargo_name", "")), FUEL_RESOURCE):
            continue
        var qty := int(data.get("cargo_qty", 0))
        var burned := mini(qty, remaining)
        if burned <= 0:
            continue
        var left := qty - burned
        # An empty wagon has no resource, like in TrainInventory
        GameState.set_wagon_cargo(i, FUEL_RESOURCE if left > 0 else "", left)
        remaining -= burned

    refresh()
    if _fuel <= 0 and not _was_empty:
        _was_empty = true
        out_of_fuel.emit()
#endregion


# Recounts the coal in the tender wagons and tells the HUD if it changed
func refresh() -> void:
    var fuel := 0
    var maximum := 0
    var fuel_wagon_type = ResourceTypes.wagon_type_for(FUEL_RESOURCE)
    var capacity := int(WagonTypes.TYPES.get(fuel_wagon_type, {}).get("capacity", 0))

    for wagon in GameState.get_player_train().get("wagons", []):
        var data: Dictionary = wagon
        if data.get("type", "") != fuel_wagon_type:
            continue
        maximum += capacity
        if ResourceTypes.same(str(data.get("cargo_name", "")), FUEL_RESOURCE):
            fuel += int(data.get("cargo_qty", 0))

    var counted := read_fuel()
    var changed := counted.x != _fuel or counted.y != _max_fuel
    _fuel = counted.x
    _max_fuel = counted.y
    if _fuel > 0:
        _was_empty = false
    if changed:
        fuel_changed.emit(_fuel, _max_fuel)
