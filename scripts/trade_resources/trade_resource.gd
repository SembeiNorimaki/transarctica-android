extends Node2D
class_name TradeResource
# One resource of the city, shown in a cell of the trade scene.
# It is only a VIEW: it shows what it is told, and emits signals when the player taps it or
# presses a button. The scene decides what that means (TradeService) and updates the numbers
# from the inventories' signals.

signal clicked(resource: TradeResource)

## Which side of the trade this node stands for. A resource the place sells (the player buys it) is
## shown on the buy placeholders; one the place buys, on the sell placeholders; one it does both
## with, once on each.
enum Side {BUY, SELL}

@onready var sprite: Sprite2D = $Sprite2D
@onready var qty_label: Label = $QtyLabel
@onready var price_label: Label = $PriceLabel

var resource_type := ""
var side: int = Side.BUY # a Side
var qty := 0
var buy_price := 0 # what the player pays for 1 unit
var sell_price := 0 # what the city pays the player for 1 unit


func _ready() -> void:
    _refresh()


#region view state (the setters are safe to call before the node is in the tree)
func set_resource_type(t: String) -> void:
    resource_type = t
    if not ResourceTypes.is_known(t) or ResourceTypes.frame_for(t) < 0:
        push_warning("TradeResource: no sprite for resource '%s'" % t)
    _refresh()


func set_side(value: int) -> void:
    side = value
    _refresh()


func set_qty(q: int) -> void:
    qty = q
    _refresh()


func set_prices(buy: int, sell: int) -> void:
    buy_price = buy
    sell_price = sell
    _refresh()



func _refresh() -> void:
    if not is_node_ready():
        return

    qty_label.text = str(qty)
    # BUY side: what the player pays (0: this place doesn't sell it). SELL side: what the place pays.
    var shown := buy_price if side == Side.BUY else sell_price
    price_label.text = str(shown) if shown > 0 else "-"

    var frame: int = ResourceTypes.frame_for(resource_type)
    if frame >= 0:
        sprite.frame = frame
    sprite.visible = frame >= 0
#endregion


func get_icon() -> Texture2D:
    if sprite.texture == null or ResourceTypes.frame_for(resource_type) < 0:
        return null
    var cell := sprite.texture.get_size() / Vector2(sprite.hframes, sprite.vframes)
    var atlas := AtlasTexture.new()
    atlas.atlas = sprite.texture
    atlas.region = Rect2(Vector2(sprite.frame_coords) * cell, cell)
    return atlas

#region input
func _on_area_2d_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
    if InputUtils.is_tap(event):
        clicked.emit(self)

#endregion
