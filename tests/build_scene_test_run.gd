extends Node
# Headless test of the build scene (build_scene.tscn): the city map with no enemies, real time with
# no action points, nobody shoots, and the Buildings / Roads / Walls tools of the BuildBar.
# It is a scene because the scene uses autoloads.
# Run:  godot --headless --path . res://tests/build_scene_test_run.tscn

var _failed := 0
var _checks := 0
var scene: BuildScene

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
    scene = load("res://scenes/core/build_scene.tscn").instantiate()
    get_tree().root.add_child(scene)
    await get_tree().process_frame
    await get_tree().process_frame
    get_tree().paused = false
    await _test_setup()
    await _test_units()
    await _test_buildings()
    _test_roads()
    await _test_building_needs_road()
    await _test_road_drag()
    await _test_speed()
    _test_walls()
    _test_tools()
    scene.queue_free()
    await get_tree().process_frame
    print("%d checks, %d failed" % [_checks, _failed])
    print("ALL PASSED" if _failed == 0 else "FAILED")
    get_tree().quit(1 if _failed > 0 else 0)


# The first tile where a building of this type can be built
func _spot_for(building_type: String, after := 0) -> Vector2i:
    var found := 0
    var rect := scene.grid_service.map_rect
    for y in range(rect.position.y, rect.end.y):
        for x in range(rect.position.x, rect.end.x):
            if scene.combat_map_manager.why_not_building(building_type, Vector2i(x, y)) == "":
                if found == after:
                    return Vector2i(x, y)
                found += 1
    return Vector2i(-1, -1)

func _road_spot() -> Vector2i:
    # a tile and its east neighbor, both free for a road
    var rect := scene.grid_service.map_rect
    for y in range(rect.position.y, rect.end.y):
        for x in range(rect.position.x, rect.end.x - 2):
            var tile := Vector2i(x, y)
            if scene.combat_map_manager.why_not_road(tile) == "" and scene.combat_map_manager.why_not_road(tile + Vector2i(1, 0)) == "" \
                    and not scene.combat_map.has_road(tile + Vector2i(-1, 0)) and not scene.combat_map.has_road(tile + Vector2i(2, 0)) \
                    and not scene.combat_map.has_road(tile + Vector2i(0, -1)) and not scene.combat_map.has_road(tile + Vector2i(0, 1)) \
                    and not scene.combat_map.has_road(tile + Vector2i(1, -1)) and not scene.combat_map.has_road(tile + Vector2i(1, 1)):
                return tile
    return Vector2i(-1, -1)

# Where the pointer is on the screen when it is over a tile
func _screen_of(tile: Vector2i) -> Vector2:
    return scene.combat_map.get_global_transform_with_canvas() * (scene.grid_service.tile_to_world(Vector2(tile)))

func _mouse(pressed: bool, at: Vector2) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = at
    event.global_position = at
    get_viewport().push_input(event, true)

func _motion(at: Vector2) -> void:
    var event := InputEventMouseMotion.new()
    event.position = at
    event.global_position = at
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    get_viewport().push_input(event, true)

# A place for a building with a ring of free tiles round it (for roads), and no road along it
func _bare_spot(building_type: String, avoid: Array[Vector2i] = []) -> Vector2i:
    var size := BuildingTypes.get_size(building_type)
    var rect := scene.grid_service.map_rect
    var manager := scene.combat_map_manager
    for y in range(rect.position.y + 1, rect.end.y - size.y - 1):
        for x in range(rect.position.x + 1, rect.end.x - size.x - 1):
            var tile := Vector2i(x, y)
            var far := true
            for other in avoid:
                if Vector2(other).distance_to(Vector2(tile)) < 8.0:
                    far = false
            if not far:
                continue
            var clear := true
            for dy in range(-1, size.y + 1):
                for dx in range(-1, size.x + 1):
                    var t := tile + Vector2i(dx, dy)
                    var inside := dx >= 0 and dy >= 0 and dx < size.x and dy < size.y
                    if inside:
                        clear = clear and scene.terrain_service.is_walkable(t) and scene.terrain_service.get_type(t) != "road" and scene.occupancy_service.is_free(t)
                    else:
                        clear = clear and manager.why_not_road(t) == ""
            if clear and manager.get_road_sides(building_type, tile).is_empty():
                return tile
    return Vector2i(-1, -1)

