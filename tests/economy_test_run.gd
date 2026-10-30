extends Node
# Tests of the economy: PriceModel, CityEconomyManager (one city), GlobalEconomyManager (the world),
# their data in GameState, and the trade scene showing the prices. A scene because of the autoloads.
# Run:  godot --headless --path . res://tests/economy_test_run.tscn

var _failed := 0
var _checks := 0

func skips_quests_when_debugging() -> bool:
    return true

func _ready() -> void:
    _run.call_deferred()

func ok(condition: bool, what: String) -> void:
    _checks += 1
    if not condition:
        _failed += 1
        print("FAIL: ", what)

func eq(actual: Variant, expected: Variant, what: String) -> void:
    _checks += 1
    if actual != expected:
        _failed += 1
        print("FAIL: %s (got %s, expected %s)" % [what, actual, expected])

func seconds(t: float) -> void:
    await get_tree().create_timer(t, true, false, true).timeout


# A city of the game as an inventory with its economy
func _city(city_name: String) -> Array:
    var inventory := CityInventory.new()
    inventory.load_from_game_state(city_name)
    var economy := CityEconomyManager.new()
    economy.setup(inventory)
    return [inventory, economy]

func _fresh_game() -> void:
    GameState.start_new_game(GameState.DEBUG_SLOT)

func _run() -> void:
    _test_price_model()
    _test_city_prices_react()
    _test_city_data()
    _test_daily_update()
    _test_global_days_and_scarcity()
    _test_shocks()
    _test_save_data()
    await _test_timer()
    await _test_trade_scene()
    _test_scenes_have_managers()
    print("%d checks, %d failed" % [_checks, _failed])
    print("ALL PASSED" if _failed == 0 else "FAILED")
    get_tree().quit(1 if _failed > 0 else 0)


func _test_price_model() -> void:
    eq(PriceModel.stock_multiplier(20, 20), 1.0, "the stock is the target: normal price")
    ok(PriceModel.stock_multiplier(10, 20) > 1.0, "less than wanted: dearer")
    ok(PriceModel.stock_multiplier(30, 20) < 1.0, "more than wanted: cheaper")
    ok(is_equal_approx(PriceModel.stock_multiplier(5, 20), 2.0), "a quarter of the target doubles the price")
    eq(PriceModel.stock_multiplier(0, 20), PriceModel.MAX_STOCK_MULTIPLIER, "none at all: the highest price")
    eq(PriceModel.stock_multiplier(1000, 20), PriceModel.MIN_STOCK_MULTIPLIER, "far too much: the lowest price")
    eq(PriceModel.stock_multiplier(3, 0), 1.0, "a city that wants nothing does not change the price")
    var last := 100.0
    var monotonic := true
    for stock in range(0, 80):
        var m := PriceModel.stock_multiplier(stock, 20)
        if m > last + 0.0000001:
            monotonic = false
        last = m
    ok(monotonic, "the more stock, the lower the price, never the other way")
    eq(PriceModel.price(0.0, 2.0), 0, "a side that is not traded stays 0")
    eq(PriceModel.price(0.2, 0.5), 1, "a traded side costs at least 1")
    eq(PriceModel.price(4.0, 1.5), 6, "price rounds")
    var never_loses := true
    for tenth in range(1, 200):
        var m := tenth / 20.0
        if PriceModel.price(7.7, m) < PriceModel.price(6.1, m):
            never_loses = false
    ok(never_loses, "rounding keeps buy >= sell (no infinite money)")
    ok(PriceModel.scarcity_index(10, 100) > 1.0, "the world has little: dearer everywhere")
    ok(PriceModel.scarcity_index(300, 100) < 1.0, "the world has plenty: cheaper")
    eq(PriceModel.scarcity_index(5, 0), 1.0, "nobody wants it: no effect")
    ok(PriceModel.scarcity_index(0, 100) <= PriceModel.MAX_GLOBAL_INDEX, "the index has a ceiling")


