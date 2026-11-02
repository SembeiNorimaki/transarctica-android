class_name UnitTypes
extends RefCounted
# Static data of the soldier types the player can recruit. No autoload needed: use UnitTypes.TYPES
# or the helpers below from anywhere.
#
# The dynamic data of a soldier (hp, experience, weapon...) lives in GameState's units, keyed by
# the id "u0", "u1"... A barracks wagon only lists the ids of the soldiers it holds ("unit_ids").
# A new recruit starts with the values below.

const TYPES := {
    "liquidator": {"max_hp": 100, "weapon_type": "AK47"},
    "pioneer": {"max_hp": 100, "weapon_type": "SniperRifle", "combat": {"view_range": 12, "view_angle": 90.0}},
    "redops": {"max_hp": 100, "weapon_type": "AK47"},
    # Tanks cover 2 x 2 tiles ("size"). "scene" is the unit scene to use instead of the soldier's.
    "light_tank": {
        "max_hp": 250, "weapon_type": "TankCannon", "size": Vector2i(2, 2),
        "scene": "res://scenes/units/light_tank.tscn",
        "combat": {"move_speed": 2.0, "view_range": 10, "view_angle": 100.0, "max_ap": 10.0},
    },
    "heavy_tank": {
        "max_hp": 450, "weapon_type": "HeavyCannon", "size": Vector2i(2, 2),
        "scene": "res://scenes/units/heavy_tank.tscn",
        "combat": {"move_speed": 1.5, "view_range": 9, "view_angle": 90.0, "max_ap": 8.0},
    },
}

const SOLDIER_SCENE := "res://scenes/units/soldier.tscn"

static var _footprints := {}


# What a soldier of this type is like on the battlefield. Types can override any key with a
# "combat" dictionary in TYPES.
#   move_speed : tiles per second
#   view_range : tiles
#   view_angle : degrees, the width of the vision cone
#   max_ap     : action points per turn in turn based combat (a step on flat ground costs 1)
const DEFAULT_COMBAT := {"move_speed": 3.0, "view_range": 8, "view_angle": 120.0, "max_ap": 8.0}


static func combat_stats(unit_type: String) -> Dictionary:
    var stats := DEFAULT_COMBAT.duplicate()
    stats.merge(TYPES.get(unit_type, {}).get("combat", {}), true)
    return stats


static func exists(unit_type: String) -> bool:
    return TYPES.has(unit_type)


## The tiles a unit of this type covers: one for a soldier, 2 x 2 for a tank.
static func get_footprint(unit_type: String) -> Footprint:
    var size: Vector2i = TYPES.get(unit_type, {}).get("size", Vector2i.ONE)
    if size == Vector2i.ONE:
        return Footprint.single()
    if not _footprints.has(size):
        _footprints[size] = Footprint.rect(size.x, size.y)
    return _footprints[size]

## The scene of the unit on the battlefield.
static func get_scene_path(unit_type: String) -> String:
    return str(TYPES.get(unit_type, {}).get("scene", SOLDIER_SCENE))


# The data of a fresh recruit, without an id (GameState gives it one)
static func make_unit(unit_type: String) -> Dictionary:
    var info: Dictionary = TYPES[unit_type]
    return {
        "unit_type": unit_type,
        "hp": info["max_hp"],
        "max_hp": info["max_hp"],
        "experience": 0,
        "weapon_type": info["weapon_type"],
        "owner_id": "Player",
    }