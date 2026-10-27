extends CanvasLayer
class_name RoundedCorners
# Draws black rounded corners over the whole screen, to see on the PC roughly what a phone with a
# rounded screen shows. Nothing else uses it. It is only shown on the PC (not on the phone, which has
# its own corners).
#
# A rectangle in a corner stays clear of a corner with radius r if its margin from both edges is at
# least r * (1 - 1 / sqrt(2)), about 0.29 * r. The HUD uses that as its screen margin.
#
# Scene structure (rounded_corners.tscn). Layer 200, above everything (the loading screen is 100):
#   RoundedCorners (CanvasLayer, this script)
#   `- Canvas (Control, Full Rect, Mouse Filter = Ignore)

@export var enabled := true
@export var corner_radius := 90.0 # in pixels of the game's screen. Measure it on the phone.
@export var color := Color.BLACK
@export var arc_points := 24

@onready var canvas: Control = $Canvas


func _ready() -> void:
    visible = enabled and OS.has_feature("pc")
    canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.draw.connect(_draw_corners)
    canvas.resized.connect(canvas.queue_redraw)
    canvas.queue_redraw()


func _draw_corners() -> void:
    var r := corner_radius
    # The top left corner: the square of side r minus the quarter disc whose centre is (r, r)
    var shape := PackedVector2Array([Vector2(0.0, 0.0), Vector2(r, 0.0)])
    for i in arc_points + 1:
        var angle := -PI * 0.5 - PI * 0.5 * i / arc_points # from the top (r, 0) to the left (0, r)
        shape.append(Vector2(r, r) + Vector2(cos(angle), sin(angle)) * r)

    # The other three are the same shape mirrored
    var screen := canvas.size
    for flip_x in [false, true]:
        for flip_y in [false, true]:
            var points := PackedVector2Array()
            for p in shape:
                points.append(Vector2(screen.x - p.x if flip_x else p.x, screen.y - p.y if flip_y else p.y))
            canvas.draw_colored_polygon(points, color)