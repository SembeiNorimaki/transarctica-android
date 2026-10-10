extends Node2D
class_name TradeSceneOLD


# Services
@onready var horizontal_train_service: HorizontalTrainService = $Services/HorizontalTrainService
@onready var trade_resource_service: TradeResourceService = $Services/TradeResourceService

# containers
@onready var train_container: Node2D = $TrainContainer
@onready var trade_resource_container: Node2D = $ResourceContainer

const TRADE_RESOURCE_SCENE = preload("res://scenes/trade_resources/trade_resource.tscn")
const MUSIC_TRADE: AudioStream = preload("res://assets/audio/city1.wav")

var player_train: HorizontalTrain = null
var player_train_initial_position = Vector2(900, 500)
var enemy_train: HorizontalTrain = null
var enemy_train_initial_position = Vector2(900, 100)


func _ready() -> void:
    call_deferred("initialize", "Paris")
    AudioService.play_music(MUSIC_TRADE, 0.0)
    
#region initialize
func initialize(city_name: String) -> void:
    _load_city_resources_from_game_state(city_name)
    _load_train_from_game_state()


func _load_city_resources_from_game_state(city_name: String):
    # This function uses the structure returned by GameState.get_city_by_name
    # TradeResources: { resource_name: { Quantity: x, SellPrice: x, BuyPrice: x} }
    var city_data = GameState.get_city_by_name(city_name)
    if not city_data:
        print("Error, %s not found in GameState" % city_name)
        return
    
    # city_inventory.city_name = city_name
    for resource_name in city_data.TradeResources:
        print("Resource %s" % resource_name)
        var qty = city_data.TradeResources[resource_name].Quantity
        var sell_price = city_data.TradeResources[resource_name].SellPrice
        var buy_price = city_data.TradeResources[resource_name].BuyPrice
    #     var max_capacity = 999

        var trade_resource = trade_resource_service.spawn_resource(resource_name, qty)
        trade_resource_container.add_child(trade_resource)
    #     resource_manager.spawn_crate(resource_name, qty, "trade")
    #     city_inventory.initialize_resource(resource_name, qty, buy_price, sell_price, max_capacity)

func _load_train_from_game_state():
    print("Loading horizontal train from game state")
    var train_data = GameState.get_player_train()
    player_train = horizontal_train_service.spawn_train(player_train_initial_position, train_data)
    #player_train.set_speed(player_train.max_speed)
    train_container.add_child(player_train)
    

# func _initialize_trains():
#     player_train.initialize_train(train_wagons)
#     player_train.set_position(initial_player_train_position)

#     # enemy_train.initialize_train(enemy_train_wagons)
#     # enemy_train.set_position(initial_enemy_train_position)


# func _initialize_resources():
#     for resource_data in trade_resources:
#         var resource = TRADE_RESOURCE_SCENE.instantiate()
#         resource.set_resource_type(resource_data["resource_name"])
#         resource.set_qty(resource_data["qty"])
#         resource.set_price(resource_data["price"])
#         resource.position = resource_data["pos"]
#         resources_container.add_child(resource)
#endregion

func _unhandled_input(event):
    pass
    # if event.is_action_pressed("ui_left"):
    #     player_train.increase_velocity(-100)

    # elif event.is_action_pressed("ui_right"):
    #     player_train.increase_velocity(100)


func _on_right_button_pressed() -> void:
    player_train.gear_up()


func _on_left_button_pressed() -> void:
    player_train.gear_down()
