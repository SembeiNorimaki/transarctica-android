class_name Footprint
extends RefCounted
# The tiles an entity covers, as offsets from its anchor tile. Offset (0, 0) is the anchor itself.
# Works the same on isometric and cartesian maps: offsets are in tile space.
# Treat a Footprint as immutable once built: the occupancy service keeps a reference to it.

var offsets: Array[Vector2i] = [Vector2i.ZERO]

static var _single: Footprint


## One tile. Shared instance.
static func single() -> Footprint:
    if _single == null:
        _single = Footprint.new()
    return _single

## A width x height block. The anchor is its top-left tile (smallest x and y).
static func rect(width: int, height: int) -> Footprint:
    assert(width > 0 and height > 0, "Footprint: size must be positive")
    var fp := Footprint.new()
    fp.offsets = []
    for y in height:
        for x in width:
            fp.offsets.append(Vector2i(x, y))
    return fp

static func from_offsets(list: Array[Vector2i]) -> Footprint:
    assert(not list.is_empty(), "Footprint: needs at least one tile")
    var fp := Footprint.new()
    fp.offsets = list.duplicate()
    return fp


func tiles_at(anchor: Vector2i) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    for o in offsets:
        result.append(anchor + o)
    return result

## Rotated clockwise by 90 degrees * quarter_turns around the anchor (tile space, y points down).
func rotated(quarter_turns: int) -> Footprint:
    var turns := posmod(quarter_turns, 4)
    if turns == 0:
        return self
    var fp := Footprint.new()
    fp.offsets = []
    for o in offsets:
        var r := o
        for i in turns:
            r = Vector2i(-r.y, r.x)
        fp.offsets.append(r)
    return fp

func size() -> int:
    return offsets.size()
