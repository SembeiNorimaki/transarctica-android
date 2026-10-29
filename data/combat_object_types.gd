class_name CombatObjectTypes
extends RefCounted
# Static data of the objects standing on the battlefield (the "Objects" layer of a CombatMap).
#   layer : the TileOccupancyService layer it lives on. Units and obstacles block movement;
#           only LAYER_STRUCTURE also blocks sight (see VisionService.vision_blocking_layers).

const TYPES := {
    "crate": {"layer": TileOccupancyService.LAYER_OBSTACLE},
    "barrel": {"layer": TileOccupancyService.LAYER_OBSTACLE},
    "container": {"layer": TileOccupancyService.LAYER_STRUCTURE},
}


static func exists(object_type: String) -> bool:
    return TYPES.has(object_type)

static func get_layer(object_type: String) -> int:
    return int(TYPES.get(object_type, {}).get("layer", TileOccupancyService.LAYER_OBSTACLE))
