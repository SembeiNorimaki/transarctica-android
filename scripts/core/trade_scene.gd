extends Node2D
class_name TradeScene

# Services
@onready var horizontal_train_manager: HorizontalTrainManager = $Managers/HorizontalTrainManager
@onready var trade_resource_service: TradeResourceService = $Services/TradeResourceService

# Containers
@onready var train_container: Node2D = $TrainContainer
@onready var trade_resource_container: Node2D = $ResourceContainer

const MUSIC_TRADE: AudioStream = preload("res://assets/audio/city1.wav")

# TODO: replace with Marker2D nodes in the scene so they follow the layout/resolution
const PLAYER_TRAIN_POSITION := Vector2(900, 500)
const ENEMY_TRAIN_POSITION := Vector2(900, 100) # TODO: enemy train

# Only used when this scene is run on its own (F6), where SceneService is not calling initialize()
const DEBUG_CITY_NAME := "Paris"

var city_name := ""
var player_train: HorizontalTrain:
    get:
        return horizontal_train_manager.player_train

var enemy_train: HorizontalTrain = null # TODO
var city_inventory: CityInventory

var _initialized := false


func _ready() -> void:
    horizontal_train_manager.train_container = train_container
    AudioService.play_music(MUSIC_TRADE, 0.0)
    if get_tree().current_scene == self:
        initialize(DEBUG_CITY_NAME)


#region initialize
# Called by SceneService right after the scene is added to the tree (so the @onready vars exist).
# Must be called only once.
func initialize(city_name_: String) -> void:
    if _initialized:
        push_error("TradeScene: already initialized")
        return
    _initialized = true
    city_name = city_name_

    _load_city_resources()
    _load_train()


func _load_city_resources() -> void:
    city_inventory = CityInventory.new(city_name)
    if not city_inventory.load_from_game_state():
        return
    for resource_name in city_inventory.get_resource_names():
        var qty := city_inventory.get_available_qty(resource_name)
        trade_resource_container.add_child(trade_resource_service.spawn_resource(resource_name, qty))

    # var city_data: Dictionary = GameState.get_city_by_name(city_name)
    # if city_data.is_empty():
    #     push_error("TradeScene: city '%s' not found in GameState" % city_name)
    #     return

    # var resources: Dictionary = city_data.get("TradeResources", {})
    # for resource_name in resources:
    #     var data: Dictionary = resources[resource_name]
    #     var qty := int(data.get("Quantity", 0)) # JSON numbers are floats
    #     # TODO: pass data.BuyPrice and data.SellPrice once spawn_resource accepts them
    #     var trade_resource = trade_resource_service.spawn_resource(resource_name, qty)
    #     trade_resource_container.add_child(trade_resource)


func _load_train() -> void:
    var train_data: Dictionary = GameState.get_player_train()
    var train := horizontal_train_manager.spawn_train(PLAYER_TRAIN_POSITION, train_data, HorizontalTrainManager.Team.PLAYER)
    if train == null:
        return
    train.set_bounds(0.0, get_viewport_rect().size.x)
#endregion


#region UI callbacks
func _on_right_button_pressed() -> void:
    horizontal_train_manager.player_train_gear_up()

func _on_left_button_pressed() -> void:
    horizontal_train_manager.player_train_gear_down()
#endregion
