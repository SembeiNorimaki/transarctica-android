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
signal buy_wagon_requested(wagon_type: String)
signal recruit_requested(unit_type: String)

const UNITS_PER_PRESS := 1

@onready var name_label: Label = $VBoxContainer/ResourceName
@onready var image_rect: TextureRect = $VBoxContainer/ResourceImage
@onready var qty_label: Label = $VBoxContainer/GridContainer/ResourceQty
@onready var price_label: Label = $VBoxContainer/GridContainer/ResourcePrice
@onready var buy1_button: Button = $VBoxContainer/ResourceBuy1
@onready var fill_wagon_button: Button = $VBoxContainer/ResourceFillWagon
@onready var close_button: Button = $VBoxContainer/CloseButton


var current_resource := "" # "" when closed
var current_wagon_type := "" # "" unless the menu is showing a wagon
var current_unit_type := "" # "" unless the menu is showing a soldier

func _ready() -> void:
    buy1_button.pressed.connect(_on_buy1_pressed)
    fill_wagon_button.pressed.connect(_on_fill_wagon_pressed)
    fill_wagon_button.disabled = true # TODO: not implemented yet
    close_button.pressed.connect(close)
    hide()


# Opens the menu for a resource
func show_resource(resource_name: String, icon: Texture2D, qty: int, buy_price: int) -> void:
    current_resource = resource_name
    current_wagon_type = ""
    current_unit_type = ""

    name_label.text = resource_name.capitalize()
    image_rect.texture = icon
    price_label.text = str(buy_price) # what the player pays for 1 unit
    set_qty(qty)
    fill_wagon_button.visible = true
    show()

# Opens the menu for a wagon the city sells
func show_wagon(wagon_type: String, icon: Texture2D, qty: int, buy_price: int) -> void:
    current_resource = ""
    current_wagon_type = wagon_type
    name_label.text = wagon_type.capitalize() # "MerchandiseWagon" -> "Merchandise Wagon"
    image_rect.texture = icon
    price_label.text = str(buy_price)
    set_qty(qty)
    buy1_button.disabled = false # a stale disabled state from a resource would stay otherwise
    fill_wagon_button.visible = false # "fill wagon" only makes sense for resources
    show()

# Opens the menu for a soldier the city recruits
func show_unit(unit_type: String, icon: Texture2D, qty: int, price: int) -> void:
    current_resource = ""
    current_wagon_type = ""
    current_unit_type = unit_type
    name_label.text = unit_type.capitalize()
    image_rect.texture = icon
    price_label.text = str(price)
    set_qty(qty)
    buy1_button.disabled = false
    fill_wagon_button.visible = false
    show()

func set_qty(qty: int) -> void:
    qty_label.text = str(qty)


# The price changed while the menu is open (the economy reacts to every trade)
func set_price(price: int) -> void:
    price_label.text = str(price)


func set_can_buy(value: bool) -> void:
    buy1_button.disabled = not value


func close() -> void:
    current_resource = ""
    current_wagon_type = ""
    current_unit_type = ""
    hide()
    closed.emit()


func _on_buy1_pressed() -> void:
    if current_unit_type != "":
        recruit_requested.emit(current_unit_type)
    elif current_wagon_type != "":
        buy_wagon_requested.emit(current_wagon_type)
    elif current_resource != "":
        buy_requested.emit(current_resource, UNITS_PER_PRESS)


func _on_fill_wagon_pressed() -> void:
    if current_resource != "":
        fill_wagon_requested.emit(current_resource)
