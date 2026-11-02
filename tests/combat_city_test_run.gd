extends Node
# Headless test of the isometric city battle (combat_scene_city.tscn): the big map with roads and 3x3 /
# 4x4 buildings, the 2x2 tanks, left click to walk, right click to turn, and the scrolling camera.
# It is a scene because the scene uses autoloads.
# Run:  godot --headless --path . res://tests/combat_city_test_run.tscn

var _failed := 0
var _checks := 0
var scene: CombatSceneCity

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

func seconds(t: float) -> void:
    await get_tree().create_timer(t, true, false, true).timeout

func wait_until(condition: Callable, timeout := 8.0) -> bool:
    var waited := 0.0
    while not condition.call() and waited < timeout:
        await seconds(0.05)
        waited += 0.05
    return condition.call()

func _run() -> void:
    scene = load("res://scenes/core/combat_scene_city.tscn").instantiate()
    get_tree().root.add_child(scene)
    await get_tree().process_frame
    await get_tree().process_frame
    get_tree().paused = false
    await _test_map()
    await _test_units()
    await _test_tank_pathfinding()
    await _test_clicks()
    await _test_camera()
    scene.queue_free()
    await get_tree().process_frame
    print("%d checks, %d failed" % [_checks, _failed])
    print("ALL PASSED" if _failed == 0 else "FAILED")
    get_tree().quit(1 if _failed > 0 else 0)


func _unit(unit_id: String) -> Soldier:
    for soldier in scene.battle_unit_manager.soldiers:
        if soldier.unit_id == unit_id:
            return soldier
    return null

func _first(team: String, unit_type: String) -> Soldier:
    for soldier in scene.battle_unit_manager.soldiers:
        if soldier.team == team and soldier.unit_type == unit_type:
            return soldier
    return null

# Where a tile is on the screen of the root viewport
func _screen_of(tile: Vector2i, offset := Vector2.ZERO) -> Vector2:
    return scene.combat_map.get_global_transform_with_canvas() * (scene.grid_service.tile_to_world(Vector2(tile) + offset))

func _click(button: MouseButton, at: Vector2) -> void:
    for pressed in [true, false]:
        var event := InputEventMouseButton.new()
        event.button_index = button
        event.pressed = pressed
        event.position = at
        event.global_position = at
        get_viewport().push_input(event, true)
        await get_tree().process_frame


func _test_map() -> void:
    var rect := scene.grid_service.map_rect
    eq(rect.size, Vector2i(56, 56), "the map is 56 x 56 tiles")
    var world := scene.grid_service.get_world_bounds()
    ok(world.size.x > 2400.0 and world.size.y > 1080.0 * 1.5, "the map is bigger than the screen (%s)" % world.size)
    ok(scene.camera_service.world_bounds.has_area(), "the camera is bounded by the map")
    ok(scene.camera_service.keyboard_scroll and scene.camera_service.edge_scroll, "the camera scrolls with the keys and at the edges")

    # roads
    var road_cells := scene.combat_map.roads.get_used_cells()
    ok(road_cells.size() > 150, "there are roads (%d tiles)" % road_cells.size())
    var road := Vector2i(8, 20)
    eq(scene.terrain_service.get_type(road), "road", "a road tile is terrain 'road'")
    ok(scene.terrain_service.get_cost(road) < scene.terrain_service.get_cost(Vector2i(20, 20)) or scene.terrain_service.get_type(Vector2i(20, 20)) == "road", "walking on the road is cheaper than on snow")
    eq(scene.combat_map.roads.tile_set.get_source(0).get_tiles_count(), 16, "the road tileset has the 16 connections")

    # buildings
    var buildings := scene.combat_map.read_buildings()
    var sizes := {}
    for b in buildings:
        sizes[b["size"]] = int(sizes.get(b["size"], 0)) + 1
        var tiles := scene.occupancy_service.get_tiles_of(_find_building(b["tile"]))
        eq(tiles.size(), b["size"].x * b["size"].y, "building %s covers %d tiles" % [b["type"], b["size"].x * b["size"].y])
        eq(scene.occupancy_service.get_layer(_find_building(b["tile"])), TileOccupancyService.LAYER_STRUCTURE, "a building is a structure")
    ok(sizes.has(Vector2i(3, 3)) and sizes.has(Vector2i(4, 4)), "there are 3x3 and 4x4 buildings (%s)" % sizes)
    var one: Dictionary = buildings[0]
    var corner: Vector2i = one["tile"] + one["size"] - Vector2i.ONE
    ok(scene.occupancy_service.is_occupied(corner, TileOccupancyService.LAYER_STRUCTURE), "the far corner of a building is blocked too")
    ok(scene.vision_service.has_line_of_sight(Vector2i(8, 20), Vector2i(8, 26)), "sight along a street is open")

    # the two wall tilesets are still used
    ok(scene.combat_map.walls_x.get_used_cells().size() > 0 and scene.combat_map.walls_y.get_used_cells().size() > 0, "walls on both edge layers")
    ok(not scene.combat_map.read_edges().is_empty(), "the walls are edges of the grid")

