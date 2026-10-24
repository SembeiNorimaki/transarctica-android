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
    "pioneer": {"max_hp": 100, "weapon_type": "SniperRifle"},
    "redops": {"max_hp": 100, "weapon_type": "AK47"},
}


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