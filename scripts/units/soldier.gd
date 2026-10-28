extends CharacterBody2D
class_name Soldier
# A soldier on the battlefield. Its data comes from GameState's unit (see UnitTypes.make_unit);
# the state machine ("Action": idle, move, attack) says what it is doing.

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

signal clicked(soldier: Soldier)

const SELECTED_COLOR := Color(1.0, 1.0, 0.45)

var unit_id := ""
var unit_type := ""
var hp := 0
var max_hp := 0

var selected := false:
    set(value):
        selected = value
        if sprite != null:
            sprite.modulate = SELECTED_COLOR if selected else Color.WHITE

func _ready() -> void:
    sprite.play(&"N") # deployed facing north
    $Area2D.input_event.connect(_on_area_input_event)

# `data` is GameState.get_unit(unit_id). Safe to call before the node is in the tree.
func setup(id: String, data: Dictionary) -> void:
    unit_id = id
    unit_type = str(data.get("unit_type", ""))
    hp = int(data.get("hp", 0))
    max_hp = int(data.get("max_hp", hp))

func _on_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
    if InputUtils.is_tap(event):
        clicked.emit(self)
