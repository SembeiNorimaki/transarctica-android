extends Node2D
class_name TradeScene

signal trade_failed(message: String) # for the HUD

# Managers (adjust the paths to where the nodes are)
@onready var horizontal_train_manager: HorizontalTrainManager = $Managers/HorizontalTrainManager
@onready var trade_resource_manager: TradeResourceManager = $Managers/TradeResourceManager
@onready var trade_wagon_manager: TradeWagonManager = $Managers/TradeWagonManager
@onready var wagon_reorder_controller: WagonReorderController = $Managers/WagonReorderController
@onready var trade_unit_manager: TradeUnitManager = $Managers/TradeUnitManager

# Containers
@onready var train_container: Node2D = $TrainContainer
@onready var trade_resource_container: Node2D = $ResourceContainer
@onready var wagon_container: Node2D = $WagonContainer
@onready var unit_container: Node2D = $UnitContainer

# Inventories
@onready var city_inventory: CityInventory = $Inventories/CityInventory
@onready var train_inventory: TrainInventory = $Inventories/TrainInventory

# Trains
@onready var player_train: HorizontalTrain = $TrainContainer/PlayerTrain

# UI
@onready var buy_menu: BuyMenu = $CanvasLayer/UI/BuyMenu
@onready var sell_menu: SellMenu = $CanvasLayer/UI/SellMenu
@onready var player_money_label: Label = $CanvasLayer/UI/PlayerMoney
@onready var exit_button: Button = $CanvasLayer/UI/ExitButton


const MUSIC_TRADE: AudioStream = preload("res://assets/audio/city1.wav")

# TODO: replace with Marker2D nodes in the scene so they follow the layout/resolution
const ENEMY_TRAIN_POSITION := Vector2(900, 100) # TODO: enemy train

# Only used when this scene is run on its own (F6), where SceneService is not calling initialize()
const DEBUG_CITY_NAME := "Foundry"
# const DEBUG_CITY_NAME := "Paris"


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
    trade_wagon_manager.wagon_container = wagon_container
    trade_unit_manager.unit_container = unit_container
    
    _set_resource_slots()
    wagon_reorder_controller.setup(player_train)

    
    # connect signals
    trade_resource_manager.resource_clicked.connect(_on_resource_clicked)
    buy_menu.buy_requested.connect(_on_buy_requested)
    exit_button.pressed.connect(_on_exit_button_pressed)
    city_inventory.city_resource_amount_changed.connect(_on_city_resource_amount_changed)
    train_inventory.wagon_resource_amount_changed.connect(_on_wagon_resource_amount_changed)
    player_train.wagon_clicked.connect(_on_wagon_clicked)
    sell_menu.sell_requested.connect(_on_sell_from_wagon_requested)
    trade_wagon_manager.wagon_clicked.connect(_on_city_wagon_clicked)
    buy_menu.buy_wagon_requested.connect(_on_buy_wagon_requested)
    city_inventory.city_wagon_amount_changed.connect(_on_city_wagon_amount_changed)
    train_inventory.wagon_added.connect(_on_wagon_added)
    sell_menu.sell_wagon_requested.connect(_on_sell_wagon_requested)
    train_inventory.wagon_removed.connect(_on_wagon_removed)
    wagon_reorder_controller.wagon_dropped.connect(_on_wagon_dropped)
    train_inventory.wagon_moved.connect(_on_wagon_moved)
    trade_unit_manager.unit_clicked.connect(_on_city_unit_clicked)
    buy_menu.recruit_requested.connect(_on_recruit_requested)
    city_inventory.city_recruit_amount_changed.connect(_on_city_recruit_amount_changed)
    train_inventory.unit_added.connect(_on_unit_added)

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
    _load_city_wagons()
    _load_city_units()
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

func _load_city_wagons() -> void:
    for wagon_type in city_inventory.get_wagon_types():
        if city_inventory.get_wagon_available_qty(wagon_type) > 0:
            trade_wagon_manager.spawn_wagon(wagon_type) # logs an error if it can't

func _load_city_units() -> void:
    for unit_type in city_inventory.get_recruit_types():
        var qty := city_inventory.get_recruit_qty(unit_type)
        if qty > 0:
            trade_unit_manager.spawn_unit(unit_type, qty) # logs an error if it can't

#endregion


#region trading
func _on_buy_requested(resource_name: String, qty: int) -> void:
    _trade(resource_name, qty, true)


func _on_sell_requested(resource_name: String, qty: int) -> void:
    _trade(resource_name, qty, false)

