extends Node2D
class_name CameraServiceOLD

#signal camera_moved(global_transform: Transform2D)

# Dependencies
@onready var grid_service: GridService


@onready var cam = $Camera2D
var move_speed = 500.0
#var _last_transform: Transform2D
const ZOOM_SPEED := 0.1
const MIN_ZOOM := 0.1
const MAX_ZOOM := 6.0


@export var zoom: float = 1.0
@export var offset := Vector2.ZERO
#var offset := Vector2.ZERO

func _ready() -> void:
    cam.zoom = Vector2(zoom, zoom)
    cam.global_position = offset
    #cam.global_position = Vector2(1000, 800)

func _unhandled_input(event):
    if event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            #zoom += ZOOM_SPEED
            #cam.zoom = Vector2(zoom, zoom)
            _zoom_at_screenpos(1, event.position)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            #zoom -= ZOOM_SPEED
            #cam.zoom = Vector2(zoom, zoom)
            _zoom_at_screenpos(-1, event.position)

func center_at_tile(tile: Vector2i):
    var screen_pos = grid_service.tile_to_world(tile)
    cam.position = screen_pos

func set_pos(pos: Vector2):
    offset = pos
    cam.global_position = offset

func set_zoom(val: float):
    zoom = val
    cam.zoom = Vector2(zoom, zoom)

func _zoom_at_screenpos(direction: int, screen_pos: Vector2):
    # 1. Convert screen → world BEFORE zoom
    var world_before = cam.get_canvas_transform().affine_inverse() * screen_pos

    # 2. Apply zoom
    zoom = clamp(zoom + direction * ZOOM_SPEED, MIN_ZOOM, MAX_ZOOM)
    cam.zoom = Vector2(zoom, zoom)

    # 3. Convert screen → world AFTER zoom
    var world_after = cam.get_canvas_transform().affine_inverse() * screen_pos

    # 4. Move camera so the point under the mouse stays fixed
    cam.position += world_before - world_after


func _process(delta: float) -> void:
    var input := Vector2.ZERO
    input.x = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
    input.y = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")

    if input != Vector2.ZERO:
        input = input.normalized()
        offset += input * move_speed * delta
        cam.global_position = offset