func _player_unit() -> Soldier:
    for soldier in scene.battle_unit_manager.soldiers:
        if soldier.team == "player" and soldier.unit_type == "liquidator":
            return soldier
    return null

func _test_setup() -> void:
    var m := scene.battle_unit_manager
    ok(m.soldiers.size() > 0, "the player's units are there")
    for soldier in m.soldiers:
        eq(soldier.team, "player", "only the player's units are deployed (%s)" % soldier.unit_id)
    ok(scene.flow_manager is RtsManager, "real time: no action points")
    eq((scene.flow_manager as RtsManager).auto_engage, false, "nobody fires on its own")
    eq(m.attacks_enabled, false, "shooting is off")
    eq(scene.end_turn_button.visible, false, "no End turn button")
    eq(scene.build_manager.tool, BuildManager.Tool.NONE, "no tool at the start")
    eq(scene.build_bar.building_select.visible, false, "the building list shows with the Buildings tool only")
    eq(scene.build_bar.building_select.item_count, BuildingTypes.TYPES.size(), "every building type is in the list")

func _test_units() -> void:
    var m := scene.battle_unit_manager
    var unit: Soldier = null
    var goal := Vector2i.ZERO
    var rect := scene.grid_service.map_rect
    for candidate_unit in m.soldiers: # a foot soldier that is not boxed in
        if unit != null or candidate_unit.footprint.tiles_at(Vector2i.ZERO).size() != 1:
            continue
        for dy in range(-6, 7):
            for dx in range(-6, 7):
                var candidate: Vector2i = candidate_unit.tile + Vector2i(dx, dy)
                if unit == null and maxi(absi(dx), absi(dy)) >= 3 and rect.has_point(candidate) and scene.terrain_service.is_walkable(candidate) \
                        and scene.occupancy_service.is_free(candidate) \
                        and not scene.pathfinding_service.find_path(candidate_unit.tile, candidate, m.get_profile(candidate_unit)).is_empty():
                    unit = candidate_unit
                    goal = candidate
    ok(unit != null, "found a unit and a tile to walk to")
    if unit == null:
        return
    scene._on_tile_tapped(unit.tile)
    eq(m.selected, unit, "a tap selects a unit")
    ok(scene.unit_hud.visible and not scene.unit_hud.attack_button.visible, "its panel has no Attack button")
    ok(scene.unit_hud.move_button.visible, "but has Move")
    m.set_action_mode(BattleUnitManager.ActionMode.ATTACK)
    eq(m.action_mode, BattleUnitManager.ActionMode.AUTO, "the attack mode can't be chosen")
    scene._on_tile_tapped(goal)
    ok(m.is_previewing(unit, goal), "the first tap previews the path")
    scene._on_tile_tapped(goal)
    ok(await wait_until(func() -> bool: return unit.tile == goal, 12.0), "the second tap walks there, with no action points")
    ok(not m.command_attack_tile(unit, goal + Vector2i(1, 0)), "it can't be ordered to shoot")
    m.select(null)

