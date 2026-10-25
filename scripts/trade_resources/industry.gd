extends Node2D
class_name Industry
# The industry of a city, shown in the trade scene: the building the player taps to open the menu
# for manufacturing goods. It is only a VIEW: it shows what it is told and emits a signal when it
# is tapped. TradeScene decides what that means.
#
# Scene structure (industry.tscn):
#   Industry (Node2D, this script)
#   |- Sprite2D            the building (give it a texture)
#   |- Area2D              detects the taps
#   |  `- CollisionShape2D (a RectangleShape2D that covers the sprite)
#   `- NameLabel (Label)   under or over the building

signal clicked(industry: Industry)

@onready var sprite: Sprite2D = $Sprite2D
@onready var area: Area2D = $Area2D
@onready var name_label: Label = $NameLabel

var title := ""


func _ready() -> void:
    area.input_event.connect(_on_area_input_event)
    _refresh()


#region view state (safe to call before the node is in the tree)
func set_title(text: String) -> void:
    title = text
    _refresh()
#endregion


# The picture of the building, for the manufacturing menu. Call it once the node is in the tree.
func get_icon() -> Texture2D:
    return sprite.texture if sprite != null else null


func _refresh() -> void:
    if not is_node_ready():
        return
    name_label.text = title


func _on_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
    if InputUtils.is_tap(event):
        clicked.emit(self)
