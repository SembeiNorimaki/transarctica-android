extends Node
class_name TradeResourceManager
# Spawns and controls the TradeResource nodes of the trade scene: one per resource the city sells.
# Like the train managers, it owns placement: it adds the nodes to the injected container.
# It knows nothing about inventories or trading. The scene tells it what to show,
# and it relays what the player presses.

signal resource_buy_requested(resource_name: String, qty: int)
signal resource_sell_requested(resource_name: String, qty: int)
signal resource_clicked(resource_name: String)

const RESOURCE_SCENE: PackedScene = preload("res://scenes/trade_resources/trade_resource.tscn")

# Where the resources go, in the container's coordinates (one per resource).
# Replace with set_slot_positions(), e.g. from Marker2D nodes in the scene.
const DEFAULT_SLOTS: Array[Vector2] = [
    Vector2(100, 100), Vector2(250, 100), 
    Vector2(400, 100), Vector2(550, 100),
    Vector2(700, 100), Vector2(850, 100)    
]

# Injected by TradeScene
var resource_container: Node2D

var trade_resources := {} # resource name -> TradeResource

var _slots: Array[Vector2] = DEFAULT_SLOTS.duplicate()
var _next_slot := 0


#region spawning
# Call before spawning any resource.
func set_slot_positions(positions: Array[Vector2]) -> void:
    _slots = positions.duplicate()
    _next_slot = 0


# Creates the resource node in the next free slot. Returns null (with an error) if it can't.
func spawn_resource(resource_name: String, qty: int, buy_price := 0, sell_price := 0) -> TradeResource:
    if resource_container == null:
        push_error("TradeResourceManager: resource_container not injected")
        return null
    if trade_resources.has(resource_name):
        push_error("TradeResourceManager: '%s' is already spawned" % resource_name)
        return null
    if _next_slot >= _slots.size():
        push_error("TradeResourceManager: no free slot for '%s' (%d slots)" % [resource_name, _slots.size()])
        return null

    var node := RESOURCE_SCENE.instantiate() as TradeResource
    node.position = _slots[_next_slot]
    _next_slot += 1

    # These setters are safe before the node is in the tree
    node.set_resource_type(resource_name)
    node.set_qty(qty)
    node.set_prices(buy_price, sell_price)

    node.clicked.connect(_on_resource_clicked)
    node.buy_requested.connect(_on_buy_requested)
    node.sell_requested.connect(_on_sell_requested)

    resource_container.add_child(node)
    trade_resources[resource_name] = node
    return node


func clear_resources() -> void:
    for node: TradeResource in trade_resources.values():
        if is_instance_valid(node):
            node.queue_free()
    trade_resources.clear()
    _next_slot = 0
#endregion


#region control
func get_resource(resource_name: String) -> TradeResource:
    return trade_resources.get(resource_name)


func set_resource_qty(resource_name: String, qty: int) -> void:
    var node := get_resource(resource_name)
    if node != null:
        node.set_qty(qty)


func set_resource_can_buy(resource_name: String, value: bool) -> void:
    var node := get_resource(resource_name)
    if node != null:
        node.set_can_buy(value)


func set_resource_can_sell(resource_name: String, value: bool) -> void:
    var node := get_resource(resource_name)
    if node != null:
        node.set_can_sell(value)


# Only one resource is selected at a time. An empty name deselects all.
func select_resource(resource_name: String) -> void:
    for key in trade_resources:
        var node: TradeResource = trade_resources[key]
        node.set_selected(key == resource_name)
#endregion


#region relayed signals
func _on_resource_clicked(resource: TradeResource) -> void:
    resource_clicked.emit(resource.resource_type)


func _on_buy_requested(resource_name: String, qty: int) -> void:
    resource_buy_requested.emit(resource_name, qty)


func _on_sell_requested(resource_name: String, qty: int) -> void:
    resource_sell_requested.emit(resource_name, qty)
#endregion
