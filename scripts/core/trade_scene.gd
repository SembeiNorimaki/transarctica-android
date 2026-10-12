extends Node2D
class_name TradeScene

signal trade_failed(message: String) # for the HUD

# Managers (adjust the paths to where the nodes are)
@onready var horizontal_train_manager: HorizontalTrainManager = $Managers/HorizontalTrainManager
@onready var trade_resource_manager: TradeResourceManager = $Managers/TradeResourceManager

# Containers
@onready var train_container: Node2D = $TrainContainer
@onready var trade_resource_container: Node2D = $ResourceContainer

# Inventories
@onready var city_inventory: CityInventory = $Inventories/CityInventory
@onready var train_inventory: TrainInventory = $Inventories/TrainInventory

# Trains
@onready var player_train: HorizontalTrain = $TrainContainer/PlayerTrain

# UI
@onready var buy_menu: BuyMenu = $CanvasLayer/UI/BuyMenu
@onready var sell_menu: SellMenu = $CanvasLayer/UI/SellMenu
@onready var player_money_label: Label = $CanvasLayer/UI/PlayerMoney

const MUSIC_TRADE: AudioStream = preload("res://assets/audio/city1.wav")

# TODO: replace with Marker2D nodes in the scene so they follow the layout/resolution
const ENEMY_TRAIN_POSITION := Vector2(900, 100) # TODO: enemy train

# Only used when this scene is run on its own (F6), where SceneService is not calling initialize()
const DEBUG_CITY_NAME := "Paris"

static var _problems_reported := false

var city_name := ""

# Kept so other scripts reading TradeScene.player_train keep working
# var player_train: HorizontalTrain:
#     get:
#         return horizontal_train_manager.player_train

var _initialized := false


func _ready() -> void:
    # Inject before initialize()
    horizontal_train_manager.train_container = train_container
    trade_resource_manager.resource_container = trade_resource_container
    _set_resource_slots()
    
    # connect signals
    trade_resource_manager.resource_clicked.connect(_on_resource_clicked)
    buy_menu.buy_requested.connect(_on_buy_requested)
    city_inventory.city_resource_amount_changed.connect(_on_city_resource_amount_changed)
    train_inventory.wagon_resource_amount_changed.connect(_on_wagon_resource_amount_changed)
    player_train.wagon_clicked.connect(_on_wagon_clicked)
    sell_menu.sell_requested.connect(_on_sell_from_wagon_requested)

    AudioService.play_music(MUSIC_TRADE, 0.0)

    if OS.is_debug_build() and not _problems_reported:
        _problems_reported = true
        for problem in ResourceTypes.find_problems():
            push_warning("ResourceTypes: %s" % problem)

    if get_tree().current_scene == self:
        initialize(DEBUG_CITY_NAME)


# Optional: the Marker2D children of a "ResourceSlots" node define where the resources go.
# Without that node, the manager's default positions are used.
func _set_resource_slots() -> void:
    var markers := get_node_or_null("ResourceSlots")
    if markers == null:
        return
    var slots: Array[Vector2] = []
    for marker in markers.get_children():
        if marker is Node2D:
            slots.append(trade_resource_container.to_local((marker as Node2D).global_position))
    trade_resource_manager.set_slot_positions(slots)


#region initialize
# Called by SceneService right after the scene is added to the tree (so the @onready vars exist).
# Must be called only once.
func initialize(city_name_: String) -> void:
    if _initialized:
        push_error("TradeScene: already initialized")
        return
    _initialized = true
    city_name = city_name_

    GameState.money_changed.connect(_on_money_changed)
    player_money_label.text = str(GameState.get_money())
    _load_train()
    _load_city_resources()
    _update_all_wagon_prices()
    _print_inventories()


func _load_train() -> void:
    var train_data: Dictionary = GameState.get_player_train()
    if not horizontal_train_manager.setup_train(player_train, train_data, HorizontalTrainManager.Team.PLAYER):
           return
    #player_train.set_bounds(0.0, get_viewport_rect().size.x)
    train_inventory.load_from_game_state()
    
    # var train := horizontal_train_manager.spawn_train(PLAYER_TRAIN_POSITION, train_data, HorizontalTrainManager.Team.PLAYER)
    # if train == null:
    #     return
    # train.set_bounds(0.0, get_viewport_rect().size.x)
    # train_inventory.load_from_game_state()
    # TODO: train.wagon_clicked -> show the wagon's details

    
func _load_city_resources() -> void:
    if not city_inventory.load_from_game_state(city_name):
        return

    for resource_name in city_inventory.get_resource_names():
        # The manager logs an error if the resource can't be created (no free slot, duplicate...)
        trade_resource_manager.spawn_resource(
            resource_name,
            city_inventory.get_available_qty(resource_name),
            city_inventory.get_buy_price(resource_name),
            city_inventory.get_sell_price(resource_name))
#endregion


#region trading
func _on_buy_requested(resource_name: String, qty: int) -> void:
    _trade(resource_name, qty, true)


func _on_sell_requested(resource_name: String, qty: int) -> void:
    _trade(resource_name, qty, false)

func _on_sell_from_wagon_requested(wagon_index: int, qty: int) -> void:
    var result := TradeService.sell_from_wagon(city_inventory, train_inventory, wagon_index, qty)
    if result != TradeService.Result.OK:
        trade_failed.emit(TradeService.result_text(result))


