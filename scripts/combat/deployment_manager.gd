extends Node
class_name DeploymentManager
# Soldiers getting off their train and back on it. Each team has one train with a barracks wagon
# (see register_train) that carries soldiers. To deploy one, the manager picks a free tile in the
# first rows of the map next to the wagon (the "entry zone") and asks BattleUnitManager to put the
# soldier there. To board, a soldier walks back to the door tile and is removed from the battle;
# its hp is kept in the unit data, so it comes out as wounded as it went in.
#
# The map needs an entry edge for each team: the team whose train is above the map (at the top)
# enters from the top rows, the other one from the bottom rows. It works with any projection:
# it only handles tiles.
#
# The player (BarracksMenu, Board button) and the AIs (TrainAI, UnitAI) use the same functions.

signal soldier_deployed(soldier: Soldier)
## A soldier went back on its train. The unit is in `get_aboard(team)` again.
signal soldier_boarded(unit_id: String, team: String)

const NO_TILE := Vector2i(-99999, -99999)

## How many rows from the entry edge a soldier can be put in.
@export var entry_depth := 2
## A soldier boards when it stands this close (in tiles) to the door tile.
@export var board_range := 2.0

# Injected by the scene
var battle_unit_manager: BattleUnitManager
var grid_service: GridService
var occupancy_service: TileOccupancyService
var terrain_service: TerrainService
var pathfinding_service: PathfindingService
var combat_map: CombatMap
## Optional. Without it, deploying is always allowed.
var flow_manager: CombatFlowManager

var _trains := {} # team -> {"barracks": BarracksWagon, "aboard": Array[String], "units": Dictionary, "from_top": bool}
var _pending_board := {} # Soldier -> true: walking to the door to board


# Call once, after the injection
func setup() -> void:
    assert(battle_unit_manager != null and grid_service != null and occupancy_service != null \
            and terrain_service != null and pathfinding_service != null and combat_map != null,
            "DeploymentManager: not injected")
    battle_unit_manager.soldier_died.connect(func(soldier: Soldier) -> void: _pending_board.erase(soldier))


#region trains
## The barracks wagon of a team's train and the soldiers aboard. `units` is unit id -> unit data
## (see UnitTypes.make_unit); `aboard_ids` says which of them are in the wagon (default: all).
## `from_top`: the train is above the map, so the soldiers enter from the top rows.
func register_train(team: String, barracks: BarracksWagon, units: Dictionary, from_top: bool, aboard_ids: Array = []) -> void:
    var aboard: Array[String] = []
    for id in (aboard_ids if not aboard_ids.is_empty() else units.keys()):
        aboard.append(str(id))
    _trains[team] = {"barracks": barracks, "aboard": aboard, "units": units, "from_top": from_top}

func has_train(team: String) -> bool:
    return _trains.has(team)

## The unit ids waiting in the wagon, in boarding order.
func get_aboard(team: String) -> Array[String]:
    var result: Array[String] = []
    if _trains.has(team):
        result.assign(_trains[team]["aboard"])
    return result

func get_capacity(team: String) -> int:
    return (_trains[team]["barracks"] as BarracksWagon).max_cargo_amount if _trains.has(team) else 0

func get_unit_data(team: String, unit_id: String) -> Dictionary:
    return _trains[team]["units"].get(unit_id, {}) if _trains.has(team) else {}

func get_barracks(team: String) -> BarracksWagon:
    return _trains[team]["barracks"] if _trains.has(team) else null

## Which way the team's soldiers face when they get off (towards the map).
func get_entry_facing(team: String) -> String:
    return "S" if _trains[team]["from_top"] else "N"

## The soldiers of this team fighting right now.
func get_field_soldiers(team: String) -> Array[Soldier]:
    var result: Array[Soldier] = []
    for soldier in battle_unit_manager.soldiers:
        if soldier.team == team and soldier.is_alive():
            result.append(soldier)
    return result

## Soldiers alive: on the battlefield and aboard.
func count_alive(team: String) -> int:
    return get_field_soldiers(team).size() + get_aboard(team).size()

## Nobody left to fight: none on the battlefield and none aboard.
func is_team_defeated(team: String) -> bool:
    return count_alive(team) == 0
#endregion


#region deploying
## The tile of the entry edge the soldiers get off at: the one nearest to the wagon.
func get_door_tile(team: String) -> Vector2i:
    var rect := grid_service.map_rect
    var row := rect.position.y if _trains[team]["from_top"] else rect.end.y - 1
    var wagon := get_barracks(team)
    var best := Vector2i(rect.get_center().x, row)
    if wagon == null:
        return best
    var wagon_position := combat_map.to_local(wagon.global_position)
    var best_distance := INF
    for column in range(rect.position.x, rect.end.x):
        var distance := grid_service.tile_to_world(Vector2(column, row)).distance_to(wagon_position)
        if distance < best_distance:
            best = Vector2i(column, row)
            best_distance = distance
    return best