func _test_buildings() -> void:
    var manager := scene.combat_map_manager
    var count_before := manager.buildings.size()
    var unit := _player_unit()
    scene._on_tile_tapped(unit.tile)
    scene.build_bar.buildings_button.button_pressed = true
    eq(scene.build_manager.tool, BuildManager.Tool.BUILDING, "the Buildings button picks the tool")
    ok(scene.build_bar.building_select.visible, "the list of buildings shows")
    ok(scene.battle_unit_manager.selected == null, "choosing a tool puts the selection down")
    # choose a 3x3
    var index := BuildingTypes.TYPES.keys().find("apartment")
    scene.build_bar.building_select.select(index)
    scene.build_bar.building_select.item_selected.emit(index)
    eq(scene.build_manager.building_type, "apartment", "the list chooses the building")
    var spot := _spot_for("apartment")
    ok(spot != Vector2i(-1, -1), "found room for an apartment")
    scene.build_manager.set_hover(spot)
    eq(scene.build_manager.get_ghost_tiles().size(), 9, "the ghost covers its 9 tiles")
    eq(scene.build_manager.get_problem(), "", "and it can be built")
    var hp_unit_tile := unit.tile
    scene._on_tile_tapped(spot)
    eq(manager.buildings.size(), count_before + 1, "a tap builds the building")
    var building := manager.get_building_at(spot)
    ok(building != null and building.building_type == "apartment", "it stands on the tile")
    eq(building.hp, building.max_hp, "undamaged")
    ok(building.sprite.texture != null and building.sprite.visible, "with its picture")
    for tile in building.get_tiles():
        ok(scene.occupancy_service.is_occupied(tile, TileOccupancyService.LAYER_STRUCTURE), "%s is blocked" % tile)
    eq(unit.tile, hp_unit_tile, "the tap did not move any unit")
    ok(scene.building_container.get_children().has(building), "it is in the building container")
    # the same place again
    scene.build_manager.set_hover(spot)
    ok(scene.build_manager.get_problem() != "", "no second building on top of it")
    scene._on_tile_tapped(spot)
    eq(manager.buildings.size(), count_before + 1, "so nothing is built")
    ok(scene.info_label.text.begins_with("can't build"), "and the player is told why")
    # on a unit, outside the map
    scene._on_tile_tapped(unit.tile)
    eq(manager.buildings.size(), count_before + 1, "not on a unit")
    ok(manager.build_building("house", Vector2i(-5, -5)) == null, "not outside the map")
    # another type
    var small := _spot_for("guard_post")
    scene.build_bar.building_select.item_selected.emit(BuildingTypes.TYPES.keys().find("guard_post"))
    scene._on_tile_tapped(small)
    ok(manager.get_building_at(small) != null and manager.get_building_at(small).building_type == "guard_post", "a 1x1 guard post too")
    # a built building can be shot down like the others
    building.take_damage(building.max_hp)
    ok(manager.get_building_at(spot) == null, "(and it leaves rubble when destroyed)")
    # a unit can't walk through a new building
    scene.build_manager.set_tool(BuildManager.Tool.NONE)

func _test_roads() -> void:
    var manager := scene.combat_map_manager
    var tile := _road_spot()
    ok(tile != Vector2i(-1, -1), "found room for a road")
    scene.build_bar.roads_button.button_pressed = true
    eq(scene.build_manager.tool, BuildManager.Tool.ROAD, "the Roads button picks the tool")
    eq(scene.build_bar.building_select.visible, false, "the list of buildings hides")
    eq(scene.build_bar.buildings_button.button_pressed, false, "one tool at a time")
    scene._on_tile_tapped(tile)
    ok(scene.combat_map.has_road(tile), "a tap draws a road")
    eq(scene.terrain_service.get_type(tile), "road", "and the ground there is road")
    eq(scene.combat_map.roads.get_cell_atlas_coords(tile), Vector2i(0, 0), "a lone road tile has no arms")
    scene._on_tile_tapped(tile + Vector2i(1, 0))
    eq(scene.combat_map.roads.get_cell_atlas_coords(tile), Vector2i(2, 0), "joined to its east neighbor: arm to the east")
    eq(scene.combat_map.roads.get_cell_atlas_coords(tile + Vector2i(1, 0)), Vector2i(8, 0), "and that one has an arm to the west")
    scene._on_tile_tapped(tile)
    ok(scene.info_label.text.begins_with("can't build"), "a second road on the same tile is refused")
    ok(manager.why_not_road(Vector2i(-3, 0)) != "", "no road outside the map")
    var building := manager.buildings[0]
    ok(manager.why_not_road(building.tile) != "", "no road under a building")
    scene.build_manager.set_tool(BuildManager.Tool.NONE)

