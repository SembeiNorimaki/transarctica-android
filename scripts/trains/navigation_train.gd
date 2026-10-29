extends Node2D
class_name NavigationTrain

enum Gear {NEUTRAL, DRIVE}

signal train_tile_changed(navigation_train: NavigationTrain, old_tile: Vector2i, new_tile: Vector2i)
signal gear_changed(gear: Gear)
signal train_collided(navigation_train: NavigationTrain, other_wagon: NavigationWagon)


const LOCOMOTIVE_SCENE: PackedScene = preload("res://scenes/wagons/navigation_locomotive.tscn")
# Used when the train data has no stats (the enemy trains, for now)
const DEFAULT_MAX_SPEED := 300.0
const DEFAULT_ACCELERATION := 50.0
const DEFAULT_DECELERATION := 200.0

const PLAYER_SPRITE_FRAMES: SpriteFrames = preload("res://assets/tilesets/navigation_locomotive_spriteframes.tres")
const ENEMY_SPRITE_FRAMES: SpriteFrames = preload("res://assets/tilesets/navigation_locomotive_enemy_spriteframes.tres")

# false: the map shows only the locomotive, as a marker of where the train is.
# true: it also shows the other wagons, following the rail behind it.
const SHOW_WAGONS := false

# Injected (train_manager removed: it was never used here)
var grid_service: GridService
var rail_service: RailService

var id := ""
var team: NavigationTrainManager.Team
var gear := Gear.NEUTRAL
var move_speed := 0.0
var max_speed := DEFAULT_MAX_SPEED # pixels per second
var acceleration := DEFAULT_ACCELERATION
var deceleration := DEFAULT_DECELERATION
var wagons: Array[NavigationWagon] = [] # wagons[0] is the locomotive, in the order of the train data
var reversed := false # the train goes backwards: the locomotive is at the REAR, pushing

@onready var wagon_container: Node2D = $WagonContainer


#region initialization
# `train_data` has the structure of GameState.get_player_train(): the stats (max_speed, acceleration,
# deceleration) and a "wagons" list with one entry per wagon, the locomotive first. Without it the
# train is a lone locomotive with the default stats.
# `tile_pos` and `ori` are the locomotive's. The other wagons are placed along the rail behind it,
# or in front of it if `is_reversed`.
func initialize(id_: String, team_: NavigationTrainManager.Team, tile_pos: Vector2i, ori: String,
        train_data := {}, is_reversed := false) -> void:
    assert(id.is_empty(), "NavigationTrain: already initialized")
    id = id_
    team = team_
    reversed = is_reversed

    max_speed = float(train_data.get("max_speed", DEFAULT_MAX_SPEED))
    acceleration = float(train_data.get("acceleration", DEFAULT_ACCELERATION))
    deceleration = float(train_data.get("deceleration", DEFAULT_DECELERATION))

    var wagon_types: Array[String] = []
    for wagon_data: Dictionary in train_data.get("wagons", []):
        wagon_types.append(str(wagon_data.get("type", "")))
    if wagon_types.is_empty():
        wagon_types.append("LocomotiveWagon")
    if not SHOW_WAGONS:
        wagon_types.resize(1) # only the locomotive

    for i in wagon_types.size():
        var wagon := LOCOMOTIVE_SCENE.instantiate() as NavigationWagon
        wagon.grid_service = grid_service
        wagon_container.add_child(wagon)
        wagon.set_sprite_frames(_get_sprite_frames())
        if i > 0:
            wagon.set_placeholder(wagon_types[i].trim_suffix("Wagon"))
        wagons.append(wagon)

    _place_wagons(tile_pos, ori)
    # Connect AFTER placement so the teleport from (0,0) isn't reported as movement.
    for wagon in wagons:
        wagon.can_enter = _can_wagon_enter
        wagon.blocked.connect(_on_wagon_blocked)
        wagon.tile_changed.connect(_on_wagon_tile_changed)
        wagon.setup_collision(team == NavigationTrainManager.Team.PLAYER)
        wagon.collided.connect(_on_wagon_collided)

