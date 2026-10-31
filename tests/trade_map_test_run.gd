extends Node
# The trade scene's maps: one per kind of place, with buy and sell placeholders where the resources
# are shown. A scene because of the autoloads.
# Run:  godot --headless --path . res://tests/trade_map_test_run.tscn

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


func _scene(city_name: String) -> TradeScene:
    var scene: TradeScene = load("res://scenes/core/trade_scene.tscn").instantiate()
    get_tree().root.add_child(scene)
    await get_tree().process_frame
    scene.initialize(city_name)
    await seconds(0.2)
    return scene

func _run() -> void:
    GameState.start_new_game(GameState.DEBUG_SLOT)
    await get_tree().process_frame
    get_tree().paused = false
    _test_map_scenes()
    await _test_city()
    await _test_industry()
    await _test_depot()
    await _test_sell_click()
    print("%d checks, %d failed" % [_checks, _failed])
    print("ALL PASSED" if _failed == 0 else "FAILED")
    get_tree().quit(1 if _failed > 0 else 0)


func _test_map_scenes() -> void:
    for path in ["res://scenes/maps/trade_city.tscn", "res://scenes/maps/trade_industry.tscn", "res://scenes/maps/trade_depot.tscn"]:
        var map := load(path).instantiate() as TradeMap
        add_child(map)
        ok(map != null, "%s is a TradeMap" % path)
        for layer in ["Ground", "Roads", "Buildings"]:
            var tile_layer := map.get_node(layer) as TileMapLayer
            ok(tile_layer != null and tile_layer.get_used_cells().size() > 0, "%s has a painted %s" % [path, layer])
        ok(map.get_buy_positions().size() >= 6, "%s has buy placeholders" % path)
        ok(map.get_sell_positions().size() >= 6, "%s has sell placeholders" % path)
        ok(map.get_buy_positions()[0].y < map.get_sell_positions()[0].y, "buy placeholders above, sell ones by the train")
        remove_child(map)
        map.free()
    var scene: PackedScene = load("res://scenes/core/trade_scene.tscn")
    var instance := scene.instantiate()
    ok(instance.get_node("MapRoot").get_child_count() == 1, "the scene shows a map in the editor")
    instance.free()


# Positions of a manager's nodes, in global coordinates
func _globals(nodes: Dictionary) -> Array:
    var result := []
    for node: TradeResource in nodes.values():
        result.append(node.global_position)
    return result


func _test_city() -> void:
    var scene := await _scene("Paris")
    eq(scene.trade_map.name, "TradeCity", "a city uses the city map")
    var manager := scene.trade_resource_manager
    var names: Array = scene.city_inventory.get_resource_names()
    eq(manager.trade_resources.size(), names.size(), "every resource the city trades is on a buy placeholder (mode Both)")
    eq(manager.sell_resources.size(), names.size(), "and on a sell placeholder")
    var buy_positions := scene.trade_map.get_buy_positions()
    var sell_positions := scene.trade_map.get_sell_positions()
    for i in names.size():
        var buy_node: TradeResource = manager.trade_resources[names[i]]
        var sell_node: TradeResource = manager.sell_resources[names[i]]
        ok(buy_node.global_position.distance_to(buy_positions[i]) < 0.5, "%s stands on buy placeholder %d" % [names[i], i + 1])
        ok(sell_node.global_position.distance_to(sell_positions[i]) < 0.5, "%s stands on sell placeholder %d" % [names[i], i + 1])
        eq(buy_node.side, TradeResource.Side.BUY, "the buy node is on the buy side")
        eq(sell_node.side, TradeResource.Side.SELL, "the sell node is on the sell side")
        eq(buy_node.price_label.text, str(scene.city_inventory.get_buy_price(names[i])), "the buy node shows the buy price")
        eq(sell_node.price_label.text, str(scene.city_inventory.get_sell_price(names[i])), "the sell node shows the sell price")
    eq(scene.place.global_position, scene.trade_map.get_place_position(), "the building stands on the map's Place marker")
    # the economy moves both
    var item: String = names[0]
    GameState.add_money(1000)
    TradeService.buy(scene.city_inventory, scene.train_inventory, item, 1)
    eq(manager.get_sell_resource(item).qty, scene.city_inventory.get_available_qty(item), "a trade updates both nodes' stock")
    eq(manager.get_sell_resource(item).price_label.text, str(scene.city_inventory.get_sell_price(item)), "and the sell price shown")
    scene.queue_free()
    await get_tree().process_frame


func _test_industry() -> void:
    var scene := await _scene("Foundry")
    eq(scene.trade_map.name, "TradeIndustry", "an industry uses the industry map")
    var manager := scene.trade_resource_manager
    var city := scene.city_inventory
    var checked_buy := 0
    var checked_sell := 0
    for resource_name: String in city.get_resource_names():
        eq(manager.trade_resources.has(resource_name), city.can_player_buy(resource_name), "%s: on a buy placeholder only if the player can buy it" % resource_name)
        eq(manager.sell_resources.has(resource_name), city.can_player_sell(resource_name), "%s: on a sell placeholder only if the player can sell it" % resource_name)
        if city.can_player_buy(resource_name) and not city.can_player_sell(resource_name):
            checked_buy += 1
        if city.can_player_sell(resource_name) and not city.can_player_buy(resource_name):
            checked_sell += 1
    ok(checked_buy > 0 and checked_sell > 0, "the foundry has resources that only go to one side")
    ok(scene.place.area.input_pickable, "an industry's building can be tapped")
    scene.queue_free()
    await get_tree().process_frame


func _test_depot() -> void:
    var scene := await _scene("Central Depot")
    eq(scene.trade_map.name, "TradeDepot", "a depot uses the depot map")
    eq(scene.trade_resource_manager.trade_resources.size() + scene.trade_resource_manager.sell_resources.size(), 0, "a depot trades no resources")
    scene.queue_free()
    await get_tree().process_frame


func _test_sell_click() -> void:
    var scene := await _scene("Paris")
    var city := scene.city_inventory
    var train := scene.train_inventory
    var item := "alcohol"
    var refusals := []
    scene.trade_ui.refused.connect(func(text: String) -> void: refusals.append(text))
    var missing := "furs" # the train starts with no furs
    ok(train.get_total_qty_of(missing) == 0, "the train carries no %s" % missing)
    scene.trade_resource_manager.sell_resource_clicked.emit(missing)
    eq(refusals.size(), 1, "tapping a sell placeholder when the train carries none of it says so")
    ok(not scene.trade_ui.sell_menu.visible, "and opens nothing")

    GameState.add_money(1000)
    ok(TradeService.buy(city, train, item, 2) == TradeService.Result.OK, "the player buys some")
    scene.trade_ui.close_all()
    var node := scene.trade_resource_manager.get_sell_resource(item)
    scene.trade_resource_manager.sell_resource_clicked.emit(item) # what a tap on the node does
    ok(scene.trade_ui.sell_menu.visible, "now it opens the sell menu of the wagon that carries it")
    eq(scene.trade_ui.sell_menu.price_label.text, str(city.get_sell_price(item)), "with the price the city pays")
    # and a tap on the buy placeholder opens the buy menu
    scene.trade_ui.close_all()
    scene.trade_resource_manager.resource_clicked.emit(item)
    ok(scene.trade_ui.buy_menu.visible and scene.trade_ui.buy_menu.current_resource == item, "a buy placeholder opens the buy menu")
    ok(node != null and node.side == TradeResource.Side.SELL, "the node tapped was the sell one")
    scene.queue_free()
    await get_tree().process_frame
