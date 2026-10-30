extends Node
class_name GlobalEconomyManager
# The economy of the whole world. It lives in the navigation scene, so time passes while the player
# travels (and not in a city or a fight, where that scene is suspended). It:
#   - counts the days: one every `seconds_per_day` of travel (or advance_day() by hand)
#   - makes every city live a day (CityEconomyManager.daily_update), so their stocks and prices
#     move even where the player is not
#   - keeps one price index per resource, which multiplies its price in every city: it follows
#     how scarce the resource is in the whole world (all the stock against all the targets), plus a
#     little noise. If the player empties the world of coal, coal gets expensive everywhere.
#   - applies shocks: events that change the price of a resource (or of everything) for some days,
#     e.g. add_shock("missiles", 1.5, 10) for a war. Quests and events can call it.
#
# The data lives in GameState (saved with the game); this node only runs the rules.

signal day_passed(day: int)
signal indices_changed

@export var enabled := true
## Seconds of travel in a day. 0 or less: days only pass with advance_day().
@export var seconds_per_day := 60.0
## Passed to every CityEconomyManager.
@export_range(0.0, 1.0) var city_recovery_rate := 0.1
## Part of the way to what the world's stock calls for that the base index moves each day.
@export_range(0.0, 1.0) var index_follow_rate := 0.2
## Random change of the base index each day (a fraction of its value, either way).
@export_range(0.0, 0.2) var noise := 0.02

var _elapsed := 0.0


func _process(delta: float) -> void:
    if not enabled or seconds_per_day <= 0.0:
        return
    _elapsed += delta
    while _elapsed >= seconds_per_day:
        _elapsed -= seconds_per_day
        advance_day()


func get_day() -> int:
    return GameState.get_economy_day()

func get_price_index(resource_name: String) -> float:
    return GameState.get_price_index(resource_name)


func advance_days(count: int) -> void:
    for i in count:
        advance_day()

func advance_day() -> void:
    GameState.set_economy_day(GameState.get_economy_day() + 1)
    var totals := _cities_live_a_day()
    _update_base_indices(totals)
    _tick_shocks()
    _write_effective_indices()
    day_passed.emit(GameState.get_economy_day())
    indices_changed.emit()


#region cities
# Returns {resource: {"stock": int, "target": int}}, summed over all the cities
func _cities_live_a_day() -> Dictionary:
    var totals := {}
    for city_name: String in GameState.get_all_city_names():
        var inventory := CityInventory.new() # a stand-in for the scene's: it is not in the tree
        if inventory.load_from_game_state(city_name):
            var economy := CityEconomyManager.new()
            economy.recovery_rate = city_recovery_rate
            economy.setup(inventory)
            economy.daily_update()
            for resource_name: String in inventory.get_resource_names():
                var total: Dictionary = totals.get_or_add(resource_name, {"stock": 0, "target": 0})
                total["stock"] += inventory.get_available_qty(resource_name)
                total["target"] += inventory.get_target(resource_name)
            economy.free()
        inventory.free()
    return totals
#endregion


#region indices
func _update_base_indices(totals: Dictionary) -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = hash(["economy", GameState.get_economy_day()]) # the same day gives the same noise
    var base := {}
    var names := totals.keys()
    names.sort() # so the noise goes to the same resources every time
    for resource_name: String in names:
        var current := GameState.get_base_price_index(resource_name)
        var wanted := PriceModel.scarcity_index(totals[resource_name]["stock"], totals[resource_name]["target"])
        var next := current + (wanted - current) * index_follow_rate
        next *= 1.0 + rng.randf_range(-noise, noise)
        base[resource_name] = clampf(next, PriceModel.MIN_GLOBAL_INDEX, PriceModel.MAX_GLOBAL_INDEX)
    GameState.set_price_indices(base, GameState.get_economy_effective())
#endregion


#region shocks
## For `days` days, the price of `resource_name` (all the resources if "") is multiplied by
## `factor` in every city. The effect is immediate.
func add_shock(resource_name: String, factor: float, days: int) -> void:
    if factor <= 0.0 or days <= 0:
        push_error("GlobalEconomyManager: a shock needs a positive factor and days")
        return
    var shocks := GameState.get_price_shocks()
    shocks.append({"resource": resource_name.to_lower(), "factor": factor, "days": days})
    GameState.set_price_shocks(shocks)
    _write_effective_indices()
    indices_changed.emit()

func clear_shocks() -> void:
    GameState.set_price_shocks([])
    _write_effective_indices()
    indices_changed.emit()

func get_shocks() -> Array:
    return GameState.get_price_shocks()

func _tick_shocks() -> void:
    var left: Array = []
    for shock: Dictionary in GameState.get_price_shocks():
        shock["days"] = int(shock["days"]) - 1
        if shock["days"] > 0:
            left.append(shock)
    GameState.set_price_shocks(left)

# index = base x every shock that applies
func _write_effective_indices() -> void:
    var base: Dictionary = GameState.get_economy_base()
    var shocks := GameState.get_price_shocks()
    var names := base.keys()
    for known: String in ResourceTypes.RESOURCES: # a shock on everything reaches resources not seen yet
        if not names.has(known):
            names.append(known)
    for shock: Dictionary in shocks:
        if shock["resource"] != "" and not names.has(shock["resource"]):
            names.append(shock["resource"])
    var effective := {}
    for resource_name: String in names:
        var index := float(base.get(resource_name, 1.0))
        for shock: Dictionary in shocks:
            if shock["resource"] == "" or shock["resource"] == resource_name:
                index *= float(shock["factor"])
        effective[resource_name] = clampf(index, PriceModel.MIN_EFFECTIVE_INDEX, PriceModel.MAX_EFFECTIVE_INDEX)
    GameState.set_price_indices(base, effective)
#endregion
