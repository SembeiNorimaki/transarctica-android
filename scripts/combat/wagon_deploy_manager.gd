extends Node
class_name WagonDeployManager
# Units getting off the wagons of a train in a tile based battle where the train stands next to the
# map (the city). Each barracks or vehicle carrier wagon has its units aboard; deploy() puts one on the
# free tile of the deploy area that is nearest to the wagon, as BattleUnitManager.spawn_unit does, and
# the unit is no longer aboard. A vehicle needs room for its whole footprint, so a 2x2 tank is put where
# 2x2 tiles are free.
#
# The units' data is a copy: what happens to them in the battle does not touch the campaign's units.
# The manager owns the placement; the views (UnitHud) only ask for it (see CombatSceneCity).

## A unit left the wagon and is on the battlefield.
signal unit_deployed(wagon: GenericWagon, soldier: Soldier)
## The units aboard this wagon changed.
signal aboard_changed(wagon: GenericWagon)

const NO_TILE := Vector2i(-99999, -99999)

## The tiles where units may get off: the ground next to the train (tile coordinates).
@export var deploy_area := Rect2i(0, 0, 0, 0)
## A unit is only put where it can walk to this tile (somewhere out in the open, like an avenue), so
## nobody gets off into a closed pocket. NO_TILE: no such rule.
@export var exit_tile := NO_TILE
## Which way they face when they get off.
@export var deploy_facing := "NW"
## The team of the train.
@export var team := Soldier.TEAM_PLAYER

# Injected by the scene
var battle_unit_manager: BattleUnitManager
var grid_service: GridService
var occupancy_service: TileOccupancyService
var terrain_service: TerrainService
var pathfinding_service: PathfindingService # only needed with an exit_tile
var combat_map: CombatMap
## Optional. Without it, deploying is always allowed.
var flow_manager: CombatFlowManager

var _aboard := {} # GenericWagon -> Array[String]: the unit ids in it
var _units := {} # unit id -> data (see UnitTypes.make_unit)


func setup() -> void:
    assert(battle_unit_manager != null and grid_service != null and occupancy_service != null \
            and terrain_service != null and combat_map != null, "WagonDeployManager: not injected")


#region the units aboard
## The wagon carries these units. `units` is unit id -> data, for at least the ids of the wagon.
## A wagon that is not a place for units (it stores no soldiers nor vehicles) can be added too: it has none.
func add_wagon(wagon: GenericWagon, unit_ids: Array, units: Dictionary) -> void:
    var ids: Array[String] = []
    for id in unit_ids:
        var data: Dictionary = units.get(str(id), {})
        if data.is_empty() or not UnitTypes.exists(str(data.get("unit_type", ""))):
            push_warning("WagonDeployManager: no valid data for unit '%s'" % id)
            continue
        ids.append(str(id))
        _units[str(id)] = data
    _aboard[wagon] = ids

func has_wagon(wagon: GenericWagon) -> bool:
    return _aboard.has(wagon)

## Can units be taken from this wagon (a barracks or a vehicle carrier), empty or not?
func carries_units(wagon: GenericWagon) -> bool:
    return wagon != null and (wagon.stores.has("Soldiers") or wagon.stores.has("Vehicles"))

## The unit ids aboard, in the order they will leave.
func get_aboard(wagon: GenericWagon) -> Array[String]:
    var result: Array[String] = []
    result.assign(_aboard.get(wagon, []))
    return result

func get_unit_data(unit_id: String) -> Dictionary:
    return _units.get(unit_id, {})

func count_aboard() -> int:
    var count := 0
    for ids: Array in _aboard.values():
        count += ids.size()
    return count
#endregion


