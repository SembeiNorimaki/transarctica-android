extends Node
class_name TradeResourceManager
# Spawns and controls the TradeResource nodes of the trade scene: one per resource the city sells.
# Like the train managers, it owns placement: it adds the nodes to the injected container.
# It knows nothing about inventories or trading. The scene tells it what to show,
# and it relays what the player taps.

signal resource_clicked(resource_name: String) # a resource on a BUY placeholder
signal sell_resource_clicked(resource_name: String) # a resource on a SELL placeholder

const RESOURCE_SCENE: PackedScene = preload("res://scenes/trade_resources/trade_resource.tscn")

# Where the resources go, in the container's coordinates: the placeholders of the map (see TradeMap),
# the BUY ones for the resources the player can buy, the SELL ones for those it can sell.
# Replace with set_slot_positions().
const DEFAULT_SLOTS: Array[Vector2] = [
    Vector2(100, 100), Vector2(250, 100),
    Vector2(400, 100), Vector2(550, 100),
    Vector2(700, 100), Vector2(850, 100)
]

# Injected by TradeScene
var resource_container: Node2D

var trade_resources := {} # resource name -> TradeResource, on a buy placeholder
var sell_resources := {} # resource name -> TradeResource, on a sell placeholder

var _buy_slots: Array[Vector2] = DEFAULT_SLOTS.duplicate()
var _sell_slots: Array[Vector2] = DEFAULT_SLOTS.duplicate()
var _next_buy_slot := 0
var _next_sell_slot := 0


#region spawning
# Call before spawning any resource. The positions are in the container's coordinates.
func set_slot_positions(buy_positions: Array[Vector2], sell_positions: Array[Vector2]) -> void:
    _buy_slots = buy_positions.duplicate()
    _sell_slots = sell_positions.duplicate()
    _next_buy_slot = 0
    _next_sell_slot = 0


# Creates the resource node in the next free placeholder of its side. Returns null (with an error)
# if it can't. A resource that is bought AND sold is spawned twice, once per side.
func spawn_resource(resource_name: String, qty: int, buy_price := 0, sell_price := 0, side: int = TradeResource.Side.BUY) -> TradeResource: # side: a TradeResource.Side
    if resource_container == null:
        push_error("TradeResourceManager: resource_container not injected")
        return null
    var nodes := trade_resources if side == TradeResource.Side.BUY else sell_resources
    var slots := _buy_slots if side == TradeResource.Side.BUY else _sell_slots
    var next_slot := _next_buy_slot if side == TradeResource.Side.BUY else _next_sell_slot
    var side_name := "buy" if side == TradeResource.Side.BUY else "sell"
    if nodes.has(resource_name):
        push_error("TradeResourceManager: '%s' is already spawned on the %s side" % [resource_name, side_name])
        return null
    if next_slot >= slots.size():
        push_error("TradeResourceManager: no free %s placeholder for '%s' (%d placeholders)" % [side_name, resource_name, slots.size()])
        return null

    var node := RESOURCE_SCENE.instantiate() as TradeResource
    node.position = slots[next_slot]
    if side == TradeResource.Side.BUY:
        _next_buy_slot += 1
    else:
        _next_sell_slot += 1

    # These setters are safe before the node is in the tree
    node.set_side(side)
    node.set_resource_type(resource_name)
    node.set_qty(qty)
    node.set_prices(buy_price, sell_price)

    node.clicked.connect(_on_resource_clicked)

    resource_container.add_child(node)
    nodes[resource_name] = node
    return node


func clear_resources() -> void:
    for node: TradeResource in trade_resources.values() + sell_resources.values():
        if is_instance_valid(node):
            node.queue_free()
    trade_resources.clear()
    sell_resources.clear()
    _next_buy_slot = 0
    _next_sell_slot = 0
#endregion


#region control
# The resource on a buy placeholder; if the place only buys it, the one on a sell placeholder
func get_resource(resource_name: String) -> TradeResource:
    if trade_resources.has(resource_name):
        return trade_resources[resource_name]
    return sell_resources.get(resource_name)


func get_sell_resource(resource_name: String) -> TradeResource:
    return sell_resources.get(resource_name)


func set_resource_qty(resource_name: String, qty: int) -> void:
    for nodes in [trade_resources, sell_resources]:
        if nodes.has(resource_name):
            nodes[resource_name].set_qty(qty)


func set_resource_prices(resource_name: String, buy_price: int, sell_price: int) -> void:
    for nodes in [trade_resources, sell_resources]:
        if nodes.has(resource_name):
            nodes[resource_name].set_prices(buy_price, sell_price)
#endregion


func _on_resource_clicked(resource: TradeResource) -> void:
    if resource.side == TradeResource.Side.BUY:
        resource_clicked.emit(resource.resource_type)
    else:
        sell_resource_clicked.emit(resource.resource_type)