func _on_sell_from_wagon_requested(wagon_index: int, qty: int) -> void:
    var resource_name := train_inventory.get_wagon_current_resource(wagon_index)
    var result := TradeService.sell_from_wagon(city_inventory, train_inventory, wagon_index, qty)
    if result == TradeService.Result.OK:
        QuestManager.notify_goods_delivered(city_name, resource_name, qty)
    else:
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
    if city_inventory.allows_rearranging():
        wagon_reorder_controller.begin_drag(wagon) # in a depot a press starts a drag, there is no trading
        return
        
    var index := player_train.wagons.find(wagon)
    if index < 0:
        return
    if sell_menu.visible and sell_menu.current_wagon == index:
        sell_menu.close() # tapping the open wagon again closes it
        return

    var wagon_type := train_inventory.get_wagon_type(index)
    var resource_name := train_inventory.get_wagon_current_resource(index)
    var sells_cargo := resource_name != "" and city_inventory.has_resource(resource_name)
    if not sells_cargo and not TradeService.can_sell_wagon(city_inventory, train_inventory, index):
        trade_failed.emit("The city doesn't buy anything from this wagon.")
        return

    buy_menu.close() # only one menu at a time
    if sells_cargo:
        var node := trade_resource_manager.get_resource(resource_name)
        sell_menu.show_wagon(
            index,
            resource_name,
            node.get_icon() if node != null else null,
            train_inventory.get_wagon_resource_qty(index),
            city_inventory.get_sell_price(resource_name))
    else:
        sell_menu.show_empty_wagon(index, wagon_type, wagon.get_icon())
    _refresh_sell_menu()

func _on_city_wagon_clicked(wagon_type: String) -> void:
    if buy_menu.visible and buy_menu.current_wagon_type == wagon_type:
        buy_menu.close() # tapping the open wagon again closes it
        return
    sell_menu.close() # only one menu at a time
    var wagon := trade_wagon_manager.get_wagon(wagon_type)
    buy_menu.show_wagon(
        wagon_type,
        wagon.get_icon() if wagon != null else null,
        city_inventory.get_wagon_available_qty(wagon_type),
        city_inventory.get_wagon_buy_price(wagon_type))
    _refresh_buy_menu()

func _on_city_unit_clicked(unit_type: String) -> void:
    if buy_menu.visible and buy_menu.current_unit_type == unit_type:
        buy_menu.close() # tapping the open soldier again closes it
        return
    sell_menu.close() # only one menu at a time
    var unit := trade_unit_manager.get_unit(unit_type)
    buy_menu.show_unit(
        unit_type,
        unit.get_icon() if unit != null else null,
        city_inventory.get_recruit_qty(unit_type),
        city_inventory.get_recruit_price(unit_type))
    _refresh_buy_menu()


func _on_buy_wagon_requested(wagon_type: String) -> void:
    var result := TradeService.buy_wagon(city_inventory, train_inventory, wagon_type)
    if result != TradeService.Result.OK:
        trade_failed.emit(TradeService.result_text(result))
    _print_inventories() # TODO: remove after checking

func _on_sell_wagon_requested(wagon_index: int) -> void:
    var result := TradeService.sell_wagon(city_inventory, train_inventory, wagon_index)
    if result != TradeService.Result.OK:
        trade_failed.emit(TradeService.result_text(result))

func _on_recruit_requested(unit_type: String) -> void:
    var result := TradeService.recruit(city_inventory, train_inventory, unit_type)
    if result != TradeService.Result.OK:
        trade_failed.emit(TradeService.result_text(result))


func _on_city_wagon_amount_changed(wagon_type: String, qty: int) -> void:
    if qty == 0:
        # The last one was bought: the wagon leaves the city
        if buy_menu.current_wagon_type == wagon_type:
            buy_menu.close()
        trade_wagon_manager.remove_wagon(wagon_type)
    else:
        if trade_wagon_manager.get_wagon(wagon_type) == null:
            trade_wagon_manager.spawn_wagon(wagon_type) # the city has this wagon again
        _refresh_buy_menu()

func _on_city_recruit_amount_changed(unit_type: String, qty: int) -> void:
    if qty == 0:
        # The last one was hired: the soldier leaves the city
        if buy_menu.current_unit_type == unit_type:
            buy_menu.close()
        trade_unit_manager.remove_unit(unit_type)
    else:
        trade_unit_manager.set_unit_qty(unit_type, qty)
        _refresh_buy_menu()


# The data already has the wagon, so the train only has to show it at the rear
func _on_wagon_added(wagon_index: int, _wagon_type: String) -> void:
    var wagons_data: Array = GameState.get_player_train().get("wagons", [])
    player_train.add_wagon(wagons_data[wagon_index])

func _on_wagon_removed(wagon_index: int) -> void:
    sell_menu.close() # the indices after this wagon moved, so an open menu would point at the wrong wagon
    player_train.remove_wagon(wagon_index)

