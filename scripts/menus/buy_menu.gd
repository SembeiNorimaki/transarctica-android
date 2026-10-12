extends Control
class_name BuyMenu
# Pop-up to buy a resource from the city. It is only a VIEW: it shows what it is told and emits
# signals. TradeScene fills it, keeps it up to date, and decides what the buttons do.
#
# The child nodes are found by unique name: right-click each one in the scene and enable
# "Access as Unique Name" (the % icon), or change the paths below.

signal buy_requested(resource_name: String, qty: int)
signal fill_wagon_requested(resource_name: String)
signal closed

const UNITS_PER_PRESS := 1

@onready var name_label: Label = $VBoxContainer/ResourceName
@onready var image_rect: TextureRect = $VBoxContainer/ResourceImage
@onready var qty_label: Label = $VBoxContainer/ResourceQty
@onready var price_label: Label = $VBoxContainer/ResourceSellPrice
@onready var buy1_button: Button = $VBoxContainer/ResourceBuy1
@onready var fill_wagon_button: Button = $VBoxContainer/ResourceFillWagon
@onready var close_button: Button = $VBoxContainer/CloseButton


var current_resource := "" # "" when closed


func _ready() -> void:
    buy1_button.pressed.connect(_on_buy1_pressed)
    fill_wagon_button.pressed.connect(_on_fill_wagon_pressed)
    fill_wagon_button.disabled = true # TODO: not implemented yet
    close_button.pressed.connect(close)
    hide()


# Opens the menu for a resource
func show_resource(resource_name: String, icon: Texture2D, qty: int, buy_price: int) -> void:
    current_resource = resource_name
    name_label.text = resource_name.capitalize()
    image_rect.texture = icon
    price_label.text = str(buy_price) # what the player pays for 1 unit
    set_qty(qty)
    show()


func set_qty(qty: int) -> void:
    qty_label.text = str(qty)


func set_can_buy(value: bool) -> void:
    buy1_button.disabled = not value


func close() -> void:
    current_resource = ""
    hide()
    closed.emit()


func _on_buy1_pressed() -> void:
    if current_resource != "":
        buy_requested.emit(current_resource, UNITS_PER_PRESS)


func _on_fill_wagon_pressed() -> void:
    if current_resource != "":
        fill_wagon_requested.emit(current_resource)
