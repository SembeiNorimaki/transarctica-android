extends Node
class_name CombatFlowManager
# How a battle flows: base of TurnManager (turn based) and RtsManager (real time). A battle has
# exactly ONE of them, as a child of the scene's Managers node: that is what decides the mode.
#
# BattleUnitManager asks the flow manager before it gives an order, so each mode can set its own
# rules (whose turn it is, how many action points an order costs). In the base class everything is
# allowed. Do not use this class on its own: add a TurnManager or an RtsManager.

## Something about the flow changed that the HUD may want to show (a new turn, a pause...).
signal status_changed
## An order was not given. `reason` is a short text for the player.
signal command_refused(soldier: Soldier, reason: String)
## The battle is decided: nobody can be commanded any more (see end_battle).
signal battle_ended

## true once end_battle() was called.
var battle_over := false

# Injected by the scene
var battle_unit_manager: BattleUnitManager
var pathfinding_service: PathfindingService
var visibility_service: VisibilityService


# Call once, after the injection and before the soldiers are deployed
func setup() -> void:
    assert(battle_unit_manager != null, "%s: not injected" % name)
    battle_unit_manager.soldier_spawned.connect(_on_soldier_spawned)
    for soldier in battle_unit_manager.soldiers:
        _on_soldier_spawned(soldier)

# Call when the soldiers are deployed: the battle begins
func start() -> void:
    status_changed.emit()


#region to override
## "Turn based", "Real time"
func get_mode_name() -> String:
    return "Free"

## One line for the HUD.
func get_status_text() -> String:
    return get_mode_name()

## May this soldier be given an order now?
func can_command(soldier: Soldier) -> bool:
    return soldier.is_alive() and not battle_over

## May this team do things now (deploy soldiers from its train...)? Not for a soldier: for the team.
func can_team_act(_team: String) -> bool:
    return not battle_over

## The part of the path this soldier is allowed to walk now (the whole path if there is no limit).
func limit_move(_soldier: Soldier, path: Array[Vector2i]) -> Array[Vector2i]:
    return path

## What walking this path costs the soldier (action points; 0 where there is no such thing).
func get_move_cost(_soldier: Soldier, _path: Array[Vector2i]) -> float:
    return 0.0

## Can the soldier shoot after spending `move_cost` on walking?
func can_attack(_soldier: Soldier, _move_cost := 0.0) -> bool:
    return true

# A soldier joined the battle (also called for those already there by setup())
func _on_soldier_spawned(_soldier: Soldier) -> void:
    pass
#endregion


## Nobody can be commanded from now on.
func end_battle() -> void:
    if battle_over:
        return
    battle_over = true
    battle_ended.emit()
    status_changed.emit()


func refuse(soldier: Soldier, reason: String) -> void:
    soldier.show_event(reason)
    command_refused.emit(soldier, reason)