func _test_city_prices_react() -> void:
    _fresh_game()
    var pair := _city("Paris")
    var city: CityInventory = pair[0]
    var economy: CityEconomyManager = pair[1]
    var changes := []
    economy.price_changed.connect(func(r: String, b: int, s: int) -> void: changes.append([r, b, s]))
    var inventory_signals := []
    city.city_prices_changed.connect(func(r: String) -> void: inventory_signals.append(r))

    var item := "alcohol"
    var qty := city.get_available_qty(item)
    eq(city.get_target(item), qty, "the city wants the stock it starts with")
    eq(city.get_demand(item), 0, "so it needs nothing yet")
    var start_buy := city.get_buy_price(item)
    var start_sell := city.get_sell_price(item)
    ok(start_buy > start_sell and start_sell > 0, "alcohol sells for more than it is bought for")

    # the player buys most of it: the city NEEDS it
    ok(city.remove_resource_amount(item, qty - 1), "the player buys almost all")
    ok(city.get_demand(item) > 0, "the city is short of it")
    eq(economy.get_demand(item), qty - 1, "the demand is what is missing")
    ok(city.get_buy_price(item) > start_buy, "demand pushes the buy price up")
    ok(city.get_sell_price(item) > start_sell, "and the price the city pays")
    ok(changes.size() > 0 and changes[-1][0] == item, "the economy says the price changed")
    ok(inventory_signals.has(item), "and the inventory too")
    var scarce_buy := city.get_buy_price(item)

    # the player brings it: the need goes away
    ok(city.add_resource_amount(item, qty - 1), "the player supplies it again")
    eq(city.get_demand(item), 0, "no demand left")
    eq(city.get_buy_price(item), start_buy, "the price is back")
    ok(city.add_resource_amount(item, 20), "and keeps supplying")
    ok(city.get_buy_price(item) < start_buy, "an oversupplied city pays less")
    ok(city.get_buy_price(item) < scarce_buy, "much less than when it was scarce")

    # the spread never turns into money for free
    var always_ok := true
    for stock in [0, 1, 3, 10, 40]:
        city.remove_resource_amount(item, city.get_available_qty(item))
        if stock > 0 and not city.add_resource_amount(item, stock):
            continue
        if city.get_buy_price(item) < city.get_sell_price(item):
            always_ok = false
    ok(always_ok, "at any stock the player gets less for a unit than it costs")

    # a resource the city only buys keeps its buy side at 0
    var foundry := _city("Foundry")
    var foundry_city: CityInventory = foundry[0]
    var checked := false
    for resource_name in foundry_city.get_resource_names():
        if not foundry_city.can_player_buy(resource_name):
            eq(foundry_city.get_buy_price(resource_name), 0, "%s is only bought by the foundry: nothing to buy" % resource_name)
            checked = true
        if not foundry_city.can_player_sell(resource_name):
            eq(foundry_city.get_sell_price(resource_name), 0, "%s is only sold by the foundry: it pays nothing" % resource_name)
            checked = true
    ok(checked, "the foundry has one-sided resources")
    for node: Node in [city, economy, foundry_city, foundry[1]]:
        node.free()


func _test_city_data() -> void:
    _fresh_game()
    var pair := _city("Foundry")
    var city: CityInventory = pair[0]
    var saved: Dictionary = GameState.get_city_by_name("Foundry")["TradeResources"]
    var all_have_target := true
    var empty_wants_something := true
    for resource_name in city.get_resource_names():
        if not saved[resource_name].has("Target"):
            all_have_target = false
        if city.get_target(resource_name) <= 0:
            empty_wants_something = false
    ok(all_have_target, "the targets are saved with the city")
    ok(empty_wants_something, "a city that starts with none still wants some (half its capacity)")
    # a stock that changes does not move the target
    var name0: String = city.get_resource_names()[0]
    var target := city.get_target(name0)
    city.add_resource_amount(name0, 1)
    eq(city.get_target(name0), target, "the target does not follow the stock")
    pair[1].free()
    city.free()
    # a later visit reads the same target
    var again := CityInventory.new()
    again.load_from_game_state("Foundry")
    eq(again.get_target(name0), target, "a new inventory of the city has the same target")
    again.free()
    # an explicit Target in the data wins
    GameState.get_city_by_name("Foundry")["TradeResources"][name0]["Target"] = 7
    var explicit := CityInventory.new()
    explicit.load_from_game_state("Foundry")
    eq(explicit.get_target(name0), 7, "a Target in the data is used")
    explicit.free()


