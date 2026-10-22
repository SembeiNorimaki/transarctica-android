extends Node2D
class_name NavigationScene


# Managers
@onready var navigation_train_manager: NavigationTrainManager = $Managers/NavigationTrainManager
@onready var cities_manager: CitiesManager = $Managers/CitiesManager
@onready var fuel_manager: FuelManager = $Managers/FuelManager

# Services
@onready var navigation_rail_service: NavigationRailService = $Services/NavigationRailService
@onready var grid_service: GridService = $Services/GridService
@onready var camera_service: CameraService = $Services/CameraService
@onready var rail_service: RailService = $Services/RailService
@onready var exploration_service: ExplorationService = $Services/ExplorationService

# Overlays
@onready var rails_overlay: RailsOverlay = $Overlays/RailsOverlay

# Map 
@onready var map_root: Node2D = $MapRoot
@onready var fog_layer: TileMapLayer = $FogLayer

# Containers
@onready var train_container: Node2D = $TrainContainer
@onready var city_labels_container: Node2D = $CityLabelsContainer

# UI
@onready var fuel_bar: ProgressBar = $CanvasLayer/FuelBar
@onready var fuel_label: Label = $CanvasLayer/FuelLabel

# Constants
const MUSIC_TRAVEL: AudioStream = preload("res://assets/audio/Travelling.mp3")
# Train placeholder atlas: row = team, column = orientation (clockwise from E, tile-space names)
const TRAIN_ATLAS_TEAMS := [
    NavigationTrainManager.Team.PLAYER, # row 0
    NavigationTrainManager.Team.ENEMY, # row 1
]
const TRAIN_ATLAS_ORIENTATIONS: Array[String] = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]

var dragging := false
var last_pos := Vector2.ZERO

# TODO: This values should be loaded from somewhere else
var map_name: String = "world_1"

# This should be read from navigationtrainmanager.playerTrain
var initial_player_train_pos = Vector2i(31, 9)


#region Lifecycle & Setup
func _ready() -> void:
    SceneService.register_navigation_scene(self)

    _inject_services()
    _wire_signals()
    _load_map(map_name)


    camera_service.center_at_tile(initial_player_train_pos)
    camera_service.set_zoom(1.0)

    AudioService.play_music(MUSIC_TRAVEL, 0.0)


func suspend() -> void:
    process_mode = Node.PROCESS_MODE_DISABLED # stops _process, _input and all children
    hide()
    camera_service.cam.enabled = false
    # if the HUD buttons live in a CanvasLayer, hide that layer here too

func resume() -> void:
    process_mode = Node.PROCESS_MODE_INHERIT
    show()
    camera_service.cam.enabled = true
    navigation_train_manager.resume() # only if you adopted the _transitioning flag
    navigation_train_manager.recenter_player_train()
    AudioService.play_music(MUSIC_TRAVEL, 0.0)

func _inject_services() -> void:
    navigation_train_manager.camera_service = camera_service
    navigation_train_manager.cities_manager = cities_manager
    navigation_train_manager.grid_service = grid_service
    navigation_train_manager.rail_service = rail_service
    navigation_train_manager.train_container = train_container
    navigation_train_manager.exploration_service = exploration_service
    navigation_train_manager.fuel_manager = fuel_manager
    
    cities_manager.rail_service = rail_service
    cities_manager.city_labels_container = city_labels_container
    cities_manager.grid_service = grid_service
    fuel_manager.grid_service = grid_service
    
    camera_service.grid_service = grid_service
    exploration_service.fog_layer = fog_layer
    exploration_service.grid_service = grid_service
    rail_service.grid_service = grid_service

    rails_overlay.grid_service = grid_service
    rails_overlay.rail_service = rail_service

    
func _wire_signals() -> void:
    navigation_train_manager.train_reached_city.connect(_on_train_reached_city)
    navigation_train_manager.trains_collided.connect(_on_trains_collided)
    # navigation_train_manager.player_tile_changed.connect(_on_player_tile_changed)
    rail_service.rail_changed.connect(_on_rail_changed)
    fuel_manager.fuel_changed.connect(_on_fuel_changed)
    
    _on_fuel_changed(fuel_manager.get_fuel(), fuel_manager.get_max_fuel()) # the starting value
    
#endregion

#region Map Loading
# TODO: children (trains, cities, rails, labels) spawned from the old map are not cleaned up when you reload a map, only the map node is removed. Containers train_container and city_labels_container, plus rail and city data in services, would keep stale entries.
func _load_map(map_name: String) -> void:
    var map_path := "res://scenes/maps/%s.tscn" % map_name
    if not ResourceLoader.exists(map_path):
        push_error("Map not found for map: %s at path: %s" % [map_name, map_path])
        return

    # remove existing map
    if map_root.get_child_count() > 0:
        var existing_map: Node2D = map_root.get_child(0)
        map_root.remove_child(existing_map)
        existing_map.queue_free()

    # load new map
    var new_map: Node2D = load(map_path).instantiate()
    map_root.add_child(new_map)
    map_root.move_child(new_map, 0)

    # Set tilesize to grid service and tile occupancy service
    var terrain: TileMapLayer = new_map.get_node("Terrain")
    grid_service.set_tile_size(terrain.tile_set.tile_size)
    grid_service.set_map_rect(terrain.get_used_rect()) # instead of map_size = ...size
    camera_service.set_world_bounds(grid_service.get_world_bounds())

    rail_service.rails_tilemap = new_map.get_node("Rails")
    navigation_train_manager.clear_trains()
    rail_service.clear()

    exploration_service.setup(map_name, terrain.get_used_cells()) # before _spawn_trains_from_map

    
    _build_rails_from_map(new_map.get_node("Rails"))
    #_build_bridges_from_map(new_map.get_node("Bridges"))
    _spawn_cities_from_map(new_map.get_node("CitiesIds"))
    
    _spawn_trains_from_map(new_map.get_node("Trains"))
    #_spawn_wagons()
    # _reveal_around_player()
    
    # exploration_service.update_position(grid_service.tile_to_world(Vector2(initial_player_train_pos))) # TEMP

