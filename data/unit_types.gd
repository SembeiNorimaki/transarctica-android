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
}


# What a soldier of this type is like on the battlefield. Types can override any key with a
# "combat" dictionary in TYPES.
#   move_speed : tiles per second
#   view_range : tiles
#   view_angle : degrees, the width of the vision cone
const DEFAULT_COMBAT := {"move_speed": 3.0, "view_range": 8, "view_angle": 120.0}


static func combat_stats(unit_type: String) -> Dictionary:
    var stats := DEFAULT_COMBAT.duplicate()
    stats.merge(TYPES.get(unit_type, {}).get("combat", {}), true)
    return stats


static func exists(unit_type: String) -> bool:
    return TYPES.has(unit_type)


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