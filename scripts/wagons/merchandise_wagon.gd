extends GenericWagon
class_name MerchandiseWagon
# Wagon that carries trade resources. Horizontal-view behavior only: the cargo itself lives in
# TrainInventory and GameState. When the wagon is not empty it shows, below the wagon, the
# resource it carries, how much of it, and what the city would pay for each unit.
#
# GenericWagon calls _refresh_visuals() when the wagon is ready and whenever its cargo changes.

@onready var resource_info: Node2D = $ResourceInfo
@onready var resource_sprite: Sprite2D = $ResourceInfo/ResourceSprite
@onready var qty_label: Label = $ResourceInfo/ResourceQty
@onready var price_label: Label = $ResourceInfo/ResourceSellPrice

# What the city pays the player for 1 unit of the cargo. -1 = the city doesn't buy it.
# The wagon can't know this by itself: TradeScene sets it (a view shows what it is told).
var sell_price := -1


func set_sell_price(price: int) -> void:
    sell_price = price
    _refresh_visuals()


func _refresh_visuals() -> void:
    if not is_node_ready():
        return

    var has_cargo := cargo_type != "" and cargo_amount > 0
    resource_info.visible = has_cargo
    if not has_cargo:
        return

    var frame = ResourceTypes.frame_for(cargo_type)
    resource_sprite.visible = frame >= 0
    if frame >= 0:
        resource_sprite.frame = frame
    qty_label.text = "%d / %d" % [cargo_amount, max_cargo_amount]
    price_label.text = str(sell_price) if sell_price >= 0 else "-"
