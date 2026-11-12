extends Node
class_name FieldAI
# The AI of the units of a team on a battlefield with no trains (the city): each unit has two modes.
#
#   NORMAL : it plays its role, as long as it sees no enemy.
#     GUARD  stands at its post (the tile it started on) and turns around now and then, so its view
#            sweeps the surroundings. If it was pulled away, it goes back.
#     PATROL walks a round of a few stops around its post, resting at each.
#   ALERT  : it has seen an enemy (inside the view range and cone of the unit itself, see can_see_unit),
#            or was shot by one. It engages: it shoots what it can hit from where it stands; otherwise
#            it goes after it, but only as far as its leash lets it from its post (a guard's is short).
#            Out of range and beyond the leash it holds, facing the enemy. When the enemy is gone from
#            its sight it goes to where it saw it last; after alert_memory rounds with no enemy in
#            sight it calms down and goes back to its role.
#
# The role comes from the unit (Soldier.role, from the Spawns layer or else UnitTypes.default_role):
# fast units patrol, soldiers, tanks and artillery guard.
#
# It plays by the rules of the player: the only things it does are BattleUnitManager's commands, and the
# flow manager refuses what the action points don't allow. Real time: it thinks every think_interval.
# Turn based: it thinks the same way in its team's turn and ends the turn when nobody has anything left
# to do (TurnManager.auto_pass_computer_turns must be off, or the turn ends by itself).

enum Mode { NORMAL, ALERT }

## A unit went alert, at the tile where it saw an enemy.
signal alerted(unit: Soldier, enemy_tile: Vector2i)
## A unit lost the enemy and is back to its role.
signal calmed(unit: Soldier)

const NO_TILE := Vector2i(-99999, -99999)

@export var team := Soldier.TEAM_ENEMY
@export var enabled := true
## Game seconds between two rounds of thinking.
@export var think_interval := 0.5
## A unit also sees this many tiles all around it, whichever way it faces (as in FogManager).
@export var awareness_range := 2
## The stops of a patrol are at most this many tiles from its post, and there are this many.
@export var patrol_radius := 8
@export var patrol_stops := 3
## Rounds a patrol rests at a stop (min and max).
@export var patrol_rest_min := 1
@export var patrol_rest_max := 3
## A guard turns a quarter round every this many rounds.
@export var scan_interval := 3
## How far from its post an alert unit goes after an enemy (tiles, beyond its weapon's range).
@export var guard_leash := 4.0
@export var patrol_leash := 12.0
## Rounds without an enemy in sight before an alert unit calms down.
@export var alert_memory := 4
## Seed of the random choices (patrol stops, rests). 0 = a different game every time.
@export var rng_seed := 0

# Injected by the scene
var battle_unit_manager: BattleUnitManager
var vision_service: VisionService
var pathfinding_service: PathfindingService
var occupancy_service: TileOccupancyService
var grid_service: GridService
var flow_manager: CombatFlowManager


# What one unit remembers
class Brain extends RefCounted:
    var home := Vector2i.ZERO # its post
    var mode := Mode.NORMAL
    var lost := 0 # rounds alert without an enemy in sight
    var last_seen := NO_TILE # where an enemy was last seen
    var route: Array[Vector2i] = [] # the stops of a patrol
    var route_built := false
    var next_stop := 0
    var rest := 0 # rounds it still rests
    var scan := 0 # rounds since a guard turned

var _brains := {} # Soldier -> Brain
var _timer := 0.0
var _rng := RandomNumberGenerator.new()


func setup() -> void:
    assert(battle_unit_manager != null and vision_service != null and pathfinding_service != null \
            and occupancy_service != null and grid_service != null and flow_manager != null, "FieldAI: not injected")
    if rng_seed != 0:
        _rng.seed = rng_seed
    battle_unit_manager.soldier_spawned.connect(_on_soldier_spawned)
    battle_unit_manager.soldier_died.connect(_forget)
    battle_unit_manager.soldier_removed.connect(_forget)
    battle_unit_manager.shot_resolved.connect(_on_shot_resolved)
    for soldier in battle_unit_manager.soldiers:
        _on_soldier_spawned(soldier)

## Makes the random choices repeat: for tests and replays.
func seed_random(value: int) -> void:
    _rng.seed = value


#region what it knows of a unit
func get_mode(soldier: Soldier) -> int:
    return _brains[soldier].mode if _brains.has(soldier) else Mode.NORMAL

func is_alert(soldier: Soldier) -> bool:
    return get_mode(soldier) == Mode.ALERT

## The post of the unit: where it started.
func get_home(soldier: Soldier) -> Vector2i:
    return _brains[soldier].home if _brains.has(soldier) else NO_TILE

## The stops of its patrol (empty for a guard, and before its first walk).
func get_route(soldier: Soldier) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    if _brains.has(soldier):
        result.assign(_brains[soldier].route)
    return result

func get_units() -> Array[Soldier]:
    var result: Array[Soldier] = []
    for soldier: Soldier in _brains.keys():
        if is_instance_valid(soldier) and soldier.is_alive():
            result.append(soldier)
    return result

