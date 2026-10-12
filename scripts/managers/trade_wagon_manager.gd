extends Node
class_name TradeWagonManager
# Spawns and controls the wagons the city has for sale in the trade scene. They don't belong to
# any train. Like TradeResourceManager, it owns placement: it adds the nodes to the injected
# container. It knows nothing about inventories or trading: the scene tells it what to show,
# and it relays the clicks.

signal wagon_clicked(wagon_type: String)

# Where the wagons go, in the container's coordinates. These are the CENTERS of the wagons.
# Replace with set_slot_positions(), e.g. from Marker2D nodes in the scene.
const DEFAULT_SLOTS: Array[Vector2] = [
    Vector2(150, 300), Vector2(350, 300), Vector2(550, 300),
]

# Injected by TradeScene
var wagon_container: Node2D

var trade_wagons := {} # wagon type -> GenericWagon

var _slots: Array[Vector2] = DEFAULT_SLOTS.duplicate()
var _slot_of := {} # wagon type -> index of its slot (slots are reused when a wagon is removed)


#region spawning
# Call before spawning any wagon.
func set_slot_positions(positions: Array[Vector2]) -> void:
    _slots = positions.duplicate()
    _slot_of.clear()


# Creates an empty wagon of this type in the first free slot. Returns null (with an error) if it can't.
func spawn_wagon(wagon_type: String) -> GenericWagon:
    if wagon_container == null:
        push_error("TradeWagonManager: wagon_container not injected")
        return null
    if trade_wagons.has(wagon_type):
        push_error("TradeWagonManager: '%s' is already spawned" % wagon_type)
        return null
    if not WagonTypes.TYPES.has(wagon_type):
        push_error("TradeWagonManager: unknown wagon type '%s'" % wagon_type)
        return null
    var slot := _find_free_slot()
    if slot < 0:
        push_error("TradeWagonManager: no free slot for '%s' (%d slots)" % [wagon_type, _slots.size()])
        return null

    var wagon_info: Dictionary = WagonTypes.TYPES[wagon_type]
    var node: Node = wagon_info.horizontal_scene.instantiate()
    var wagon := node as GenericWagon
    if wagon == null:
        node.free()
        push_error("TradeWagonManager: the scene of '%s' must use a script that extends GenericWagon" % wagon_type)
        return null

    # Plain data only, so this is safe before the wagon is in the tree. A wagon for sale is empty.
    wagon.apply_data({"type": wagon_type}, wagon_info)
    wagon.position = _slots[slot]
    wagon.clicked.connect(_on_wagon_clicked)

    wagon_container.add_child(wagon)
    trade_wagons[wagon_type] = wagon
    _slot_of[wagon_type] = slot
    return wagon


# The city has no more wagons of this type: the wagon leaves, and its slot becomes free
func remove_wagon(wagon_type: String) -> void:
    var wagon := get_wagon(wagon_type)
    if wagon != null:
        wagon.queue_free()
    trade_wagons.erase(wagon_type)
    _slot_of.erase(wagon_type)


func clear_wagons() -> void:
    for wagon: GenericWagon in trade_wagons.values():
        if is_instance_valid(wagon):
            wagon.queue_free()
    trade_wagons.clear()
    _slot_of.clear()


func _find_free_slot() -> int:
    var used := _slot_of.values()
    for i in _slots.size():
        if not used.has(i):
            return i
    return -1
#endregion


func get_wagon(wagon_type: String) -> GenericWagon:
    return trade_wagons.get(wagon_type)


func _on_wagon_clicked(wagon: GenericWagon) -> void:
    wagon_clicked.emit(wagon.wagon_type)