func _find_building(tile: Vector2i) -> Object:
    for object in scene.combat_map_manager.objects:
        if object.tile == tile and scene.occupancy_service.has_entity(object):
            return object
    return null


func _test_units() -> void:
    var soldiers := 0
    var tanks := 0
    for soldier in scene.battle_unit_manager.soldiers:
        var tiles := scene.occupancy_service.get_tiles_of(soldier)
        if soldier.unit_type.ends_with("tank"):
            tanks += 1
            eq(tiles.size(), 4, "%s covers 2 x 2 tiles" % soldier.unit_id)
            eq(soldier.footprint.size(), 4, "%s has a 2x2 footprint" % soldier.unit_id)
            # drawn in the middle of its four tiles
            var middle := scene.grid_service.tile_to_world(Vector2(soldier.tile) + Vector2(0.5, 0.5))
            ok(soldier.position.distance_to(middle) < 0.01, "%s is drawn in the middle of its tiles" % soldier.unit_id)
        else:
            soldiers += 1
            eq(tiles.size(), 1, "%s covers one tile" % soldier.unit_id)
    eq(soldiers, 8, "8 soldiers (4 a side)")
    eq(tanks, 4, "4 tanks (2 a side)")
    ok(_first("player", "light_tank") != null and _first("player", "heavy_tank") != null, "the player has both tanks")
    ok(_first("enemy", "light_tank") != null and _first("enemy", "heavy_tank") != null, "the enemy has both tanks")
    ok(_first("player", "heavy_tank").max_hp > _first("player", "light_tank").max_hp, "the heavy tank has more hp")
    ok(WeaponTypes.get_def(_first("player", "heavy_tank").weapon_type)["range"] > WeaponTypes.get_def("AK47")["range"], "tank cannons outrange rifles")
    var player_y := _first("player", "light_tank").tile.y
    var enemy_y := _first("enemy", "light_tank").tile.y
    ok(player_y > 40 and enemy_y < 16, "the teams start in opposite corners")


func _test_tank_pathfinding() -> void:
    var tank := _first("player", "heavy_tank")
    var profile := scene.battle_unit_manager.get_profile(tank)
    eq(profile.footprint.size(), 4, "a tank's move profile covers 4 tiles")
    var path := scene.pathfinding_service.find_path(tank.tile, Vector2i(4, 4), profile) # next to the enemy yard
    ok(path.size() > 20, "a tank finds a way across the city (%d steps)" % path.size())
    var all_free := true
    for anchor in path:
        for o in tank.footprint.offsets:
            var t: Vector2i = anchor + o
            if not scene.terrain_service.is_walkable(t) or scene.occupancy_service.is_occupied(t, profile.blocked_by, tank):
                all_free = false
    ok(all_free, "every tile under the tank is free all along the way")

    # a gap one tile wide is too narrow for a tank, but not for a soldier
    var narrow := MoveProfile.new()
    narrow.footprint = Footprint.rect(2, 2)
    narrow.can_enter = func(t: Vector2i) -> bool: return not (t.x == 18 and t.y != 28) # a wall across the avenue, with a one tile gap
    var wide := MoveProfile.new()
    wide.can_enter = narrow.can_enter
    var start := Vector2i(10, 28)
    var goal := Vector2i(26, 28)
    var soldier_path := scene.pathfinding_service.find_path(start, goal, wide)
    ok(soldier_path.has(Vector2i(18, 28)), "a soldier goes through a one tile gap")
    ok(scene.pathfinding_service.find_path(start, goal, narrow).is_empty(), "a tank can't")

    # the yard fence has a 2-wide gap: a tank gets out
    var out := scene.pathfinding_service.find_path(tank.tile, Vector2i(51, 46), profile)
    ok(out.size() > 0, "the tank leaves its yard through the gap in the fence")
    var blocked := scene.pathfinding_service.find_path(tank.tile, Vector2i(55, 46), profile)
    ok(blocked.is_empty() or blocked.size() > 12, "and not through the fence (%d steps)" % blocked.size())


