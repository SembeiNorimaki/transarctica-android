class_name UnitMoveState
extends UnitState
# Walking a path, one tile at a time. Params of enter(): {"path": Array[Vector2i], "then_attack": Soldier}.
# The path starts at the soldier's own tile. `then_attack` (optional) is attacked on arrival.
#
# Before each step the soldier asks its `can_step` rule; if the step is not allowed it stops where it
# is and never enters the tile. At the start of a step the soldier's `tile` is already the tile it
# is walking to (that tile is reserved), and `step_started` fires so the managers can follow.

var _path: Array[Vector2i] = []
var _index := 1 # the path tile being walked to
var _then_attack: Soldier = null
var _pending := {} # a new order received during a step: starts when the step ends
var _stepping := false
var _from_pos := Vector2.ZERO
var _to_pos := Vector2.ZERO
var _duration := 0.3
var _time := 0.0


func enter(params = {}) -> void:
    _path.assign(params.get("path", []))
    _then_attack = params.get("then_attack", null)
    _index = 1
    _pending = {}
    _stepping = false
    if not _path.is_empty() and _path[0] != unit.tile:
        push_warning("UnitMoveState: the path of %s does not start at its tile" % unit.unit_id)
        _stop()
        return
    if _path.size() < 2:
        _arrive()
    else:
        _begin_step()


func exit(_next_state = &"") -> void:
    _stepping = false


## Another order while walking: it starts when the step in progress ends.
func redirect(path: Array[Vector2i], then_attack: Soldier = null) -> void:
    _pending = {"path": path, "then_attack": then_attack}


func update(delta: float) -> void:
    if not _stepping:
        return
    _time += delta
    var k := clampf(_time / _duration, 0.0, 1.0)
    unit.position = _from_pos.lerp(_to_pos, k)
    if k >= 1.0:
        _stepping = false
        unit.step_finished.emit(unit, unit.tile)
        _next()


## The tiles still to walk, from the one being walked to now (a new order not started yet included).
func get_path_ahead() -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    if _index < _path.size():
        result.append(_path[_index])
    if not _pending.is_empty():
        var pending: Array[Vector2i] = _pending["path"]
        for i in range(1, pending.size()):
            result.append(pending[i])
    else:
        for i in range(_index + 1, _path.size()):
            result.append(_path[i])
    return result

## Who is attacked on arrival, or null.
func get_target() -> Soldier:
    var target: Soldier = _pending["then_attack"] if not _pending.is_empty() else _then_attack
    return target if is_instance_valid(target) else null


func describe() -> String:
    if _index < _path.size():
        return "MOVING -> %s" % _path[-1]
    return "MOVING"


func _begin_step() -> void:
    var from := unit.tile
    var to := _path[_index]
    # Check first, move after: a refused step leaves the soldier on its current tile
    if unit.can_step.is_valid() and not unit.can_step.call(unit, from, to):
        unit.show_event("blocked")
        _stop()
        return
    unit.face_towards(to)
    unit.tile = to
    _from_pos = unit.position
    _to_pos = unit.grid_service.tile_to_world(Vector2(to))
    var diagonal := from.x != to.x and from.y != to.y
    _duration = (1.4142135 if diagonal else 1.0) / maxf(unit.move_speed, 0.1)
    _time = 0.0
    _stepping = true
    unit.step_started.emit(unit, from, to)
    unit.refresh_labels()


func _next() -> void:
    if not _pending.is_empty():
        _path.assign(_pending["path"])
        _then_attack = _pending["then_attack"]
        _pending = {}
        _index = 1
    else:
        _index += 1
    if _index >= _path.size():
        _arrive()
    else:
        _begin_step()


func _arrive() -> void:
    if _then_attack != null and is_instance_valid(_then_attack) and _then_attack.is_alive():
        change_to(&"AttackState", {"target": _then_attack})
    else:
        _stop()


func _stop() -> void:
    change_to(&"IdleState")
