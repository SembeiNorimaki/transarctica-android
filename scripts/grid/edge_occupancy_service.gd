class_name EdgeOccupancyService
extends Node
# Which borders between adjacent tiles have an Edge (wall, fence, window, door...), and the rules
# that follow: can you walk across, see across, shoot across, how much cover it gives.
#
# An edge sits between two tiles that share a side (4-neighbors). It has no direction: the edge
# between A and B is the same as the one between B and A. Diagonal moves and sight are answered by
# looking at the sides around the corner they cross.
#
# Same service for isometric and cartesian maps: it only knows tile coordinates.

## Any change that can alter movement, sight or cover: added, removed, opened, closed.
signal edge_changed(a: Vector2i, b: Vector2i)
signal edge_destroyed(a: Vector2i, b: Vector2i, edge: Edge)

var _edges: Dictionary = {} # Vector4i (see _key) -> Edge


#region editing
## Puts an edge of this type between two adjacent tiles, replacing what was there.
## Returns the new edge (null for an unknown type or non adjacent tiles).
func add(a: Vector2i, b: Vector2i, edge_type: String) -> Edge:
    if not _are_adjacent(a, b):
        push_error("EdgeOccupancyService: %s and %s do not share a side" % [a, b])
        return null
    var edge := Edge.create(edge_type)
    if edge == null:
        return null
    _edges[_key(a, b)] = edge
    edge_changed.emit(a, b)
    return edge

## Puts an edge on one side of a tile. `side` is a unit step: (0,-1), (1,0), (0,1) or (-1,0).
func add_side(tile: Vector2i, side: Vector2i, edge_type: String) -> Edge:
    return add(tile, tile + side, edge_type)

## Puts the same edge type on every border crossed by a straight horizontal or vertical run of
## tiles: `length` tiles starting at `start`, going `direction`, each with its edge on `side`.
func add_run(start: Vector2i, direction: Vector2i, length: int, side: Vector2i, edge_type: String) -> void:
    for i in length:
        add_side(start + direction * i, side, edge_type)

func remove(a: Vector2i, b: Vector2i) -> bool:
    if not _are_adjacent(a, b) or not _edges.erase(_key(a, b)):
        return false
    edge_changed.emit(a, b)
    return true

func clear() -> void:
    var keys := _edges.keys()
    _edges.clear()
    for key: Vector4i in keys:
        edge_changed.emit(Vector2i(key.x, key.y), Vector2i(key.z, key.w))

## Opens or closes a toggleable edge (a door). Returns false if there is none or it can't toggle.
func set_open(a: Vector2i, b: Vector2i, open: bool) -> bool:
    var edge := get_edge(a, b)
    if edge == null or not edge.can_toggle():
        return false
    if edge.is_open != open:
        edge.is_open = open
        edge_changed.emit(a, b)
    return true

func toggle(a: Vector2i, b: Vector2i) -> bool:
    var edge := get_edge(a, b)
    return edge != null and set_open(a, b, not edge.is_open)

## Damages the edge. Returns true if it was destroyed (and removed).
func damage(a: Vector2i, b: Vector2i, amount: int) -> bool:
    var edge := get_edge(a, b)
    if edge == null or not edge.take_damage(amount):
        return false
    _edges.erase(_key(a, b))
    edge_destroyed.emit(a, b, edge)
    edge_changed.emit(a, b)
    return true
#endregion


#region queries
func get_edge(a: Vector2i, b: Vector2i) -> Edge:
    if not _are_adjacent(a, b):
        return null
    return _edges.get(_key(a, b), null)

func has_edge(a: Vector2i, b: Vector2i) -> bool:
    return get_edge(a, b) != null

## The edges around a tile, keyed by side (0,-1), (1,0), (0,1), (-1,0).
func get_edges_of(tile: Vector2i) -> Dictionary:
    var result := {}
    for side: Vector2i in GridService.NEIGHBORS_4:
        var edge := get_edge(tile, tile + side)
        if edge != null:
            result[side] = edge
    return result

func get_edge_count() -> int:
    return _edges.size()

## Can a unit step from one tile to a neighboring one (8 directions) as far as edges are concerned?
## A diagonal step is also blocked by any edge touching the corner it passes, so units can't cut
## around the end of a wall.
func is_move_blocked(from: Vector2i, to: Vector2i) -> bool:
    var d := to - from
    if d == Vector2i.ZERO or absi(d.x) > 1 or absi(d.y) > 1:
        push_error("EdgeOccupancyService: %s and %s are not neighbors" % [from, to])
        return true
    if d.x == 0 or d.y == 0:
        return _blocks(from, to, 0)
    var a := from + Vector2i(d.x, 0)
    var b := from + Vector2i(0, d.y)
    return _blocks(from, a, 0) or _blocks(a, to, 0) or _blocks(from, b, 0) or _blocks(b, to, 0)

## Does sight (kind 1) or fire (kind 2) get stopped between two neighboring tiles?
## A diagonal passes if at least one of the two routes around the corner is open.
func is_view_blocked(from: Vector2i, to: Vector2i) -> bool:
    return _is_blocked_either_way(from, to, 1)

func is_fire_blocked(from: Vector2i, to: Vector2i) -> bool:
    return _is_blocked_either_way(from, to, 2)

## Cover that the tile `to` gets against someone shooting from the neighboring tile `from`.
func get_cover(from: Vector2i, to: Vector2i) -> int:
    var d := to - from
    if d == Vector2i.ZERO or absi(d.x) > 1 or absi(d.y) > 1:
        return CoverLevel.NONE
    if d.x == 0 or d.y == 0:
        return _cover_of(from, to)
    # diagonal: the sides of `to` that face the shooter
    return maxi(_cover_of(from + Vector2i(d.x, 0), to), _cover_of(from + Vector2i(0, d.y), to))
#endregion


func _is_blocked_either_way(from: Vector2i, to: Vector2i, kind: int) -> bool:
    var d := to - from
    if d == Vector2i.ZERO or absi(d.x) > 1 or absi(d.y) > 1:
        push_error("EdgeOccupancyService: %s and %s are not neighbors" % [from, to])
        return true
    if d.x == 0 or d.y == 0:
        return _blocks(from, to, kind)
    var a := from + Vector2i(d.x, 0)
    var b := from + Vector2i(0, d.y)
    var route_a := _blocks(from, a, kind) or _blocks(a, to, kind)
    var route_b := _blocks(from, b, kind) or _blocks(b, to, kind)
    return route_a and route_b

# kind: 0 movement, 1 vision, 2 fire
func _blocks(a: Vector2i, b: Vector2i, kind: int) -> bool:
    var edge: Edge = _edges.get(_key(a, b), null)
    if edge == null:
        return false
    match kind:
        0: return edge.blocks_movement()
        1: return edge.blocks_vision()
        _: return edge.blocks_fire()

func _cover_of(a: Vector2i, b: Vector2i) -> int:
    var edge: Edge = _edges.get(_key(a, b), null)
    return CoverLevel.NONE if edge == null else edge.cover()

func _are_adjacent(a: Vector2i, b: Vector2i) -> bool:
    var d := b - a
    return absi(d.x) + absi(d.y) == 1

# Same key whichever way round the tiles are given.
func _key(a: Vector2i, b: Vector2i) -> Vector4i:
    if a.x < b.x or (a.x == b.x and a.y < b.y):
        return Vector4i(a.x, a.y, b.x, b.y)
    return Vector4i(b.x, b.y, a.x, a.y)
