extends Node
class_name CityInventory
# Runtime stock of one city in the trade scene.
# Every change goes through this object, which also writes it to GameState. With a single path
# for changes, both copies stay in sync.
#
# Create it in code: CityInventory.new(city_name), then load_from_game_state().
# (If you prefer it as a node in the scene, change the first line back to "extends Node".)
#
# Price convention, from the PLAYER's point of view:
#   buy_price  = what the player pays to buy 1 unit from the city
#   sell_price = what the city pays the player for 1 unit
# buy_price should be >= sell_price, otherwise the player can make infinite money
# by buying and selling the same goods.
#
# resources example:
# {
#     "Oil": {"qty": 3, "buy_price": 5, "sell_price": 4, "max_capacity": 999},
# }

signal city_resource_amount_changed(resource_name: String, qty: int)
signal city_wagon_amount_changed(wagon_type: String, qty: int)
signal city_recruit_amount_changed(unit_type: String, qty: int)

const DEFAULT_MAX_CAPACITY := 999 # used when the city data has no MaxCapacity
const MODE_BOTH := "Both" # the place buys and sells it (cities)
const MODE_BUYS := "Buys" # the place only BUYS it: the player can sell it, not buy it
const MODE_SELLS := "Sells" # the place only SELLS it: the player can buy it, not sell it


var place_type := "City" # the "Type" in the JSON: "City" or "Industry"
var city_name := ""
var recipes: Array[Dictionary] = [] # [{name, inputs: {resource: qty}, outputs: {resource: qty}}]
var resources := {} # resource_name -> {qty, buy_price, sell_price, max_capacity}
var wagons := {} # wagon_name -> {qty, buy_price, sell_price, max_capacity}
var recruits := {} # unit_type -> {qty, price}. Soldiers can only be bought: there is no sell price

func _init(city_name_: String = "") -> void:
    city_name = city_name_


#region setup
# Builds the stock from GameState. TradeResources: { name: { Quantity, BuyPrice, SellPrice, MaxCapacity? } }
func load_from_game_state(city_name_: String) -> bool:
    city_name = city_name_
    var city_data: Dictionary = GameState.get_city_by_name(city_name)
    place_type = str(city_data.get("Type", "City"))
    if city_data.is_empty():
        push_error("CityInventory: city '%`s' not found in GameState" % city_name)
        return false

    # read resources
    resources.clear()
    var trade_resources: Dictionary = city_data.get("TradeResources", {})
    for resource_name in trade_resources:
        var data: Dictionary = trade_resources[resource_name]
        var mode := str(data.get("Mode", MODE_BOTH))
        if not [MODE_BOTH, MODE_BUYS, MODE_SELLS].has(mode):
            push_error("CityInventory: '%s' in %s has Mode '%s' (use Both, Buys or Sells)" % [resource_name, city_name, mode])
            mode = MODE_BOTH
        # JSON numbers are floats, so everything goes through int()
        initialize_resource(
            resource_name,
            int(data.get("Quantity", 0)),
            int(data.get("BuyPrice", 0)),
            int(data.get("SellPrice", 0)),
            int(data.get("MaxCapacity", DEFAULT_MAX_CAPACITY)))
    
    # read wagons
    wagons.clear()
    var trade_wagons: Dictionary = city_data.get("TradeWagons", {}) # optional: most cities don't sell wagons
    for wagon_type in trade_wagons:
        if not WagonTypes.TYPES.has(wagon_type):
            push_error("CityInventory: '%s' in %s is not a wagon type" % [wagon_type, city_name])
            continue
        var data: Dictionary = trade_wagons[wagon_type]
        var buy_price := int(data.get("BuyPrice", 0))
        var sell_price := int(data.get("SellPrice", 0))
        if buy_price < sell_price:
            push_warning("CityInventory: wagon '%s' in %s has buy_price %d < sell_price %d (infinite money)" % [wagon_type, city_name, buy_price, sell_price])
        wagons[wagon_type] = {"qty": int(data.get("Quantity", 0)), "buy_price": buy_price, "sell_price": sell_price}
    
    # read recruits (optional): the soldiers the player can hire here
    recruits.clear()
    var city_recruits: Dictionary = city_data.get("Recruits", {})
    for unit_type in city_recruits:
        if not UnitTypes.exists(unit_type):
            push_error("CityInventory: '%s' in %s is not a unit type" % [unit_type, city_name])
            continue
        var data: Dictionary = city_recruits[unit_type]
        recruits[unit_type] = {"qty": int(data.get("Quantity", 0)), "price": int(data.get("Price", 0))}
        
    # read recipes
    recipes.clear()
    for recipe_data in city_data.get("Recipes", []):
        _add_recipe(recipe_data)
    return true


func initialize_resource(resource_name: String, qty: int, buy_price: int, sell_price: int, max_capacity: int, mode := MODE_BOTH) -> void:
    if mode == MODE_BOTH and buy_price < sell_price:
        push_warning("CityInventory: '%s' in %s has buy_price %d < sell_price %d (infinite money)" % [resource_name, city_name, buy_price, sell_price])

    resources[resource_name] = {
        "qty": qty,
        "buy_price": buy_price,
        "sell_price": sell_price,
        "max_capacity": maxi(max_capacity, qty), # the initial stock always fits
        "mode": mode
    }
#endregion


#region queries
func allows_rearranging() -> bool:
    return place_type == "Depot"
    
# The place sells it, so the player can buy it
func can_player_buy(resource_name: String) -> bool:
    return [MODE_BOTH, MODE_SELLS].has(resources.get(resource_name, {}).get("mode", ""))


