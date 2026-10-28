extends Node2D
class_name CameraService

signal camera_moved

const ZOOM_STEP := 1.1 # multiplicative, per wheel notch
const MIN_ZOOM := 0.25
const MAX_ZOOM := 6.0

@export var initial_zoom := 1.0

var grid_service: GridService # injected
var world_bounds := Rect2() # empty rect = unbounded

@onready var cam: Camera2D = $Camera2D

# Single source of truth: the camera itself
var zoom: float:
    get:
        return cam.zoom.x
    set(value):
        var z := clampf(value, MIN_ZOOM, MAX_ZOOM)
        cam.zoom = Vector2(z, z)


func _ready() -> void:
    zoom = initial_zoom


# --- Public API ---------------------------------------------------------

func center_at_tile(tile: Vector2i) -> void:
    assert(grid_service != null, "CameraService: grid_service not injected")
    _move_to(grid_service.tile_to_world(tile))

func set_pos(pos: Vector2) -> void:
    _move_to(pos)

func set_zoom(val: float) -> void:
    zoom = val

func set_world_bounds(rect: Rect2) -> void:
    world_bounds = rect
    _move_to(cam.global_position) # re-clamp

## Pan by a screen-space delta (e.g. InputEventMouseMotion.relative).
func pan(screen_delta: Vector2) -> void:
    _move_to(cam.global_position - screen_delta / zoom)

## Zoom by a multiplicative factor, keeping the world point under screen_pos fixed.
func zoom_at_screen_pos(factor: float, screen_pos: Vector2) -> void:
    var old_zoom := zoom
    zoom = old_zoom * factor
    if is_equal_approx(zoom, old_zoom):
        return # hit a limit
    var from_center := screen_pos - get_viewport_rect().size * 0.5
    # world = cam_pos + from_center / zoom  ->  keep it constant
    _move_to(cam.global_position + from_center / old_zoom - from_center / zoom)


# --- Input --------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed:
        match event.button_index:
            MOUSE_BUTTON_WHEEL_UP:
                zoom_at_screen_pos(ZOOM_STEP, event.position)
            MOUSE_BUTTON_WHEEL_DOWN:
                zoom_at_screen_pos(1.0 / ZOOM_STEP, event.position)
    elif event is InputEventMagnifyGesture:
        zoom_at_screen_pos(event.factor, event.position)

# --- Internal -----------------------------------------------------------

func _move_to(world_pos: Vector2) -> void:
    if world_bounds.has_area():
        world_pos = world_pos.clamp(world_bounds.position, world_bounds.end)
    cam.global_position = world_pos
    camera_moved.emit()
