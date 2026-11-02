extends Node2D
class_name CameraService

signal camera_moved

const ZOOM_STEP := 1.1 # multiplicative, per wheel notch
const MIN_ZOOM := 0.25
const MAX_ZOOM := 6.0

@export var initial_zoom := 1.0
@export var zoom_enabled := true # wheel and pinch
@export var horizontal_only := false # the camera never moves vertically
## Arrow keys and WASD scroll the camera (for maps bigger than the screen).
@export var keyboard_scroll := false
## The camera scrolls when the mouse is at the edge of the window.
@export var edge_scroll := false
@export var scroll_speed := 900.0 # screen pixels per second
@export var edge_margin := 12.0 # screen pixels

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


# --- Scrolling ----------------------------------------------------------

func _process(delta: float) -> void:
    if not (keyboard_scroll or edge_scroll):
        return
    var direction := get_scroll_direction()
    if direction != Vector2.ZERO:
        pan(-direction * scroll_speed * delta)

## Which way the keyboard or the mouse at the edge ask the camera to go: each axis is -1, 0 or 1.
func get_scroll_direction() -> Vector2:
    var direction := Vector2.ZERO
    if keyboard_scroll:
        direction.x += float(Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D)) \
                - float(Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A))
        direction.y += float(Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S)) \
                - float(Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W))
    if edge_scroll and DisplayServer.window_is_focused() and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
        var view := get_viewport()
        var rect := view.get_visible_rect()
        var mouse := view.get_mouse_position()
        if rect.has_point(mouse):
            direction.x += float(mouse.x > rect.end.x - edge_margin) - float(mouse.x < rect.position.x + edge_margin)
            direction.y += float(mouse.y > rect.end.y - edge_margin) - float(mouse.y < rect.position.y + edge_margin)
    return direction.clamp(Vector2(-1, -1), Vector2(1, 1))

# --- Input --------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
    if not zoom_enabled:
        return
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
    if horizontal_only:
        world_pos.y = cam.global_position.y
    if world_bounds.has_area():
        world_pos = world_pos.clamp(world_bounds.position, world_bounds.end)
    cam.global_position = world_pos
    camera_moved.emit()
