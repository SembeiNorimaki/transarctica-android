class_name UnitAttackState
extends UnitState
# Shooting at a target. Params of enter(): {"target": Soldier}.
# After a short windup the soldier emits attack_fired; the managers decide whether it hits and how
# hard. Then the weapon cools down and the soldier goes idle.

var _target: Soldier = null
var _fired := false
var _time := 0.0
var _weapon := {}


func enter(params = {}) -> void:
    _target = params.get("target", null)
    if _target == null or not is_instance_valid(_target) or not _target.is_alive():
        change_to(&"IdleState")
        return
    _weapon = unit.get_weapon()
    _fired = false
    _time = 0.0
    unit.face_towards(_target.tile)


func exit(_next_state = &"") -> void:
    _target = null


func update(delta: float) -> void:
    if _target == null:
        return
    _time += delta
    if not _fired:
        if not is_instance_valid(_target) or not _target.is_alive():
            change_to(&"IdleState")
            return
        unit.face_towards(_target.tile)
        if _time >= float(_weapon["windup"]):
            _fired = true
            _time = 0.0
            unit.attack_fired.emit(unit, _target)
    elif _time >= float(_weapon["cooldown"]):
        change_to(&"IdleState")


func describe() -> String:
    return "ATTACKING %s" % (_target.unit_id if is_instance_valid(_target) else "-")