func _test_daily_update() -> void:
    _fresh_game()
    var pair := _city("Paris")
    var city: CityInventory = pair[0]
    var economy: CityEconomyManager = pair[1]
    var item := "furs"
    var target := city.get_target(item)

    city.remove_resource_amount(item, target) # sold out
    eq(city.get_available_qty(item), 0, "sold out")
    var before := city.get_buy_price(item)
    economy.daily_update()
    var after_one := city.get_available_qty(item)
    ok(after_one > 0 and after_one < target, "a day brings some back, not all")
    for i in 4:
        economy.daily_update()
    ok(city.get_buy_price(item) < before, "so the price falls as the stock comes back (%d -> %d, stock %d, base %s)" % [before, city.get_buy_price(item), city.get_available_qty(item), city.get_base_buy_price(item)])
    for i in 60:
        economy.daily_update()
    eq(city.get_available_qty(item), target, "in time the stock is back to the target")

    city.add_resource_amount(item, city.get_free_capacity(item)) # a glut
    ok(city.get_available_qty(item) > target, "a glut")
    var glut_price := city.get_buy_price(item)
    economy.daily_update()
    ok(city.get_available_qty(item) < city.get_target(item) + city.get_free_capacity(item) + 100, "sanity")
    ok(city.get_buy_price(item) >= glut_price, "a day of use makes it a little dearer")
    for i in 200:
        economy.daily_update()
    eq(city.get_available_qty(item), target, "and it settles at the target")
    pair[1].free()
    city.free()


func _test_global_days_and_scarcity() -> void:
    _fresh_game()
    var world := GlobalEconomyManager.new()
    eq(world.get_day(), 0, "a new game starts at day 0")
    world.advance_day()
    eq(world.get_day(), 1, "a day passes")
    world.advance_days(29)
    eq(world.get_day(), 30, "thirty days")
    var calm := true
    for resource_name in ["alcohol", "furs", "wood"]:
        if absf(world.get_price_index(resource_name) - 1.0) > 0.15:
            calm = false
    ok(calm, "with nobody trading, prices stay about normal")

    # the player buys all the alcohol of the world
    _fresh_game()
    var drained := 0
    for city_name: String in GameState.get_all_city_names():
        var inventory := CityInventory.new()
        inventory.load_from_game_state(city_name)
        if inventory.has_resource("alcohol"):
            drained += inventory.get_available_qty("alcohol")
            inventory.remove_resource_amount("alcohol", inventory.get_available_qty("alcohol"))
        inventory.free()
    ok(drained > 0, "some alcohol was drained")
    world.advance_day()
    var index := world.get_price_index("alcohol")
    ok(index > 1.1, "the world is short of alcohol: it gets dearer everywhere (index %.2f)" % index)
    ok(index <= PriceModel.MAX_GLOBAL_INDEX, "within its limits")
    var wood := world.get_price_index("wood")
    ok(wood < index, "other resources are not touched as much")
    var before_more := index
    world.advance_days(3)
    ok(world.get_price_index("alcohol") != before_more or before_more >= PriceModel.MAX_GLOBAL_INDEX, "it keeps moving")

    # a city's price shows it
    var paris := _city("Paris")
    var paris_city: CityInventory = paris[0]
    var base := paris_city.get_base_buy_price("alcohol")
    ok(paris_city.get_buy_price("alcohol") >= roundi(base), "the price in a city includes the world's index")
    paris[1].free()
    paris_city.free()

    # the same day gives the same result
    _fresh_game()
    world.advance_days(5)
    var first := world.get_price_index("alcohol")
    _fresh_game()
    world.advance_days(5)
    eq(world.get_price_index("alcohol"), first, "the same game gives the same indices")
    world.free()


func _test_shocks() -> void:
    _fresh_game()
    var world := GlobalEconomyManager.new()
    world.advance_day()
    var base := world.get_price_index("missiles")
    var city_pair := _city("Paris")
    var city: CityInventory = city_pair[0]
    var item := "alcohol"
    var normal_price := city.get_buy_price(item)
    var normal_index := world.get_price_index(item)

    world.add_shock(item, 2.0, 3)
    ok(is_equal_approx(world.get_price_index(item), normal_index * 2.0), "a shock acts at once")
    city_pair[1].refresh_all()
    ok(city.get_buy_price(item) > normal_price * 1.5, "and shows in the city's prices")
    eq(world.get_price_index("missiles"), base, "other resources are not affected")
    eq(world.get_shocks().size(), 1, "one shock is active")
    world.advance_day()
    world.advance_day()
    ok(world.get_price_index(item) > normal_index * 1.5, "it lasts")
    world.advance_day()
    eq(world.get_shocks().size(), 0, "after its days it is gone")
    ok(world.get_price_index(item) < normal_index * 1.3, "and the price comes back")

    world.add_shock("", 1.5, 5) # everything
    ok(world.get_price_index("furs") > 1.3 and world.get_price_index("wood") > 1.3, "a shock on everything reaches all")
    world.clear_shocks()
    ok(world.get_price_index("furs") < 1.2, "cleared")
    world.add_shock(item, 100.0, 1)
    ok(world.get_price_index(item) <= PriceModel.MAX_EFFECTIVE_INDEX, "a shock is limited")
    world.clear_shocks()
    city_pair[1].free()
    city.free()
    world.free()


