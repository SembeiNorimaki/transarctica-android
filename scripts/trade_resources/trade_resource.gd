extends Node2D
class_name TradeResource

@onready var sprite: Sprite2D = $Sprite2D
@onready var area2d: Area2D = $Area2D
@onready var qty_label: Label = $QtyLabel
@onready var price_label: Label = $PriceLabel
@onready var buy_button: Button = $BuyButton
@onready var sell_button: Button = $SellButton

const RESOURCE_TYPES = {
    "alcohol": 0,
    "antiques": 1,
    "missiles": 2,
    "bricks": 3,
    "caviar": 4,
    "oil": 5,
    "earth": 6,
    "coal": 7,
    "plants": 8,
    "red": 9,
    "mammothdung": 10,
    "rails": 11,
    "fish": 12,
    "fishingrods": 13,
    "salt": 14,
    "furs": 15,
    "gasoline": 16,
    "inspection": 17,
    "gray": 18,
    "meat": 19,
    "wood": 20
}

var resource_type := ""
var qty: int = 0
var price: int = 100


func set_selected(value: bool) -> void:
    buy_button.visible = value
    
func set_resource_type(t: String) -> void:
    resource_type = t
    call_deferred("_set_texture", t)

func set_qty(q: int) -> void:
    qty = q
    call_deferred("_update_labels")

func set_price(p: int) -> void:
    price = p
    call_deferred("_update_labels")

func _update_labels():
    qty_label.text = str(qty)
    price_label.text = str(price)

func _set_texture(t: String) -> void:
    sprite.frame = RESOURCE_TYPES[t]

func set_visibility(value: bool):
    sprite.visible = value
    area2d.monitoring = value

func _on_area_2d_input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
    if event is InputEventScreenTouch or event is InputEventMouseButton:
        if event.pressed:
            print("Resource %s tapped" % resource_type)
            set_selected(true)


func _on_sell_button_pressed() -> void:
    if qty >= 1:
        set_qty(qty - 1)
    if qty == 0:
        sell_button.disabled = true


func _on_buy_button_pressed() -> void:
    if qty >= 1:
        set_qty(qty - 1)
    if qty == 0:
        buy_button.disabled = true
