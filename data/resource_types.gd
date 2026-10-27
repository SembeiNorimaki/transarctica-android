extends Node

# Static data about resources, in one place: the sprite frame (TradeResource) and the wagon type
# that carries each one (TrainInventory).
# Resource names are compared case-insensitively, because the data mixes "Oil" and "oil".
#
# frame      = frame in the TradeResource sprite sheet, or -1 if there is no sprite yet
# wagon_type = wagon type that carries it, or "" if no wagon carries it yet
# buy        = NOMINAL price the player pays for 1 unit
# sell       = NOMINAL price the player gets for 1 unit (keep it <= buy)
# A city multiplies them by its BuyFactor / SellFactor (see CityInventory), so a factor of 2 means
# "twice the nominal price" and prices of different cities can be compared at a glance.
# find_problems() lists the incomplete entries.
#
# NOTE: WagonTypes has "stores" / "default_cargo", which describe the same compatibility from
# the other side. Keep only one of the two.

const RESOURCES := {
    "alcohol": {"frame": 0, "wagon_type": "MerchandiseWagon", "buy": 10, "sell": 8},
    "antiques": {"frame": 1, "wagon_type": "MerchandiseWagon", "buy": 40, "sell": 30},
    "missiles": {"frame": 2, "wagon_type": "MerchandiseWagon", "buy": 6, "sell": 5},
    "bricks": {"frame": 3, "wagon_type": "MerchandiseWagon", "buy": 5, "sell": 4},
    "caviar": {"frame": 4, "wagon_type": "MerchandiseWagon", "buy": 12, "sell": 10},
    "oil": {"frame": 5, "wagon_type": "TankerWagon", "buy": 6, "sell": 5},
    "earth": {"frame": 6, "wagon_type": "MerchandiseWagon", "buy": 2, "sell": 1},
    "coal": {"frame": 7, "wagon_type": "TenderWagon", "buy": 4, "sell": 3},
    "plants": {"frame": 8, "wagon_type": "MerchandiseWagon", "buy": 12, "sell": 10},
    "red": {"frame": 9, "wagon_type": "", "buy": 5, "sell": 4}, # TODO: which wagon carries it?
    "mammothdung": {"frame": 10, "wagon_type": "MerchandiseWagon", "buy": 3, "sell": 2},
    "rails": {"frame": 11, "wagon_type": "MerchandiseWagon", "buy": 40, "sell": 30},
    "fish": {"frame": 12, "wagon_type": "MerchandiseWagon", "buy": 12, "sell": 10},
    "fishingrods": {"frame": 13, "wagon_type": "MerchandiseWagon", "buy": 4, "sell": 3},
    "salt": {"frame": 14, "wagon_type": "MerchandiseWagon", "buy": 4, "sell": 3},
    "furs": {"frame": 15, "wagon_type": "MerchandiseWagon", "buy": 10, "sell": 8},
    "gasoline": {"frame": 16, "wagon_type": "TankerWagon", "buy": 30, "sell": 25},
    "inspection": {"frame": 17, "wagon_type": "MerchandiseWagon", "buy": 20, "sell": 15},
    "gray": {"frame": 18, "wagon_type": "MerchandiseWagon", "buy": 5, "sell": 4},
    "meat": {"frame": 19, "wagon_type": "", "buy": 8, "sell": 6}, # TODO: same as "wolfmeat"?
    "wood": {"frame": 20, "wagon_type": "MerchandiseWagon", "buy": 3, "sell": 2},
    # No sprite frame yet:
    "water": {"frame": - 1, "wagon_type": "TankerWagon", "buy": 2, "sell": 1},
    "copper": {"frame": - 1, "wagon_type": "MerchandiseWagon", "buy": 10, "sell": 8},
    "wolfmeat": {"frame": - 1, "wagon_type": "MerchandiseWagon", "buy": 8, "sell": 6},
    "iron": {"frame": - 1, "wagon_type": "MerchandiseWagon", "buy": 12, "sell": 10},
    "ironore": {"frame": 23, "wagon_type": "MerchandiseWagon", "buy": 4, "sell": 3},
    "copperore": {"frame": - 1, "wagon_type": "MerchandiseWagon", "buy": 4, "sell": 3},
    "ironingot": {"frame": 21, "wagon_type": "MerchandiseWagon", "buy": 14, "sell": 12},
    "copperingot": {"frame": - 1, "wagon_type": "MerchandiseWagon", "buy": 12, "sell": 10},
    "woodplanks": {"frame": 22, "wagon_type": "MerchandiseWagon", "buy": 9, "sell": 8}
}


func is_known(resource_name: String) -> bool:
    return RESOURCES.has(resource_name.to_lower())


# Wagon type that carries this resource, or "" if unknown.
func wagon_type_for(resource_name: String) -> String:
    return RESOURCES.get(resource_name.to_lower(), {}).get("wagon_type", "")


# Sprite frame of this resource, or -1 if unknown or without sprite.
func frame_for(resource_name: String) -> int:
    return RESOURCES.get(resource_name.to_lower(), {}).get("frame", -1)


# Nominal price the player pays for 1 unit, or -1 if the resource is unknown.
func nominal_buy_price(resource_name: String) -> int:
    return RESOURCES.get(resource_name.to_lower(), {}).get("buy", -1)


# Nominal price the player gets for 1 unit, or -1 if the resource is unknown.
func nominal_sell_price(resource_name: String) -> int:
    return RESOURCES.get(resource_name.to_lower(), {}).get("sell", -1)


func same(a: String, b: String) -> bool:
    return a.to_lower() == b.to_lower()


# Incomplete entries: no sprite, no wagon type, or a wagon type that is not in WagonTypes.
func find_problems() -> Array[String]:
    var result: Array[String] = []
    for resource_name in RESOURCES:
        var info: Dictionary = RESOURCES[resource_name]
        if info.frame < 0:
            result.append("'%s' has no sprite frame" % resource_name)
        if info.buy <= 0 or info.sell <= 0:
            result.append("'%s' has no nominal price" % resource_name)
        elif info.buy < info.sell:
            result.append("'%s' has nominal buy %d < sell %d (infinite money)" % [resource_name, info.buy, info.sell])
        if info.wagon_type == "":
            result.append("'%s' has no wagon type" % resource_name)
        elif not WagonTypes.TYPES.has(info.wagon_type):
            result.append("'%s' needs '%s', which is not in WagonTypes" % [resource_name, info.wagon_type])
    return result