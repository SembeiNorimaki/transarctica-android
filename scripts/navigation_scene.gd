extends Node2D
class_name NavigationScene

@onready var camera_2d: Camera2D = $Camera2D

var dragging := false
var last_pos := Vector2.ZERO

func _input(event):
    # --- Touch input (Android) ---
    if event is InputEventScreenTouch:
        if event.pressed:
            dragging = true
            last_pos = event.position
        else:
            dragging = false

    if dragging and event is InputEventScreenDrag:
        var delta = event.position - last_pos
        camera_2d.global_position -= delta
        last_pos = event.position

    # --- Mouse input (Desktop) ---
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                dragging = true
                last_pos = event.position
            else:
                dragging = false

    if dragging and event is InputEventMouseMotion:
        var delta = event.position - last_pos
        camera_2d.global_position -= delta
        last_pos = event.position
