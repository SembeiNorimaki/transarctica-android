extends CombatFlowManager
class_name RtsManager
# Real time combat. Everybody acts at once, whenever they are given an order, with no limit but
# the time things take. Orders can be given while the game is paused.
#
# A battle is real time when this node is a child of the scene's Managers (see TurnManager for
# turn based). Soldiers that stand idle shoot at an enemy they can see and reach from where they
# are, so a fight goes on without orders (`auto_engage`). Pausing and the game speed use
# Engine.time_scale, which is put back to 1 when this node leaves the scene.

@export var auto_engage := true
@export var engage_interval := 0.25
## 1 is normal speed.
@export var game_speed := 1.0:
    set(value):
        game_speed = maxf(value, 0.0)
        _apply_time_scale()

var paused := false

var _engage_timer := 0.0


func get_mode_name() -> String:
    return "Real time"

func get_status_text() -> String:
    return "%s%s" % [get_mode_name(), " | PAUSED" if paused else ""]

func start() -> void:
    _apply_time_scale()
    super.start()

func set_paused(value: bool) -> void:
    paused = value
    _apply_time_scale()
    status_changed.emit()

func toggle_pause() -> void:
    set_paused(not paused)

func _exit_tree() -> void:
    Engine.time_scale = 1.0

func _apply_time_scale() -> void:
    Engine.time_scale = 0.0 if paused else game_speed


func _process(delta: float) -> void:
    if not auto_engage or paused:
        return
    _engage_timer += delta
    if _engage_timer < engage_interval:
        return
    _engage_timer = 0.0
    for soldier in battle_unit_manager.soldiers:
        if soldier.is_alive() and soldier.get_action() == &"idle":
            _try_to_fire(soldier)

# The nearest enemy it can see and hit from where it stands
func _try_to_fire(soldier: Soldier) -> void:
    var best: Soldier = null
    var best_distance := INF
    for other in battle_unit_manager.soldiers:
        if other.team == soldier.team or not other.is_alive():
            continue
        if visibility_service != null and not visibility_service.is_visible(soldier.team, other.tile):
            continue
        if not battle_unit_manager.can_shoot(soldier, soldier.tile, other):
            continue
        var distance := Vector2(soldier.tile).distance_to(Vector2(other.tile))
        if distance < best_distance:
            best = other
            best_distance = distance
    if best != null:
        soldier.order_attack(best)
