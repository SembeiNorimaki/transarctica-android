extends RefCounted
class_name InputUtils


# True when the event is the start of a tap or click: a touch press, or a left mouse press that
# is not the mouse event Godot emulates from a touch (the touch itself is already counted).
# Works with any "emulate mouse from touch" project setting, and ignores the mouse wheel.
static func is_tap(event: InputEvent) -> bool:
    if event is InputEventScreenTouch:
        return (event as InputEventScreenTouch).pressed
    if event is InputEventMouseButton:
        var mouse := event as InputEventMouseButton
        return mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT \
                and mouse.device != InputEvent.DEVICE_ID_EMULATION
    return false