# The barracks has one soldier more, and fewer places: the menu's button may have to be disabled
func _on_unit_added(_wagon_index: int, _unit_id: String) -> void:
    _refresh_buy_menu()

# Keeps the open menu in sync: stock and whether buying is possible right now
func _refresh_buy_menu() -> void:
    if buy_menu.current_unit_type != "":
        var unit_type := buy_menu.current_unit_type
        buy_menu.set_qty(city_inventory.get_recruit_qty(unit_type))
        buy_menu.set_can_buy(TradeService.can_recruit(city_inventory, train_inventory, unit_type))
        return
        
    if buy_menu.current_wagon_type != "":
        var wagon_type := buy_menu.current_wagon_type
        buy_menu.set_qty(city_inventory.get_wagon_available_qty(wagon_type))
        buy_menu.set_can_buy(TradeService.can_buy_wagon(city_inventory, wagon_type))
        return

    var resource_name := buy_menu.current_resource
    if resource_name == "":
        return
    buy_menu.set_qty(city_inventory.get_available_qty(resource_name))
    buy_menu.set_can_buy(TradeService.max_buyable(city_inventory, train_inventory, resource_name) > 0)

func _refresh_sell_menu() -> void:
    var index := sell_menu.current_wagon
    if index < 0:
        return
    var wagon_type := train_inventory.get_wagon_type(index)
    var can_sell_wagon := TradeService.can_sell_wagon(city_inventory, train_inventory, index)
    sell_menu.set_wagon_offer(city_inventory.get_wagon_sell_price(wagon_type) if can_sell_wagon else -1)

    var qty := train_inventory.get_wagon_resource_qty(index)
    if qty > 0:
        sell_menu.set_qty(qty)
        sell_menu.set_can_sell(TradeService.max_sellable_from_wagon(city_inventory, train_inventory, index) > 0)
    elif can_sell_wagon:
        # emptied: only the wagon itself can be sold now
        sell_menu.show_empty_wagon(index, wagon_type, player_train.wagons[index].get_icon())
    else:
        sell_menu.close()

func _trade(resource_name: String, qty: int, buying: bool) -> void:
    var result: TradeService.Result
    if buying:
        result = TradeService.buy(city_inventory, train_inventory, resource_name, qty)
    else:
        result = TradeService.sell(city_inventory, train_inventory, resource_name, qty)
    
    if result == TradeService.Result.OK:
        if not buying:
            QuestManager.notify_goods_delivered(city_name, resource_name, qty)
    else:
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

func _on_exit_button_pressed() -> void:
    if get_tree().current_scene == self:
        print("Running the trade scene on its own: there is no navigation scene to return to")
        return
    SceneService.leave_city()

#endregion


#region UI callbacks
func _on_right_button_pressed() -> void:
    horizontal_train_manager.player_train_gear_up()


func _on_left_button_pressed() -> void:
    horizontal_train_manager.player_train_gear_down()
#endregion

func _on_wagon_dropped(from_index: int, to_index: int) -> void:
    train_inventory.move_wagon(from_index, to_index) # the inventory announces it, and the view follows


func _on_wagon_moved(from_index: int, to_index: int) -> void:
    sell_menu.close() # indices changed, so an open menu would point at the wrong wagon
    player_train.move_wagon(from_index, to_index)
    

func _print_inventories() -> void:
    print("=== City inventory: %s ===" % city_name)
    print("  Type: %s" % city_inventory.place_type)
    print("  Resources:")
    for resource_name in city_inventory.get_resource_names():
        var info := city_inventory.get_resource_info(resource_name)
        print("  %s [%s]: qty %d / max %d, buy %d, sell %d" % [resource_name, info.mode, info.qty, info.max_capacity, info.buy_price, info.sell_price])
    
    print("  Recipes:")
    for recipe in city_inventory.get_recipes():
        print("  Recipe '%s': %s -> %s" % [recipe.name, recipe.inputs, recipe.outputs])

    print("  Wagons:")
    for wagon_type in city_inventory.get_wagon_types():
        print("    %s: qty %d, buy %d, sell %d" % [wagon_type, city_inventory.get_wagon_available_qty(wagon_type), city_inventory.get_wagon_buy_price(wagon_type), city_inventory.get_wagon_sell_price(wagon_type)])

    print("=== Train inventory (money: %d) ===" % GameState.get_money())
    for i in train_inventory.get_wagon_count():
        var wagon := train_inventory.get_wagon_info(i)
        var cargo: String = wagon.resource_name if wagon.resource_name != "" else "(empty)"
        print("  [%d] %s: %s %d / %d" % [i, wagon.wagon_type, cargo, wagon.qty, wagon.max_capacity])