# The place buys it, so the player can sell it
func can_player_sell(resource_name: String) -> bool:
    return [MODE_BOTH, MODE_BUYS].has(resources.get(resource_name, {}).get("mode", ""))
    
func has_resource(resource_name: String) -> bool:
    return resources.has(resource_name)


func get_resource_names() -> Array:
    return resources.keys()


# Returns copies, so callers can't change the stock by accident.
func get_all_info() -> Dictionary:
    return resources.duplicate(true)


func get_resource_info(resource_name: String) -> Dictionary:
    return resources.get(resource_name, {}).duplicate()


func get_available_qty(resource_name: String) -> int:
    return resources.get(resource_name, {}).get("qty", 0)


func get_buy_price(resource_name: String) -> int:
    return resources.get(resource_name, {}).get("buy_price", 0)


func get_sell_price(resource_name: String) -> int:
    return resources.get(resource_name, {}).get("sell_price", 0)


# Free space for this resource (was get_storage_capacity)
func get_free_capacity(resource_name: String) -> int:
    var info: Dictionary = resources.get(resource_name, {})
    return info.get("max_capacity", 0) - info.get("qty", 0)


func has_wagon_type(wagon_type: String) -> bool:
    return wagons.has(wagon_type)

func has_industry() -> bool:
    return not recipes.is_empty()

func get_wagon_types() -> Array:
    return wagons.keys()

func get_wagon_available_qty(wagon_type: String) -> int:
    return wagons.get(wagon_type, {}).get("qty", 0)

func get_wagon_buy_price(wagon_type: String) -> int:
    return wagons.get(wagon_type, {}).get("buy_price", 0)

func get_wagon_sell_price(wagon_type: String) -> int:
    return wagons.get(wagon_type, {}).get("sell_price", 0)

func get_recipes() -> Array:
    return recipes.duplicate(true)

func has_recruit_type(unit_type: String) -> bool:
    return recruits.has(unit_type)

func get_recruit_types() -> Array:
    return recruits.keys()

func get_recruit_qty(unit_type: String) -> int:
    return recruits.get(unit_type, {}).get("qty", 0)

func get_recruit_price(unit_type: String) -> int:
    return recruits.get(unit_type, {}).get("price", 0)
#endregion


#region changes
func _add_recipe(recipe_data: Dictionary) -> void:
    var recipe_name := str(recipe_data.get("Name", "?"))
    var inputs := _read_amounts(recipe_data.get("Inputs", {}), recipe_name)
    var outputs := _read_amounts(recipe_data.get("Outputs", {}), recipe_name)
    if inputs.is_empty() or outputs.is_empty():
        push_error("CityInventory: recipe '%s' in %s needs valid Inputs and Outputs, so it was skipped" % [recipe_name, city_name])
        return
    recipes.append({"name": recipe_name, "inputs": inputs, "outputs": outputs})

# {resource: qty} with int quantities. Every resource must be listed in this place's TradeResources.
func _read_amounts(data: Dictionary, recipe_name: String) -> Dictionary:
    var result := {}
    for resource_name in data:
        var qty := int(data[resource_name])
        if qty <= 0 or not resources.has(resource_name):
            push_error("CityInventory: recipe '%s' in %s uses '%s' x%d, which is not in its TradeResources" % [recipe_name, city_name, resource_name, qty])
            return {}
        result[resource_name] = qty
    return result

# Adds units to the city's stock. Returns false, changing nothing, if it doesn't fit.
func add_resource_amount(resource_name: String, qty: int) -> bool:
    if qty <= 0 or not resources.has(resource_name):
        return false
    if qty > get_free_capacity(resource_name):
        return false
    _apply_change(resource_name, qty)
    return true


# Removes units from the city's stock. Returns false, changing nothing, if there isn't enough.
func remove_resource_amount(resource_name: String, qty: int) -> bool:
    if qty <= 0 or not resources.has(resource_name):
        return false
    if qty > get_available_qty(resource_name):
        return false
    _apply_change(resource_name, -qty)
    return true

# The player sold wagons to the city. Returns false if the city doesn't trade that type.
func add_wagon_amount(wagon_type: String, qty: int) -> bool:
    if qty <= 0 or not wagons.has(wagon_type):
        return false
    var info: Dictionary = wagons[wagon_type]
    info["qty"] += qty
    GameState.change_city_wagons(city_name, wagon_type, qty)
    city_wagon_amount_changed.emit(wagon_type, info["qty"])
    return true
    
# Takes wagons out of the city's stock. Returns false, changing nothing, if there aren't enough.
func remove_wagon_amount(wagon_type: String, qty: int) -> bool:
    if qty <= 0 or not wagons.has(wagon_type):
        return false
    if qty > get_wagon_available_qty(wagon_type):
        return false
    var info: Dictionary = wagons[wagon_type]
    info["qty"] -= qty
    GameState.change_city_wagons(city_name, wagon_type, -qty)
    city_wagon_amount_changed.emit(wagon_type, info["qty"])
    return true

# The player hired soldiers. Returns false, changing nothing, if there aren't enough.
func remove_recruit_amount(unit_type: String, qty: int) -> bool:
    if qty <= 0 or not recruits.has(unit_type):
        return false
    if qty > get_recruit_qty(unit_type):
        return false
    var info: Dictionary = recruits[unit_type]
    info["qty"] -= qty
    GameState.change_city_recruits(city_name, unit_type, -qty)
    city_recruit_amount_changed.emit(unit_type, info["qty"])
    return true
    
func _apply_change(resource_name: String, delta: int) -> void:
    var info: Dictionary = resources[resource_name]
    info["qty"] += delta
    GameState.change_city_goods(city_name, resource_name, delta)
    city_resource_amount_changed.emit(resource_name, info["qty"])
#endregion
