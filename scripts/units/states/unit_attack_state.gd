class_name UnitAttackState
extends UnitState
# Shooting at a target. Params of enter(): {"target": Soldier} or {"tile": Vector2i} to shoot at a tile.
# After a short windup the soldier emits attack_fired; the managers decide whether it hits and how
# hard. Then the weapon cools down and the soldier goes idle.

var _target: Soldier = null
var _tile := Vector2i.ZERO
var _active := false
var _fired := false
var _time := 0.0
var _weapon := {}


func enter(params = {}) -> void:
    _target = params.get("target", null)
    _active = false
    if params.has("tile"):
        _tile = params["tile"]
    elif _target == null or not is_instance_valid(_target) or not _target.is_alive():
        change_to(&"IdleState")
        return
    else:
        _tile = _target.tile
    _active = true
    unit.attack_tile = _tile
    _weapon = unit.get_weapon()
    _fired = false
    _time = 0.0
    unit.face_towards(_tile)


func exit(_next_state = &"") -> void:
    _target = null
    _active = false


func update(delta: float) -> void:
    if not _active:
        return
    _time += delta
    if not _fired:
        if _target != null:
            if not is_instance_valid(_target) or not _target.is_alive():
                change_to(&"IdleState")
                return
            _tile = _target.tile
            unit.attack_tile = _tile
        unit.face_towards(_tile)
        if _time >= float(_weapon["windup"]):
            _fired = true
            _time = 0.0
            unit.attack_fired.emit(unit, _target)
    elif _time >= float(_weapon["cooldown"]):
        change_to(&"IdleState")


func get_target() -> Soldier:
    return _target if is_instance_valid(_target) else null


func describe() -> String:
    if _target == null:
        return "ATTACKING %s" % _tile
    return "ATTACKING %s" % (_target.unit_id if is_instance_valid(_target) else "-")
