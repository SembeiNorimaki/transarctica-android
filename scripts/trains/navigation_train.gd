extends Node2D
class_name NavigationTrain

enum Gear {NEUTRAL, DRIVE}

signal train_tile_changed(navigation_train: NavigationTrain, old_tile: Vector2i, new_tile: Vector2i)
signal gear_changed(gear: Gear)
signal train_collided(navigation_train: NavigationTrain, other_wagon: NavigationWagon)


const LOCOMOTIVE_SCENE: PackedScene = preload("res://scenes/wagons/navigation_locomotive.tscn")
const MAX_SPEED := 300.0
const ACCELERATION := 50.0
const DECELERATION := 200.0
const WAGON_SPACING_TILES := 1 # replaces Vector2(-32, -16); adjust to what you actually want

const PLAYER_SPRITE_FRAMES: SpriteFrames = preload("res://assets/tilesets/navigation_locomotive_spriteframes.tres")
const ENEMY_SPRITE_FRAMES: SpriteFrames = preload("res://assets/tilesets/navigation_locomotive_enemy_spriteframes.tres")


# Injected (train_manager removed: it was never used here)
var grid_service: GridService
var rail_service: RailService

var id := ""
var team: NavigationTrainManager.Team
var gear := Gear.NEUTRAL
var move_speed := 0.0
var wagons: Array[NavigationWagon] = [] # wagons[0] is the head

@onready var wagon_container: Node2D = $WagonContainer


#region initialization
func initialize(id_: String, team_: NavigationTrainManager.Team, tile_pos: Vector2i, ori: String) -> void:
    assert(id.is_empty(), "NavigationTrain: already initialized")
    id = id_
    team = team_

    var locomotive := LOCOMOTIVE_SCENE.instantiate() as NavigationWagon
    locomotive.grid_service = grid_service
    wagon_container.add_child(locomotive)
    locomotive.set_sprite_frames(_get_sprite_frames())
    wagons.append(locomotive)

    _place_wagons(tile_pos, ori)
    # Connect AFTER placement so the teleport from (0,0) isn't reported as movement.
    # (If the locomotive tracks its tile in _process, reset that tracking in set_pos.)
    locomotive.tile_changed.connect(_on_wagon_tile_changed)
    locomotive.setup_collision(team == NavigationTrainManager.Team.PLAYER)
    locomotive.collided.connect(_on_wagon_collided)

func _place_wagons(tile_pos: Vector2i, ori: String) -> void:
    var back: Vector2i = grid_service.orientation_to_delta(grid_service.turn_right(ori, 4))
    for i in wagons.size():
        # Straight-line placement only. With real wagons, walk the rail backwards via rail_service.
        var tile := tile_pos + back * i * WAGON_SPACING_TILES
        wagons[i].place_at(tile, ori)
        _face(wagons[i], ori)

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
    var target := MAX_SPEED if driving else 0.0
    var rate := ACCELERATION if driving else DECELERATION
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
    # TODO: on a curve tile, derive the reverse direction from the previous tile instead
    var n := wagons.size()
    var positions: Array[Vector2] = []
    var oris: Array[String] = []
    for wagon in wagons:
        positions.append(wagon.position)
        oris.append(wagon.orientation)
    for i in n:
        var target := wagons[n - i - 1]
        _face(target, grid_service.turn_right(oris[i], 4))

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
    if wagon == wagons[0]:
        train_tile_changed.emit(self, old_tile, new_tile)

func _follow_rail(wagon: NavigationWagon, old_tile: Vector2i, new_tile: Vector2i) -> bool:
    var delta := new_tile - old_tile
    if absi(delta.x) > 1 or absi(delta.y) > 1:
        push_warning("Train %s skipped tiles: %s -> %s" % [id, old_tile, new_tile])
    var new_ori = rail_service.calculate_new_orientation(new_tile, delta)
    if new_ori.is_empty():
        return false
    _face(wagon, new_ori)
    return true
#endregion

func _on_wagon_collided(_wagon: NavigationWagon, other_wagon: NavigationWagon) -> void:
    train_collided.emit(self, other_wagon)