## Is any unit of the team in the middle of an action?
func is_busy() -> bool:
    for soldier in get_units():
        if soldier.get_action() != &"idle":
            return true
    return false
#endregion


func _process(delta: float) -> void:
    if not enabled or flow_manager.battle_over:
        return
    _timer += delta
    if _timer < think_interval:
        return
    _timer = 0.0
    think()


## One round: every unit looks around and, if it stands idle, decides what to do. In turn based combat
## only in its team's turn, which ends when nothing is left to do. Returns how many gave an order.
func think() -> int:
    var turn_manager := flow_manager as TurnManager
    if turn_manager != null and turn_manager.current_team != team:
        return 0
    var orders := 0
    for soldier in get_units():
        var brain: Brain = _brains[soldier]
        _look_around(soldier, brain)
        if soldier.get_action() == &"idle" and _act(soldier, brain):
            orders += 1
    if turn_manager != null and orders == 0 and not is_busy():
        turn_manager.end_turn()
    return orders


#region seeing
## The enemies this unit sees now: inside its cone and range, or close around it, in line of sight.
func get_visible_enemies(soldier: Soldier) -> Array[Soldier]:
    var result: Array[Soldier] = []
    for other in battle_unit_manager.soldiers:
        if other.team != soldier.team and other.is_alive() and can_see_unit(soldier, other):
            result.append(other)
    return result

func can_see_unit(viewer: Soldier, target: Soldier) -> bool:
    for tile in target.footprint.tiles_at(target.tile):
        if vision_service.can_see(viewer.tile, viewer.facing, viewer.view_angle, viewer.view_range, tile):
            return true
        if vision_service.can_see(viewer.tile, "N", 360.0, awareness_range, tile):
            return true
    return false

# Updates the mode: an enemy in sight makes the unit alert; alert units forget after a while
func _look_around(soldier: Soldier, brain: Brain) -> void:
    var enemies := get_visible_enemies(soldier)
    if not enemies.is_empty():
        _go_alert(soldier, brain, _nearest(soldier, enemies).tile)
    elif brain.mode == Mode.ALERT:
        brain.lost += 1
        if brain.lost >= alert_memory:
            brain.mode = Mode.NORMAL
            brain.last_seen = NO_TILE
            soldier.show_event("calm")
            calmed.emit(soldier)

func _go_alert(soldier: Soldier, brain: Brain, enemy_tile: Vector2i) -> void:
    brain.lost = 0
    brain.last_seen = enemy_tile
    if brain.mode == Mode.ALERT:
        return
    brain.mode = Mode.ALERT
    soldier.show_event("ALERT!")
    alerted.emit(soldier, enemy_tile)

# A unit that is shot at is alert, even if the one who shoots is out of its sight (artillery)
func _on_shot_resolved(attacker: Soldier, target: Soldier, _damage: int, _cover: int) -> void:
    if target == null or target.team != team or attacker == null or attacker.team == team or not _brains.has(target):
        return
    _go_alert(target, _brains[target], attacker.tile)

func _nearest(soldier: Soldier, enemies: Array[Soldier]) -> Soldier:
    var best: Soldier = null
    var best_distance := INF
    for enemy in enemies:
        var distance := Vector2(soldier.tile).distance_to(Vector2(enemy.tile))
        if distance < best_distance:
            best = enemy
            best_distance = distance
    return best

## The best enemy to shoot: of those it can hit from where it stands, the weakest; otherwise the nearest.
func pick_target(soldier: Soldier, enemies: Array[Soldier]) -> Soldier:
    var best: Soldier = null
    var best_score := INF
    for enemy in enemies:
        var score := Vector2(soldier.tile).distance_to(Vector2(enemy.tile))
        if battle_unit_manager.can_shoot(soldier, soldier.tile, enemy):
            score = float(enemy.hp) - 1000.0
        if score < best_score:
            best = enemy
            best_score = score
    return best
#endregion


#region acting
func _act(soldier: Soldier, brain: Brain) -> bool:
    if not _has_action_points(soldier):
        return false
    if brain.mode == Mode.ALERT:
        return _act_alert(soldier, brain)
    return _patrol(soldier, brain) if soldier.role == "patrol" else _guard(soldier, brain)

# Turn based: a unit with no action points can't do anything (asking would only make it say "no AP")
func _has_action_points(soldier: Soldier) -> bool:
    var turn_manager := flow_manager as TurnManager
    return turn_manager == null or soldier.action_points >= turn_manager.min_action_cost

func _act_alert(soldier: Soldier, brain: Brain) -> bool:
    var enemies := get_visible_enemies(soldier)
    if enemies.is_empty():
        # Go and see where it was, if that is not too far from the post
        if brain.last_seen != NO_TILE and Vector2(soldier.tile).distance_to(Vector2(brain.last_seen)) > 2.0 \
                and Vector2(brain.home).distance_to(Vector2(brain.last_seen)) <= _leash(soldier):
            return _step_towards(soldier, brain.last_seen, 8)
        return false
    var target := pick_target(soldier, enemies)
    if battle_unit_manager.can_shoot(soldier, soldier.tile, target):
        return flow_manager.can_attack(soldier) and battle_unit_manager.command_attack(soldier, target)
    # Out of reach: go after it, as far as the leash allows
    var weapon_range := float(soldier.get_weapon()["range"])
    if Vector2(brain.home).distance_to(Vector2(target.tile)) - weapon_range <= _leash(soldier):
        if battle_unit_manager.command_attack(soldier, target):
            return true
        return _step_towards(soldier, target.tile, 8)
    soldier.look_at_tile(target.tile) # it holds, watching it
    return false

