extends Node
class_name CombatAI
# The top AI of a computer team. It does not move anybody: it looks at the battle, decides what the
# team should be doing (its stance), and gives orders to the two AIs under it, which are its
# children in the scene:
#   TrainAI : lets soldiers off the train, calls them back, drives the train away.
#   UnitAI  : moves and fights with the soldiers on the battlefield.
#
# Stance, from the balance of forces (what the team has, against what it knows of the enemy):
#   ATTACK  : strong enough. All soldiers off the train, and go for the enemy.
#   DEFEND  : about even. Part of the soldiers off the train, holding near it.
#   RETREAT : too weak. Everybody back on the train, which drives away.
# Once it retreats it keeps at it: a fleeing train does not come back.
#
# It works the same in both combat modes. Real time: it thinks every `think_interval`. Turn based:
# it thinks the same way during its team's turn and ends the turn when nobody has anything left to
# do (TurnManager.auto_pass_computer_turns must be off, or the turn ends by itself).

signal stance_changed(stance: UnitAI.Stance)
## The AI's team gave up and its train left.
signal fled

@export var team := Soldier.TEAM_ENEMY
@export var enabled := true
## Game seconds between two rounds of thinking.
@export var think_interval := 0.5
## The team attacks when it has at least this many times the enemy's strength.
@export var attack_ratio := 0.75
## Below this many times the enemy's strength it retreats.
@export var retreat_ratio := 0.35
## Seconds a stance lasts at least, so it does not change its mind all the time.
@export var min_stance_time := 4.0
## What the AI supposes about the enemy soldiers it has not seen yet: each one has this much hp.
@export var assumed_enemy_hp := 100.0

# Injected by the scene
var battle_unit_manager: BattleUnitManager
var deployment_manager: DeploymentManager
var flow_manager: CombatFlowManager

@onready var train_ai: TrainAI = $TrainAI
@onready var unit_ai: UnitAI = $UnitAI

var stance := UnitAI.Stance.DEFEND
var fleeing := false
## What it believes: strengths of both sides and their ratio (for the HUD and tests).
var my_strength := 0.0
var enemy_strength := 0.0
var strength_ratio := 1.0

var _timer := 0.0
var _stance_time := 0.0
var _assumed_enemies := -1 # how many enemy soldiers it supposes there were at the start
var _enemies_killed := 0


# Call once, after the injection and after the flow manager and the trains are ready
func setup() -> void:
    assert(battle_unit_manager != null and deployment_manager != null and flow_manager != null,
            "CombatAI: not injected")
    train_ai.team = team
    unit_ai.team = team
    train_ai.setup()
    unit_ai.setup()
    train_ai.departed.connect(_on_departed)
    battle_unit_manager.soldier_died.connect(_on_soldier_died)
    # It assumes the enemy has as many soldiers as it has itself, until it learns better
    _assumed_enemies = deployment_manager.count_alive(team)
    _stance_time = min_stance_time # decides its first stance at once


func get_enemy_team() -> String:
    return Soldier.TEAM_PLAYER if team == Soldier.TEAM_ENEMY else Soldier.TEAM_ENEMY

## One line for the HUD.
func get_status_text() -> String:
    var stances := ["ATTACK", "DEFEND", "RETREAT"]
    return "AI %s: %s | strength %d vs %d%s | deploy %d%s" % [team, stances[stance], my_strength, enemy_strength,
            " (fled)" if train_ai.has_departed else "", train_ai.deploy_wanted, " | recall" if train_ai.recall else ""]


func _process(delta: float) -> void:
    if not enabled or flow_manager.battle_over or train_ai.has_departed:
        return
    _stance_time += delta
    _timer += delta
    if _timer < think_interval:
        return
    _timer = 0.0
    think()


## One round: assess the battle, choose a stance, give the orders. In turn based combat, only in
## its team's turn; the turn ends when there is nothing more to do.
func think() -> void:
    var turn_manager := flow_manager as TurnManager
    if turn_manager != null and turn_manager.current_team != team:
        return
    _assess()
    _choose_stance()
    _give_orders()
    var orders := train_ai.think() + unit_ai.think()
    if turn_manager != null and orders == 0 and not train_ai.is_busy() and not unit_ai.is_busy():
        turn_manager.end_turn()


#region assessing
# Strength: the hp of the soldiers, on the battlefield and in the train. The enemy's is what the
# team has seen of it (the soldiers in sight now, plus the last it knew of the others) and, for
# the soldiers it never saw, a guess.
func _assess() -> void:
    my_strength = _strength_of(team)
    var known := 0.0
    var known_enemies := unit_ai.get_known_enemies()
    for soldier in known_enemies:
        known += float(soldier.hp)
    var known_count := known_enemies.size()
    # The AI sees only some of them: those in sight are certain, the rest of the guess is the unknown
    var unknown := maxi(_assumed_enemies - _enemies_killed - known_count, 0)
    enemy_strength = known + float(unknown) * assumed_enemy_hp
    strength_ratio = my_strength / maxf(enemy_strength, 1.0)

func _strength_of(for_team: String) -> float:
    var total := 0.0
    for soldier in deployment_manager.get_field_soldiers(for_team):
        total += float(soldier.hp)
    for id in deployment_manager.get_aboard(for_team):
        total += float(deployment_manager.get_unit_data(for_team, id).get("hp", 0))
    return total

func _choose_stance() -> void:
    if fleeing:
        return
    var wanted := stance
    if strength_ratio < retreat_ratio:
        wanted = UnitAI.Stance.RETREAT
    elif strength_ratio >= attack_ratio:
        wanted = UnitAI.Stance.ATTACK
    else:
        wanted = UnitAI.Stance.DEFEND
    if wanted == stance or _stance_time < min_stance_time:
        return
    stance = wanted
    _stance_time = 0.0
    fleeing = stance == UnitAI.Stance.RETREAT
    stance_changed.emit(stance)
#endregion


#region ordering
func _give_orders() -> void:
    var enemy_team := get_enemy_team()
    var alive := deployment_manager.count_alive(team)
    var objective := deployment_manager.get_door_tile(enemy_team) if deployment_manager.has_train(enemy_team) \
            else deployment_manager.get_door_tile(team)
    var home := deployment_manager.get_door_tile(team)
    match stance:
        UnitAI.Stance.ATTACK:
            train_ai.set_orders(alive, false, false)
        UnitAI.Stance.DEFEND:
            train_ai.set_orders(maxi(ceili(alive * 0.6), 1), false, false)
        UnitAI.Stance.RETREAT:
            train_ai.set_orders(0, true, true)
    unit_ai.set_orders(stance, objective, home)
#endregion


func _on_soldier_died(soldier: Soldier) -> void:
    if soldier.team != team:
        _enemies_killed += 1

func _on_departed() -> void:
    fled.emit()
