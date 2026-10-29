class_name UnitState
extends GenericState
# Base of the action states of a Soldier (idle, move, attack, dead). `unit` is the soldier.

var unit: Soldier


func _setup() -> void:
    unit = owner_node as Soldier
    assert(unit != null, "%s must be a child of the StateMachine of a Soldier" % name)


## Short text for the soldier's status label.
func describe() -> String:
    return String(name).trim_suffix("State").to_upper()
