extends Node
class_name GenericState
# Base of the states of a StateMachine. A state is a child node of the StateMachine; its node name
# is the name of the state. Override the methods below (they all do nothing by default).
#
#   extends GenericState
#   class_name IdleState
#
#   func enter(_params = {}):
#       owner_node.play("idle")
#
#   func update(delta: float):
#       if owner_node.sees_enemy():
#           change_to(&"AttackState", {"target": owner_node.enemy})
#
# A state gets what it needs from `owner_node` (the node that owns the state machine) and can
# ask for another state with change_to().

var owner_node: Node # the node that has the state machine (its parent)
var state_machine: StateMachine


# Called by the StateMachine when it finds the state, BEFORE the first enter(). Not for you to call.
func setup(new_owner: Node, machine: StateMachine) -> void:
    owner_node = new_owner
    state_machine = machine
    _setup()


#region to override
# Once, when the state machine has found the state. owner_node and state_machine are set.
# The place to find nodes or connect signals (the state's own _ready() runs before they are set).
func _setup() -> void:
    pass


# The state is now the current one. `params` are what change_to() / set_state() gave.
func enter(_params = {}):
    pass


# The state is about to be left. `next_state` is the name of the state that comes next
# (empty if the state machine is stopping).
func exit(_next_state = &""):
    pass


# Every frame (or every physics frame), while this is the current state
func update(_delta: float):
    pass


# The owner forwards a click on a tile to the current state
func handle_click(_tile: Vector2i):
    pass


# Unhandled input events, if the StateMachine has forward_input on
func handle_input(_event: InputEvent):
    pass
#endregion


# Asks the state machine for another state. If it is called from enter(), exit() or update() it
# happens when that method returns.
func change_to(state_name: StringName, params := {}) -> void:
    state_machine.set_state(state_name, params)
