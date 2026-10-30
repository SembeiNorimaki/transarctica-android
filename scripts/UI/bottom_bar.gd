extends MarginContainer
class_name BottomBar
# The two buttons at the bottom of the screen. It is only a view: it says which was pressed.
# In both the navigation and the trade scene the left one reverses the train and the right one
# starts and stops it.

signal left_pressed
signal right_pressed

@onready var button_left: Button = $HBoxContainer/ButtonLeft
@onready var button_right: Button = $HBoxContainer/ButtonRight


func _ready() -> void:
    button_left.pressed.connect(left_pressed.emit)
    button_right.pressed.connect(right_pressed.emit)