func _test_walls() -> void:
    var a := _road_spot() + Vector2i(0, 3)
    for i in 30:
        if scene.edge_service.get_edge(a, a + Vector2i(1, 0)) == null and scene.edge_service.get_edge(a + Vector2i(1, 0), a + Vector2i(2, 0)) == null:
            break
        a += Vector2i(0, 1)
    var b := a + Vector2i(1, 0)
    var c := a + Vector2i(2, 0)
    scene.build_bar.walls_button.button_pressed = true
    eq(scene.build_manager.tool, BuildManager.Tool.WALL, "the Walls button picks the tool")
    scene._on_tile_tapped(a)
    ok(scene.build_manager.has_wall_start and scene.build_manager.wall_start == a, "the first tap starts a wall")
    eq(scene.edge_service.get_edge(a, b), null, "nothing is built yet")
    scene.build_manager.set_hover(b)
    eq(scene.build_manager.get_problem(), "", "the wall can go there")
    scene._on_tile_tapped(b)
    var wall := scene.edge_service.get_edge(a, b)
    ok(wall != null and wall.type == "wall", "the second tap builds a wall between the tiles")
    ok(scene.edge_service.is_move_blocked(a, b), "nobody walks through it")
    ok(scene.edge_service.is_fire_blocked(a, b) and scene.edge_service.is_view_blocked(a, b), "or sees or shoots through it")
    eq(scene.combat_map.walls_x.get_cell_source_id(a), 0, "and it is drawn")
    ok(scene.build_manager.wall_start == b, "the wall goes on from the second tile")
    scene._on_tile_tapped(c)
    ok(scene.edge_service.get_edge(b, c) != null, "the next tap goes on with the wall")
    scene._on_tile_tapped(c)
    eq(scene.build_manager.has_wall_start, false, "tapping the last tile again stops")
    scene._on_tile_tapped(a)
    scene._on_tile_tapped(b)
    ok(scene.info_label.text.begins_with("can't build"), "the same wall twice is refused")
    # a tile that is no neighbor starts again
    scene.build_manager.has_wall_start = false
    scene._on_tile_tapped(a)
    scene._on_tile_tapped(a + Vector2i(0, 5))
    ok(scene.build_manager.wall_start == a + Vector2i(0, 5), "a tap far away starts a new wall there")
    eq(scene.edge_service.get_edge(a, a + Vector2i(0, 1)), null, "and builds none")
    # vertical wall (the other layer)
    var d := a + Vector2i(0, 8)
    scene.build_manager.has_wall_start = false
    scene._on_tile_tapped(d)
    scene._on_tile_tapped(d + Vector2i(0, 1))
    ok(scene.edge_service.get_edge(d, d + Vector2i(0, 1)) != null, "a wall between a tile and the one south of it")
    eq(scene.combat_map.walls_y.get_cell_source_id(d), 0, "drawn in the other wall layer")
    scene.build_manager.set_tool(BuildManager.Tool.NONE)

func _test_tools() -> void:
    var bm: BuildManager = scene.build_manager
    scene.build_bar.walls_button.button_pressed = true
    eq(bm.tool, BuildManager.Tool.WALL, "a tool is active")
    scene.build_bar.walls_button.button_pressed = false
    eq(bm.tool, BuildManager.Tool.NONE, "pressing the button again puts it down")
    scene.build_bar.roads_button.button_pressed = true
    scene._on_tile_right_tapped(Vector2i(1, 1))
    eq(bm.tool, BuildManager.Tool.NONE, "a right click puts the tool down")
    eq(scene.build_bar.roads_button.button_pressed, false, "and the button shows it")
    eq(bm.handle_tile_tap(Vector2i(2, 2)), false, "with no tool, taps are not for building")


