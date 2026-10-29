extends Node
class_name CombatInputManager
# Turns pointer input (mouse or touch) into tile taps and camera drags on the battlefield.
# A press that moves more than DRAG_THRESHOLD pixels pans the camera; one that doesn't is a tap,
# reported on release as tile_tapped. It only reports: others decide what a tap means.

signal tile_tapped(tile: Vector2i)
signal tile_hovered(tile: Vector2i)

const DRAG_THRESHOLD := 12.0 # px the pointer must move before it counts as a drag and not a tap

# Injected by the scene
var grid_service: GridService
var camera_service: CameraService
var world: Node2D # the node the tiles are drawn in (the CombatMap)

var _pressed := false
var _dragging := false
var _press_position := Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
    # A touch also arrives as an emulated mouse event: only count the touch itself
    if event is InputEventMouse and (event as InputEventMouse).device == InputEvent.DEVICE_ID_EMULATION:
        return
    if event is InputEventScreenTouch or event is InputEventMouseButton:
        _on_press_or_release(event)
    elif event is InputEventScreenDrag:
        _on_move((event as InputEventScreenDrag).position, (event as InputEventScreenDrag).relative)
    elif event is InputEventMouseMotion:
        var motion := event as InputEventMouseMotion
        if _pressed:
            _on_move(motion.position, motion.relative)
        else:
            tile_hovered.emit(tile_at_screen(motion.position))


## The tile under a point of the screen.
func tile_at_screen(screen_position: Vector2) -> Vector2i:
    var world_position := world.get_canvas_transform().affine_inverse() * screen_position
    return grid_service.world_to_tile(world.to_local(world_position))


func _on_press_or_release(event: InputEvent) -> void:
    var pressed: bool
    var position: Vector2
    if event is InputEventScreenTouch:
        pressed = (event as InputEventScreenTouch).pressed
        position = (event as InputEventScreenTouch).position
    else:
        var mouse := event as InputEventMouseButton
        if mouse.button_index != MOUSE_BUTTON_LEFT:
            return
        pressed = mouse.pressed
        position = mouse.position
    if pressed:
        _pressed = true
        _dragging = false
        _press_position = position
    elif _pressed:
        _pressed = false
        if not _dragging:
            tile_tapped.emit(tile_at_screen(position))

func _on_move(position: Vector2, relative: Vector2) -> void:
    if not _pressed:
        return
    if not _dragging and position.distance_to(_press_position) > DRAG_THRESHOLD:
        _dragging = true
    if _dragging and camera_service != null:
        camera_service.pan(relative)
