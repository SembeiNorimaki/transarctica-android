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
@onready var city_economy_manager: CityEconomyManager = $Managers/CityEconomyManager

# Services
@onready var camera_service: CameraService = $Services/CameraService

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

@onready var map_root: Node2D = $MapRoot
@onready var place: TradePlace = $Place
@onready var brake_marker: Marker2D = $TrainBrakeStart

# The map of each kind of place (the "Type" of the place in the data)
const TRADE_MAPS := {
    "City": preload("res://scenes/maps/trade_city.tscn"),
    "Industry": preload("res://scenes/maps/trade_industry.tscn"),
    "Depot": preload("res://scenes/maps/trade_depot.tscn"),
}

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

# Horizontal extent of the world the camera may show. Set them to the width of the background.
@export var world_left := 0.0
@export var world_right := 2400.0

var trade_map: TradeMap # the map of the place, in MapRoot (the scene has the city one to look at in the editor)
var _phase := Phase.TRADING
var city_name := ""
var _pressing := false
var _initialized := false


func _ready() -> void:
    var screen := get_viewport_rect().size
    camera_service.set_pos(screen * 0.5) # the view starts as it was without a camera
    # The camera's center may go from half a screen after the left edge to half a screen before the right
    var half_width := screen.x * 0.5
    camera_service.set_world_bounds(Rect2(
            world_left + half_width, screen.y * 0.5,
            maxf(world_right - world_left - screen.x, 0.0) + 1.0, 1.0))

    # Inject before initialize()
    horizontal_train_manager.train_container = train_container
    trade_resource_manager.resource_container = trade_resource_container
    trade_wagon_manager.wagon_container = wagon_container
    trade_unit_manager.unit_container = unit_container
    
    wagon_reorder_controller.setup(player_train)

    trade_ui.setup(city_inventory, train_inventory, player_train, trade_resource_manager, trade_wagon_manager, trade_unit_manager)
    
    
    # connect signals
    city_inventory.city_resource_amount_changed.connect(_on_city_resource_amount_changed)
    city_inventory.city_wagon_amount_changed.connect(_on_city_wagon_amount_changed)
    city_inventory.city_recruit_amount_changed.connect(_on_city_recruit_amount_changed)
    city_inventory.city_prices_changed.connect(_on_city_prices_changed)
    
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
    trade_resource_manager.sell_resource_clicked.connect(trade_ui.toggle_sell_resource)
    trade_wagon_manager.wagon_clicked.connect(trade_ui.toggle_city_wagon)
    trade_unit_manager.unit_clicked.connect(trade_ui.toggle_city_unit)
    
    hud.quests_pressed.connect(QuestUI.toggle_panel)
    hud.menu_pressed.connect(GameMenu.open_menu)
    hud.reverse_pressed.connect(_on_reverse_button_pressed)
    hud.gear_pressed.connect(_on_gear_button_pressed)
    
    exit_button.pressed.connect(_on_exit_button_pressed)
    player_train.wagon_clicked.connect(_on_wagon_clicked)
    wagon_reorder_controller.wagon_dropped.connect(_on_wagon_dropped)
    place.clicked.connect(_on_place_clicked)
    
    AudioService.play_music(MUSIC_TRADE, 0.0, false)


    if OS.is_debug_build() and not _problems_reported:
        _problems_reported = true
        for problem in ResourceTypes.find_problems():
            push_warning("ResourceTypes: %s" % problem)
        for problem in IndustryTypes.find_problems():
            push_warning("IndustryTypes: %s" % problem)

    if get_tree().current_scene == self:
        initialize(DEBUG_CITY_NAME)


