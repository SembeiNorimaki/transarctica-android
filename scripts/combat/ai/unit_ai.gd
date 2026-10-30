extends Node
class_name UnitAI
# The AI of the soldiers of one team: it decides what each of them does, one soldier at a time, when
# it is standing idle. It follows the stance the CombatAI above it gives:
#   ATTACK  : go for the enemy. Shoot what it sees (walking into range if it must); if it sees
#             nothing, advance towards the last place an enemy was seen, or the objective.
#   DEFEND  : hold near home. Shoot what comes within reach; if no enemy is around, stay (or go
#             back) near home.
#   RETREAT : go back to the train and board it.
# In any stance a badly wounded soldier that sees an enemy runs for the train.
#
# It plays by the player's rules: the only things it does are BattleUnitManager's commands, and
# it only knows about enemies the team can see (VisibilityService), plus the last place it saw
# one. In turn based combat the flow manager refuses what the action points don't allow, and the
# AI simply tries something else.

enum Stance { ATTACK, DEFEND, RETREAT }

@export var team := Soldier.TEAM_ENEMY
## A soldier below this share of its hp runs for the train when it sees an enemy.
@export_range(0.0, 1.0) var wounded_ratio := 0.35
## How many tiles a soldier walks towards its goal before it thinks again.
@export var advance_steps := 6
## An attacking soldier stops this many tiles from where it was going.
@export var objective_radius := 3.0
## A defender stays within this many tiles of home.
@export var defend_radius := 4.0
## A defender goes for an enemy that is at most this much further than its weapon range.
@export var defend_reach := 2.0

# Injected by the scene
var battle_unit_manager: BattleUnitManager
var deployment_manager: DeploymentManager
var visibility_service: VisibilityService
var pathfinding_service: PathfindingService
var occupancy_service: TileOccupancyService

var stance := Stance.DEFEND
## Where an attack goes, and where a defense holds (tiles).
var objective := Vector2i.ZERO
var home := Vector2i.ZERO

var _last_seen := {} # Soldier (enemy) -> the tile it was last seen on


func setup() -> void:
    assert(battle_unit_manager != null and deployment_manager != null and visibility_service != null \
            and pathfinding_service != null and occupancy_service != null, "UnitAI: not injected")


func set_orders(new_stance: Stance, new_objective: Vector2i, new_home: Vector2i) -> void:
    stance = new_stance
    objective = new_objective
    home = new_home


## Lets every idle soldier decide what to do. Returns how many gave an order.
func think() -> int:
    _update_memory()
    var orders := 0
    for soldier in deployment_manager.get_field_soldiers(team):
        if soldier.get_action() == &"idle" and _decide(soldier):
            orders += 1
    return orders

## Is any soldier of the team in the middle of an action?
func is_busy() -> bool:
    for soldier in deployment_manager.get_field_soldiers(team):
        if soldier.get_action() != &"idle":
            return true
    return false


#region deciding
func _decide(soldier: Soldier) -> bool:
    if stance == Stance.RETREAT:
        return deployment_manager.order_board(soldier)

    var enemies := get_visible_enemies(soldier)
    if enemies.is_empty():
        return _no_enemy_in_sight(soldier)
    if float(soldier.hp) < wounded_ratio * float(soldier.max_hp) and deployment_manager.order_board(soldier):
        return true

    var target := pick_target(soldier, enemies)
    var in_reach := battle_unit_manager.can_shoot(soldier, soldier.tile, target)
    if stance == Stance.DEFEND and not in_reach:
        var reach: float = float(soldier.get_weapon()["range"]) + defend_reach
        if Vector2(soldier.tile).distance_to(Vector2(target.tile)) > reach:
            return _go_home(soldier)
    if battle_unit_manager.command_attack(soldier, target):
        return true
    # It can't afford the whole attack (turn based): get as close as it can
    return false if in_reach else _step_towards(soldier, target.tile, advance_steps)

func _no_enemy_in_sight(soldier: Soldier) -> bool:
    if stance == Stance.DEFEND:
        return _go_home(soldier)
    # Attack: the nearest place an enemy was seen, otherwise the objective
    var goal := objective
    var nearest := INF
    for enemy: Soldier in _last_seen:
        var distance := Vector2(soldier.tile).distance_to(Vector2(_last_seen[enemy]))
        if distance < nearest:
            nearest = distance
            goal = _last_seen[enemy]
    if Vector2(soldier.tile).distance_to(Vector2(goal)) <= objective_radius:
        return false
    return _step_towards(soldier, goal, advance_steps)

func _go_home(soldier: Soldier) -> bool:
    if Vector2(soldier.tile).distance_to(Vector2(home)) <= defend_radius:
        return false
    return _step_towards(soldier, home, advance_steps)

# Walks up to `steps` tiles of the way to `goal`. The goal may be taken: it stops short of it.
func _step_towards(soldier: Soldier, goal: Vector2i, steps: int) -> bool:
    var profile := battle_unit_manager.get_profile(soldier)
    profile.goal_may_be_occupied = true
    var path := pathfinding_service.find_path(soldier.tile, goal, profile)
    profile.goal_may_be_occupied = false
    for i in range(mini(steps, path.size() - 1), 0, -1):
        if occupancy_service.is_free(path[i], TileOccupancyService.LAYER_ALL, soldier):
            return battle_unit_manager.command_move(soldier, path[i])
    return false
#endregion


#region knowledge
## The enemy soldiers the team has seen and thinks are still there (those in sight now, and those
## it saw last somewhere it can't see at the moment).
func get_known_enemies() -> Array[Soldier]:
    _update_memory()
    var result: Array[Soldier] = []
    for enemy: Soldier in _last_seen:
        result.append(enemy)
    return result

## The enemy soldiers the soldier's team sees now.
func get_visible_enemies(soldier: Soldier) -> Array[Soldier]:
    var result: Array[Soldier] = []
    for other in battle_unit_manager.soldiers:
        if other.team != soldier.team and other.is_alive() and visibility_service.is_visible(soldier.team, other.tile):
            result.append(other)
    return result

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

# Remembers where enemies were seen; forgets an enemy that is dead, or whose place can be seen
# and it is not there any more.
func _update_memory() -> void:
    for key in _last_seen.keys(): # untyped: a soldier that left the battle is freed
        if not is_instance_valid(key) or not (key as Soldier).is_alive():
            _last_seen.erase(key)
        elif not visibility_service.is_visible(team, (key as Soldier).tile) and visibility_service.is_visible(team, _last_seen[key]):
            _last_seen.erase(key)
    for other in battle_unit_manager.soldiers:
        if other.team != team and other.is_alive() and visibility_service.is_visible(team, other.tile):
            _last_seen[other] = other.tile
#endregion
