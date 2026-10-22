class_name RailEdge
extends Resource

var a: String
var b: String
var cost: float

func _init(a_: String, b_: String, cost_: float):
    self.a = a_
    self.b = b_
    self.cost = cost_

func get_edges() -> Array[String]:
    return [a, b]

func get_cost() -> float:
    return cost