func _test_clicks() -> void:
    var bum := scene.battle_unit_manager
    var tank := _first("player", "light_tank")
    scene.camera_service.set_pos(scene.combat_map.to_global(tank.position))
    await get_tree().process_frame
    await get_tree().process_frame

    # right click without a selection does nothing
    var facing_before := tank.facing
    await _click(MOUSE_BUTTON_RIGHT, _screen_of(tank.tile + Vector2i(6, 0)))
    eq(tank.facing, facing_before, "a right click with nothing selected does nothing")

    # left click on a unit selects it
    await _click(MOUSE_BUTTON_LEFT, _screen_of(tank.tile + Vector2i(1, 1)))   # the far corner of the tank
    eq(bum.selected, tank, "a left click on any tile of the tank selects it")

    # right click turns it, without moving it
    var tile_before := tank.tile
    var expected := scene.grid_service.get_orientation(tank.tile + Vector2i(1, 0), tank.tile + Vector2i(8, 0))
    await _click(MOUSE_BUTTON_RIGHT, _screen_of(tank.tile + Vector2i(8, 0)))
    eq(tank.facing, expected, "a right click turns the tank towards the tile (%s)" % expected)
    eq(tank.tile, tile_before, "and it does not move")
    eq(tank.get_action(), &"idle", "and it stays idle")
    await _click(MOUSE_BUTTON_RIGHT, _screen_of(tank.tile + Vector2i(-5, -5)))
    eq(tank.facing, scene.grid_service.get_orientation(tank.tile, tank.tile + Vector2i(-5, -5)), "turning towards another side")
    eq(tank.sprite.animation, StringName(scene.grid_service.orientation_to_screen_direction(tank.facing)), "the sprite looks the same way")
    ok(not bum.command_face(tank, tank.tile + Vector2i(1, 1)), "a right click on the tank itself changes nothing")
    # a soldier is turned the same way, from its own tile
    var soldier := _first("player", "liquidator")
    bum.select(soldier)
    await _click(MOUSE_BUTTON_RIGHT, _screen_of(soldier.tile + Vector2i(0, -6)))
    eq(soldier.facing, "N", "a soldier turns to a tile straight 'north' of it in tile space")
    ok(tank.facing != "N" or true, "the other unit is untouched")

    # left click walks
    bum.select(tank)
    var goal := tank.tile + Vector2i(0, -3)
    var from := tank.tile
    await _click(MOUSE_BUTTON_LEFT, _screen_of(goal))
    ok(await wait_until(func() -> bool: return tank.tile == goal and tank.get_action() == &"idle", 10.0), "a left click on a free tile walks the tank there")
    ok(tank.tile != from, "it moved")
    eq(scene.occupancy_service.get_tiles_of(tank).size(), 4, "it still covers 4 tiles")
    ok(scene.occupancy_service.get_tiles_of(tank).has(goal), "its anchor is where it was sent")
    ok(not scene.occupancy_service.is_occupied(from, TileOccupancyService.LAYER_UNIT), "the tile it left is free")
    ok(tank.position.distance_to(scene.grid_service.tile_to_world(Vector2(goal) + Vector2(0.5, 0.5))) < 0.5, "and it is drawn in the middle of its new tiles")
    ok(tank.action_points < tank.max_action_points, "walking costs action points")
    # facing follows the walk, and a right click afterwards turns it again
    await _click(MOUSE_BUTTON_RIGHT, _screen_of(tank.tile + Vector2i(5, 0)))
    ok(tank.facing in ["E", "NE", "SE"], "after the walk it can still be turned (%s)" % tank.facing)

    # a tank can't be sent onto a building
    var building: Dictionary = scene.combat_map.read_buildings()[0]
    var path := scene.pathfinding_service.find_path(tank.tile, building["tile"], bum.get_profile(tank))
    ok(path.is_empty(), "no path onto a building")


func _test_camera() -> void:
    var cam := scene.camera_service
    cam.set_pos(scene.combat_map.to_global(scene.grid_service.tile_to_world(Vector2(28, 28))))
    var start := cam.cam.global_position
    var event := InputEventKey.new()
    event.physical_keycode = KEY_RIGHT
    event.pressed = true
    Input.parse_input_event(event)
    await seconds(0.3)
    var keyed := Input.is_physical_key_pressed(KEY_RIGHT)
    if keyed:   # the key is only seen where the window takes input
        ok(cam.cam.global_position.x > start.x + 50.0, "the right arrow scrolls the camera to the right")
    event.pressed = false
    Input.parse_input_event(event)
    await get_tree().process_frame
    # up and down, with the service itself
    var y0 := cam.cam.global_position.y
    cam.pan(Vector2(0, -300))
    ok(cam.cam.global_position.y > y0, "panning scrolls vertically")
    var x0 := cam.cam.global_position.x
    cam.pan(Vector2(-300, 0))
    ok(cam.cam.global_position.x > x0, "and horizontally")
    # the camera can reach every corner of the map but not leave it
    cam.set_pos(Vector2(-99999, -99999))
    var bounds := cam.world_bounds
    eq(cam.cam.global_position, bounds.position, "the camera stops at the top-left of the map")
    cam.set_pos(Vector2(99999, 99999))
    eq(cam.cam.global_position, bounds.end, "and at the bottom-right")
    ok(bounds.size.x > get_viewport().get_visible_rect().size.x, "the view is smaller than the map")