#region deploying
## The free tile of the deploy area, nearest to the wagon, where this type fits (and from where it can
## walk to the exit tile, if there is one). NO_TILE if there is none.
func get_deploy_tile(wagon: GenericWagon, unit_type: String) -> Vector2i:
    var footprint := UnitTypes.get_footprint(unit_type)
    var from := combat_map.to_local(wagon.global_position)
    var candidates: Array[Dictionary] = []
    for y in range(deploy_area.position.y, deploy_area.end.y):
        for x in range(deploy_area.position.x, deploy_area.end.x):
            var tile := Vector2i(x, y)
            if _fits(tile, footprint):
                candidates.append({"tile": tile, "distance": grid_service.tile_to_world(Vector2(tile)).distance_to(from)})
    candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance"] < b["distance"])
    var profile := MoveProfile.new()
    profile.footprint = footprint
    profile.goal_may_be_occupied = true # somebody standing at the exit does not close it
    for candidate in candidates:
        if exit_tile == NO_TILE or pathfinding_service == null:
            return candidate["tile"]
        if not pathfinding_service.find_path(candidate["tile"], exit_tile, profile).is_empty() \
                and not _would_trap_a_unit(candidate["tile"], footprint):
            return candidate["tile"]
    return NO_TILE

func can_deploy(wagon: GenericWagon, unit_id: String) -> bool:
    if not _aboard.has(wagon) or not _aboard[wagon].has(unit_id):
        return false
    if flow_manager != null and not flow_manager.can_team_act(team):
        return false
    return get_deploy_tile(wagon, str(_units[unit_id].get("unit_type", ""))) != NO_TILE

## Puts this unit of the wagon on the battlefield. Returns it, or null if it can't be (see can_deploy).
func deploy(wagon: GenericWagon, unit_id: String) -> Soldier:
    if not can_deploy(wagon, unit_id):
        return null
    var data: Dictionary = _units[unit_id]
    var tile := get_deploy_tile(wagon, str(data.get("unit_type", "")))
    var soldier := battle_unit_manager.spawn_unit(team, unit_id, data, tile, deploy_facing)
    if soldier == null:
        return null
    _aboard[wagon].erase(unit_id)
    _update_wagon_picture(wagon)
    unit_deployed.emit(wagon, soldier)
    aboard_changed.emit(wagon)
    return soldier

## Deploys everything of the wagon, as far as there is room. Returns the units that got off.
func deploy_all(wagon: GenericWagon) -> Array[Soldier]:
    var result: Array[Soldier] = []
    for id in get_aboard(wagon):
        var soldier := deploy(wagon, id)
        if soldier != null:
            result.append(soldier)
    return result
#endregion


# Would a unit here shut in one of the units already out, which can now walk to the exit?
func _would_trap_a_unit(anchor: Vector2i, footprint: Footprint) -> bool:
    var new_tiles := {}
    for offset in footprint.offsets:
        new_tiles[anchor + offset] = true
    for soldier in battle_unit_manager.soldiers:
        if soldier.team != team or not soldier.is_alive():
            continue
        var profile := MoveProfile.new()
        profile.ignore = soldier
        profile.footprint = soldier.footprint
        profile.goal_may_be_occupied = true
        if pathfinding_service.find_path(soldier.tile, exit_tile, profile).is_empty():
            continue # it was shut in before
        profile.can_enter = func(tile: Vector2i) -> bool: return not new_tiles.has(tile)
        if pathfinding_service.find_path(soldier.tile, exit_tile, profile).is_empty():
            return true
    return false

# A wagon that shows its vehicles (the vehicle carrier) shows only those that are still aboard
func _update_wagon_picture(wagon: GenericWagon) -> void:
    if not wagon.has_method("set_unit_types"):
        return
    var types: Array[String] = []
    for id: String in _aboard[wagon]:
        types.append(str(_units[id].get("unit_type", "")))
    wagon.call("set_unit_types", types)

func _fits(anchor: Vector2i, footprint: Footprint) -> bool:
    for offset in footprint.offsets:
        var tile := anchor + offset
        if not grid_service.is_inside_map(tile) or not terrain_service.is_walkable(tile):
            return false
    return occupancy_service.is_footprint_free(anchor, footprint, TileOccupancyService.LAYER_ALL)
