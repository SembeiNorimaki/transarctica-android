extends Node
class_name CityEconomyManager
# The economy of ONE city: it reacts to what happens to the city's stock.
#   - The city WANTS a stock of each resource (its target). With less than that, it needs the
#     resource: the price goes up. When you supply it, the need falls and the price goes down.
#     With more than it wants, the price is lower still (see PriceModel).
#   - With time (GlobalEconomyManager calls daily_update) the stock drifts back towards the target:
#     the city produces or uses up what it lacks or has too much of, so prices settle again.
#   - The world's index (GlobalEconomyManager) multiplies every price of the resource.
#
# It does not own data: the prices are written to the CityInventory (set_prices), which is the only
# thing that changes the city. It works with any CityInventory, in a scene or not.
#
# Use: city_economy_manager.setup(city_inventory)   # after the inventory has loaded its city

signal price_changed(resource_name: String, buy_price: int, sell_price: int)

## Part of the gap to the target that the stock closes each day (production and consumption).
@export_range(0.0, 1.0) var recovery_rate := 0.1

var _city: CityInventory


func setup(city: CityInventory) -> void:
    if is_instance_valid(_city) and _city.city_resource_amount_changed.is_connected(_on_stock_changed):
        _city.city_resource_amount_changed.disconnect(_on_stock_changed)
    _city = city
    _city.city_resource_amount_changed.connect(_on_stock_changed)
    refresh_all()


#region prices
## What the base price is multiplied by now: the city's need and the world's index.
func get_price_multiplier(resource_name: String) -> float:
    if _city == null:
        return 1.0
    return PriceModel.stock_multiplier(_city.get_available_qty(resource_name), _city.get_target(resource_name)) \
            * GameState.get_price_index(resource_name)

## How many units the city is short of. 0 when it has what it wants.
func get_demand(resource_name: String) -> int:
    return _city.get_demand(resource_name) if _city != null else 0

func refresh_all() -> void:
    if _city == null:
        return
    for resource_name in _city.get_resource_names():
        refresh(resource_name)

func refresh(resource_name: String) -> void:
    if _city == null or not _city.has_resource(resource_name):
        return
    var multiplier := get_price_multiplier(resource_name)
    var buy := PriceModel.price(_city.get_base_buy_price(resource_name), multiplier)
    var sell := PriceModel.price(_city.get_base_sell_price(resource_name), multiplier)
    if _city.set_prices(resource_name, buy, sell):
        price_changed.emit(resource_name, buy, sell)

func _on_stock_changed(resource_name: String, _qty: int) -> void:
    refresh(resource_name)
#endregion


#region time
## One day passes in this city: every stock moves a part of the way to its target. The prices
## follow through the inventory's signal.
func daily_update() -> void:
    if _city == null:
        return
    for resource_name in _city.get_resource_names():
        var gap := _city.get_target(resource_name) - _city.get_available_qty(resource_name)
        if gap == 0:
            continue
        var step := clampi(roundi(absf(gap) * recovery_rate), 1, absi(gap))
        if gap > 0:
            _city.add_resource_amount(resource_name, mini(step, _city.get_free_capacity(resource_name)))
        else:
            _city.remove_resource_amount(resource_name, step)
    refresh_all() # the world index may have changed even where the stock did not
#endregion
