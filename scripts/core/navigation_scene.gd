extends Node2D
class_name NavigationScene


# Managers
@onready var navigation_train_manager: NavigationTrainManager = $Managers/NavigationTrainManager
@onready var cities_manager: CitiesManager = $Managers/CitiesManager
@onready var fuel_manager: FuelManager = $Managers/FuelManager

# Services
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
const TAP_MAX_DRAG := 10.0 # screen pixels; moving more than this is a camera drag, not a tap

var dragging := false
var _drag_distance := 0.0
var last_pos := Vector2.ZERO
var events_manager: EventsManager
var event_popup: EventPopup
var _open_event := {} # the event the pop-up is showing

# TODO: This values should be loaded from somewhere else
const DEFAULT_MAP_NAME: String = "world_1"

# This should be read from navigationtrainmanager.playerTrain
var initial_player_train_pos = Vector2i(31, 9)


#region Lifecycle & Setup
func _ready() -> void:
    _create_event_nodes()
    SceneService.register_navigation_scene(self)
    _inject_services()
    _wire_signals()
    _load_map(DEFAULT_MAP_NAME)


    var player_train := navigation_train_manager.player_train
    if is_instance_valid(player_train):
        camera_service.center_at_tile(player_train.wagons[0].current_tile)
    else:
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
    navigation_train_manager.rebuild_player_train() # the wagons may have changed in the city or in combat
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
    events_manager.rail_service = rail_service
    
    camera_service.grid_service = grid_service
    exploration_service.fog_layer = fog_layer
    exploration_service.grid_service = grid_service
    rail_service.grid_service = grid_service

    rails_overlay.grid_service = grid_service
    rails_overlay.rail_service = rail_service

    
func _wire_signals() -> void:
    navigation_train_manager.train_reached_city.connect(_on_train_reached_city)
    navigation_train_manager.trains_collided.connect(_on_trains_collided)
    navigation_train_manager.player_tile_changed.connect(events_manager.on_player_tile_changed)
    # navigation_train_manager.player_tile_changed.connect(_on_player_tile_changed)

    rail_service.rail_changed.connect(_on_rail_changed)
    fuel_manager.fuel_changed.connect(_on_fuel_changed)
    events_manager.event_triggered.connect(_on_event_triggered)
    event_popup.accepted.connect(_on_event_accepted)
    event_popup.declined.connect(_on_event_declined)
    
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
    events_manager.setup(map_name, new_map)
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


# The Trains tilemap holds placeholders: they say where a NEW game starts the trains, and which
# way they face. A loaded game takes the player train's position from GameState instead, so its
# placeholder is only erased. The wagons and the stats of the player train always come from GameState.
func _spawn_trains_from_map(trains_tilemap: TileMapLayer) -> void:
    var player_spawned := false
    var enemy_spots: Array[Dictionary] = [] # where new enemy trains can start: {tile, ori}
    for tile in trains_tilemap.get_used_cells():
        var atlas := trains_tilemap.get_cell_atlas_coords(tile)
        trains_tilemap.erase_cell(tile) # remove the placeholder whatever happens below

        var valid_col := atlas.x >= 0 and atlas.x < TRAIN_ATLAS_ORIENTATIONS.size()
        var valid_row := atlas.y >= 0 and atlas.y < TRAIN_ATLAS_TEAMS.size()
        if not (valid_col and valid_row):
            push_warning("Train placeholder at %s has unknown atlas coords %s" % [tile, atlas])
            continue

        var team: NavigationTrainManager.Team = TRAIN_ATLAS_TEAMS[atlas.y]
        var orientation := TRAIN_ATLAS_ORIENTATIONS[atlas.x]
        if team == NavigationTrainManager.Team.PLAYER:
            if player_spawned:
                push_warning("Second player train at %s ignored (only one is supported)" % tile)
                continue
            player_spawned = true
            if not GameState.has_player_position():
                GameState.set_player_position(tile, orientation) # a new game starts where the map says
        else:
            enemy_spots.append({"tile": tile, "ori": orientation})

    # get_used_cells has no fixed order, so sort the spots: by tile y, then by tile x
    enemy_spots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        if a["tile"].y != b["tile"].y:
            return a["tile"].y < b["tile"].y
        return a["tile"].x < b["tile"].x)

    _spawn_player_train()
    _spawn_enemy_trains(enemy_spots)


func _spawn_player_train() -> void:
    if not GameState.has_player_position():
        push_error("NavigationScene: there is no player train placeholder on the Trains tilemap, and the game has no saved position")
        return
    var saved := GameState.get_player_position()
    if not rail_service.has_rail(saved["tile"]):
        push_warning("The player train position %s has no rail under it" % saved["tile"])
    print("Spawning player train at tile %s" % saved["tile"])
    navigation_train_manager.spawn_train(saved["tile"], saved["ori"], NavigationTrainManager.Team.PLAYER,
            GameState.get_player_train(), saved["reversed"])

