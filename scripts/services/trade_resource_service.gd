extends Node
class_name TradeResourceService

var RESOURCE_SCENE = preload("res://scenes/trade_resources/trade_resource.tscn")

var trade_resources = {}

var resource_positions = [
    Vector2i(100, 100),
    Vector2i(200, 100),
    Vector2i(300, 100),
    Vector2i(400, 100)
]
var resource_idx = 0

func spawn_resource(resource_name_: String, qty_: int) -> TradeResource:
    var trade_resource = RESOURCE_SCENE.instantiate()
    
    trade_resource.call_deferred("set_resource_type", resource_name_)
    trade_resource.call_deferred("set_qty", qty_)
    
    trade_resource.set_position(resource_positions[resource_idx])
    resource_idx += 1
    
    trade_resources[resource_name_] = trade_resource
    return trade_resource
