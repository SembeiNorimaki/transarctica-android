extends Node
class_name StateMachine
# A generic state machine. It is a node, and each state is a CHILD node that extends GenericState,
# so the owner's scene tree shows whether it has a state machine and which states it has:
#
#   Unit
#   └── StateMachine            (this script)
#       ├── IdleState           (extends GenericState)
#       ├── MoveState
#       └── AttackState
#
# The owner is the parent of the StateMachine. The first state is `initial_state`; if that is
# empty, it is "IdleState" when there is one, and otherwise the first child state.
#
# Changing state: a state calls change_to("MoveState", {...}), or anyone calls set_state().
# A change asked for DURING enter(), exit() or update() of a state waits until that call returns,
# so a state is never half-way through a method when it is left.
#
# The owner can follow the changes with the state_changed signal, e.g. for a debug label:
#   $StateMachine.state_changed.connect(func(_previous, next): update_state_label(next))

# Emitted after the new state has been entered
signal state_changed(previous: StringName, next: StringName)

const MAX_CHAINED_CHANGES := 16 # states asking for a change from enter() in a loop would never end

@export var initial_state: StringName = &""
@export var active := true: # false: update() is not called, and the state machine only waits
    set(value):
        active = value
        _update_processing()
@export var update_in_physics := false: # true: update() runs in _physics_process
    set(value):
        update_in_physics = value
        _update_processing()
@export var forward_input := false: # true: unhandled input events go to the state's handle_input()
    set(value):
        forward_input = value
        set_process_unhandled_input(value)

var owner_node: Node = null
var id := "" # the name of the owner, for debug messages
var current_state: GenericState = null
var states: Dictionary[StringName, GenericState] = {} # state name -> state, e.g. {&"IdleState": <IdleState>}

var _started := false
var _busy := false # inside enter(), exit() or update() of a state
var _queued: Array = [] # a change asked for while busy: [state name, params]


func _ready() -> void:
    owner_node = get_parent()
    id = str(owner_node.name)

    # Discover the child states
    for child in get_children():
        if child is GenericState:
            register_state(child)
        else:
            push_warning("StateMachine %s: child '%s' is not a GenericState, so it is not a state" % [id, child.name])
    if states.is_empty():
        push_error("StateMachine %s has no states: add GenericState nodes as children" % id)
        return

    _update_processing()
    set_process_unhandled_input(forward_input)

    # The states are ready before this node, and the owner after it: wait for the owner, so the
    # first enter() can use anything the owner sets up in its own _ready()
    if not owner_node.is_node_ready():
        await owner_node.ready
    start()


#region setup
# Adds a state. The children are registered automatically; call this for a state created in code
# (add it as a child first).
func register_state(state: GenericState) -> void:
    if states.has(state.name):
        push_error("StateMachine %s: two states are called '%s'" % [id, state.name])
        return
    states[state.name] = state
    state.setup(owner_node, self)


# Enters the first state. Called by itself; call it yourself only after stop().
func start() -> void:
    if _started or states.is_empty():
        return
    _started = true
    var first: StringName = initial_state
    if first.is_empty():
        first = &"IdleState" if states.has(&"IdleState") else states.keys()[0]
    if not states.has(first):
        push_error("StateMachine %s: initial state '%s' does not exist" % [id, first])
        first = states.keys()[0]
    set_state(first)


# Leaves the current state and goes idle, e.g. when the owner dies. start() restarts it.
func stop() -> void:
    if current_state != null and not _busy:
        current_state.exit(&"")
    current_state = null
    _queued.clear()
    _started = false
#endregion


#region changing state
# `params` are given to the new state's enter()
func set_state(new_state: StringName, params := {}) -> void:
    if not states.has(new_state):
        push_error("StateMachine %s: there is no state '%s' (states: %s)" % [id, new_state, states.keys()])
        return
    if _busy:
        _queued = [new_state, params] # only the last request counts
        return
    _change(new_state, params)
    _flush_queue()


func _change(new_state: StringName, params: Dictionary) -> void:
    var previous := current_state
    var previous_name: StringName = previous.name if previous != null else &""
    _busy = true
    if previous != null:
        previous.exit(new_state)
    current_state = states[new_state]
    current_state.enter(params)
    _busy = false
    state_changed.emit(previous_name, new_state)


# Applies the changes asked for during a state's call, one after the other
func _flush_queue() -> void:
    var count := 0
    while not _queued.is_empty():
        count += 1
        if count > MAX_CHAINED_CHANGES:
            push_error("StateMachine %s: more than %d changes in a row (last: '%s'), stopped" % [id, MAX_CHAINED_CHANGES, _queued[0]])
            _queued.clear()
            return
        var request := _queued
        _queued = []
        _change(request[0], request[1])
#endregion


#region queries
func get_current_state() -> StringName:
    return current_state.name if current_state != null else &""


func is_in_state(state_name: StringName) -> bool:
    return current_state != null and current_state.name == state_name


func has_state(state_name: StringName) -> bool:
    return states.has(state_name)
#endregion


#region update and input
func _update_processing() -> void:
    set_process(active and not update_in_physics)
    set_physics_process(active and update_in_physics)


func _process(delta: float) -> void:
    _update(delta)


func _physics_process(delta: float) -> void:
    _update(delta)


func _update(delta: float) -> void:
    if current_state == null:
        return # not started yet (or stopped)
    _busy = true
    current_state.update(delta)
    _busy = false
    _flush_queue()


func handle_click(tile: Vector2i) -> void:
    if current_state != null:
        current_state.handle_click(tile)


func _unhandled_input(event: InputEvent) -> void:
    if current_state != null:
        current_state.handle_input(event)
#endregion
