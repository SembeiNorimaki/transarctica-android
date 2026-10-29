class_name Edge
extends RefCounted
# Something on the border between two adjacent tiles: a wall, a fence, a window, a door...
# What each type does is data (EdgeTypes). An edge has no tile coordinates: EdgeOccupancyService
# knows where it is.
#
# Only EdgeOccupancyService should change an edge that is registered (open/close, damage), so that
# its signals fire and caches elsewhere can refresh.

var type := ""
var max_hp := 0 # 0 = indestructible
var hp := 0
var is_open := false

var _def := {}


## Returns null (and logs an error) for an unknown type.
static func create(edge_type: String) -> Edge:
    if not EdgeTypes.exists(edge_type):
        push_error("Edge: unknown edge type '%s'" % edge_type)
        return null
    var edge := Edge.new()
    edge.type = edge_type
    edge._def = EdgeTypes.get_def(edge_type)
    edge.max_hp = int(edge._def.get("hp", 0))
    edge.hp = edge.max_hp
    edge.is_open = bool(edge._def.get("starts_open", false)) and edge.can_toggle()
    return edge


func blocks_movement() -> bool:
    return bool(_flag("blocks_movement", false))

func blocks_vision() -> bool:
    return bool(_flag("blocks_vision", false))

func blocks_fire() -> bool:
    return bool(_flag("blocks_fire", false))

func cover() -> int:
    return int(_flag("cover", CoverLevel.NONE))

func can_toggle() -> bool:
    return _def.has("open")

func is_destructible() -> bool:
    return max_hp > 0

## Returns true when the edge is destroyed by this damage. Does nothing to an indestructible edge.
func take_damage(amount: int) -> bool:
    if not is_destructible() or amount <= 0:
        return false
    hp = maxi(hp - amount, 0)
    return hp == 0


func _flag(key: String, fallback: Variant) -> Variant:
    if is_open:
        var open_def: Dictionary = _def.get("open", {})
        if open_def.has(key):
            return open_def[key]
    return _def.get(key, fallback)
