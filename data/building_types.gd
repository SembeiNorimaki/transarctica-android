class_name BuildingTypes
extends RefCounted
# Static data of the buildings of the combat maps (see GenericBuilding). Which painted tile is which
# building is in data/combat_tiles.json.
#   size   : the tiles it covers, from its first (north) tile: 1 x 1 up to 4 x 4
#   max_hp : damage it takes before it is destroyed and leaves rubble

const TYPES := {
    "guard_post": {"size": Vector2i(1, 1), "max_hp": 60},
    "generator": {"size": Vector2i(1, 1), "max_hp": 90},
    "house": {"size": Vector2i(2, 2), "max_hp": 150},
    "workshop": {"size": Vector2i(2, 2), "max_hp": 200},
    "apartment": {"size": Vector2i(3, 3), "max_hp": 300},
    "warehouse": {"size": Vector2i(3, 3), "max_hp": 250},
    "factory": {"size": Vector2i(4, 4), "max_hp": 400},
    "bunker": {"size": Vector2i(4, 4), "max_hp": 700},
}


static func exists(building_type: String) -> bool:
    return TYPES.has(building_type)

static func get_size(building_type: String) -> Vector2i:
    return TYPES.get(building_type, {}).get("size", Vector2i.ONE)

static func get_max_hp(building_type: String) -> int:
    return int(TYPES.get(building_type, {}).get("max_hp", 100))
