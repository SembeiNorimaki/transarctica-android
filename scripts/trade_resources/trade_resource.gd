extends Node2D
class_name TradeResource
# One resource of the city, shown in a cell of the trade scene.
# It is only a VIEW: it shows what it is told, and emits signals when the player taps it or
# presses a button. The scene decides what that means (TradeService) and updates the numbers
# from the inventories' signals.

signal clicked(resource: TradeResource)
signal buy_requested(resource_name: String, qty: int)
signal sell_requested(resource_name: String, qty: int)

const UNITS_PER_PRESS := 1

@onready var sprite: Sprite2D = $Sprite2D
@onready var area2d: Area2D = $Area2D
@onready var qty_label: Label = $QtyLabel
@onready var price_label: Label = $PriceLabel
@onready var buy_button: Button = $BuyButton
@onready var sell_button: Button = $SellButton

var resource_type := ""
var qty := 0
var buy_price := 0 # what the player pays for 1 unit
var sell_price := 0 # what the city pays the player for 1 unit

var _selected := false
var _can_buy := true
var _can_sell := true
var _shown := true


func _ready() -> void:
    _refresh()


#region view state (the setters are safe to call before the node is in the tree)
func set_resource_type(t: String) -> void:
    resource_type = t
    if not ResourceTypes.is_known(t) or ResourceTypes.frame_for(t) < 0:
        push_warning("TradeResource: no sprite for resource '%s'" % t)
    _refresh()


func set_qty(q: int) -> void:
    qty = q
    _refresh()


func set_prices(buy: int, sell: int) -> void:
    buy_price = buy
    sell_price = sell
    _refresh()


# Kept for compatibility: sets the buy price
func set_price(p: int) -> void:
    buy_price = p
    _refresh()


# Selected: the buy and sell buttons are shown. The scene keeps a single resource selected.
func set_selected(value: bool) -> void:
    _selected = value
    _refresh()


func set_can_buy(value: bool) -> void:
    _can_buy = value
    _refresh()


func set_can_sell(value: bool) -> void:
    _can_sell = value
    _refresh()


# Hides the sprite and stops it from being clickable
func set_visibility(value: bool) -> void:
    _shown = value
    _refresh()


func _refresh() -> void:
    if not is_node_ready():
        return

    qty_label.text = str(qty)
    price_label.text = str(buy_price) # TODO: also show sell_price (e.g. on the sell button)

    var frame = ResourceTypes.frame_for(resource_type)
    if frame >= 0:
        sprite.frame = frame
    sprite.visible = _shown and frame >= 0
    area2d.input_pickable = _shown

    buy_button.visible = _selected
    sell_button.visible = _selected
    buy_button.disabled = not _can_buy
    sell_button.disabled = not _can_sell
#endregion


#region input
func _on_area_2d_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
    if InputUtils.is_tap(event):
        clicked.emit(self)


func _on_buy_button_pressed() -> void:
    buy_requested.emit(resource_type, UNITS_PER_PRESS)


func _on_sell_button_pressed() -> void:
    sell_requested.emit(resource_type, UNITS_PER_PRESS)
#endregion
