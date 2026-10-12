extends Node
class_name TradeService
# Buying and selling between a city and the player's train.
# Stateless: the inventories are passed in. Money lives in GameState.
# Every rule is checked BEFORE anything changes, so a trade is all or nothing.
#
# Assumption: a city only trades the resources it lists (it needs their prices).

enum Result {OK, INVALID, NO_STOCK, NO_MONEY, NO_TRAIN_SPACE, NOT_IN_TRAIN, NO_CITY_SPACE}


#region limits (for the UI: enable buttons, "buy max")
# Most units the player can buy right now: limited by city stock, money and train space.
static func max_buyable(city: CityInventory, train: TrainInventory, resource_name: String) -> int:
    if not city.has_resource(resource_name):
        return 0
    var limit := mini(city.get_available_qty(resource_name), train.get_free_capacity_for(resource_name))
    var price := city.get_buy_price(resource_name)
    if price > 0:
        limit = mini(limit, floori(GameState.get_money() / float(price)))
    return limit


# Most units the player can sell right now: limited by what the train carries and the city's free space.
static func max_sellable(city: CityInventory, train: TrainInventory, resource_name: String) -> int:
    if not city.has_resource(resource_name):
        return 0
    return mini(train.get_total_qty_of(resource_name), city.get_free_capacity(resource_name))

# Most units that can be sold from this wagon: what it holds, limited by the city's free space.
static func max_sellable_from_wagon(city: CityInventory, train: TrainInventory, wagon_index: int) -> int:
    var resource_name := train.get_wagon_current_resource(wagon_index)
    if resource_name == "" or not city.has_resource(resource_name):
        return 0
    return mini(train.get_wagon_resource_qty(wagon_index), city.get_free_capacity(resource_name))

#endregion


#region transactions
static func buy(city: CityInventory, train: TrainInventory, resource_name: String, qty: int) -> Result:
    if qty <= 0 or not city.has_resource(resource_name):
        return Result.INVALID
    if city.get_available_qty(resource_name) < qty:
        return Result.NO_STOCK
    var cost := city.get_buy_price(resource_name) * qty
    if GameState.get_money() < cost:
        return Result.NO_MONEY
    if train.get_free_capacity_for(resource_name) < qty:
        return Result.NO_TRAIN_SPACE

    # Everything is valid, so these can't fail. The check only guards against a bug in the inventories.
    var ok := GameState.add_money(-cost)
    ok = city.remove_resource_amount(resource_name, qty) and ok
    ok = train.add_resource_amount(resource_name, qty) and ok
    if not ok:
        push_error("TradeService: buy of %d %s failed after validation" % [qty, resource_name])
    return Result.OK


static func sell(city: CityInventory, train: TrainInventory, resource_name: String, qty: int) -> Result:
    if qty <= 0 or not city.has_resource(resource_name):
        return Result.INVALID
    if train.get_total_qty_of(resource_name) < qty:
        return Result.NOT_IN_TRAIN
    if city.get_free_capacity(resource_name) < qty:
        return Result.NO_CITY_SPACE
    var income := city.get_sell_price(resource_name) * qty

    var ok := train.remove_resource_amount(resource_name, qty)
    ok = city.add_resource_amount(resource_name, qty) and ok
    ok = GameState.add_money(income) and ok
    if not ok:
        push_error("TradeService: sell of %d %s failed after validation" % [qty, resource_name])
    return Result.OK

static func sell_from_wagon(city: CityInventory, train: TrainInventory, wagon_index: int, qty: int) -> Result:
    var resource_name := train.get_wagon_current_resource(wagon_index)
    if qty <= 0 or resource_name == "" or not city.has_resource(resource_name):
        return Result.INVALID
    if train.get_wagon_resource_qty(wagon_index) < qty:
        return Result.NOT_IN_TRAIN
    if city.get_free_capacity(resource_name) < qty:
        return Result.NO_CITY_SPACE
    var income := city.get_sell_price(resource_name) * qty

    var ok := train.remove_resource_qty_from_wagon(wagon_index, qty)
    ok = city.add_resource_amount(resource_name, qty) and ok
    ok = GameState.add_money(income) and ok
    if not ok:
        push_error("TradeService: sell from wagon %d failed after validation" % wagon_index)
    return Result.OK
#endregion


# Text for the player when a trade is refused
static func result_text(result: Result) -> String:
    match result:
        Result.NO_STOCK:
            return "The city doesn't have enough."
        Result.NO_MONEY:
            return "Not enough money."
        Result.NO_TRAIN_SPACE:
            return "No room in the train."
        Result.NOT_IN_TRAIN:
            return "The train doesn't carry that."
        Result.NO_CITY_SPACE:
            return "The city can't store more."
        Result.INVALID:
            return "That can't be traded."
    return ""
