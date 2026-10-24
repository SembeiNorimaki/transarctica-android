extends Node
class_name TradeUnitManager
# Spawns and controls the soldiers the city recruits in the trade scene: one TradeUnit per soldier
# type. Like TradeWagonManager, it owns placement: it adds the nodes to the injected container.
# It knows nothing about inventories or trading: the scene tells it what to show, and it relays
# the clicks.

signal unit_clicked(unit_type: String)

const UNIT_SCENE: PackedScene = preload("res://scenes/trade_resources/trade_unit.tscn")

# Where the soldiers go, in the container's coordinates (their centers).
# Replace with set_slot_positions(), e.g. from Marker2D nodes in the scene.
const DEFAULT_SLOTS: Array[Vector2] = [
    Vector2(800, 300), Vector2(1000, 300), Vector2(1200, 300),
]

# Injected by TradeScene
var unit_container: Node2D

var trade_units := {} # unit type -> TradeUnit

var _slots: Array[Vector2] = DEFAULT_SLOTS.duplicate()
var _slot_of := {} # unit type -> index of its slot (slots are reused when a soldier type is removed)


#region spawning
# Call before spawning any soldier.
func set_slot_positions(positions: Array[Vector2]) -> void:
    _slots = positions.duplicate()
    _slot_of.clear()


# Creates the soldier in the first free slot. Returns null (with an error) if it can't.
func spawn_unit(unit_type: String, qty: int) -> TradeUnit:
    if unit_container == null:
        push_error("TradeUnitManager: unit_container not injected")
        return null
    if trade_units.has(unit_type):
        push_error("TradeUnitManager: '%s' is already spawned" % unit_type)
        return null
    if not UnitTypes.exists(unit_type):
        push_error("TradeUnitManager: unknown unit type '%s'" % unit_type)
        return null
    var slot := _find_free_slot()
    if slot < 0:
        push_error("TradeUnitManager: no free slot for '%s' (%d slots)" % [unit_type, _slots.size()])
        return null

    var unit := UNIT_SCENE.instantiate() as TradeUnit
    unit.position = _slots[slot]
    unit.set_unit_type(unit_type) # safe before the node is in the tree
    unit.set_qty(qty)
    unit.clicked.connect(_on_unit_clicked)

    unit_container.add_child(unit)
    trade_units[unit_type] = unit
    _slot_of[unit_type] = slot
    return unit


# The city has no more of this soldier: it leaves, and its slot becomes free
func remove_unit(unit_type: String) -> void:
    var unit := get_unit(unit_type)
    if unit != null:
        unit.queue_free()
    trade_units.erase(unit_type)
    _slot_of.erase(unit_type)


func clear_units() -> void:
    for unit: TradeUnit in trade_units.values():
        if is_instance_valid(unit):
            unit.queue_free()
    trade_units.clear()
    _slot_of.clear()


func _find_free_slot() -> int:
    var used := _slot_of.values()
    for i in _slots.size():
        if not used.has(i):
            return i
    return -1
#endregion


func get_unit(unit_type: String) -> TradeUnit:
    return trade_units.get(unit_type)


func set_unit_qty(unit_type: String, qty: int) -> void:
    var unit := get_unit(unit_type)
    if unit != null:
        unit.set_qty(qty)


func _on_unit_clicked(unit: TradeUnit) -> void:
    unit_clicked.emit(unit.unit_type)
