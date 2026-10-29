class_name TileOccupancyService
extends Node
# Who stands on which tile. Generic: it only knows tile coordinates, so it works the same on
# isometric and cartesian maps, and for any kind of entity (units, buildings, crates, items...).
#
# Every entity is placed once, with an anchor tile, a Footprint (the tiles it covers around the
# anchor) and a layer (a bit; see the LAYER_* constants, add your own). Queries filter by a mask of
# layers. The service never decides who may stand where: ask is_footprint_free() first.
#
# Entities are any Object (usually Nodes). A Node that leaves the tree is removed automatically.

const LAYER_UNIT := 1
const LAYER_STRUCTURE := 2 # buildings, walls made of tiles, big props
const LAYER_OBSTACLE := 4 # small blockers: crates, wrecks, rocks
const LAYER_ITEM := 8 # loot: normally does not block anything
const LAYER_ALL := 0x7fffffff

signal entity_placed(entity: Object, tiles: Array[Vector2i])
signal entity_moved(entity: Object, old_tiles: Array[Vector2i], new_tiles: Array[Vector2i])
signal entity_removed(entity: Object, tiles: Array[Vector2i])
## Every change of occupancy, with all the tiles touched. Caches (navigation, vision) listen to this.
signal tiles_changed(tiles: Array[Vector2i])

## Tiles outside it count as not free. An empty rect (the default) means unbounded.
var bounds := Rect2i()

class Record:
    var anchor: Vector2i
    var footprint: Footprint
    var layer: int
    var tiles: Array[Vector2i]

var _records: Dictionary = {} # entity -> Record
var _tiles: Dictionary = {} # Vector2i -> Array of entities


#region placing
## Places a new entity. Does not check that the tiles are free. Placing an entity that is already
## placed moves it instead.
func place(entity: Object, anchor: Vector2i, footprint: Footprint = null, layer := LAYER_UNIT) -> void:
    assert(entity != null, "TileOccupancyService: null entity")
    if footprint == null:
        footprint = Footprint.single()
    if _records.has(entity):
        var old: Record = _records[entity]
        old.layer = layer
        _relocate(entity, anchor, footprint)
        return
    var rec := Record.new()
    rec.anchor = anchor
    rec.footprint = footprint
    rec.layer = layer
    rec.tiles = footprint.tiles_at(anchor)
    _records[entity] = rec
    for tile in rec.tiles:
        _add_to_tile(tile, entity)
    if entity is Node and not (entity as Node).tree_exiting.is_connected(_on_entity_exiting.bind(entity)):
        (entity as Node).tree_exiting.connect(_on_entity_exiting.bind(entity), CONNECT_ONE_SHOT)
    entity_placed.emit(entity, rec.tiles.duplicate())
    tiles_changed.emit(rec.tiles.duplicate())

## Moves a placed entity (keeping its footprint and layer). Does not check that the tiles are free.
func move(entity: Object, anchor: Vector2i) -> void:
    if not _records.has(entity):
        push_error("TileOccupancyService: move() of an entity that was never placed")
        return
    _relocate(entity, anchor, (_records[entity] as Record).footprint)

## Gives a placed entity another footprint (it turned, it grew...), same anchor.
func set_footprint(entity: Object, footprint: Footprint) -> void:
    if not _records.has(entity):
        push_error("TileOccupancyService: set_footprint() of an entity that was never placed")
        return
    _relocate(entity, (_records[entity] as Record).anchor, footprint)

func remove(entity: Object) -> void:
    if not _records.has(entity):
        return
    var rec: Record = _records[entity]
    for tile in rec.tiles:
        _remove_from_tile(tile, entity)
    _records.erase(entity)
    entity_removed.emit(entity, rec.tiles.duplicate())
    tiles_changed.emit(rec.tiles.duplicate())

func clear() -> void:
    var touched: Array[Vector2i] = []
    for tile: Vector2i in _tiles:
        touched.append(tile)
    _records.clear()
    _tiles.clear()
    if not touched.is_empty():
        tiles_changed.emit(touched)
#endregion


#region queries
func has_entity(entity: Object) -> bool:
    return _records.has(entity)

func get_anchor(entity: Object) -> Vector2i:
    assert(_records.has(entity), "TileOccupancyService: entity is not placed")
    return (_records[entity] as Record).anchor

