extends HBoxContainer
class_name BarracksMenu
# The soldiers of ONE barracks wagon, in SLOT_COUNT slots. A slot is empty or shows a soldier.
# It is only a VIEW: it shows what it is told and emits unit_clicked when a soldier is pressed.

signal unit_clicked(unit_id: String)

const SLOT_COUNT := 5
const SOLDIER_FRAMES: SpriteFrames = preload("res://assets/tilesets/unit.tres")
const ICON_SIZE := Vector2(96, 96)

var _buttons: Array[TextureButton] = []
var _unit_ids: Array[String] = [] # per slot: the soldier in it, or "" if empty


func _ready() -> void:
    for i in SLOT_COUNT:
        var button := TextureButton.new()
        button.ignore_texture_size = true
        button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
        button.custom_minimum_size = ICON_SIZE
        button.pressed.connect(_on_slot_pressed.bind(i))
        add_child(button)
        _buttons.append(button)
        _unit_ids.append("")
    show_units([])


# `unit_ids` are the "unit_ids" of the wagon. They fill the slots in order; the rest stay empty.
func show_units(unit_ids: Array) -> void:
    for i in SLOT_COUNT:
        _set_slot(i, str(unit_ids[i]) if i < unit_ids.size() else "")


# The soldier leaves its slot, which stays empty
func remove_unit(unit_id: String) -> void:
    var i := _unit_ids.find(unit_id)
    if i >= 0:
        _set_slot(i, "")


func _set_slot(slot: int, unit_id: String) -> void:
    _unit_ids[slot] = unit_id
    var button := _buttons[slot]
    button.texture_normal = SOLDIER_FRAMES.get_frame_texture(&"S", 0) if unit_id != "" else null
    button.disabled = unit_id == ""


func _on_slot_pressed(slot: int) -> void:
    if _unit_ids[slot] != "":
        unit_clicked.emit(_unit_ids[slot])