func _test_building_needs_road() -> void:
    var manager := scene.combat_map_manager
    var used: Array[Vector2i] = []
    # a 2x2 house far from any road is refused, and the player is told why
    var house := _bare_spot("house", used)
    used.append(house)
    ok(house != Vector2i(-1, -1), "found a bare place for a house")
    eq(manager.why_not_building("house", house), "needs a road along one whole side", "no road: no house")
    ok(manager.build_building("house", house) == null, "it is not built")
    scene.build_manager.set_tool(BuildManager.Tool.BUILDING)
    scene.build_manager.set_building_type("house")
    scene._on_tile_tapped(house)
    ok(scene.info_label.text.contains("road"), "the message says it needs a road")
    # one road tile of the two along its north side is not enough
    manager.build_road(house + Vector2i(0, -1))
    eq(manager.get_road_sides("house", house).size(), 0, "half a side is not a side")
    ok(manager.build_building("house", house) == null, "so it is still refused")
    # the whole north side
    manager.build_road(house + Vector2i(1, -1))
    eq(manager.get_road_sides("house", house), [Vector2i(0, -1)] as Array[Vector2i], "the north side has a road along it")
    eq(manager.why_not_building("house", house), "", "now it can be built")
    var built := manager.build_building("house", house)
    ok(built != null, "and it is built")
    # a road beside only the corner does not count, nor does one that is not along the side
    var apartment := _bare_spot("apartment", used)
    used.append(apartment)
    for i in 3:
        manager.build_road(apartment + Vector2i(-1, i)) # the west side, three tiles
    eq(manager.get_road_sides("apartment", apartment), [Vector2i(-1, 0)] as Array[Vector2i], "the west side of a 3x3 with its three tiles on a road")
    ok(manager.build_building("apartment", apartment) != null, "so the apartment is built")
    # 1x1 and 4x4 (east and south sides)
    var post := _bare_spot("guard_post", used)
    used.append(post)
    manager.build_road(post + Vector2i(1, 0))
    eq(manager.get_road_sides("guard_post", post), [Vector2i(1, 0)] as Array[Vector2i], "a guard post needs one road tile beside it")
    ok(manager.build_building("guard_post", post) != null, "it is built")
    var factory := _bare_spot("factory", used)
    used.append(factory)
    for i in 4:
        manager.build_road(factory + Vector2i(i, 4)) # the south side
    eq(manager.get_road_sides("factory", factory), [Vector2i(0, 1)] as Array[Vector2i], "the south side of a 4x4")
    manager.build_road(factory + Vector2i(4, 0)) # only one tile of the east side
    eq(manager.get_road_sides("factory", factory).size(), 1, "one road tile of four is not a side")
    ok(manager.build_building("factory", factory) != null, "the factory is built")
    scene.build_manager.set_tool(BuildManager.Tool.NONE)

