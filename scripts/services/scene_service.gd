extends Node

@onready var navigation_scene = get_tree().get_root().get_node("MainScene/NavigationScene")

var city_scene

func enter_city(city_name: String):
    # Disable navigation scene
    navigation_scene.visible = false
    navigation_scene.camera_service.cam.enabled = false
    navigation_scene.set_process(false)
    navigation_scene.set_physics_process(false)

    # Load and instantiate the city scene
    var CITY_SCENE_CLASS = load("res://scenes/core/trade_scene.tscn")
    city_scene = CITY_SCENE_CLASS.instantiate()

    # Pass city data to the cisty scene
    city_scene.call_deferred("initialize", city_name)

    # Add it to scene tree
    get_parent().add_child(city_scene)

func leave_city():
    if city_scene:
        city_scene.queue_free()
        city_scene = null
    
    # Re-enable navigation scene
    navigation_scene.visible = true
    navigation_scene.camera_service.cam.enabled = true
    navigation_scene.set_process(true)
    navigation_scene.set_physics_process(true)

    navigation_scene.recenter_player_train()