func _spawn_cities_from_map(cities_ids_tilemap: TileMapLayer) -> void:
    for tile in cities_ids_tilemap.get_used_cells():
        #print("Spawn city on tile %s" % tile)
        var atlas_coords = cities_ids_tilemap.get_cell_atlas_coords(tile)
        var city_id = atlas_coords.y * 10 + atlas_coords.x
        cities_manager.spawn_city(city_id, tile)


func _spawn_trains_from_map(trains_tilemap: TileMapLayer) -> void:
    var player_spawned := false
    for tile in trains_tilemap.get_used_cells():
        var atlas := trains_tilemap.get_cell_atlas_coords(tile)
        trains_tilemap.erase_cell(tile) # remove the placeholder whatever happens below

        var valid_col := atlas.x >= 0 and atlas.x < TRAIN_ATLAS_ORIENTATIONS.size()
        var valid_row := atlas.y >= 0 and atlas.y < TRAIN_ATLAS_TEAMS.size()
        if not (valid_col and valid_row):
            push_warning("Train placeholder at %s has unknown atlas coords %s" % [tile, atlas])
            continue

        var team: NavigationTrainManager.Team = TRAIN_ATLAS_TEAMS[atlas.y]
        if team == NavigationTrainManager.Team.PLAYER:
            if player_spawned:
                push_warning("Second player train at %s ignored (only one is supported)" % tile)
                continue
            player_spawned = true

        if not rail_service.has_rail(tile):
            push_warning("Train placeholder at %s has no rail under it" % tile)

        print("Spawning %s train at tile %s" % [team, tile])
        navigation_train_manager.spawn_train(tile, TRAIN_ATLAS_ORIENTATIONS[atlas.x], team)

func _build_rails_from_map(rails_tilemap: TileMapLayer) -> void:
    for tile in rails_tilemap.get_used_cells():
        var atlas_coords = rails_tilemap.get_cell_atlas_coords(tile)
        # var source_id = rails_tilemap.get_cell_source_id(tile)
        
        rail_service.spawn_rail(tile, atlas_coords)

# func _unhandled_inputOLD(event) -> void:
#     # --- Touch input (Android) ---
#     if event is InputEventScreenTouch:
#         if event.pressed:
#             dragging = true
#             last_pos = event.position
#         else:
#             dragging = false

#     if dragging and event is InputEventScreenDrag:
#         var delta = event.position - last_pos
#         camera_service.cam.global_position -= delta / camera_service.cam.zoom
#         last_pos = event.position

#     # --- Mouse input (Desktop) ---
#     if event is InputEventMouseButton:
#         if event.button_index == MOUSE_BUTTON_LEFT:
#             if event.pressed:
#                 dragging = true
#                 last_pos = event.position
#             else:
#                 dragging = false

#     if dragging and event is InputEventMouseMotion:
#         var delta = event.position - last_pos
#         camera_service.cam.global_position -= delta / camera_service.cam.zoom
#         last_pos = event.position

func end_combat(enemy: NavigationTrain) -> void:
    # TODO: depends on the combat result. For now the enemy is removed. Otherwise it would collide
    # again as soon as the scene is enabled, because its area is still overlapping the player's.
    if is_instance_valid(enemy):
        navigation_train_manager.remove_train(enemy)
    resume()
    
func _unhandled_input(event: InputEvent) -> void:
    # Godot also sends a mouse event for every touch. Ignore those, the touch events are used instead.
    if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
        return
        
    if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
        dragging = event.pressed
        #last_pos = event.position
    elif dragging and (event is InputEventScreenDrag or event is InputEventMouseMotion):
        camera_service.pan(event.relative)
        #last_pos = event.position

func _on_train_reached_city(city_name: String) -> void:
    print("Nav Scene: Train reached city %s" % city_name)
    # Fade out travel music before entering the city scene.
    AudioService.stop_music(1.5)
    QuestManager.notify_city_reached(city_name)
    SceneService.enter_city(city_name)

func _on_rail_changed(tile: Vector2i) -> void:
    map_root.get_child(0).get_node("Rails").set_cell(tile, 0, RailService.RAILNAME_TO_ATLAS[rail_service.rails[tile]])

func _on_trains_collided(_player: NavigationTrain, enemy: NavigationTrain) -> void:
    AudioService.stop_music(1.5)
    SceneService.enter_combat(enemy)

func _on_button_left_pressed() -> void:
    navigation_train_manager.player_train_reverse()


func _on_button_right_pressed() -> void:
    navigation_train_manager.player_train_gear_toggle()


func _on_fuel_changed(current: int, maximum: int) -> void:
    fuel_bar.max_value = maxf(maximum, 1.0)
    fuel_bar.value = current
    fuel_label.text = "NO COAL" if current <= 0 else "%d / %d" % [current, maximum]
    fuel_bar.modulate = Color.RED if current * 5 < maximum else Color.WHITE # below 20%
    
# func _on_player_tile_changed(tile: Vector2i) -> void:
#     exploration_service.update_vision(tile)
#     navigation_train_manager.update_enemy_visibility()


# The train appears without a tile change, so reveal the start by hand
# func _reveal_around_player() -> void:
#     var train := navigation_train_manager.player_train
#     if is_instance_valid(train) and not train.wagons.is_empty():
#         _on_player_tile_changed(train.wagons[0].current_tile)