extends Node2D
class_name TradeScene

signal trade_failed(message: String) # for the HUD
signal menu_requested

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
@onready var hud: TradeHUD = $TradeHUD
@onready var trade_ui: TradeUI = $TradeHUD/UI/TradeUI
@onready var exit_button: Button = $TradeHUD/UI/ExitButton

@onready var resource_slots: Node2D = $ResourceSlots
@onready var place: TradePlace = $Place
@onready var brake_marker: Marker2D = $TrainBrakeStart

const MUSIC_TRADE: AudioStream = preload("res://assets/audio/city1.wav")


# Only used when this scene is run on its own (F6), where SceneService is not calling initialize()
const DEBUG_CITY_NAME := "Paris"
# const DEBUG_CITY_NAME := "Foundry"
# const DEBUG_CITY_NAME := "Central Depot"
# const DEBUG_CITY_NAME := "Forest"
# const DEBUG_CITY_NAME := "Iron Mine"
# const DEBUG_CITY_NAME := "Coal Mine"
# const DEBUG_CITY_NAME := "Sawmill"
# const DEBUG_CITY_NAME := "Workshop"


const PRINT_INVENTORIES := false # debug: print both inventories when the scene opens
enum Phase {INTRO, TRADING, OUTRO}

static var _problems_reported := false

var _phase := Phase.TRADING
var city_name := ""

var _initialized := false


func _ready() -> void:
    # Inject before initialize()
    horizontal_train_manager.train_container = train_container
    trade_resource_manager.resource_container = trade_resource_container
    trade_wagon_manager.wagon_container = wagon_container
    trade_unit_manager.unit_container = unit_container
    
    _set_resource_slots()
    wagon_reorder_controller.setup(player_train)

    trade_ui.setup(city_inventory, train_inventory, player_train, trade_resource_manager, trade_wagon_manager, trade_unit_manager)
    
    
    # connect signals
    city_inventory.city_resource_amount_changed.connect(_on_city_resource_amount_changed)
    city_inventory.city_wagon_amount_changed.connect(_on_city_wagon_amount_changed)
    city_inventory.city_recruit_amount_changed.connect(_on_city_recruit_amount_changed)
    
    train_inventory.wagon_resource_amount_changed.connect(_on_wagon_resource_amount_changed)
    train_inventory.wagon_added.connect(_on_wagon_added)
    train_inventory.wagon_removed.connect(_on_wagon_removed)
    train_inventory.wagon_moved.connect(_on_wagon_moved)
    
    trade_ui.buy_requested.connect(_on_buy_requested)
    trade_ui.buy_wagon_requested.connect(_on_buy_wagon_requested)
    trade_ui.recruit_requested.connect(_on_recruit_requested)
    trade_ui.produce_requested.connect(_on_produce_requested)
    trade_ui.sell_from_wagon_requested.connect(_on_sell_from_wagon_requested)
    trade_ui.sell_wagon_requested.connect(_on_sell_wagon_requested)
    trade_ui.refused.connect(trade_failed.emit)
    
    trade_resource_manager.resource_clicked.connect(trade_ui.toggle_resource)
    trade_wagon_manager.wagon_clicked.connect(trade_ui.toggle_city_wagon)
    trade_unit_manager.unit_clicked.connect(trade_ui.toggle_city_unit)
    
    hud.quests_pressed.connect(QuestUI.toggle_panel)
    hud.menu_pressed.connect(GameMenu.open_menu)
    
    exit_button.pressed.connect(_on_exit_button_pressed)
    player_train.wagon_clicked.connect(_on_wagon_clicked)
    wagon_reorder_controller.wagon_dropped.connect(_on_wagon_dropped)
    place.clicked.connect(_on_place_clicked)
    
    AudioService.play_music(MUSIC_TRADE, 0.0)


    if OS.is_debug_build() and not _problems_reported:
        _problems_reported = true
        for problem in ResourceTypes.find_problems():
            push_warning("ResourceTypes: %s" % problem)
        for problem in IndustryTypes.find_problems():
            push_warning("IndustryTypes: %s" % problem)

    if get_tree().current_scene == self:
        initialize(DEBUG_CITY_NAME)


# Optional: the Marker2D children of a "ResourceSlots" node define where the resources go.
# Without that node, the manager's default positions are used.
func _set_resource_slots() -> void:
    # var markers := get_node_or_null("ResourceSlots")
    var markers := resource_slots
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

    _load_train()
    _load_city_resources()
    _load_city_wagons()
    _load_city_units()
    _load_place()
    _update_all_wagon_prices()
    if PRINT_INVENTORIES:
        _print_inventories()
    _start_intro()


# The train is already in the scene: the manager only builds its wagons
func _load_train() -> void:
    var train_data: Dictionary = GameState.get_player_train()
    if not horizontal_train_manager.setup_train(player_train, train_data, HorizontalTrainManager.Team.PLAYER):
        return
    train_inventory.load_from_game_state()


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

# Shows the building of this place. It is only clickable when there is something to open: for now,
# an industry.
func _load_place() -> void:
    place.setup(city_name, IndustryTypes.get_trade_image(city_inventory.kind), city_inventory.has_industry())

