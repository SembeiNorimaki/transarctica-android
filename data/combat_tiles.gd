class_name CombatTiles
extends RefCounted
# What the painted tiles of the combat maps stand for: a building or a unit. The relation between
# a tile (the TileSet file of its layer, its atlas id and its atlas coords) and what it stands for
# is in data/combat_tiles.json, not in the TileSets, so a TileSet only needs pictures.
#
#   CombatTiles.lookup("res://assets/combat/combat_buildings.tres", 2, Vector2i(0, 0))
#   -> {"building_type": "apartment"}
#   CombatTiles.lookup("res://assets/combat/combat_spawns.tres", 1, Vector2i(0, 0))
#   -> {"team": "player", "unit_type": "tank", "facing": "NW"}   (the first column of a vehicle row)
#
# An empty dictionary means the tile stands for nothing.

const PATH := "res://data/combat_tiles.json"

static var _tilesets := {} # TileSet path -> {"atlas_id:x,y" -> entry}
static var _facings: Array[String] = []
static var _loaded := false


## What this tile stands for. The returned dictionary is a copy.
static func lookup(tileset_path: String, atlas_id: int, coords: Vector2i) -> Dictionary:
    _load()
    var entries: Dictionary = _tilesets.get(tileset_path, {})
    return (entries.get(_key(atlas_id, coords), {}) as Dictionary).duplicate()

## The facing (tile-space orientation) of each column of an atlas row that covers a whole row (see the "row" entries).
static func get_column_facings() -> Array[String]:
    _load()
    return _facings.duplicate()

## Every tile of this TileSet that stands for something: [{"atlas_id", "coords", ...}].
static func get_entries(tileset_path: String) -> Array[Dictionary]:
    _load()
    var result: Array[Dictionary] = []
    var entries: Dictionary = _tilesets.get(tileset_path, {})
    for key: String in entries:
        result.append((entries[key] as Dictionary).duplicate())
    return result

## Reads the file again (after it was edited).
static func reload() -> void:
    _loaded = false
    _load()


static func _key(atlas_id: int, coords: Vector2i) -> String:
    return "%d:%d,%d" % [atlas_id, coords.x, coords.y]

static func _load() -> void:
    if _loaded:
        return
    _loaded = true
    _tilesets = {}
    _facings = []
    var text := FileAccess.get_file_as_string(PATH)
    var parsed: Variant = JSON.parse_string(text)
    if not parsed is Dictionary:
        push_error("CombatTiles: %s is missing or is not a JSON object" % PATH)
        return
    for facing in parsed.get("column_facings", []):
        _facings.append(str(facing))
    var tilesets: Dictionary = parsed.get("tilesets", {})
    for tileset_path: String in tilesets:
        var index := {}
        for raw: Dictionary in tilesets[tileset_path]:
            _add_entry(index, raw, tileset_path)
        _tilesets[tileset_path] = index

static func _add_entry(index: Dictionary, raw: Dictionary, tileset_path: String) -> void:
    var atlas_id := int(raw.get("atlas_id", 0))
    var meaning := raw.duplicate()
    meaning.erase("atlas_id")
    meaning.erase("coords")
    meaning.erase("row")
    if raw.has("row"):
        # the whole row: one tile per column, each column a facing
        for column in _facings.size():
            var entry := meaning.duplicate()
            entry["facing"] = _facings[column]
            entry["atlas_id"] = atlas_id
            entry["coords"] = Vector2i(column, int(raw["row"]))
            index[_key(atlas_id, entry["coords"])] = entry
    elif raw.has("coords"):
        var c: Array = raw["coords"]
        meaning["atlas_id"] = atlas_id
        meaning["coords"] = Vector2i(int(c[0]), int(c[1]))
        index[_key(atlas_id, meaning["coords"])] = meaning
    else:
        push_warning("CombatTiles: an entry of %s has neither coords nor row" % tileset_path)
