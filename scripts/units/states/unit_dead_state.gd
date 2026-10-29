class_name UnitDeadState
extends UnitState
# Dead: nothing more happens. Once a soldier is here it never leaves.


func enter(_params = {}) -> void:
    unit.on_death()


func describe() -> String:
    return "DEAD"
