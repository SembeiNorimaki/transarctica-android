class_name WeaponTypes
extends RefCounted
# Static data of the weapons (the "weapon_type" of a soldier, see UnitTypes).
#   range    : tiles
#   damage   : hp taken off by a hit in the open (cover reduces it)
#   windup   : seconds between the order to fire and the shot
#   cooldown : seconds after the shot before the soldier can do something else
#   ap_cost  : action points a shot costs in turn based combat

const DEFAULT := {"range": 6, "damage": 15, "windup": 0.3, "cooldown": 0.6, "ap_cost": 2.0}

const TYPES := {
    "AK47": {"range": 7, "damage": 20, "windup": 0.3, "cooldown": 0.6, "ap_cost": 2.0},
    "SniperRifle": {"range": 12, "damage": 60, "windup": 0.6, "cooldown": 1.2, "ap_cost": 3.0},
}


## The weapon's data with every missing key filled from DEFAULT. Unknown weapons get DEFAULT.
static func get_def(weapon_type: String) -> Dictionary:
    var def := DEFAULT.duplicate()
    def.merge(TYPES.get(weapon_type, {}), true)
    return def