# The locomotive goes on `tile_pos`. The others follow the rail backwards from it. If the rail
# ends before all the wagons are placed, the rest are piled on the last tile (with a warning).
func _place_wagons(tile_pos: Vector2i, ori: String) -> void:
    wagons[0].place_at(tile_pos, ori)
    _face(wagons[0], ori)
    if wagons.size() == 1:
        return

    # Reversed: the wagons are in front of the locomotive, so walk back from the opposite direction
    var walk_ori := grid_service.turn_right(ori, 4) if reversed else ori
    var trail := rail_service.tiles_behind(tile_pos, walk_ori, wagons.size() - 1)
    if trail.size() < wagons.size() - 1:
        push_warning("Train %s: the rail behind %s is too short for %d wagons (found %d tiles)" % [id, tile_pos, wagons.size() - 1, trail.size()])

    var last_tile := tile_pos
    var last_ori := ori
    for i in range(1, wagons.size()):
        if i - 1 < trail.size():
            last_tile = trail[i - 1]["tile"]
            var trail_ori: String = trail[i - 1]["ori"]
            last_ori = grid_service.turn_right(trail_ori, 4) if reversed else trail_ori
        wagons[i].place_at(last_tile, last_ori)
        _face(wagons[i], last_ori)

# The wagon at the front: the locomotive, or the last wagon when the train is reversed.
# City entries and the tile events of the train are about this one.
func get_lead_wagon() -> NavigationWagon:
    return wagons.back() if reversed else wagons[0]

func _face(wagon: NavigationWagon, ori: String) -> void:
    wagon.set_orientation(ori)
    #wagon.set_heading(grid_service.orientation_to_heading(ori))

func _get_sprite_frames() -> SpriteFrames:
    if team == NavigationTrainManager.Team.ENEMY:
        return ENEMY_SPRITE_FRAMES
    return PLAYER_SPRITE_FRAMES
#endregion


#region control
func update(delta: float) -> void:
    var driving := gear == Gear.DRIVE
    var target := max_speed if driving else 0.0
    var rate := acceleration if driving else deceleration
    move_speed = move_toward(move_speed, target, rate * delta)
    for wagon in wagons:
        wagon.speed = move_speed
        wagon.advance(delta)


func gear_toggle() -> void:
    _set_gear(Gear.NEUTRAL if gear == Gear.DRIVE else Gear.DRIVE)

func immediate_stop() -> void:
    move_speed = 0.0
    _set_gear(Gear.NEUTRAL)
    for wagon in wagons:
        wagon.speed = 0.0

func reverse_train() -> void:
    reversed = not reversed
    # TODO: on a curve tile, derive the reverse direction from the previous tile instead
    var n := wagons.size()
    var oris: Array[String] = []
    for wagon in wagons:
        oris.append(wagon.orientation)
    for i in n:
        var target := wagons[n - i - 1]
        _face(target, grid_service.turn_right(oris[i], 4))

# Cuts the power: the train brakes by itself
func coast() -> void:
    _set_gear(Gear.NEUTRAL)
    
func drive() -> void:
    _set_gear(Gear.DRIVE)

func is_driving() -> bool:
    return gear == Gear.DRIVE


func _set_gear(new_gear: Gear) -> void:
    if gear == new_gear:
        return
    gear = new_gear
    gear_changed.emit(gear)
#endregion


#region rail following
func _on_wagon_tile_changed(wagon: NavigationWagon, old_tile: Vector2i, new_tile: Vector2i) -> void:
    if not _follow_rail(wagon, old_tile, new_tile):
        immediate_stop()
    # Emit AFTER the stop: a city at a dead end must still be seen by the manager.
    if wagon == get_lead_wagon():
        train_tile_changed.emit(self, old_tile, new_tile)

func _follow_rail(wagon: NavigationWagon, old_tile: Vector2i, new_tile: Vector2i) -> bool:
    var delta := new_tile - old_tile
    if absi(delta.x) > 1 or absi(delta.y) > 1:
        push_warning("Train %s skipped tiles: %s -> %s" % [id, old_tile, new_tile])
    var new_ori: String = rail_service.calculate_new_orientation(new_tile, delta)
    if new_ori.is_empty():
        return false
    _face(wagon, new_ori)
    return true

func _can_wagon_enter(_wagon: NavigationWagon, from_tile: Vector2i, to_tile: Vector2i) -> bool:
    return not rail_service.calculate_new_orientation(to_tile, to_tile - from_tile).is_empty()

func _on_wagon_blocked(_wagon: NavigationWagon) -> void:
    immediate_stop()
#endregion

func _on_wagon_collided(_wagon: NavigationWagon, other_wagon: NavigationWagon) -> void:
    train_collided.emit(self, other_wagon)