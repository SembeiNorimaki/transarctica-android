extends Node2D
class_name TradeUnit
# One soldier type that the city recruits, shown in the trade scene (a soldier with its name and
# how many are left). It is only a VIEW: it shows what it is told and emits a signal when it is
# tapped. TradeScene decides what that means.

signal clicked(unit: TradeUnit)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var qty_label: Label = $QtyLabel

var unit_type := ""
var qty := 0


func _ready() -> void:
    sprite.play(&"S")
    _refresh()


#region view state (safe to call before the node is in the tree)
func set_unit_type(t: String) -> void:
    unit_type = t
    _refresh()


func set_qty(q: int) -> void:
    qty = q
    _refresh()
#endregion


# The first frame of the sprite, for the buy menu. Call it once the node is in the tree.
func get_icon() -> Texture2D:
    if sprite == null or sprite.sprite_frames == null:
        return null
    return sprite.sprite_frames.get_frame_texture(&"S", 0)


func _refresh() -> void:
    if not is_node_ready():
        return
    qty_label.text = "%s x%d" % [unit_type.capitalize(), qty]


func _on_area_2d_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
    if InputUtils.is_tap(event):
        clicked.emit(self)