func get_footprint(entity: Object) -> Footprint:
    assert(_records.has(entity), "TileOccupancyService: entity is not placed")
    return (_records[entity] as Record).footprint

func get_layer(entity: Object) -> int:
    assert(_records.has(entity), "TileOccupancyService: entity is not placed")
    return (_records[entity] as Record).layer

## All the tiles the entity covers. Empty if it is not placed.
func get_tiles_of(entity: Object) -> Array[Vector2i]:
    if not _records.has(entity):
        return []
    return (_records[entity] as Record).tiles.duplicate()

## Entities on the tile whose layer is in mask, in the order they arrived.
func get_entities_at(tile: Vector2i, mask := LAYER_ALL) -> Array:
    var result: Array = []
    for entity: Object in _tiles.get(tile, []):
        if (_records[entity] as Record).layer & mask:
            result.append(entity)
    return result

func get_first_at(tile: Vector2i, mask := LAYER_ALL) -> Object:
    for entity: Object in _tiles.get(tile, []):
        if (_records[entity] as Record).layer & mask:
            return entity
    return null

## Distinct entities touching any of the tiles.
func get_entities_in(tiles: Array[Vector2i], mask := LAYER_ALL) -> Array:
    var seen := {}
    var result: Array = []
    for tile in tiles:
        for entity: Object in get_entities_at(tile, mask):
            if not seen.has(entity):
                seen[entity] = true
                result.append(entity)
    return result

func get_entities_in_rect(rect: Rect2i, mask := LAYER_ALL) -> Array:
    var tiles: Array[Vector2i] = []
    for y in range(rect.position.y, rect.end.y):
        for x in range(rect.position.x, rect.end.x):
            tiles.append(Vector2i(x, y))
    return get_entities_in(tiles, mask)

func get_all_entities(mask := LAYER_ALL) -> Array:
    var result: Array = []
    for entity: Object in _records:
        if (_records[entity] as Record).layer & mask:
            result.append(entity)
    return result

## True if an entity of the mask layers stands on the tile. `ignore` is not counted (the mover).
func is_occupied(tile: Vector2i, mask := LAYER_ALL, ignore: Object = null) -> bool:
    for entity: Object in _tiles.get(tile, []):
        if entity != ignore and (_records[entity] as Record).layer & mask:
            return true
    return false

## Inside the bounds and not occupied (by the mask layers, apart from `ignore`).
func is_free(tile: Vector2i, mask := LAYER_ALL, ignore: Object = null) -> bool:
    if bounds.has_area() and not bounds.has_point(tile):
        return false
    return not is_occupied(tile, mask, ignore)

## Could a footprint be put at this anchor? Pass the entity as `ignore` to ask about moving it
## (its own tiles don't count).
func is_footprint_free(anchor: Vector2i, footprint: Footprint = null, mask := LAYER_ALL, ignore: Object = null) -> bool:
    if footprint == null:
        footprint = Footprint.single()
    for o in footprint.offsets:
        if not is_free(anchor + o, mask, ignore):
            return false
    return true
#endregion


func _relocate(entity: Object, anchor: Vector2i, footprint: Footprint) -> void:
    var rec: Record = _records[entity]
    var old_tiles := rec.tiles
    var new_tiles := footprint.tiles_at(anchor)
    for tile in old_tiles:
        _remove_from_tile(tile, entity)
    rec.anchor = anchor
    rec.footprint = footprint
    rec.tiles = new_tiles
    for tile in new_tiles:
        _add_to_tile(tile, entity)
    var touched: Array[Vector2i] = old_tiles.duplicate()
    for tile in new_tiles:
        if tile not in touched:
            touched.append(tile)
    entity_moved.emit(entity, old_tiles.duplicate(), new_tiles.duplicate())
    tiles_changed.emit(touched)

func _add_to_tile(tile: Vector2i, entity: Object) -> void:
    if not _tiles.has(tile):
        _tiles[tile] = []
    (_tiles[tile] as Array).append(entity)

func _remove_from_tile(tile: Vector2i, entity: Object) -> void:
    var list: Array = _tiles.get(tile, [])
    list.erase(entity)
    if list.is_empty():
        _tiles.erase(tile)

func _on_entity_exiting(entity: Object) -> void:
    remove(entity)
