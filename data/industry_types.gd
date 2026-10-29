class_name IndustryTypes
extends RefCounted
# What each KIND of place is: its picture in the trade scene and the recipes it can run.
# A city in cities_World2.json says which kind it is with "Kind". Without "Kind", its "Type"
# ("City", "Depot") is used, so Paris and the Central Depot need no extra field.
#
#   trade_image : picture shown by TradePlace in the trade scene. null: the scene's own picture stays.
#   recipes     : [{Name, Inputs: {resource: qty}, Outputs: {resource: qty}}]
#                 Inputs may be empty (a forest, a mine). Every resource used here must also be in the
#                 place's TradeResources, in the right mode: inputs "Buys" (or "Both"), outputs "Sells".
#
# Only the Sawmill picture is filled in: replace each `null` by a preload of its picture, e.g.
#   "trade_image": preload("res://assets/industries/navigation/Forest.png"),

const KINDS := {
    "City": {
        "trade_image": preload("res://assets/industries/navigation/City.png"),
        "recipes": [],
    },
    "Depot": {
        "trade_image": preload("res://assets/industries/navigation/Depot.png"),
        "recipes": [],
    },
    "Forest": {
        "trade_image": preload("res://assets/industries/navigation/Forest.png"),
        "recipes": [
            {"Name": "Chop wood", "Inputs": {}, "Outputs": {"wood": 5}},
        ],
    },
    "IronMine": {
        "trade_image": preload("res://assets/industries/navigation/Iron_mine.png"),
        "recipes": [
            {"Name": "Mine iron ore", "Inputs": {}, "Outputs": {"ironore": 5}},
        ],
    },
    "CoalMine": {
        "trade_image": preload("res://assets/industries/navigation/CoalMine.png"),
        "recipes": [
            {"Name": "Mine coal", "Inputs": {}, "Outputs": {"coal": 5}},
        ],
    },
    "Sawmill": {
        "trade_image": preload("res://assets/industries/navigation/SawMill.png"),
        "recipes": [
            {"Name": "Saw planks", "Inputs": {"wood": 2}, "Outputs": {"woodplanks": 1}},
        ],
    },
    "Foundry": {
        "trade_image": preload("res://assets/industries/navigation/Foundry.png"),
        "recipes": [
            {"Name": "Iron ingot", "Inputs": {"ironore": 2, "coal": 1}, "Outputs": {"ironingot": 1}},
            {"Name": "Copper ingot", "Inputs": {"copperore": 2, "coal": 1}, "Outputs": {"copperingot": 1}},
            {"Name": "Steel", "Inputs": {"ironore": 2, "coal": 1}, "Outputs": {"steel": 1}},
        ],
    },
    "Workshop": {
        "trade_image": preload("res://assets/industries/navigation/Workshop.png"),
        "recipes": [
            {"Name": "Make rails", "Inputs": {"woodplanks": 2, "ironingot": 1}, "Outputs": {"rails": 2}},
        ],
    },
}


static func exists(kind: String) -> bool:
    return KINDS.has(kind)


# The picture of this kind, or null (unknown kind, or no picture yet)
static func get_trade_image(kind: String) -> Texture2D:
    return KINDS.get(kind, {}).get("trade_image")


# A copy of the recipes of this kind: [] for an unknown kind or a kind without recipes
static func get_recipes(kind: String) -> Array:
    return KINDS.get(kind, {}).get("recipes", []).duplicate(true)


# Everything in KINDS that does not match the rest of the game's data
static func find_problems() -> Array[String]:
    var problems: Array[String] = []
    for kind in KINDS:
        for recipe in KINDS[kind].get("recipes", []):
            if recipe.get("Outputs", {}).is_empty():
                problems.append("%s: recipe '%s' has no outputs" % [kind, recipe.get("Name", "?")])
            for side in ["Inputs", "Outputs"]:
                for resource_name in recipe.get(side, {}):
                    if not ResourceTypes.is_known(resource_name):
                        problems.append("%s: recipe '%s' uses the unknown resource '%s'" % [kind, recipe.get("Name", "?"), resource_name])
    return problems