func _on_resource_clicked(resource_name: String) -> void:
    if buy_menu.visible and buy_menu.current_resource == resource_name:
        buy_menu.close() # tapping the open resource again closes it
        return
    if sell_menu.visible:
        sell_menu.close()
    var node := trade_resource_manager.get_resource(resource_name)
    buy_menu.show_resource(
        resource_name,
        node.get_icon() if node != null else null,
        city_inventory.get_available_qty(resource_name),
        city_inventory.get_buy_price(resource_name))
    _refresh_buy_menu()

func _on_wagon_clicked(wagon: GenericWagon) -> void:
    print("TradeScene: Wagon clicked %s" % wagon)
    if not wagon is MerchandiseWagon:
        print("Wagon is not merchandise")
        return # other wagon types will do other things (combat, navigation...)
    var index := player_train.wagons.find(wagon)
    if index < 0:
        print("TradeScene: wagon not found in train")
        return
    if sell_menu.visible and sell_menu.current_wagon == index:
        sell_menu.close() # tapping the open wagon again closes it
        return

    var resource_name := train_inventory.get_wagon_current_resource(index)
    if resource_name == "":
        print("TradeScene: wagon %d is empty" % index)
        trade_failed.emit("This wagon is empty.")
        return
    if not city_inventory.has_resource(resource_name):
        print("TradeScene: city doesn't buy %s" % resource_name)
        trade_failed.emit("The city doesn't buy that.")
        return

    buy_menu.close() # only one menu at a time
    var node := trade_resource_manager.get_resource(resource_name)
    sell_menu.show_wagon(
        index,
        resource_name,
        node.get_icon() if node != null else null,
        train_inventory.get_wagon_resource_qty(index),
        city_inventory.get_sell_price(resource_name))
    _refresh_sell_menu()

# Keeps the open menu in sync: stock and whether buying is possible right now
func _refresh_buy_menu() -> void:
    var resource_name := buy_menu.current_resource
    if resource_name == "":
        return
    buy_menu.set_qty(city_inventory.get_available_qty(resource_name))
    buy_menu.set_can_buy(TradeService.max_buyable(city_inventory, train_inventory, resource_name) > 0)

# Keeps the open menu in sync with the wagon and the city
func _refresh_sell_menu() -> void:
    var index := sell_menu.current_wagon
    if index < 0:
        return
    var qty := train_inventory.get_wagon_resource_qty(index)
    if qty == 0:
        sell_menu.close() # the wagon is empty now
        return
    sell_menu.set_qty(qty)
    sell_menu.set_can_sell(TradeService.max_sellable_from_wagon(city_inventory, train_inventory, index) > 0)
    
func _trade(resource_name: String, qty: int, buying: bool) -> void:
    var result: TradeService.Result
    if buying:
        result = TradeService.buy(city_inventory, train_inventory, resource_name, qty)
    else:
        result = TradeService.sell(city_inventory, train_inventory, resource_name, qty)
    if result != TradeService.Result.OK:
        trade_failed.emit(TradeService.result_text(result))


func _update_wagon_price(wagon_index: int) -> void:
    var wagon := player_train.wagons[wagon_index] as MerchandiseWagon
    if wagon == null:
        return
    var resource_name := train_inventory.get_wagon_current_resource(wagon_index)
    var price := -1 # -1: the city doesn't buy it
    if resource_name != "" and city_inventory.has_resource(resource_name):
        price = city_inventory.get_sell_price(resource_name)
    wagon.set_sell_price(price)

func _update_all_wagon_prices() -> void:
    for i in player_train.wagons.size():
        _update_wagon_price(i)

# The numbers on screen come from the inventories' signals, never from the buttons themselves
func _on_city_resource_amount_changed(resource_name: String, qty: int) -> void:
    trade_resource_manager.set_resource_qty(resource_name, qty)
    _refresh_buy_menu()
    _refresh_sell_menu()


func _on_wagon_resource_amount_changed(wagon_index: int, resource_name: String, qty: int) -> void:
    var train := player_train
    if is_instance_valid(train) and wagon_index < train.wagons.size():
        train.wagons[wagon_index].set_cargo(resource_name, qty)
        _update_wagon_price(wagon_index)
    _refresh_buy_menu()
    _refresh_sell_menu()


func _on_money_changed(money: int) -> void:
    player_money_label.text = str(money)
    _refresh_buy_menu()


#endregion


#region UI callbacks
func _on_right_button_pressed() -> void:
    horizontal_train_manager.player_train_gear_up()


func _on_left_button_pressed() -> void:
    horizontal_train_manager.player_train_gear_down()
#endregion

func _print_inventories() -> void:
    print("=== City inventory: %s ===" % city_name)
    for resource_name in city_inventory.get_resource_names():
        var info := city_inventory.get_resource_info(resource_name)
        print("  %s: qty %d / max %d, buy %d, sell %d" % [resource_name, info.qty, info.max_capacity, info.buy_price, info.sell_price])

    print("  Wagons for sale:")
    for wagon_type in city_inventory.get_wagon_types():
        print("    %s: qty %d, buy %d, sell %d" % [wagon_type, city_inventory.get_wagon_available_qty(wagon_type), city_inventory.get_wagon_buy_price(wagon_type), city_inventory.get_wagon_sell_price(wagon_type)])

    print("=== Train inventory (money: %d) ===" % GameState.get_money())
    for i in train_inventory.get_wagon_count():
        var wagon := train_inventory.get_wagon_info(i)
        var cargo: String = wagon.resource_name if wagon.resource_name != "" else "(empty)"
        print("  [%d] %s: %s %d / %d" % [i, wagon.wagon_type, cargo, wagon.qty, wagon.max_capacity])
