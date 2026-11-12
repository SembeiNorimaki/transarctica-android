extends Node
# Test of data/combat_tiles.json: it says what each tile of the combat TileSets is (a building or a
# unit), so it has to agree with the TileSets, the building and unit types and the vehicle pictures.
# Run:  godot --headless --path . res://tests/combat_tiles_test_run.tscn

const BUILDINGS := "res://assets/combat/combat_buildings.tres"
const SPAWNS := "res://assets/combat/combat_spawns.tres"
const SQUARE_SPAWNS := "res://assets/combat/sq_spawns.tres"
const FRAME := Vector2i(70, 54) # a frame of assets/combat/FHUnits.png and of the placeholders
const UNITS_PNG := "res://assets/combat/FHUnits.png"
const PLACEHOLDERS_PNG := "res://assets/combat/unitsFH_placeholder.png"
const VEHICLES: Array[String] = ["artillery", "tank", "buggy", "grav_tank", "speeder", "humvee"] # the rows, in the order of the pictures

var _failed := 0
var _checks := 0

func skips_quests_when_debugging() -> bool:
    return true

func _ready() -> void:
    _run.call_deferred()

func ok(condition: bool, what: String) -> void:
    _checks += 1
    if not condition:
        _failed += 1
        print("FAIL: ", what)

func eq(actual: Variant, expected: Variant, what: String) -> void:
    _checks += 1
    if actual != expected:
        _failed += 1
        print("FAIL: %s (got %s, expected %s)" % [what, actual, expected])

func _run() -> void:
    _test_lookup()
    _test_buildings()
    _test_vehicles()
    _test_soldiers()
    await _test_maps()
    print("%d checks, %d failed" % [_checks, _failed])
    print("ALL PASSED" if _failed == 0 else "FAILED")
    get_tree().quit(1 if _failed > 0 else 0)


func _tiles_of(source: TileSetAtlasSource) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    for i in source.get_tiles_count():
        result.append(source.get_tile_id(i))
    return result


func _test_lookup() -> void:
    var facings := CombatTiles.get_column_facings()
    eq(facings.size(), 8, "a vehicle row has 8 columns, one for each orientation")
    for facing in facings:
        ok(facing in GridService.ORIENTATIONS, "'%s' is an orientation" % facing)
    eq(facings.size(), facings.duplicate().size(), "every column has a facing")
    var seen := {}
    for facing in facings:
        seen[facing] = true
    eq(seen.size(), 8, "and no two columns have the same one")

    eq(CombatTiles.lookup(BUILDINGS, 2, Vector2i(0, 0)), {"building_type": "apartment", "atlas_id": 2, "coords": Vector2i(0, 0)}, "atlas 2, (0, 0) of the buildings is an apartment")
    eq(CombatTiles.lookup(BUILDINGS, 0, Vector2i(1, 0))["building_type"], "generator", "atlas 0, (1, 0) is a generator")
    eq(CombatTiles.lookup(BUILDINGS, 9, Vector2i(0, 0)), {}, "an atlas that is not there stands for nothing")
    eq(CombatTiles.lookup("res://nothing.tres", 0, Vector2i(0, 0)), {}, "and neither does an unknown TileSet")
    var copy := CombatTiles.lookup(BUILDINGS, 2, Vector2i(0, 0))
    copy["building_type"] = "changed"
    eq(CombatTiles.lookup(BUILDINGS, 2, Vector2i(0, 0))["building_type"], "apartment", "lookup returns a copy")
    var tank := CombatTiles.lookup(SPAWNS, 1, Vector2i(0, 1))
    eq([tank["team"], tank["unit_type"], tank["facing"]], ["player", "tank", "NE"], "atlas 1, (0, 1) is the player's tank, looking east on the screen")
    var enemy := CombatTiles.lookup(SPAWNS, 1, Vector2i(1, 5))
    eq([enemy["team"], enemy["unit_type"], enemy["facing"]], ["enemy", "humvee", "NE"], "atlas 1, (1, 5) is the enemy's humvee")
    ok(CombatTiles.lookup(SPAWNS, 0, Vector2i(0, 0)).get("facing") == null, "a soldier tile has no facing")


