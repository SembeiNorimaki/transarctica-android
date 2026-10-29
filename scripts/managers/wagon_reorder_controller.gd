extends Node
class_name WagonReorderController
# Lets the player rearrange the wagons of the horizontal train by dragging them (used in depots).
# It only handles the input and the drag visuals: it NEVER changes the train's data. When a wagon
# is dropped between two others it emits wagon_dropped(from, to), and the scene moves the wagon
# through TrainInventory, which updates GameState and announces it.
#
# Rules:
# - The locomotive (index 0) stays at the head and can't be dragged.
# - A wagon can be dropped between any two other wagons, or at the rear end of the train.
# - Releasing without having dragged (a tap), or dropping far above or below the train, cancels.

signal wagon_dropped(from_index: int, to_index: int)
signal drag_cancelled

const DRAG_THRESHOLD := 12.0 # px the pointer must move before it counts as a drag and not a tap
const DROP_MAX_DISTANCE_Y := 140.0 # px above or below the train within which a drop counts
const LIFT_OFFSET := Vector2(0, -30) # the dragged wagon is drawn a little above the pointer (a finger hides it)
const DRAG_Z_INDEX := 10
const MARKER_SIZE := Vector2(8, 100)
const MARKER_COLOR := Color(1.0, 0.85, 0.2, 0.9)

var _train: HorizontalTrain
var _marker: ColorRect # shows where the wagon would be dropped
var _wagon: GenericWagon
var _dragging := false
var _moved := false # the pointer moved more than DRAG_THRESHOLD since the press
var _from := -1 # index of the dragged wagon
var _slot := -1 # boundary where it would be dropped (-1 = nowhere)
var _pointer := Vector2.ZERO # world position of the pointer
var _start_pointer := Vector2.ZERO
var _grab_offset := Vector2.ZERO # where the wagon was grabbed, relative to its center


# Call once, with the train that can be rearranged
func setup(train: HorizontalTrain) -> void:
    _train = train
    _marker = ColorRect.new()
    _marker.size = MARKER_SIZE
    _marker.color = MARKER_COLOR
    _marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _marker.z_index = DRAG_Z_INDEX - 1
    _marker.visible = false
    _train.add_child(_marker)


# Call when the player presses a wagon (the train's wagon_clicked signal)
func begin_drag(wagon: GenericWagon) -> void:
    if _dragging or _train == null:
        return
    var index := _train.wagons.find(wagon)
    if index <= 0: # not in the train, or the locomotive
        return
    _wagon = wagon
    _from = index
    _slot = -1
    _moved = false
    _dragging = true
    _start_pointer = _pointer
    _grab_offset = _pointer - wagon.global_position
    _train.set_speed(0.0) # the train stands still while it is rearranged

func is_dragging() -> bool:
    return _dragging
    
# The pointer is tracked from the events, so it is already up to date when the press arrives
# (_input runs before the wagon's own click detection).
func _input(event: InputEvent) -> void:
    # Godot also sends a mouse event for every touch. Ignore those, the touch events are used.
    if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
        return
    if event is InputEventScreenTouch and event.index != 0:
        return
    if event is InputEventScreenDrag and event.index != 0:
        return

    if event is InputEventMouseMotion or event is InputEventScreenDrag:
        _pointer = _to_world(event.position)
        if _dragging:
            _update_drag()
    elif event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
        _pointer = _to_world(event.position)
        if _dragging and not event.pressed:
            _drop()


func _to_world(screen_pos: Vector2) -> Vector2:
    return get_viewport().get_canvas_transform().affine_inverse() * screen_pos


func _update_drag() -> void:
    if not _moved:
        if _pointer.distance_to(_start_pointer) < DRAG_THRESHOLD:
            return # still just a press
        _moved = true
        _wagon.z_index = DRAG_Z_INDEX
        _wagon.modulate.a = 0.75

    _wagon.global_position = _pointer - _grab_offset + LIFT_OFFSET
    _slot = _find_slot()
    _marker.visible = _slot >= 0
    if _slot >= 0:
        _marker.position = Vector2(_train.get_boundary_x(_slot) - MARKER_SIZE.x * 0.5, -MARKER_SIZE.y * 0.5)


# The boundary nearest to the pointer where the wagon could be dropped. Boundary k lies before
# wagon k, and boundary n (the number of wagons) is the rear end. -1 if the pointer is too far
# from the train.
func _find_slot() -> int:
    var local := _train.to_local(_pointer)
    if absf(local.y) > DROP_MAX_DISTANCE_Y:
        return -1
    var best := -1
    var best_distance := INF
    for slot in range(1, _train.wagons.size() + 1): # not 0: nothing goes before the locomotive
        if slot == _from or slot == _from + 1:
            continue # next to the wagon itself: nothing would change
        var distance := absf(_train.get_boundary_x(slot) - local.x)
        if distance < best_distance:
            best = slot
            best_distance = distance
    return best


func _drop() -> void:
    var from := _from
    var slot := _slot if _moved else -1
    _end_drag()

    if slot < 0:
        _train.relayout() # the wagon slides back to its place
        drag_cancelled.emit()
        return
    # Removing the wagon shifts the boundaries behind it by one
    wagon_dropped.emit(from, slot - 1 if slot > from else slot)
    # Slides everything into place. It also brings the wagon back if the move was refused.
    _train.relayout()


func _end_drag() -> void:
    if is_instance_valid(_wagon):
        _wagon.z_index = 0
        _wagon.modulate.a = 1.0
    _marker.visible = false
    _wagon = null
    _from = -1
    _slot = -1
    _dragging = false
    _moved = false
