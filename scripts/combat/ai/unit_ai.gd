extends Node
class_name UnitAI
# The AI of the soldiers of one team: it decides what each of them does, one soldier at a time, when
# it is standing idle. It follows the stance the CombatAI above it gives:
#   ATTACK  : go for the enemy, from cover to cover. Shoot what it sees (walking into range if it
#             must); if it sees nothing, advance to the next cover towards the last place an enemy
#             was seen, or the objective.
#   DEFEND  : most soldiers PATROL near the train (sideways, along rows close to it); some (see
#             forward_fraction) take a POST: a covered tile towards the middle of the map, which
#             they keep. Both shoot what comes within reach and don't chase what is further.
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
## Seed of the random choices (patrol places, posts). 0 = a different game every time.
@export var rng_seed := 0
## How many tiles a soldier walks towards its goal before it thinks again.
@export var advance_steps := 6
## An attacking soldier stops this many tiles from where it was going.
@export var objective_radius := 3.0
## Patrolling soldiers walk sideways up to this many tiles from the door of the train.
@export var patrol_half_width := 10
## They walk along rows from the door row up to this many rows towards the enemy.
@export var patrol_depth := 4
## Rests of a patrolling soldier between two walks, in thinking rounds (min and max).
@export var patrol_rest_min := 2
@export var patrol_rest_max := 6
## The share of the soldiers that take a post in cover towards the middle of the map when defending.
@export_range(0.0, 1.0) var forward_fraction := 0.3
## How far the posts are from home, as a share of the distance between the two trains' doors.
@export_range(0.0, 1.0) var post_min_depth := 0.25
@export_range(0.0, 1.0) var post_max_depth := 0.55
## A defender goes for an enemy that is at most this much further than its weapon range.
@export var defend_reach := 2.0

# Injected by the scene
var battle_unit_manager: BattleUnitManager
var deployment_manager: DeploymentManager
var visibility_service: VisibilityService
var pathfinding_service: PathfindingService
var occupancy_service: TileOccupancyService
var terrain_service: TerrainService # optional: without it there is no cover to look for
var grid_service: GridService # optional, same

var stance := Stance.DEFEND
## Where an attack goes, and where a defense holds (tiles).
var objective := Vector2i.ZERO
var home := Vector2i.ZERO

var _last_seen := {} # Soldier (enemy) -> the tile it was last seen on

enum Role { PATROL, POST }
var _roles := {} # Soldier -> Role
var _posts := {} # Soldier -> the covered tile it holds
var _rest := {} # Soldier -> thinking rounds it still rests before it walks again
var _cover_tiles: Array[Vector2i] = [] # every walkable tile with cover, see _find_cover_tiles()
var _cover_built := false
var _rng := RandomNumberGenerator.new()


func setup() -> void:
    if rng_seed != 0:
        _rng.seed = rng_seed
    assert(battle_unit_manager != null and deployment_manager != null and visibility_service != null \
            and pathfinding_service != null and occupancy_service != null, "UnitAI: not injected")


func set_orders(new_stance: Stance, new_objective: Vector2i, new_home: Vector2i) -> void:
    stance = new_stance
    objective = new_objective
    home = new_home

## Makes the random choices (patrol places, posts) repeat: for tests and replays.
func seed_random(value: int) -> void:
    _rng.seed = value

func get_role(soldier: Soldier) -> int:
    return _roles.get(soldier, Role.PATROL)

func get_post(soldier: Soldier) -> Vector2i:
    return _posts.get(soldier, DeploymentManager.NO_TILE)


## Lets every idle soldier decide what to do. Returns how many gave an order.
func think() -> int:
    _update_memory()
    _assign_roles()
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
        # Defenders don't chase. A soldier on a post doesn't leave it at all
        var reach: float = float(soldier.get_weapon()["range"]) + defend_reach
        if get_role(soldier) == Role.POST or Vector2(soldier.tile).distance_to(Vector2(target.tile)) > reach:
            return _hold_role(soldier)
    if battle_unit_manager.command_attack(soldier, target):
        return true
    # It can't afford the whole attack (turn based): get as close as it can
    return false if in_reach else _step_towards(soldier, target.tile, advance_steps)

func _no_enemy_in_sight(soldier: Soldier) -> bool:
    if stance == Stance.DEFEND:
        return _hold_role(soldier)
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
    return _advance(soldier, goal)

# Advances from cover to cover: the covered tile that gets it closest to the goal within a short
# walk. With no cover that is better than where it stands, it just walks towards the goal.
func _advance(soldier: Soldier, goal: Vector2i) -> bool:
    var here := Vector2(soldier.tile)
    var best := DeploymentManager.NO_TILE
    var best_score := INF
    for tile in _get_cover_tiles():
        var walk := here.distance_to(Vector2(tile))
        var left := Vector2(tile).distance_to(Vector2(goal))
        if walk < 2.0 or walk > float(advance_steps) + 3.0 or left > here.distance_to(Vector2(goal)) - 2.0:
            continue
        if not occupancy_service.is_free(tile, TileOccupancyService.LAYER_ALL, soldier):
            continue
        var score := left + 0.3 * walk
        if score < best_score:
            best_score = score
            best = tile
    if best != DeploymentManager.NO_TILE and _step_towards(soldier, best, advance_steps + 3):
        return true
    return _step_towards(soldier, goal, advance_steps)

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


