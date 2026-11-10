extends Node
# Headless test of the isometric city battle (combat_scene_city.tscn): the big map with roads and
# buildings of 1x1 to 4x4 tiles (GenericBuildings, destroyable), one unit of each type per team (soldiers and
# six vehicles, 1x1 and 2x2), fog off by default, left click to walk, right click to turn, and the scrolling camera.
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
    await _test_vehicles_get_out()
    await _test_destroying_buildings()
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

    # buildings: placeholders in the map, GenericBuildings in the battle
    var placeholders := scene.combat_map.read_buildings()
    eq(placeholders.size(), scene.combat_map_manager.buildings.size(), "a GenericBuilding for each placeholder")
    ok(not scene.combat_map.buildings.visible, "the placeholder tiles are hidden")
    var sizes := {}
    var kinds := {}
    for building in scene.combat_map_manager.buildings:
        sizes[building.size] = int(sizes.get(building.size, 0)) + 1
        kinds[building.building_type] = true
        eq(scene.occupancy_service.get_tiles_of(building).size(), building.size.x * building.size.y, "building %s covers %d tiles" % [building.building_type, building.size.x * building.size.y])
        eq(scene.occupancy_service.get_layer(building), TileOccupancyService.LAYER_STRUCTURE, "a building is a structure")
        eq(building.get_parent(), scene.building_container, "it is in the building container")
        ok(building.sprite.texture != null, "%s has a picture" % building.name)
    for size in [Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 3), Vector2i(4, 4)]:
        ok(sizes.has(size), "there are %s buildings" % size)
    for kind in BuildingTypes.TYPES:
        ok(kinds.has(kind), "there is a %s" % kind)
    var one: GenericBuilding = scene.combat_map_manager.buildings[0]
    var corner: Vector2i = one.tile + one.size - Vector2i.ONE
    ok(scene.occupancy_service.is_occupied(corner, TileOccupancyService.LAYER_STRUCTURE), "the far corner of a building is blocked too")
    eq(scene.combat_map_manager.get_building_at(corner), one, "and it is the building that is found there")
    ok(scene.vision_service.has_line_of_sight(Vector2i(8, 20), Vector2i(8, 26)), "sight along a street is open")
    ok(not scene.fog_manager.enabled, "the fog is off by default")
    ok(not scene.combat_map.fog.visible, "and the fog layer is hidden")

    # the two wall tilesets are still used
    ok(scene.combat_map.walls_x.get_used_cells().size() > 0 and scene.combat_map.walls_y.get_used_cells().size() > 0, "walls on both edge layers")
    ok(not scene.combat_map.read_edges().is_empty(), "the walls are edges of the grid")

func _test_units() -> void:
    var types := ["liquidator", "pioneer", "redops", "tank", "artillery", "buggy", "grav_tank", "speeder", "gunship"]
    for team in ["player", "enemy"]:
        for unit_type in types:
            var count := 0
            for soldier in scene.battle_unit_manager.soldiers:
                if soldier.team == team and soldier.unit_type == unit_type:
                    count += 1
            eq(count, 1, "%s has exactly one %s" % [team, unit_type])
    eq(scene.battle_unit_manager.soldiers.size(), 18, "9 units a side")
    var big := 0
    for soldier in scene.battle_unit_manager.soldiers:
        var tiles := scene.occupancy_service.get_tiles_of(soldier)
        var size: Vector2i = UnitTypes.TYPES[soldier.unit_type].get("size", Vector2i.ONE)
        eq(tiles.size(), size.x * size.y, "%s covers %d tiles" % [soldier.unit_id, size.x * size.y])
        eq(soldier.footprint.size(), size.x * size.y, "%s has the footprint of its type" % soldier.unit_id)
        var middle := scene.grid_service.tile_to_world(Vector2(soldier.tile) + Vector2(size - Vector2i.ONE) / 2.0)
        ok(soldier.position.distance_to(middle) < 0.01, "%s is drawn in the middle of its tiles" % soldier.unit_id)
        if size == Vector2i(2, 2):
            big += 1
        ok(soldier.sprite.sprite_frames != null and soldier.sprite.sprite_frames.has_animation(StringName(scene.grid_service.orientation_to_screen_direction(soldier.facing))), "%s has a picture for the way it faces" % soldier.unit_id)
    eq(big, 8, "4 big vehicles a side (tank, artillery, grav tank, gunship)")
    # the markers say which way the vehicles face: the player's look up the screen, the enemy's down
    eq(_first("player", "tank").facing, "NW", "the player's vehicles face up the screen")
    eq(_first("enemy", "gunship").facing, "SE", "the enemy's face down")
    ok(WeaponTypes.get_def(_first("player", "artillery").weapon_type)["range"] > WeaponTypes.get_def(_first("player", "tank").weapon_type)["range"], "artillery outranges a tank")
    ok(_first("player", "grav_tank").max_hp > _first("player", "buggy").max_hp, "a grav tank has more hp than a buggy")
    ok(WeaponTypes.get_def(_first("player", "tank").weapon_type)["range"] > WeaponTypes.get_def("AK47")["range"], "tank cannons outrange rifles")
    ok(_first("player", "tank").tile.y > 40 and _first("enemy", "tank").tile.y < 16, "the teams start in opposite corners")
    for soldier in scene.battle_unit_manager.soldiers:
        ok(soldier.visible, "%s is visible (no fog)" % soldier.unit_id)


