extends Node2D
class_name TradePlace
# The building of the place you are trading in: a city, an industry or a depot. It is only a VIEW:
# it shows what it is told and emits a signal when it is tapped. TradeScene decides what that
# means (for an industry: open the manufacturing menu), and which picture it shows
# (IndustryTypes.get_trade_image).
#
# Scene structure (trade_place.tscn):
#   TradePlace (Node2D, this script)
#   |- Sprite2D            the building (its own texture is the one used when there is no picture)
#   |- Area2D              detects the taps
#   |  `- CollisionShape2D (any shape: the script resizes it to the picture)
#   `- NameLabel (Label)   the name of the place
#
# Put one TradePlace in trade_scene.tscn, at the place where the building goes.

signal clicked(place: TradePlace)

@onready var sprite: Sprite2D = $Sprite2D
@onready var area: Area2D = $Area2D
@onready var collision: CollisionShape2D = $Area2D/CollisionShape2D
@onready var name_label: Label = $NameLabel

var title := ""


func _ready() -> void:
    area.input_event.connect(_on_area_input_event)


# Call it once, when the trade scene is initialized (the node is already in the tree).
# `image` null: the picture of the scene stays. `clickable`: whether tapping it does anything
# (a city without an industry: nothing to open).
func setup(title_: String, image: Texture2D, clickable: bool) -> void:
    title = title_
    name_label.text = title
    if image != null:
        sprite.texture = image
    else:
        push_warning("TradePlace: '%s' has no trade_image in IndustryTypes, so the scene's picture is shown" % title)
    _fit_collision_to_sprite()
    set_clickable(clickable)


func set_clickable(value: bool) -> void:
    area.input_pickable = value


# The picture of the building, for the menus. Call it once the node is in the tree.
func get_icon() -> Texture2D:
    return sprite.texture


# The tap area has the size of the picture, whichever picture it is
func _fit_collision_to_sprite() -> void:
    if sprite.texture == null:
        return
    var rect := RectangleShape2D.new()
    rect.size = sprite.texture.get_size()
    collision.shape = rect
    collision.position = sprite.position


func _on_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
    if InputUtils.is_tap(event):
        clicked.emit(self)