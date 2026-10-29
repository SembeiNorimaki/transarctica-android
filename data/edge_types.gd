class_name EdgeTypes
extends RefCounted
# Static data of the things that can sit on the border between two adjacent tiles (see Edge).
# No autoload needed: use EdgeTypes.exists(...) / EdgeTypes.get_def(...) from anywhere.
#
# Keys of a definition (all optional):
#   blocks_movement / blocks_vision / blocks_fire : bool, default false
#   cover : CoverLevel.NONE / HALF / FULL, default NONE (given to whoever is shot across the edge)
#   hp    : int, 0 or missing = indestructible
#   open  : overrides used while the edge is open. Its presence makes the edge toggleable (a door).
#   starts_open : bool, default false
# New types can be added at runtime (a campaign, a mod) with EdgeTypes.register().

const DEFS := {
    "wall": {
        "blocks_movement": true, "blocks_vision": true, "blocks_fire": true,
        "cover": CoverLevel.FULL, "hp": 40,
    },
    "fence": {
        "blocks_movement": true, "cover": CoverLevel.HALF, "hp": 20,
    },
    "window": {
        "blocks_movement": true, "cover": CoverLevel.FULL, "hp": 15,
    },
    "door": {
        "blocks_movement": true, "blocks_vision": true, "blocks_fire": true, "hp": 25,
        "open": {"blocks_movement": false, "blocks_vision": false, "blocks_fire": false, "cover": CoverLevel.NONE},
    },
}

static var _defs: Dictionary = DEFS.duplicate(true)


static func exists(edge_type: String) -> bool:
    return _defs.has(edge_type)

static func get_def(edge_type: String) -> Dictionary:
    return _defs.get(edge_type, {})

static func register(edge_type: String, definition: Dictionary) -> void:
    _defs[edge_type] = definition.duplicate(true)

static func reset() -> void:
    _defs = DEFS.duplicate(true)