func _test_buildings() -> void:
    var tile_set := load(BUILDINGS) as TileSet
    eq(tile_set.get_custom_data_layers_count(), 0, "the building TileSet holds only pictures")
    eq(tile_set.get_source_count(), 4, "one atlas for each size: 1x1, 2x2, 3x3, 4x4")
    var kinds := {}
    for atlas_id in tile_set.get_source_count():
        var source := tile_set.get_source(tile_set.get_source_id(atlas_id)) as TileSetAtlasSource
        var expected_size := atlas_id + 1
        for coords in _tiles_of(source):
            var entry := CombatTiles.lookup(BUILDINGS, atlas_id, coords)
            var building_type := str(entry.get("building_type", ""))
            ok(BuildingTypes.exists(building_type), "atlas %d %s is a known building (%s)" % [atlas_id, coords, building_type])
            if not BuildingTypes.exists(building_type):
                continue
            kinds[building_type] = int(kinds.get(building_type, 0)) + 1
            eq(BuildingTypes.get_size(building_type), Vector2i(expected_size, expected_size), "%s is in the atlas of %dx%d buildings" % [building_type, expected_size, expected_size])
            var region := source.get_tile_texture_region(coords)
            eq(int(region.size.x), expected_size * 2 * 32, "the picture of %s is as wide as its %dx%d tiles" % [building_type, expected_size, expected_size])
            ok(int(region.size.y) >= expected_size * 2 * 16, "and tall enough")
    for building_type in BuildingTypes.TYPES:
        eq(kinds.get(building_type, 0), 1, "%s is exactly one tile of the TileSet" % building_type)
    for entry in CombatTiles.get_entries(BUILDINGS):
        var source := tile_set.get_source(entry["atlas_id"]) as TileSetAtlasSource
        ok(source != null and source.has_tile(entry["coords"]), "the json entry %s %s is a tile of the TileSet" % [entry["atlas_id"], entry["coords"]])


func _test_vehicles() -> void:
    var tile_set := load(SPAWNS) as TileSet
    eq(tile_set.get_custom_data_layers_count(), 0, "the spawn TileSet holds only pictures")
    eq(tile_set.get_source_count(), 2, "soldiers, and the placeholders of the vehicles")
    var grid := GridService.new()
    grid.set_projection(GridService.TileProjection.ISOMETRIC)
    grid.set_tile_size(Vector2i(64, 32))
    var facings := CombatTiles.get_column_facings()
    eq(facings, ["S", "SW", "W", "NW", "N", "NE", "E", "SE"] as Array[String], "the columns of FHUnits.png: SW W NW N NE E SE S on the screen")
    # the placeholders: a column per team, a row per vehicle
    var source := tile_set.get_source(1) as TileSetAtlasSource
    eq(source.texture.resource_path, PLACEHOLDERS_PNG, "the vehicle tiles are the pictures of unitsFH_placeholder.png")
    eq((source.texture as Texture2D).get_size(), Vector2(FRAME.x * 2, FRAME.y * 7), "2 columns (player, enemy) by 7 rows (the turret too)")
    eq(source.texture_region_size, FRAME, "a placeholder is a frame of the pictures")
    eq(_tiles_of(source).size(), 2 * 6, "2 columns by 6 rows (no turret)")
    for coords in _tiles_of(source):
        var entry := CombatTiles.lookup(SPAWNS, 1, coords)
        var team := "player" if coords.x == 0 else "enemy"
        eq(entry.get("team"), team, "(%d, %d) is a %s unit" % [coords.x, coords.y, team])
        eq(entry.get("unit_type"), VEHICLES[coords.y], "row %d is the %s" % [coords.y, VEHICLES[coords.y]])
        eq(entry.get("facing"), "NE", "it looks east on the screen")
        eq(source.get_tile_data(coords, 0).texture_origin, Vector2i(0, 6), "its feet are on the middle of its tile")
    for row in VEHICLES.size():
        var unit_type := VEHICLES[row]
        ok(UnitTypes.exists(unit_type), "%s is a unit type" % unit_type)
        var scene := load(UnitTypes.get_scene_path(unit_type)) as PackedScene
        ok(scene != null, "%s has a scene" % unit_type)
        if scene == null:
            continue
        var unit := scene.instantiate() as Soldier
        # the unit shows its row of FHUnits.png (the enemy's is 7 rows below) and each column is the facing the json says
        var player_frames := unit.get_node("AnimatedSprite2D").sprite_frames as SpriteFrames
        ok(unit.enemy_frames != null, "%s has pictures for the enemy" % unit_type)
        for pair in [[player_frames, row], [unit.enemy_frames, row + 7]]:
            var frames := pair[0] as SpriteFrames
            if frames == null:
                continue
            for column in facings.size():
                var animation := StringName(grid.orientation_to_screen_direction(facings[column]))
                ok(frames.has_animation(animation), "%s has an animation '%s'" % [unit_type, animation])
                if not frames.has_animation(animation):
                    continue
                var texture := frames.get_frame_texture(animation, 0) as AtlasTexture
                eq(texture.region, Rect2(column * FRAME.x, pair[1] * FRAME.y, FRAME.x, FRAME.y), "%s: column %d (%s) of row %d is the picture of '%s'" % [unit_type, column, facings[column], pair[1], animation])
                eq(texture.atlas.resource_path, UNITS_PNG, "%s uses FHUnits.png" % unit_type)
        var size: Vector2i = UnitTypes.TYPES[unit_type].get("size", Vector2i.ONE)
        eq(UnitTypes.get_footprint(unit_type).size(), size.x * size.y, "%s covers %dx%d tiles" % [unit_type, size.x, size.y])
        unit.free()
    ok(not UnitTypes.exists("gunship") and not UnitTypes.exists("light_tank") and not UnitTypes.exists("heavy_tank"), "the old vehicles are gone")
    grid.free()


