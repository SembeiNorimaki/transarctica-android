extends Node2D
class_name GenericWagon

@onready var sprite: Sprite2D = $Sprite2D


var wagon_type := ""
var wagon_dim := Vector2i.ZERO
var cargo_type := ""
var cargo_amount := 0
var max_cargo_amount := 20

func _ready() -> void:
    pass


func set_cargo_type(t: String) -> void:
    cargo_type = t

func add_cargo_amount(amount: int) -> void:
    cargo_amount += amount


func set_wagon_type(t: String) -> void:
    wagon_type = t


func _on_area_2d_input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
    if event is InputEventScreenTouch or event is InputEventMouseButton:
        if event.pressed:
            print("Wagon %s tapped" % wagon_type)
