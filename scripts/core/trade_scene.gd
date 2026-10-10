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
    trade_resource_manager.resource_buy_requested.connect(_on_buy_requested)
    trade_resource_manager.resource_sell_requested.connect(_on_sell_requested)
    city_inventory.city_resource_amount_changed.connect(_on_city_resource_amount_changed)
    train_inventory.wagon_resource_amount_changed.connect(_on_wagon_resource_amount_changed)

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
    _load_train()
    _load_city_resources()
    _refresh_all_buttons()
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


func _trade(resource_name: String, qty: int, buying: bool) -> void:
    var result: TradeService.Result
    if buying:
        result = TradeService.buy(city_inventory, train_inventory, resource_name, qty)
    else:
        result = TradeService.sell(city_inventory, train_inventory, resource_name, qty)
    if result != TradeService.Result.OK:
        trade_failed.emit(TradeService.result_text(result))


# The numbers on screen come from the inventories' signals, never from the buttons themselves
func _on_city_resource_amount_changed(resource_name: String, qty: int) -> void:
    trade_resource_manager.set_resource_qty(resource_name, qty)
    _refresh_buttons(resource_name)


func _on_wagon_resource_amount_changed(wagon_index: int, resource_name: String, qty: int) -> void:
    var train := player_train
    if is_instance_valid(train) and wagon_index < train.wagons.size():
        train.wagons[wagon_index].set_cargo(resource_name, qty)
    _refresh_all_buttons() # selling depends on what the train carries


func _on_money_changed(_money: int) -> void:
    _refresh_all_buttons() # buying depends on the money


func _refresh_buttons(resource_name: String) -> void:
    var can_buy := TradeService.max_buyable(city_inventory, train_inventory, resource_name) > 0
    var can_sell := TradeService.max_sellable(city_inventory, train_inventory, resource_name) > 0
    trade_resource_manager.set_resource_can_buy(resource_name, can_buy)
    trade_resource_manager.set_resource_can_sell(resource_name, can_sell)


func _refresh_all_buttons() -> void:
    for resource_name in trade_resource_manager.trade_resources:
        _refresh_buttons(resource_name)
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

    print("=== Train inventory (money: %d) ===" % GameState.get_money())
    for i in train_inventory.get_wagon_count():
        var wagon := train_inventory.get_wagon_info(i)
        var cargo: String = wagon.resource_name if wagon.resource_name != "" else "(empty)"
        print("  [%d] %s: %s %d / %d" % [i, wagon.wagon_type, cargo, wagon.qty, wagon.max_capacity])
