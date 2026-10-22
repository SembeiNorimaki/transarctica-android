extends Node

# Static data about resources, in one place: the sprite frame (TradeResource) and the wagon type
# that carries each one (TrainInventory).
# Resource names are compared case-insensitively, because the data mixes "Oil" and "oil".
#
# frame      = frame in the TradeResource sprite sheet, or -1 if there is no sprite yet
# wagon_type = wagon type that carries it, or "" if no wagon carries it yet
# find_problems() lists the incomplete entries.
#
# NOTE: WagonTypes has "stores" / "default_cargo", which describe the same compatibility from
# the other side. Keep only one of the two.

const RESOURCES := {
    "alcohol": {"frame": 0, "wagon_type": "MerchandiseWagon"},
    "antiques": {"frame": 1, "wagon_type": "MerchandiseWagon"},
    "missiles": {"frame": 2, "wagon_type": "MerchandiseWagon"},
    "bricks": {"frame": 3, "wagon_type": "MerchandiseWagon"},
    "caviar": {"frame": 4, "wagon_type": "MerchandiseWagon"},
    "oil": {"frame": 5, "wagon_type": "TankerWagon"},
    "earth": {"frame": 6, "wagon_type": "MerchandiseWagon"},
    "coal": {"frame": 7, "wagon_type": "TenderWagon"},
    "plants": {"frame": 8, "wagon_type": "MerchandiseWagon"},
    "red": {"frame": 9, "wagon_type": ""}, # TODO: which wagon carries it?
    "mammothdung": {"frame": 10, "wagon_type": "MerchandiseWagon"},
    "rails": {"frame": 11, "wagon_type": "MerchandiseWagon"},
    "fish": {"frame": 12, "wagon_type": "MerchandiseWagon"},
    "fishingrods": {"frame": 13, "wagon_type": "MerchandiseWagon"},
    "salt": {"frame": 14, "wagon_type": "MerchandiseWagon"},
    "furs": {"frame": 15, "wagon_type": "MerchandiseWagon"},
    "gasoline": {"frame": 16, "wagon_type": "TankerWagon"},
    "inspection": {"frame": 17, "wagon_type": "MerchandiseWagon"},
    "gray": {"frame": 18, "wagon_type": "MerchandiseWagon"},
    "meat": {"frame": 19, "wagon_type": ""}, # TODO: same as "wolfmeat"?
    "wood": {"frame": 20, "wagon_type": "MerchandiseWagon"},
    # No sprite frame yet:
    "water": {"frame": - 1, "wagon_type": "TankerWagon"},
    "copper": {"frame": - 1, "wagon_type": "MerchandiseWagon"},
    "wolfmeat": {"frame": - 1, "wagon_type": "MerchandiseWagon"},
    "iron": {"frame": - 1, "wagon_type": "MerchandiseWagon"},
    "ironore": {"frame": - 1, "wagon_type": "MerchandiseWagon"},
    "copperore": {"frame": - 1, "wagon_type": "MerchandiseWagon"},
    "ironingot": {"frame": - 1, "wagon_type": "MerchandiseWagon"},
    "copperingot": {"frame": - 1, "wagon_type": "MerchandiseWagon"},
}


func is_known(resource_name: String) -> bool:
    return RESOURCES.has(resource_name.to_lower())


# Wagon type that carries this resource, or "" if unknown.
func wagon_type_for(resource_name: String) -> String:
    return RESOURCES.get(resource_name.to_lower(), {}).get("wagon_type", "")


# Sprite frame of this resource, or -1 if unknown or without sprite.
func frame_for(resource_name: String) -> int:
    return RESOURCES.get(resource_name.to_lower(), {}).get("frame", -1)


func same(a: String, b: String) -> bool:
    return a.to_lower() == b.to_lower()


# Incomplete entries: no sprite, no wagon type, or a wagon type that is not in WagonTypes.
func find_problems() -> Array[String]:
    var result: Array[String] = []
    for resource_name in RESOURCES:
        var info: Dictionary = RESOURCES[resource_name]
        if info.frame < 0:
            result.append("'%s' has no sprite frame" % resource_name)
        if info.wagon_type == "":
            result.append("'%s' has no wagon type" % resource_name)
        elif not WagonTypes.TYPES.has(info.wagon_type):
            result.append("'%s' needs '%s', which is not in WagonTypes" % [resource_name, info.wagon_type])
    return result