# The map of the place: the one of its kind replaces the one in the scene. The placeholders of the
# map say where the resources go, and its Place marker where the building stands.
func _load_map(place_type: String) -> void:
    if not TRADE_MAPS.has(place_type):
        push_warning("TradeScene: no map for the place type '%s', using the city's" % place_type)
        place_type = "City"
    for child in map_root.get_children():
        map_root.remove_child(child)
        child.queue_free()
    trade_map = TRADE_MAPS[place_type].instantiate() as TradeMap
    map_root.add_child(trade_map)

    var buy_slots: Array[Vector2] = []
    for position in trade_map.get_buy_positions():
        buy_slots.append(trade_resource_container.to_local(position))
    var sell_slots: Array[Vector2] = []
    for position in trade_map.get_sell_positions():
        sell_slots.append(trade_resource_container.to_local(position))
    trade_resource_manager.set_slot_positions(buy_slots, sell_slots)
    place.position = trade_map.get_place_position()
    place.scale = trade_map.get_place_scale()


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
    city_economy_manager.setup(city_inventory) # the prices of today, before the resources show them
    _load_map(city_inventory.place_type)

    for resource_name in city_inventory.get_resource_names():
        # What the player can buy goes to the buy placeholders, what it can sell to the sell ones, and
        # what it can do both with to both. The manager logs an error if a node can't be created.
        var sides: Array[int] = [] # TradeResource.Side
        if city_inventory.can_player_buy(resource_name):
            sides.append(TradeResource.Side.BUY)
        if city_inventory.can_player_sell(resource_name):
            sides.append(TradeResource.Side.SELL)
        for side in sides:
            trade_resource_manager.spawn_resource(
                resource_name,
                city_inventory.get_available_qty(resource_name),
                city_inventory.get_buy_price(resource_name),
                city_inventory.get_sell_price(resource_name),
                side)

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


# The economy changed a price: the resource's label, and the sell price shown on the wagons
func _on_city_prices_changed(resource_name: String) -> void:
    trade_resource_manager.set_resource_prices(resource_name, city_inventory.get_buy_price(resource_name), city_inventory.get_sell_price(resource_name))
    _update_all_wagon_prices()


func _on_wagon_resource_amount_changed(wagon_index: int, resource_name: String, qty: int) -> void:
    var train := player_train
    if is_instance_valid(train) and wagon_index < train.wagons.size():
        train.wagons[wagon_index].set_cargo(resource_name, qty)
        _update_wagon_price(wagon_index)


#endregion


#region UI callbacks
# The bottom buttons work as in the navigation scene: the right one starts and stops the train, the
# left one reverses it. Not while the train comes in or leaves: it drives by itself then.
func _on_gear_button_pressed() -> void:
    if _phase == Phase.TRADING:
        horizontal_train_manager.player_train_gear_toggle()


func _on_reverse_button_pressed() -> void:
    if _phase == Phase.TRADING:
        horizontal_train_manager.player_train_reverse()


func _on_exit_button_pressed() -> void:
    _start_outro()
#endregion

#region intro and outro
# The train comes in from the left at full speed, in Drive, and brakes when it reaches the marker
func _start_intro() -> void:
    _phase = Phase.INTRO
    player_train.set_speed(player_train.max_speed) # speed > 0 puts it in Drive, at the top speed: it keeps it


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

func _process(_delta: float) -> void:
    match _phase:
        Phase.INTRO:
            if player_train.global_position.x >= brake_marker.global_position.x:
                player_train.gear_down() # D -> N: it brakes
                _phase = Phase.TRADING
        Phase.OUTRO:
            var tail_world := player_train.to_global(player_train.last_wagon_position)
            var tail_x := (get_canvas_transform() * tail_world).x
            if tail_x > get_viewport_rect().size.x:
                _phase = Phase.TRADING
                _finish_leaving()


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

func _unhandled_input(event: InputEvent) -> void:
    # Godot also sends a mouse event for every touch. Ignore those, the touch events are used instead.
    if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
        return

    if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
        _pressing = event.pressed
    elif _pressing and (event is InputEventScreenDrag or event is InputEventMouseMotion):
        if _phase != Phase.TRADING or wagon_reorder_controller.is_dragging():
            return # not while the train comes in or leaves, nor while a wagon is being dragged
        camera_service.pan(event.relative)