#endregion


#region trading
func _on_buy_requested(resource_name: String, qty: int) -> void:
    var result := TradeService.buy(city_inventory, train_inventory, resource_name, qty)
    if result != TradeService.Result.OK:
        trade_failed.emit(TradeService.result_text(result))


func _on_sell_from_wagon_requested(wagon_index: int, qty: int) -> void:
    var resource_name := train_inventory.get_wagon_current_resource(wagon_index)
    var result := TradeService.sell_from_wagon(city_inventory, train_inventory, wagon_index, qty)
    if result == TradeService.Result.OK:
        QuestManager.notify_goods_delivered(city_name, resource_name, qty)
    else:
        trade_failed.emit(TradeService.result_text(result))


func _on_wagon_clicked(wagon: GenericWagon) -> void:
    if city_inventory.allows_rearranging():
        wagon_reorder_controller.begin_drag(wagon) # in a depot a press starts a drag
    else:
        trade_ui.toggle_player_wagon(wagon)


func _on_place_clicked(_clicked_place: TradePlace) -> void:
    trade_ui.toggle_production()

func _on_buy_wagon_requested(wagon_type: String) -> void:
    var result := TradeService.buy_wagon(city_inventory, train_inventory, wagon_type)
    if result != TradeService.Result.OK:
        trade_failed.emit(TradeService.result_text(result))

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
        trade_wagon_manager.remove_wagon(wagon_type)
    elif trade_wagon_manager.get_wagon(wagon_type) == null:
        trade_wagon_manager.spawn_wagon(wagon_type)

func _on_city_recruit_amount_changed(unit_type: String, qty: int) -> void:
    if qty == 0:
        trade_unit_manager.remove_unit(unit_type)
    else:
        trade_unit_manager.set_unit_qty(unit_type, qty)


# The data already has the wagon, so the train only has to show it at the rear
func _on_wagon_added(wagon_index: int, _wagon_type: String) -> void:
    var wagons_data: Array = GameState.get_player_train().get("wagons", [])
    player_train.add_wagon(wagons_data[wagon_index])

func _on_wagon_removed(wagon_index: int) -> void:
    player_train.remove_wagon(wagon_index)


func _on_produce_requested(recipe_index: int, times: int) -> void:
    if not city_inventory.produce(recipe_index, times):
        trade_failed.emit("The industry can't produce that now.")

func _update_wagon_price(wagon_index: int) -> void:
    var wagon := player_train.wagons[wagon_index] as MerchandiseWagon
    if wagon == null:
        return
    var resource_name := train_inventory.get_wagon_current_resource(wagon_index)
    var price := -1 # -1: the city doesn't buy it
    if resource_name != "" and city_inventory.can_player_sell(resource_name):
        price = city_inventory.get_sell_price(resource_name)
    wagon.set_sell_price(price)

func _update_all_wagon_prices() -> void:
    for i in player_train.wagons.size():
        _update_wagon_price(i)

func _on_city_resource_amount_changed(resource_name: String, qty: int) -> void:
    trade_resource_manager.set_resource_qty(resource_name, qty)


func _on_wagon_resource_amount_changed(wagon_index: int, resource_name: String, qty: int) -> void:
    var train := player_train
    if is_instance_valid(train) and wagon_index < train.wagons.size():
        train.wagons[wagon_index].set_cargo(resource_name, qty)
        _update_wagon_price(wagon_index)


#endregion


#region UI callbacks
func _on_right_button_pressed() -> void:
    horizontal_train_manager.player_train_gear_up()


func _on_left_button_pressed() -> void:
    horizontal_train_manager.player_train_gear_down()


func _on_exit_button_pressed() -> void:
    _start_outro()
#endregion

#region intro and outro
# The train comes in from the left at full speed, in Drive, and brakes when it reaches the marker
func _start_intro() -> void:
    _phase = Phase.INTRO
    player_train.set_speed(player_train.max_speed) # speed > 0 puts it in Drive, at the top speed: it keeps it


func _process(_delta: float) -> void:
    match _phase:
        Phase.INTRO:
            if player_train.global_position.x >= brake_marker.global_position.x:
                player_train.gear_down() # D -> N: it brakes
                _phase = Phase.TRADING
        Phase.OUTRO:
            # The train node is its FRONT; the back end of the last wagon must be past the right edge
            var tail_x := player_train.to_global(player_train.last_wagon_position).x
            if tail_x > get_viewport_rect().size.x:
                _phase = Phase.TRADING # it only happens once
                _finish_leaving()


func _start_outro() -> void:
    _phase = Phase.OUTRO
    exit_button.disabled = true
    trade_ui.close_all()
    player_train.drive()


func _finish_leaving() -> void:
    if get_tree().current_scene == self:
        print("Running the trade scene on its own: there is no navigation scene to return to")
        return
    SceneService.leave_city()
#endregion

func _on_wagon_dropped(from_index: int, to_index: int) -> void:
    train_inventory.move_wagon(from_index, to_index) # the inventory announces it, and the view follows


func _on_wagon_moved(from_index: int, to_index: int) -> void:
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