## The free tile where the next soldier gets off, or NO_TILE if the entry zone is full.
func get_deploy_tile(team: String) -> Vector2i:
    if not _trains.has(team):
        return NO_TILE
    var rect := grid_service.map_rect
    var door := get_door_tile(team)
    var best := NO_TILE
    var best_distance := INF
    for depth in entry_depth:
        var row := door.y + depth if _trains[team]["from_top"] else door.y - depth
        for column in range(rect.position.x, rect.end.x):
            var tile := Vector2i(column, row)
            if not _can_stand(tile):
                continue
            var distance := Vector2(tile).distance_to(Vector2(door)) + depth * 0.5
            if distance < best_distance:
                best = tile
                best_distance = distance
    return best

## Is deploying allowed now, and is there a soldier and room for it?
func can_deploy(team: String, unit_id: String) -> bool:
    if not _trains.has(team) or not _trains[team]["aboard"].has(unit_id):
        return false
    if flow_manager != null and not flow_manager.can_team_act(team):
        return false
    return get_deploy_tile(team) != NO_TILE

## Puts this soldier on the battlefield. Returns it, or null if it can't be (see can_deploy).
func deploy(team: String, unit_id: String) -> Soldier:
    if not can_deploy(team, unit_id):
        return null
    var tile := get_deploy_tile(team)
    var data: Dictionary = _trains[team]["units"].get(unit_id, {})
    if data.is_empty() or not UnitTypes.exists(str(data.get("unit_type", ""))):
        push_warning("DeploymentManager: no valid data for unit '%s'" % unit_id)
        return null
    var soldier := battle_unit_manager.spawn_unit(team, unit_id, data, tile, get_entry_facing(team))
    if soldier == null:
        return null
    _trains[team]["aboard"].erase(unit_id)
    soldier_deployed.emit(soldier)
    return soldier

## Deploys the next soldier of the wagon.
func deploy_next(team: String) -> Soldier:
    for id in get_aboard(team):
        return deploy(team, id)
    return null
#endregion


#region boarding
## Is this soldier close enough to its door to get on? It has to be in the entry zone, so a wall
## between the soldier and the train can't be in the way.
func is_at_door(soldier: Soldier) -> bool:
    return _trains.has(soldier.team) and _in_entry_zone(soldier.team, soldier.tile) \
            and Vector2(soldier.tile).distance_to(Vector2(get_door_tile(soldier.team))) <= board_range

## The soldier gets on its train now, if it is at the door, standing still, and there is room.
func board(soldier: Soldier) -> bool:
    if not _trains.has(soldier.team) or not soldier.is_alive() or soldier.get_action() != &"idle":
        return false
    if not is_at_door(soldier) or get_aboard(soldier.team).size() >= get_capacity(soldier.team):
        return false
    var team: String = soldier.team
    var unit_id := soldier.unit_id
    var data: Dictionary = _trains[team]["units"].get(unit_id, {})
    data["hp"] = soldier.hp # it keeps its wounds
    _trains[team]["units"][unit_id] = data
    _trains[team]["aboard"].append(unit_id)
    _pending_board.erase(soldier)
    battle_unit_manager.remove_soldier(soldier)
    soldier_boarded.emit(unit_id, team)
    return true

## Gets the soldier back on its train: boards at once if it is at the door, otherwise walks there
## (an order, like any other) and boards when it arrives. Returns false if it can't even start.
func order_board(soldier: Soldier) -> bool:
    if not _trains.has(soldier.team) or not soldier.is_alive():
        return false
    if get_aboard(soldier.team).size() >= get_capacity(soldier.team):
        return false
    if is_at_door(soldier):
        if soldier.get_action() == &"idle":
            return board(soldier)
        return false
    var spot := _find_boarding_spot(soldier)
    if spot == NO_TILE or not battle_unit_manager.command_move(soldier, spot):
        return false
    _pending_board[soldier] = true
    return true

func _process(_delta: float) -> void:
    for key in _pending_board.keys(): # untyped: a soldier that boarded or died may be freed already
        if not is_instance_valid(key) or not (key as Soldier).is_alive():
            _pending_board.erase(key)
        elif (key as Soldier).get_action() == &"idle":
            # it arrived, or ran out of action points on the way: the owner gives the order again
            board(key)
            _pending_board.erase(key)

# The free tile at the door nearest to the soldier
func _find_boarding_spot(soldier: Soldier) -> Vector2i:
    var door := get_door_tile(soldier.team)
    var best := NO_TILE
    var best_distance := INF
    var reach := ceili(board_range)
    for dy in range(-reach, reach + 1):
        for dx in range(-reach, reach + 1):
            var tile := door + Vector2i(dx, dy)
            if Vector2(tile).distance_to(Vector2(door)) > board_range or not _in_entry_zone(soldier.team, tile) \
                    or not _can_stand(tile, soldier):
                continue
            var distance := Vector2(tile).distance_to(Vector2(soldier.tile))
            if distance < best_distance:
                best = tile
                best_distance = distance
    return best
#endregion


# The first `entry_depth` rows from the entry edge of the team
func _in_entry_zone(team: String, tile: Vector2i) -> bool:
    var rect := grid_service.map_rect
    var depth := tile.y - rect.position.y if _trains[team]["from_top"] else rect.end.y - 1 - tile.y
    return depth >= 0 and depth < entry_depth

func _can_stand(tile: Vector2i, ignore: Object = null) -> bool:
    return grid_service.is_inside_map(tile) and terrain_service.is_walkable(tile) \
            and occupancy_service.is_free(tile, TileOccupancyService.LAYER_ALL, ignore)
