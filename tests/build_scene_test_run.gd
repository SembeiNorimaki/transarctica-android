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
