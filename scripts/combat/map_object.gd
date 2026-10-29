class_name MapObject
extends RefCounted
# A crate, a container... on the battlefield, as TileOccupancyService sees it. The drawing is a
# tile of the CombatMap's Objects layer; this is only what the services need to know.

var type := ""
var tile := Vector2i.ZERO


func _init(object_type := "", object_tile := Vector2i.ZERO) -> void:
    type = object_type
    tile = object_tile