# The enemy trains come from GameState. One that already has a position (a loaded game) starts
# there. The others (a new game) take the next free spot of the map, in the order of the data.
func _spawn_enemy_trains(spots: Array[Dictionary]) -> void:
    var next_spot := 0
    for train_id in GameState.get_enemies():
        var tile: Vector2i
        var ori: String
        var reversed := false
        if GameState.has_enemy_position(train_id):
            var saved := GameState.get_enemy_position(train_id)
            tile = saved["tile"]
            ori = saved["ori"]
            reversed = saved["reversed"]
        else:
            if next_spot >= spots.size():
                push_warning("Enemy train '%s' has no placeholder left on the Trains tilemap, so it is not spawned" % train_id)
                continue
            tile = spots[next_spot]["tile"]
            ori = spots[next_spot]["ori"]
            next_spot += 1
            GameState.set_enemy_position(train_id, tile, ori)

        if not rail_service.has_rail(tile):
            push_warning("Enemy train '%s' at %s has no rail under it" % [train_id, tile])
        print("Spawning enemy train %s at tile %s" % [train_id, tile])
        navigation_train_manager.spawn_train(tile, ori, NavigationTrainManager.Team.ENEMY,
                GameState.get_enemy_train(train_id), reversed)

func _build_rails_from_map(rails_tilemap: TileMapLayer) -> void:
    for tile in rails_tilemap.get_used_cells():
        var atlas_coords = rails_tilemap.get_cell_atlas_coords(tile)
        # var source_id = rails_tilemap.get_cell_source_id(tile)
        
        rail_service.spawn_rail(tile, atlas_coords)

#endregion

# Both are made in code, so the scene file doesn't need new nodes
func _create_event_nodes() -> void:
    events_manager = EventsManager.new()
    events_manager.name = "EventsManager"
    $Managers.add_child(events_manager)
    event_popup = EventPopup.new()
    event_popup.name = "EventPopup"
    $CanvasLayer.add_child(event_popup)

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
        if event.pressed:
            dragging = true
            _drag_distance = 0.0
        else:
            if dragging and _drag_distance < TAP_MAX_DRAG:
                _on_map_tapped(event.position)
            dragging = false

    elif dragging and (event is InputEventScreenDrag or event is InputEventMouseMotion):
        _drag_distance += event.relative.length()
        camera_service.pan(event.relative)

func _on_train_reached_city(city_name: String) -> void:
    print("Nav Scene: Train reached city %s" % city_name)
    # Fade out travel music before entering the city scene.
    AudioService.stop_music(1.5)
    QuestManager.notify_city_reached(city_name)
    SceneService.enter_city(city_name)

func _on_rail_changed(tile: Vector2i) -> void:
    var tilemap := rail_service.rails_tilemap
    var rail_name: String = rail_service.rails[tile]
    tilemap.set_cell(tile, tilemap.get_cell_source_id(tile), RailService.RAILNAME_TO_ATLAS[rail_name])
    
func _on_trains_collided(_player: NavigationTrain, enemy: NavigationTrain) -> void:
    AudioService.stop_music(1.5)
    SceneService.enter_combat(enemy)

func _on_button_left_pressed() -> void:
    navigation_train_manager.player_train_reverse()


func _on_button_right_pressed() -> void:
    print("Button right pressed")
    navigation_train_manager.player_train_gear_toggle()

func _on_map_tapped(screen_pos: Vector2) -> void:
    var world_pos := get_canvas_transform().affine_inverse() * screen_pos # undoes the camera's position and zoom
    var tile := grid_service.world_to_tile(world_pos)
    print("tapped tile ", tile) # TEMPORARY
    if rail_service.has_junction(tile):
        rail_service.change_junction(tile)


func _on_fuel_changed(current: int, maximum: int) -> void:
    fuel_bar.max_value = maxf(maximum, 1.0)
    fuel_bar.value = current
    fuel_label.text = "NO COAL" if current <= 0 else "%d / %d" % [current, maximum]
    fuel_bar.modulate = Color.RED if current * 5 < maximum else Color.WHITE # below 20%

func _on_event_triggered(event: Dictionary) -> void:
    _open_event = event
    navigation_train_manager.player_train.immediate_stop()
    navigation_train_manager.pause() # the enemies wait too, so nobody attacks behind the pop-up
    event_popup.show_event(
        event["name"],
        event["text"],
        event["accept_text"],
        GameState.get_money() >= event["cost"],
        "Not now" if event["optional"] else "")


func _on_event_accepted() -> void:
    var problem := events_manager.accept(_open_event["tile"])
    if not problem.is_empty():
        push_warning("Event: %s" % problem)
    _close_event()


func _on_event_declined() -> void:
    _close_event()


func _close_event() -> void:
    _open_event = {}
    navigation_train_manager.resume()

# func _on_player_tile_changed(tile: Vector2i) -> void:
#     exploration_service.update_vision(tile)
#     navigation_train_manager.update_enemy_visibility()


# The train appears without a tile change, so reveal the start by hand
# func _reveal_around_player() -> void:
#     var train := navigation_train_manager.player_train
#     if is_instance_valid(train) and not train.wagons.is_empty():
#         _on_player_tile_changed(train.wagons[0].current_tile)
