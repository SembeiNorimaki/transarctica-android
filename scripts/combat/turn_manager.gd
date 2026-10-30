extends CombatFlowManager
class_name TurnManager
# Turn based combat. Teams play one after the other. In its turn a soldier spends action points
# (AP): a step costs the terrain cost of the tile it enters (a diagonal step a bit more), a shot
# costs the weapon's ap_cost. A soldier can't do more than its AP allow, and only the team whose
# turn it is can be commanded. AP come back, in full, at the start of the team's turn.
#
# A battle is turn based when this node is a child of the scene's Managers (see RtsManager for real
# time). Teams in `computer_teams` have no AI yet: their turn passes after `computer_turn_delay`.

signal turn_started(team: String, number: int)
signal turn_ended(team: String)

## The order the teams play in.
@export var teams: Array[String] = [Soldier.TEAM_PLAYER, Soldier.TEAM_ENEMY]
## Teams the player does not command.
@export var computer_teams: Array[String] = [Soldier.TEAM_ENEMY]
## true: a computer team's turn passes by itself after `computer_turn_delay` (there is no AI yet).
## false: an AI plays it and calls end_turn() when done (see CombatAI); `computer_turn_timeout`
## ends the turn anyway if the AI never does.
@export var auto_pass_computer_turns := true
@export var computer_turn_timeout := 30.0
## The turn ends by itself when nobody of the team can do anything any more.
@export var auto_end_turn := true
@export var computer_turn_delay := 0.8
## Below this many AP a soldier can't do anything (the cheapest step).
@export var min_action_cost := 1.0

var current_team := ""
var turn_number := 0 # 1 for the first turn of the first team, up by one each time the first team plays again

var _team_index := 0
var _started := false
var _end_requested := false
var _computer_timer := 0.0


func get_mode_name() -> String:
    return "Turn based"

func get_status_text() -> String:
    if battle_over:
        return "%s | battle over" % get_mode_name()
    if not _started:
        return get_mode_name()
    return "%s | turn %d | %s%s" % [get_mode_name(), turn_number, current_team, " (computer)" if is_computer_turn() else ""]

func start() -> void:
    if teams.is_empty():
        push_error("TurnManager: no teams")
        return
    _started = true
    turn_number = 1
    _begin_turn(0)

func is_computer_turn() -> bool:
    return current_team in computer_teams


#region the flow
## The current team is done. The turn passes when its soldiers have finished what they are doing.
func end_turn() -> void:
    if _started and not battle_over:
        _end_requested = true

func _process(delta: float) -> void:
    if not _started or battle_over:
        return
    if is_computer_turn():
        _computer_timer += delta
        var limit := computer_turn_delay if auto_pass_computer_turns else computer_turn_timeout
        if _computer_timer >= limit:
            _end_requested = true
    elif auto_end_turn and not _end_requested and _team_is_out_of_actions():
        _end_requested = true
    if _end_requested and not _team_is_busy():
        _next_turn()

func _next_turn() -> void:
    turn_ended.emit(current_team)
    _end_requested = false
    var next := (_team_index + 1) % teams.size()
    if next == 0:
        turn_number += 1
    _begin_turn(next)

func _begin_turn(index: int) -> void:
    _team_index = index
    current_team = teams[index]
    _end_requested = false
    _computer_timer = 0.0
    for soldier in battle_unit_manager.soldiers:
        if soldier.team == current_team and soldier.is_alive():
            soldier.set_action_points(soldier.max_action_points)
    turn_started.emit(current_team, turn_number)
    status_changed.emit()

func _team_is_busy() -> bool:
    for soldier in battle_unit_manager.soldiers:
        if soldier.team == current_team and soldier.is_alive() and soldier.get_action() != &"idle":
            return true
    return false

func _team_is_out_of_actions() -> bool:
    var any := false
    for soldier in battle_unit_manager.soldiers:
        if soldier.team != current_team or not soldier.is_alive():
            continue
        any = true
        if soldier.action_points >= min_action_cost or soldier.get_action() != &"idle":
            return false
    return any
#endregion


#region rules
func can_command(soldier: Soldier) -> bool:
    # Only the team whose turn it is acts. Who gives the orders (the player, an AI) is not its business:
    # the player can only select his own soldiers
    return _started and not battle_over and soldier.is_alive() and soldier.team == current_team and not _end_requested

func can_team_act(team: String) -> bool:
    return _started and not battle_over and team == current_team and not _end_requested

func limit_move(soldier: Soldier, path: Array[Vector2i]) -> Array[Vector2i]:
    var allowed: Array[Vector2i] = []
    if path.is_empty():
        return allowed
    allowed.append(path[0])
    var left := soldier.action_points
    var profile := battle_unit_manager.get_profile(soldier)
    for i in range(1, path.size()):
        var cost := pathfinding_service.step_cost(path[i - 1], path[i], profile)
        if cost > left + 0.0001:
            break
        left -= cost
        allowed.append(path[i])
    return allowed

func get_move_cost(soldier: Soldier, path: Array[Vector2i]) -> float:
    return pathfinding_service.path_cost(path, battle_unit_manager.get_profile(soldier))

func can_attack(soldier: Soldier, move_cost := 0.0) -> bool:
    return soldier.action_points + 0.0001 >= move_cost + float(soldier.get_weapon()["ap_cost"])

func _on_soldier_spawned(soldier: Soldier) -> void:
    soldier.step_started.connect(_on_step_started)
    soldier.attack_fired.connect(_on_attack_fired)
    # A soldier who arrives in the middle of the battle waits for its team's turn
    soldier.set_action_points(soldier.max_action_points if _started and soldier.team == current_team else 0.0)

func _on_step_started(soldier: Soldier, from: Vector2i, to: Vector2i) -> void:
    var cost := pathfinding_service.step_cost(from, to, battle_unit_manager.get_profile(soldier))
    soldier.set_action_points(maxf(soldier.action_points - cost, 0.0))
    status_changed.emit()

func _on_attack_fired(soldier: Soldier, _target: Soldier) -> void:
    soldier.set_action_points(maxf(soldier.action_points - float(soldier.get_weapon()["ap_cost"]), 0.0))
    status_changed.emit()
#endregion
