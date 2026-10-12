extends Control
class_name SellMenu
# Pop-up to sell the cargo of ONE wagon to the city. Like BuyMenu, it is only a VIEW: it shows
# what it is told and emits signals. TradeScene fills it, keeps it up to date, and decides
# what the buttons do.
#
# The child nodes are found by unique name ("Access as Unique Name", the % icon).
# Save this menu as its own scene, so its unique names don't clash with the BuyMenu's.
# If your nodes are named differently, change the @onready lines.

signal sell_requested(wagon_index: int, qty: int)
signal sell_wagon_requested(wagon_index: int)
signal closed

const UNITS_PER_PRESS := 1

@onready var name_label: Label = $VBoxContainer/ResourceName
@onready var image_rect: TextureRect = $VBoxContainer/ResourceImage
@onready var qty_label: Label = $VBoxContainer/ResourceQty
@onready var price_label: Label = $VBoxContainer/ResourceSellPrice
@onready var sell1_button: Button = $VBoxContainer/ResourceBuy1
@onready var sell_wagon_button: Button = $VBoxContainer/ResourceFillWagon
@onready var close_button: Button = $VBoxContainer/CloseButton

var current_wagon := -1 # index of the wagon being shown, -1 when closed


func _ready() -> void:
    sell1_button.pressed.connect(_on_sell1_pressed)
    sell_wagon_button.pressed.connect(_on_sell_wagon_pressed)
    sell_wagon_button.disabled = true # TODO: not implemented yet
    if close_button != null:
        close_button.pressed.connect(close)
    hide()


# Opens the menu for the cargo of one wagon
func show_wagon(wagon_index: int, resource_name: String, icon: Texture2D, qty: int, sell_price: int) -> void:
    current_wagon = wagon_index
    name_label.text = resource_name.capitalize()
    image_rect.texture = icon
    price_label.text = str(sell_price) # what the city pays the player for 1 unit
    set_qty(qty)
    show()


# Units of the resource in the wagon
func set_qty(qty: int) -> void:
    qty_label.text = str(qty)


func set_can_sell(value: bool) -> void:
    sell1_button.disabled = not value


func close() -> void:
    current_wagon = -1
    hide()
    closed.emit()


func _on_sell1_pressed() -> void:
    if current_wagon >= 0:
        sell_requested.emit(current_wagon, UNITS_PER_PRESS)


func _on_sell_wagon_pressed() -> void:
    if current_wagon >= 0:
        sell_wagon_requested.emit(current_wagon)