func _test_road_drag() -> void:
    var manager := scene.combat_map_manager
    var bm: BuildManager = scene.build_manager
    # a free row of 6 tiles, with free tiles round it
    var start := Vector2i(-1, -1)
    var rect := scene.grid_service.map_rect
    for y in range(rect.position.y + 2, rect.end.y - 2):
        for x in range(rect.position.x + 2, rect.end.x - 10):
            var row_free := true
            for i in range(-1, 7):
                for dy in range(-1, 2):
                    row_free = row_free and manager.why_not_road(Vector2i(x + i, y + dy)) == ""
            if start == Vector2i(-1, -1) and row_free:
                start = Vector2i(x, y)
    ok(start != Vector2i(-1, -1), "found room for a road line")
    scene.build_bar.roads_button.button_pressed = true
    eq(scene.combat_input_manager.drag_pans, false, "with the road tool a drag does not move the camera")
    # snapping: the pointer is further along x than along y: the line goes east
    bm.begin_drag(start)
    bm.drag_to(start + Vector2i(4, 1))
    eq(bm.get_ghost_tiles().size(), 5, "the line has 5 tiles")
    eq(bm.drag_end, start + Vector2i(4, 0), "and stays in its row")
    bm.drag_to(start + Vector2i(1, -3))
    eq(bm.drag_end, start + Vector2i(0, -3), "further along y: a column, north")
    eq(bm.get_ghost_tiles()[3], start + Vector2i(0, -3), "from the start to there")
    bm.drag_to(start + Vector2i(-2, 0))
    eq(bm.get_ghost_tiles().size(), 3, "west too")
    bm.drag_to(start + Vector2i(3, 0))
    eq(bm.end_drag(start + Vector2i(3, 0)), 4, "letting go builds the line: 4 tiles")
    for i in 4:
        ok(manager.combat_map.has_road(start + Vector2i(i, 0)), "road at %s" % (start + Vector2i(i, 0)))
    eq(manager.combat_map.roads.get_cell_atlas_coords(start + Vector2i(1, 0)), Vector2i(10, 0), "the road tiles join: east and west arms")
    ok(not manager.combat_map.has_road(start + Vector2i(4, 0)), "and no more")
    eq(bm.is_dragging, false, "the drag is over")
    # over what is there already: only the free tiles are built
    bm.begin_drag(start + Vector2i(2, 0))
    bm.drag_to(start + Vector2i(5, 0))
    ok(bm.is_ghost_ok(start + Vector2i(3, 0)), "a road over a road is not an error")
    eq(bm.end_drag(start + Vector2i(5, 0)), 2, "two new tiles")
    # a column, south
    var expected := 0
    for t in bm.get_road_line(start + Vector2i(0, 1), start + Vector2i(0, 3)):
        if manager.why_not_road(t) == "":
            expected += 1
    ok(expected > 0, "some of the column is free")
    bm.begin_drag(start + Vector2i(0, 1))
    eq(bm.end_drag(start + Vector2i(0, 3)), expected, "a column to the south: the free tiles are built")
    # with the real pointer: press, move, release
    var from := start + Vector2i(0, 5)
    var camera_before: Vector2 = scene.camera_service.cam.global_position
    _mouse(true, _screen_of(from))
    await get_tree().process_frame
    for i in range(1, 4):
        _motion(_screen_of(from + Vector2i(i, 0)))
        await get_tree().process_frame
    ok(bm.is_dragging, "the real drag starts a line")
    eq(bm.get_ghost_tiles().size(), 4, "the line follows the pointer")
    _mouse(false, _screen_of(from + Vector2i(3, 0)))
    await get_tree().process_frame
    for i in 4:
        ok(manager.combat_map.has_road(from + Vector2i(i, 0)) or not scene.terrain_service.is_walkable(from + Vector2i(i, 0)), "the real drag built %s" % (from + Vector2i(i, 0)))
    eq(scene.camera_service.cam.global_position, camera_before, "the camera did not move")
    # a tap is still one tile
    var single := from + Vector2i(0, 2)
    scene._on_tile_tapped(single)
    ok(manager.combat_map.has_road(single) and not manager.combat_map.has_road(single + Vector2i(1, 0)), "a tap builds one tile")
    # without the tool a drag pans again
    scene.build_bar.roads_button.button_pressed = false
    eq(scene.combat_input_manager.drag_pans, true, "no tool: dragging moves the camera")
    bm.begin_drag(start)
    eq(bm.is_dragging, false, "and no line is started")

func _test_speed() -> void:
    var m := scene.battle_unit_manager
    eq(m.unit_speed_factor, BuildScene.UNIT_SPEED_FACTOR, "the build scene hurries its units")
    ok(BuildScene.UNIT_SPEED_FACTOR > 1.0, "faster than in a battle")
    for soldier in m.soldiers:
        eq(soldier.speed_factor, BuildScene.UNIT_SPEED_FACTOR, "%s walks faster" % soldier.unit_id)
    var one := m.soldiers[0]
    var spawned := m.spawn("player", "liquidator", Vector2i(-1, -1))
    m.unit_speed_factor = 3.0
    eq(one.speed_factor, 3.0, "changing it changes every unit")
    m.unit_speed_factor = BuildScene.UNIT_SPEED_FACTOR
    # the step takes half the time: measure a walk of 1 tile
    var unit: Soldier = null
    for soldier in m.soldiers:
        if soldier.footprint.tiles_at(Vector2i.ZERO).size() == 1 and unit == null:
            for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
                var to: Vector2i = soldier.tile + step
                if unit == null and scene.grid_service.is_inside_map(to) and scene.occupancy_service.is_free(to) and scene.terrain_service.is_walkable(to) \
                        and not scene.edge_service.is_move_blocked(soldier.tile, to):
                    unit = soldier
                    var goal := to
                    var started := Time.get_ticks_msec()
                    m.command_move(soldier, goal)
                    await wait_until(func() -> bool: return soldier.tile == goal and soldier.get_action() == &"idle", 3.0)
                    var took := float(Time.get_ticks_msec() - started) / 1000.0
                    var normal := 1.0 / soldier.move_speed
                    ok(took < normal * 0.9, "a step takes %.2f s, less than the %.2f s of a battle" % [took, normal])