func _test_save_data() -> void:
    _fresh_game()
    var world := GlobalEconomyManager.new()
    world.advance_days(3)
    world.add_shock("fish", 1.4, 9)
    # what save_game writes to cities.json comes back from JSON with floats for numbers
    var state: Dictionary = JSON.parse_string(JSON.stringify({
        "day": GameState.get_economy_day(), "base": GameState.get_economy_base(),
        "indices": GameState.get_economy_effective(), "shocks": GameState.get_price_shocks()}))
    eq(GameState._validate_cities({"cities": {}, "city_ids": {}, "economy": state}), "", "a save with an economy is valid")
    eq(GameState._validate_cities({"cities": {}, "city_ids": {}}), "", "so is one from before the economy")
    ok(GameState._validate_cities({"cities": {}, "city_ids": {}, "economy": 3}) != "", "an economy that is not an object is refused")
    var day := GameState.get_economy_day()
    var fish := GameState.get_price_index("fish")
    GameState._economy_state = state
    eq(GameState.get_economy_day(), day, "the day survives a save")
    ok(is_equal_approx(GameState.get_price_index("fish"), fish), "so do the indices")
    eq(GameState.get_price_shocks().size(), 1, "and the shocks")
    world.advance_day() # the shock's days were floats in JSON
    eq(GameState.get_price_shocks()[0]["days"], 8, "a shock goes on counting after a load")
    GameState._economy_state = {}
    eq(GameState.get_economy_day(), 0, "a game with no economy starts at day 0")
    eq(GameState.get_price_index("fish"), 1.0, "with every index at 1")
    world.free()


func _test_timer() -> void:
    _fresh_game()
    await get_tree().process_frame
    get_tree().paused = false # a new game starts its quests, which pause the game on their dialog
    var world := GlobalEconomyManager.new()
    world.seconds_per_day = 0.4
    var days := []
    world.day_passed.connect(func(d: int) -> void: days.append(d))
    add_child(world)
    await seconds(1.3)
    ok(days.size() >= 2 and days[0] == 1 and days[1] == 2, "days pass with time (%s)" % [days])
    world.enabled = false
    var stopped := GameState.get_economy_day()
    await seconds(0.9)
    eq(GameState.get_economy_day(), stopped, "and stop when it is disabled")
    world.queue_free()
    await get_tree().process_frame


func _test_trade_scene() -> void:
    _fresh_game()
    var scene: TradeScene = load("res://scenes/core/trade_scene.tscn").instantiate()
    get_tree().root.add_child(scene)
    await get_tree().process_frame
    scene.initialize("Paris")
    await seconds(0.3)
    var item := "alcohol"
    var city := scene.city_inventory
    var node := scene.trade_resource_manager.get_resource(item)
    ok(node != null, "the resource is in the scene")
    var price := city.get_buy_price(item)
    eq(node.buy_price, price, "the resource shows the price")

    GameState.add_money(1000)
    var train := scene.train_inventory
    ok(train.get_free_capacity_for(item) > 0, "the train has room for it")
    var bought := 0
    for i in 3:
        if TradeService.buy(city, train, item, 1) == TradeService.Result.OK:
            bought += 1
    ok(bought > 0, "bought some")
    ok(city.get_buy_price(item) > price, "the city's price goes up as it sells")
    eq(node.buy_price, city.get_buy_price(item), "and the label follows")
    var before_sell := city.get_sell_price(item)
    ok(TradeService.sell(city, train, item, bought) == TradeService.Result.OK, "the player sells them back")
    ok(city.get_sell_price(item) < before_sell, "supplying lowers the price the city pays")
    eq(node.sell_price, city.get_sell_price(item), "and the label follows")
    ok(is_instance_valid(scene.city_economy_manager) and scene.city_economy_manager is CityEconomyManager, "the scene has its CityEconomyManager")

    # an open menu shows the new price
    scene.trade_ui.toggle_resource(item)
    var shown_before: String = scene.trade_ui.buy_menu.price_label.text
    TradeService.buy(city, train, item, 1)
    ok(scene.trade_ui.buy_menu.price_label.text == str(city.get_buy_price(item)), "the open buy menu shows the current price (was %s)" % shown_before)
    scene.queue_free()
    await get_tree().process_frame


func _test_scenes_have_managers() -> void:
    var nav: Node = load("res://scenes/core/navigation_scene.tscn").instantiate()
    ok(nav.get_node_or_null("Managers/GlobalEconomyManager") is GlobalEconomyManager, "the navigation scene has the GlobalEconomyManager")
    nav.free()