#region roles: patrol and posts
# Gives a post to as many soldiers as the stance wants, and takes it from the extra ones
func _assign_roles() -> void:
    var alive := {}
    for soldier in deployment_manager.get_field_soldiers(team):
        alive[soldier] = true
    for soldier in _roles.keys(): # untyped: a soldier that left the battle is freed
        if not alive.has(soldier):
            _roles.erase(soldier)
            _posts.erase(soldier)
            _rest.erase(soldier)
    var wanted := 0
    if stance == Stance.DEFEND:
        wanted = roundi(float(deployment_manager.count_alive(team)) * forward_fraction)
    var holders: Array = _posts.keys()
    # Too many posts: the extra soldiers go back to patrolling
    while holders.size() > wanted:
        var extra: Soldier = holders.pop_back()
        _posts.erase(extra)
        _roles[extra] = Role.PATROL
    # Too few: the soldiers that are still patrolling take the free posts
    for soldier: Soldier in alive:
        if _posts.size() >= wanted:
            break
        if _posts.has(soldier):
            continue
        var spot := _pick_free_post()
        if spot == DeploymentManager.NO_TILE:
            break
        _posts[soldier] = spot
        _roles[soldier] = Role.POST
    for soldier: Soldier in alive:
        if not _roles.has(soldier):
            _roles[soldier] = Role.PATROL

# One of the best free key spots: covered, towards the middle, near the centre column. It picks
# among the best few, so the soldiers don't always take the same.
func _pick_free_post() -> Vector2i:
    var taken := {}
    for spot: Vector2i in _posts.values():
        taken[spot] = true
    var direction := signi(objective.y - home.y)
    var total := float(absi(objective.y - home.y))
    if direction == 0 or total < 1.0:
        return DeploymentManager.NO_TILE
    var centre_x := float(grid_service.map_rect.get_center().x) if grid_service != null else float(home.x)
    var candidates: Array[Dictionary] = []
    for tile in _get_cover_tiles():
        var depth := float((tile.y - home.y) * direction) / total
        if depth < post_min_depth or depth > post_max_depth or taken.has(tile):
            continue
        if not occupancy_service.is_free(tile, TileOccupancyService.LAYER_ALL):
            continue
        candidates.append({"tile": tile, "score": absf(float(tile.x) - centre_x) + absf(depth - 0.4) * 20.0})
    if candidates.is_empty():
        return DeploymentManager.NO_TILE
    candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] < b["score"])
    return candidates[_rng.randi_range(0, mini(candidates.size(), 4) - 1)]["tile"]

# What a defender does when nobody is in sight
func _hold_role(soldier: Soldier) -> bool:
    if get_role(soldier) == Role.POST:
        var post := get_post(soldier)
        return post != DeploymentManager.NO_TILE and soldier.tile != post and _step_towards(soldier, post, 99)
    return _patrol(soldier)

# Walks sideways along a row close to the train, rests, and walks again
func _patrol(soldier: Soldier) -> bool:
    var rest: int = _rest.get(soldier, 0)
    if rest > 0:
        _rest[soldier] = rest - 1
        return false
    var direction := signi(objective.y - home.y)
    if direction == 0:
        direction = 1
    var row := home.y + direction * int(soldier.get_instance_id() % (patrol_depth + 1))
    var x_min := home.x - patrol_half_width
    var x_max := home.x + patrol_half_width
    if grid_service != null:
        x_min = maxi(x_min, grid_service.map_rect.position.x)
        x_max = mini(x_max, grid_service.map_rect.end.x - 1)
    # A new place along the row, not next to where it stands
    var column := _rng.randi_range(x_min, x_max)
    if absi(column - soldier.tile.x) < 3:
        column = x_max if soldier.tile.x - x_min < x_max - soldier.tile.x else x_min
    _rest[soldier] = _rng.randi_range(patrol_rest_min, patrol_rest_max)
    return _step_towards(soldier, Vector2i(column, row), 12)

func _get_cover_tiles() -> Array[Vector2i]:
    if not _cover_built:
        _cover_built = true
        _cover_tiles.clear()
        if terrain_service != null and grid_service != null:
            var rect := grid_service.map_rect
            for y in range(rect.position.y, rect.end.y):
                for x in range(rect.position.x, rect.end.x):
                    var tile := Vector2i(x, y)
                    if terrain_service.is_walkable(tile) and terrain_service.get_cover(tile) >= CoverLevel.HALF:
                        _cover_tiles.append(tile)
    return _cover_tiles
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