func _test_soldiers() -> void:
    var tile_set := load(SPAWNS) as TileSet
    var soldiers := tile_set.get_source(0) as TileSetAtlasSource
    eq(_tiles_of(soldiers).size(), 6, "six soldier tiles")
    var expected := [["player", "liquidator"], ["player", "pioneer"], ["player", "redops"], ["enemy", "liquidator"], ["enemy", "pioneer"], ["enemy", "redops"]]
    for i in 6:
        var entry := CombatTiles.lookup(SPAWNS, 0, Vector2i(i, 0))
        eq([entry.get("team"), entry.get("unit_type")], expected[i], "soldier tile %d" % i)
    var square := load(SQUARE_SPAWNS) as TileSet
    eq(square.get_custom_data_layers_count(), 0, "the square spawn TileSet holds only pictures")
    for i in 6:
        var entry := CombatTiles.lookup(SQUARE_SPAWNS, 0, Vector2i(i, 0))
        eq([entry.get("team"), entry.get("unit_type")], expected[i], "square soldier tile %d" % i)


# Every map reads its spawns and buildings through the json. The square and trench maps paint no
# spawns: their scenes put the units there themselves.
func _test_maps() -> void:
    var maps := {
        "res://scenes/maps/combat_map.tscn": true, "res://scenes/maps/combat_map_city.tscn": true,
        "res://scenes/maps/combat_map_square.tscn": false, "res://scenes/maps/combat_map_trenches.tscn": false,
    }
    for path: String in maps:
        var map := (load(path) as PackedScene).instantiate() as CombatMap
        add_child(map)
        await get_tree().process_frame
        var spawns := map.read_spawns()
        var painted := map.spawns.get_used_cells().size()
        eq(spawns.size(), painted, "%s: every painted spawn is a known unit (%d)" % [path.get_file(), painted])
        eq(painted > 0, maps[path], "%s %s spawns" % [path.get_file(), "has" if maps[path] else "paints no"])
        var teams := {}
        for spawn in spawns:
            teams[spawn["team"]] = true
            ok(UnitTypes.exists(spawn["unit_type"]), "%s: '%s' is a unit type" % [path.get_file(), spawn["unit_type"]])
        if maps[path]:
            eq(teams.size(), 2, "%s has both teams" % path.get_file())
        if map.buildings != null:
            var buildings := map.read_buildings()
            ok(buildings.size() > 0, "%s has buildings (%d)" % [path.get_file(), buildings.size()])
            eq(buildings.size(), map.buildings.get_used_cells().size(), "none of them is unknown")
        map.queue_free()
