class_name RailEdge
extends Resource

var a: String
var b: String
var cost: float

func _init(a: String, b: String, cost: float):
    self.a = a
    self.b = b
    self.cost = cost

func get_edges() -> Array[String]:
    return [a, b]

func get_cost() -> float:
    return cost