func _leash(soldier: Soldier) -> float:
    return patrol_leash if soldier.role == "patrol" else guard_leash

# Stands at the post, and turns a quarter round now and then
func _guard(soldier: Soldier, brain: Brain) -> bool:
    if Vector2(soldier.tile).distance_to(Vector2(brain.home)) > 1.0:
        return _step_towards(soldier, brain.home, 99)
    brain.scan += 1
    if brain.scan >= scan_interval:
        brain.scan = 0
        soldier.face(grid_service.turn_right(soldier.facing, 2))
    return false

# Walks the stops of its round one after the other, resting at each
func _patrol(soldier: Soldier, brain: Brain) -> bool:
    if not brain.route_built:
        _build_route(soldier, brain)
    if brain.route.is_empty():
        return _guard(soldier, brain) # nowhere to walk to
    if brain.rest > 0:
        brain.rest -= 1
        return false
    var stop := brain.route[brain.next_stop]
    if Vector2(soldier.tile).distance_to(Vector2(stop)) <= 1.5:
        brain.next_stop = (brain.next_stop + 1) % brain.route.size()
        brain.rest = _rng.randi_range(patrol_rest_min, patrol_rest_max)
        return false
    if _step_towards(soldier, stop, 99):
        return true
    # Blocked or no action points: the next time
    return false

# Some free places around the post, reachable and not too close to each other
func _build_route(soldier: Soldier, brain: Brain) -> void:
    brain.route_built = true
    var profile := MoveProfile.new()
    profile.ignore = soldier
    profile.footprint = soldier.footprint
    var rect := grid_service.map_rect
    for attempt in 60:
        if brain.route.size() >= patrol_stops:
            break
        var tile := brain.home + Vector2i(_rng.randi_range(-patrol_radius, patrol_radius), _rng.randi_range(-patrol_radius, patrol_radius))
        if not rect.has_point(tile) or Vector2(tile).distance_to(Vector2(brain.home)) < 4.0:
            continue
        var apart := true
        for stop in brain.route:
            apart = apart and Vector2(stop).distance_to(Vector2(tile)) >= 4.0
        if not apart or not occupancy_service.is_footprint_free(tile, soldier.footprint, TileOccupancyService.LAYER_ALL, soldier):
            continue
        if not pathfinding_service.find_path(brain.home, tile, profile).is_empty():
            brain.route.append(tile)

# Walks up to `steps` tiles of the way to `goal`. The goal may be taken: it stops short of it.
func _step_towards(soldier: Soldier, goal: Vector2i, steps: int) -> bool:
    var profile := battle_unit_manager.get_profile(soldier)
    profile.goal_may_be_occupied = true
    var path := pathfinding_service.find_path(soldier.tile, goal, profile)
    profile.goal_may_be_occupied = false
    if path.is_empty():
        # A big unit can't stand where the goal is when somebody covers part of it: go close to it
        var near := _free_tile_near(soldier, goal, 3)
        if near == NO_TILE:
            return false
        path = pathfinding_service.find_path(soldier.tile, near, profile)
    for i in range(mini(steps, path.size() - 1), 0, -1):
        if occupancy_service.is_footprint_free(path[i], soldier.footprint, TileOccupancyService.LAYER_ALL, soldier):
            return battle_unit_manager.command_move(soldier, path[i])
    return false

# The free tile within `radius` of `goal` that the soldier can walk to and is nearest to it
func _free_tile_near(soldier: Soldier, goal: Vector2i, radius: int) -> Vector2i:
    var candidates: Array[Vector2i] = []
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            var tile := goal + Vector2i(dx, dy)
            if tile != soldier.tile and occupancy_service.is_footprint_free(tile, soldier.footprint, TileOccupancyService.LAYER_ALL, soldier):
                candidates.append(tile)
    candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
        return Vector2(a).distance_squared_to(Vector2(soldier.tile)) < Vector2(b).distance_squared_to(Vector2(soldier.tile)))
    var profile := battle_unit_manager.get_profile(soldier)
    for tile in candidates:
        if not pathfinding_service.find_path(soldier.tile, tile, profile).is_empty():
            return tile
    return NO_TILE
#endregion


func _on_soldier_spawned(soldier: Soldier) -> void:
    if soldier.team != team or _brains.has(soldier):
        return
    var brain := Brain.new()
    brain.home = soldier.tile
    brain.rest = _rng.randi_range(0, patrol_rest_max) # the patrols do not all set off together
    _brains[soldier] = brain

func _forget(soldier: Soldier) -> void:
    _brains.erase(soldier)
