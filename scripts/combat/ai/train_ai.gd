extends Node
class_name TrainAI
# The AI of a train: it runs the train and its barracks wagon for one team. It does what the
# CombatAI above it orders:
#   deploy_wanted : how many soldiers it wants on the battlefield. It lets them off one by one
#                   (`deploy_interval` apart) until there are that many, if it has them.
#   recall        : soldiers on the battlefield are told to come back to the train.
#   depart        : once nobody is outside, the train drives away (the team flees).
# It never decides on its own what to do: that is the CombatAI's job. It only gives orders through
# DeploymentManager, as the player does, so the flow manager's rules apply to it too.

## The train drove off the screen (see exit_x).
signal departed

@export var team := Soldier.TEAM_ENEMY
## Game seconds between two soldiers getting off.
@export var deploy_interval := 0.6
## The train is gone when its tail is past this x (world coordinates).
@export var exit_x := 2000.0
@export var departure_speed := 500.0

# Injected by the scene
var deployment_manager: DeploymentManager
var train: HorizontalTrain

var deploy_wanted := 0
var recall := false
var depart := false
var is_departing := false
var has_departed := false

var _cooldown := 0.0
var _deploy_blocked := false # the entry zone was full the last time


func setup() -> void:
    assert(deployment_manager != null and train != null, "TrainAI: not injected")


## The order of the CombatAI. Orders that don't change leave the state alone.
func set_orders(new_deploy_wanted: int, new_recall: bool, new_depart: bool) -> void:
    if new_deploy_wanted != deploy_wanted or new_recall != recall:
        _deploy_blocked = false
    deploy_wanted = new_deploy_wanted
    recall = new_recall
    depart = new_depart

func _process(delta: float) -> void:
    _cooldown = maxf(_cooldown - delta, 0.0)
    if is_departing and not has_departed and is_instance_valid(train) \
            and train.position.x - train.train_length > exit_x:
        has_departed = true
        train.set_speed(0.0)
        departed.emit()

## Does one round of the train's decisions. Returns how many orders it gave.
func think() -> int:
    if has_departed or is_departing:
        return 0
    var orders := 0
    if recall:
        for soldier in deployment_manager.get_field_soldiers(team):
            if soldier.get_action() == &"idle" and deployment_manager.order_board(soldier):
                orders += 1
    elif _wants_to_deploy() and _cooldown <= 0.0:
        if deployment_manager.deploy_next(team) != null:
            _cooldown = deploy_interval
            orders += 1
        else:
            _deploy_blocked = true
    if depart and deployment_manager.get_field_soldiers(team).is_empty() and orders == 0:
        _start_departure()
        orders += 1
    return orders

## Is it in the middle of something that will take a while (waiting to deploy the next soldier,
## driving away)? The CombatAI doesn't end a turn while this is true.
func is_busy() -> bool:
    return is_departing or (_wants_to_deploy() and not recall)

func _wants_to_deploy() -> bool:
    return not _deploy_blocked and not recall and not deployment_manager.get_aboard(team).is_empty() \
            and deployment_manager.get_field_soldiers(team).size() < deploy_wanted

func _start_departure() -> void:
    is_departing = true
    train.max_speed = departure_speed
    train.drive()
