extends Node2D
class_name NavigationScene

@onready var camera_2d: Camera2D = $Camera2D
@onready var navigation_rail_service: NavigationRailService = $Services/NavigationRailService

const MUSIC_TRAVEL: AudioStream = preload("res://assets/audio/Travelling.mp3")

var dragging := false
var last_pos := Vector2.ZERO


func _ready() -> void:
    AudioService.play_music(MUSIC_TRAVEL, 0.0)

func _inject_services() -> void:
    pass

func _wire_signals() -> void:
    pass

func _spawn_cities_from_map(cities_ids_tilemap: TileMapLayer) -> void:
    for tile in cities_ids_tilemap.get_used_cells():
        var atlas_coords = cities_ids_tilemap.get_cell_atlas_coords(tile)
        var city_id = atlas_coords.y * 10 + atlas_coords.x
        #cities_manager.spawn_city(city_id, tile)

func _spawn_trains_from_map(trains_tilemap: TileMapLayer) -> void:
    for tile in trains_tilemap.get_used_cells():
        var atlas_coords = trains_tilemap.get_cell_atlas_coords(tile)
        var source_id = trains_tilemap.get_cell_source_id(tile)
        var orientation = "E"
        var team = "Player"
        #train_manager.spawn_train(tile, orientation, team)

        # Remove the placeholder tile
        trains_tilemap.erase_cell(tile)

func _build_rails_from_map(rails_tilemap: TileMapLayer) -> void:
    for tile in rails_tilemap.get_used_cells():
        var atlas_coords = rails_tilemap.get_cell_atlas_coords(tile)
        var source_id = rails_tilemap.get_cell_source_id(tile)
        
        #rail_service.spawn_rail(tile, atlas_coords)

func _input(event):
    # --- Touch input (Android) ---
    if event is InputEventScreenTouch:
        if event.pressed:
            dragging = true
            last_pos = event.position
        else:
            dragging = false

    if dragging and event is InputEventScreenDrag:
        var delta = event.position - last_pos
        camera_2d.global_position -= delta
        last_pos = event.position

    # --- Mouse input (Desktop) ---
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                dragging = true
                last_pos = event.position
            else:
                dragging = false

    if dragging and event is InputEventMouseMotion:
        var delta = event.position - last_pos
        camera_2d.global_position -= delta
        last_pos = event.position


func _on_train_reached_city(city_name: String):
    # print("Nav Scene: Train reached city %s" % city_name)
    # Fade out travel music before entering the city scene.
    AudioService.stop_music(1.5)
    #QuestManager.notify_city_reached(city_name)
    SceneService.enter_city(city_name)

func _on_button_pressed() -> void:
    navigation_train_manager.gear_toggle()


func _on_button_2_pressed() -> void:
    navigation_train_manager.reverse_player_train()