func _test_tank_pathfinding() -> void:
    var tank := _first("player", "tank")
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


# every vehicle can leave the yard: 2x2 ones through the 2-wide gaps, and reach the avenue
func _test_vehicles_get_out() -> void:
    for unit_type in ["tank", "artillery", "buggy", "grav_tank", "speeder", "gunship"]:
        var unit := _first("player", unit_type)
        var profile := scene.battle_unit_manager.get_profile(unit)
        var path := scene.pathfinding_service.find_path(unit.tile, Vector2i(40, 46), profile)
        ok(path.size() > 5, "the player's %s gets out of its yard (%d steps)" % [unit_type, path.size()])
        var enemy := _first("enemy", unit_type)
        var enemy_path := scene.pathfinding_service.find_path(enemy.tile, Vector2i(14, 8), scene.battle_unit_manager.get_profile(enemy))
        ok(enemy_path.size() > 5, "and the enemy's %s too (%d steps)" % [unit_type, enemy_path.size()])


# a building is destroyed when its hp run out: it leaves rubble and its tiles are free
func _test_destroying_buildings() -> void:
    var manager := scene.combat_map_manager
    var building: GenericBuilding = null
    for candidate in manager.buildings:
        if candidate.size == Vector2i(3, 3):
            building = candidate
            break
    ok(building != null, "found a 3x3 building")
    var tiles := building.get_tiles()
    eq(building.hp, building.max_hp, "a new building is undamaged")
    eq(building.max_hp, BuildingTypes.get_max_hp(building.building_type), "its hp are those of its type")
    var events := []
    building.damaged.connect(func(_b: GenericBuilding, amount: int) -> void: events.append(amount))
    var destroyed_signals := []
    manager.building_destroyed.connect(func(b: GenericBuilding) -> void: destroyed_signals.append(b))
    ok(not building.take_damage(10), "a hit that does not kill returns false")
    eq(building.hp, building.max_hp - 10, "hp go down")
    ok(building.sprite.modulate != Color.WHITE, "a damaged building looks damaged")
    ok(not building.take_damage(0) and not building.take_damage(-5), "no damage changes nothing")
    eq(events, [10], "damaged is emitted for each hit")
    for tile in tiles:
        ok(scene.occupancy_service.is_occupied(tile, TileOccupancyService.LAYER_STRUCTURE), "%s is still blocked" % tile)
    var soldier := _first("player", "liquidator")
    var profile := scene.battle_unit_manager.get_profile(soldier)
    var across_from := building.tile + Vector2i(-1, 1) # along the middle row of the building, from one side to the other
    var across_to := building.tile + Vector2i(building.size.x, 1)
    var before := scene.pathfinding_service.find_path(across_from, across_to, profile)
    for tile in before:
        ok(not tiles.has(tile), "before, the way round the building does not cross it (%s)" % tile)
    ok(building.take_damage(building.max_hp), "the hit that takes the last hp destroys it")
    ok(building.is_destroyed and building.hp == 0, "it is destroyed")
    ok(not building.sprite.visible and building.rubble.visible, "rubble instead of the building")
    eq(destroyed_signals, [building], "the manager says it was destroyed")
    for tile in tiles:
        ok(not scene.occupancy_service.is_occupied(tile, TileOccupancyService.LAYER_STRUCTURE), "%s is free now" % tile)
        ok(scene.terrain_service.is_walkable(tile), "and walkable")
    ok(manager.get_building_at(tiles[0]) == null, "no building is found there any more")
    ok(not building.take_damage(50), "a destroyed building takes no more damage")
    # a unit can now walk over what it left
    var after := scene.pathfinding_service.find_path(across_from, across_to, profile)
    ok(after.size() > 0, "a soldier finds a way across the ruin")
    var crosses := false
    for tile in after:
        if tiles.has(tile):
            crosses = true
    ok(crosses, "and it goes over the rubble")
    ok(after.size() <= before.size() or before.is_empty(), "which is shorter than going round")
    ok(scene.vision_service.has_line_of_sight(across_from, across_to), "and sight goes through where it stood")


func _test_clicks() -> void:
    var bum := scene.battle_unit_manager
    var tank := _first("player", "tank")
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

    # left click walks
    bum.select(tank)
    var goal := tank.tile + Vector2i(-3, 0)
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
    var building: GenericBuilding = null
    for candidate in scene.combat_map_manager.buildings:
        if not candidate.is_destroyed:
            building = candidate
            break
    var path := scene.pathfinding_service.find_path(tank.tile, building.tile, bum.get_profile(tank))
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
