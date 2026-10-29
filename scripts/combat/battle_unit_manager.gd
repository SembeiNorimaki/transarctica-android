extends Node
class_name BattleUnitManager
# The soldiers of a tile based battle: it deploys them, keeps the occupancy up to date as they
# walk, works out their paths, resolves their shots, and keeps track of the selected one.
#
# Soldiers only emit signals and run their own actions (see Soldier); this manager is the one that
# places them in TileOccupancyService and decides what a shot does.

signal selection_changed(soldier: Soldier) # null: nothing is selected
signal soldier_spawned(soldier: Soldier)
signal soldier_died(soldier: Soldier)
signal shot_resolved(attacker: Soldier, target: Soldier, damage: int, cover: int)

const SOLDIER_SCENE: PackedScene = preload("res://scenes/units/soldier.tscn")
## Share of the damage that gets through, by CoverLevel.
const COVER_DAMAGE := {CoverLevel.NONE: 1.0, CoverLevel.HALF: 0.75, CoverLevel.FULL: 0.5}

## The team the player commands. Soldiers of other teams can only be attacked.
var player_team := Soldier.TEAM_PLAYER

# Injected by the scene
var unit_container: Node2D
var grid_service: GridService
var occupancy_service: TileOccupancyService
var pathfinding_service: PathfindingService
var vision_service: VisionService
var cover_service: CoverService

var soldiers: Array[Soldier] = []
var selected: Soldier = null

var _profiles := {} # Soldier -> MoveProfile
var _next_number := 0


# Call once, after the injection
func setup() -> void:
    assert(unit_container != null and grid_service != null and occupancy_service != null \
            and pathfinding_service != null and vision_service != null and cover_service != null,
            "BattleUnitManager: not injected")


#region deploying
## Puts a new soldier on a free tile. Returns null (with a warning) if it can't.
func spawn(team: String, unit_type: String, tile: Vector2i, facing := "S") -> Soldier:
    if not UnitTypes.exists(unit_type):
        push_warning("BattleUnitManager: unknown unit type '%s'" % unit_type)
        return null
    if not occupancy_service.is_free(tile, TileOccupancyService.LAYER_ALL):
        push_warning("BattleUnitManager: tile %s is not free for a %s" % [tile, unit_type])
        return null
    var data := UnitTypes.make_unit(unit_type)
    data["team"] = team
    var soldier := SOLDIER_SCENE.instantiate() as Soldier
    soldier.setup("%s%d" % [team.left(1), _next_number], data)
    _next_number += 1
    soldier.grid_service = grid_service
    soldier.can_step = _can_soldier_step
    soldier.step_started.connect(_on_step_started)
    soldier.attack_fired.connect(_on_attack_fired)
    soldier.died.connect(_on_soldier_died)
    unit_container.add_child(soldier)
    soldier.place_at(tile, facing)
    occupancy_service.place(soldier, tile, Footprint.single(), TileOccupancyService.LAYER_UNIT)
    soldiers.append(soldier)
    soldier_spawned.emit(soldier)
    return soldier

## Deploys the soldiers of CombatMapManager.get_spawns(). Facing: the player's face north-east,
## the enemy's south-west, so they look at each other on a map laid out corner to corner.
func spawn_all(spawns: Array[Dictionary]) -> void:
    for spawn_data in spawns:
        var facing := "SE" if spawn_data["team"] == Soldier.TEAM_ENEMY else "NW"
        spawn(spawn_data["team"], spawn_data["unit_type"], spawn_data["tile"], facing)
#endregion


#region selection and orders
func select(soldier: Soldier) -> void:
    if selected == soldier:
        return
    if is_instance_valid(selected):
        selected.selected = false
    selected = soldier
    if selected != null:
        selected.selected = true
    selection_changed.emit(selected)

## What a tap on a tile means: a soldier of the player's team is selected; an enemy is attacked by
## the selected soldier; an empty tile is where the selected soldier walks.
func handle_tile_tap(tile: Vector2i) -> void:
    var tapped := occupancy_service.get_first_at(tile, TileOccupancyService.LAYER_UNIT) as Soldier
    if tapped != null:
        if tapped.team == player_team:
            select(null if tapped == selected else tapped)
        elif selected != null:
            command_attack(selected, tapped)
    elif selected != null:
        command_move(selected, tile)

func command_move(soldier: Soldier, tile: Vector2i) -> bool:
    var path := pathfinding_service.find_path(soldier.tile, tile, _profile_of(soldier))
    if path.size() < 2:
        soldier.show_event("no path")
        return false
    soldier.order_move(path)
    return true

## Shoots from where it stands if the target is in range and in sight, otherwise walks towards the
## target until it is, then shoots.
func command_attack(soldier: Soldier, target: Soldier) -> bool:
    if target.team == soldier.team or not target.is_alive():
        return false
    if can_shoot(soldier, soldier.tile, target):
        soldier.order_attack(target)
        return true
    var profile := _profile_of(soldier)
    profile.goal_may_be_occupied = true
    var path := pathfinding_service.find_path(soldier.tile, target.tile, profile)
    for i in path.size():
        if can_shoot(soldier, path[i], target):
            var walk: Array[Vector2i] = []
            walk.assign(path.slice(0, i + 1))
            soldier.order_move(walk, target)
            return true
    soldier.show_event("can't reach")
    return false

## Could this soldier, standing on `from_tile`, hit the target?
func can_shoot(soldier: Soldier, from_tile: Vector2i, target: Soldier) -> bool:
    var weapon := soldier.get_weapon()
    var distance := Vector2(from_tile).distance_to(Vector2(target.tile))
    return distance <= float(weapon["range"]) and vision_service.has_line_of_sight(from_tile, target.tile)
#endregion


func _profile_of(soldier: Soldier) -> MoveProfile:
    if not _profiles.has(soldier):
        var profile := MoveProfile.new()
        profile.ignore = soldier
        _profiles[soldier] = profile
    return _profiles[soldier]

func _can_soldier_step(soldier: Soldier, from: Vector2i, to: Vector2i) -> bool:
    return pathfinding_service.can_step(from, to, _profile_of(soldier))

func _on_step_started(soldier: Soldier, _from: Vector2i, to: Vector2i) -> void:
    occupancy_service.move(soldier, to)

func _on_attack_fired(attacker: Soldier, target: Soldier) -> void:
    if not is_instance_valid(target) or not target.is_alive():
        return
    if not can_shoot(attacker, attacker.tile, target):
        attacker.show_event("no shot")
        return
    var cover := cover_service.get_cover(attacker.tile, target.tile)
    var damage := roundi(float(attacker.get_weapon()["damage"]) * float(COVER_DAMAGE[cover]))
    attacker.show_event("fire!")
    target.take_damage(damage, attacker)
    shot_resolved.emit(attacker, target, damage, cover)

func _on_soldier_died(soldier: Soldier) -> void:
    occupancy_service.remove(soldier)
    if selected == soldier:
        select(null)
    soldier_died.emit(soldier)
