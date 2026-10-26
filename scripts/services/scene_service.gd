extends Node
# Autoload. Swaps between the navigation scene and the city (trade) scene.

const TRADE_SCENE: PackedScene = preload("res://scenes/core/trade_scene.tscn")
const COMBAT_SCENE: PackedScene = preload("res://scenes/core/combat_scene.tscn") # adjust the path


# Registered by NavigationScene in its _ready().
# (An autoload's _ready runs before the main scene exists, so it can't look the scene up itself.)
var navigation_scene: NavigationScene

# If trade_scene.gd has a class_name (e.g. TradeScene), use it as the type here.
var city_scene: Node
var combat_scene: Node
var _combat_enemy: NavigationTrain


func register_navigation_scene(scene: NavigationScene) -> void:
    navigation_scene = scene


func is_in_city() -> bool:
    return city_scene != null


func enter_city(city_name: String) -> void:
    if city_scene != null or combat_scene != null:
        return # already in a city (e.g. two entry events in the same frame)
    if not is_instance_valid(navigation_scene):
        push_error("SceneService: navigation scene not registered")
        return

    navigation_scene.suspend()

    city_scene = TRADE_SCENE.instantiate()
    get_tree().root.add_child(city_scene)
    # After add_child (so its @onready vars exist) and synchronous, so there is no frame
    # where the city scene is in the tree but not initialized.
    city_scene.initialize(city_name)


func leave_city() -> void:
    if city_scene == null:
        return
    city_scene.queue_free()
    city_scene = null

    if is_instance_valid(navigation_scene):
        navigation_scene.resume()
    QuestManager.notify_city_left()

func enter_combat(enemy_train: NavigationTrain) -> void:
    if city_scene != null or combat_scene != null:
        return
    if not is_instance_valid(navigation_scene):
        push_error("SceneService: navigation scene not registered")
        return
    navigation_scene.suspend()
    _combat_enemy = enemy_train
    combat_scene = COMBAT_SCENE.instantiate()
    get_tree().root.add_child(combat_scene)
    # TODO: combat_scene.initialize(...) with the two trains' data, once the scene exists

func leave_combat() -> void:
    if combat_scene == null:
        return
    combat_scene.queue_free()
    combat_scene = null
    if is_instance_valid(navigation_scene):
        navigation_scene.end_combat(_combat_enemy)
    _combat_enemy = null

# Forgets the running game: for when it is thrown away (loading another one, back to the menu)
func reset() -> void:
    for scene in [city_scene, combat_scene]:
        if is_instance_valid(scene):
            scene.queue_free()
    city_scene = null
    combat_scene = null
    _combat_enemy = null
    navigation_scene = null
