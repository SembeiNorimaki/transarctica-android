extends Node2D
class_name TradeMap
# The place the trade scene happens in, as the designer paints it. One scene per kind of place:
# trade_city.tscn, trade_industry.tscn, trade_depot.tscn (scenes/maps). TradeScene picks the one that
# matches the place (a city, an industry or a depot) and puts it in its MapRoot.
#
# Scene structure:
#   TradeMap (Node2D, this script)
#   |- Ground     TileMapLayer   the snow
#   |- Roads      TileMapLayer   streets and the loading strip
#   |- Buildings  TileMapLayer   stalls, houses, warehouses (y-sorted)
#   |- Placeholders (Node2D)
#   |  |- BuyPlaceholders   Marker2D children: where the resources the player can BUY go
#   |  `- SellPlaceholders  Marker2D children: where the resources the player can SELL go
#   `- Place (Marker2D)     where the building of the place (TradePlace) stands; its scale is the
#                           TradePlace's scale
#
# A resource that the place only sells goes to a buy placeholder, one that it only buys to a sell
# placeholder, and one it buys and sells (mode Both) to one of each. The placeholders are used in
# the order of the children of their container.

@onready var buy_container: Node2D = $Placeholders/BuyPlaceholders
@onready var sell_container: Node2D = $Placeholders/SellPlaceholders
@onready var place_marker: Marker2D = $Place


## Where the resources the player can buy are shown, in global coordinates, in order.
func get_buy_positions() -> Array[Vector2]:
    return _positions(buy_container)

## Where the resources the player can sell are shown, in global coordinates, in order.
func get_sell_positions() -> Array[Vector2]:
    return _positions(sell_container)

func get_place_position() -> Vector2:
    return place_marker.global_position

func get_place_scale() -> Vector2:
    return place_marker.global_scale


func _positions(container: Node2D) -> Array[Vector2]:
    var result: Array[Vector2] = []
    for child in container.get_children():
        if child is Node2D:
            result.append((child as Node2D).global_position)
    return result
