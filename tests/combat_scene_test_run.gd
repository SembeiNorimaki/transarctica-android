extends SceneTree
# Headless test of CombatSceneTest: the map is read into the services, soldiers are deployed, and
# their actions (idle, move, attack, dead) work.
# Run from the project folder:  godot --headless --path . -s tests/combat_scene_test_run.gd

var _failed := 0
var _checks := 0
var scene: CombatSceneTest


func _initialize() -> void:
    process_frame.connect(_run, CONNECT_ONE_SHOT)


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

func wait_until(condition: Callable, timeout := 6.0) -> bool:
    var waited := 0.0
    while not condition.call() and waited < timeout:
        await create_timer(0.05).timeout
        waited += 0.05
    return condition.call()


func _run() -> void:
    scene = load("res://scenes/core/combat_scene_test.tscn").instantiate()
    root.add_child(scene)
    await process_frame
    await process_frame
    await _test_loading()
    await _test_move()
    await _test_attack()
    await _test_doors()
    await _test_death()
    print("%d checks, %d failed" % [_checks, _failed])
    print("ALL PASSED" if _failed == 0 else "FAILED")
    quit(1 if _failed > 0 else 0)


func _soldier(team: String, unit_type: String) -> Soldier:
    for s in scene.battle_unit_manager.soldiers:
        if s.team == team and s.unit_type == unit_type and s.is_alive():
            return s
    return null


func _test_loading() -> void:
    var g := scene.grid_service
    eq(g.tile_size, Vector2i(64, 32), "grid tile size from the map")
    eq(g.map_rect, Rect2i(0, 0, 16, 12), "map rect from the ground layer")
    eq(g.tile_to_world(Vector2(0, 0)), Vector2.ZERO, "tile (0,0) is at the map origin")
    eq(scene.terrain_service.get_type(Vector2i(6, 2)), "rock", "terrain read from the ground layer")
    eq(scene.terrain_service.get_type(Vector2i(0, 5)), "road", "road")
    eq(scene.terrain_service.get_type(Vector2i(0, 0)), "grass", "grass")
    eq(scene.edge_service.get_edge_count(), 20, "edges read from the wall layers")
    eq(scene.edge_service.get_edge(Vector2i(6, 5), Vector2i(6, 6)).type, "wall", "north wall of the building")
    eq(scene.edge_service.get_edge(Vector2i(7, 6), Vector2i(7, 5)).type, "door", "door, asked the other way round")
    eq(scene.edge_service.get_edge(Vector2i(5, 8), Vector2i(6, 8)).type, "door", "west door")
    eq(scene.edge_service.get_edge(Vector2i(3, 2), Vector2i(4, 2)).type, "fence", "fence")
    eq(scene.combat_map_manager.objects.size(), 8, "objects registered")
    ok(scene.occupancy_service.is_occupied(Vector2i(11, 4)), "container occupies its tile")
    ok(scene.occupancy_service.is_occupied(Vector2i(11, 4), TileOccupancyService.LAYER_STRUCTURE), "container is a structure")
    eq(scene.battle_unit_manager.soldiers.size(), 6, "six soldiers deployed")
    eq(scene.battle_unit_manager.soldiers.filter(func(s: Soldier) -> bool: return s.team == "enemy").size(), 3, "three enemies")
    for s in scene.battle_unit_manager.soldiers:
        ok(scene.occupancy_service.get_anchor(s) == s.tile, "occupancy matches the soldier %s" % s.unit_id)
        eq(s.get_action(), &"idle", "%s starts idle" % s.unit_id)
        ok(s.status_label.text.contains(str(s.tile)), "%s label shows its tile" % s.unit_id)
        ok(s.position.is_equal_approx(g.tile_to_world(Vector2(s.tile))), "%s stands on its tile" % s.unit_id)
    ok(not scene.combat_map.spawns.visible, "spawn markers hidden")
    ok(_soldier("player", "pioneer").status_label.text.begins_with("IDLE"), "status label says idle")
    ok(_soldier("player", "pioneer").info_label.text.contains("pioneer"), "info label names the type")
    eq(_soldier("player", "pioneer").view_range, 12, "pioneer sees further")
    eq(_soldier("player", "liquidator").view_range, 8, "default view range")


func _test_move() -> void:
    var m := scene.battle_unit_manager
    var s := _soldier("player", "liquidator")
    var start := s.tile
    var steps := []
    s.step_started.connect(func(_u: Soldier, from: Vector2i, to: Vector2i) -> void: steps.append([from, to]))
    var actions := []
    s.action_changed.connect(func(_u: Soldier, a: StringName) -> void: actions.append(a))
    m.handle_tile_tap(s.tile)
    eq(m.selected, s, "tapping own soldier selects it")
    var goal := start + Vector2i(0, 3)
    m.handle_tile_tap(goal)
    await process_frame
    eq(s.get_action(), &"move", "moving after the order")
    ok(s.status_label.text.begins_with("MOVING"), "status label says moving")
    ok(await wait_until(func() -> bool: return s.get_action() == &"idle"), "back to idle on arrival")
    eq(s.tile, goal, "arrived")
    ok(s.position.is_equal_approx(scene.grid_service.tile_to_world(Vector2(goal))), "standing exactly on the tile")
    eq(scene.occupancy_service.get_anchor(s), goal, "occupancy followed")
    ok(not scene.occupancy_service.is_occupied(start, TileOccupancyService.LAYER_UNIT), "old tile freed")
    eq(steps.size(), 3, "three steps")
    eq(actions, [&"move", &"idle"], "action changes reported")
    # unreachable: the tile of a rock
    m.handle_tile_tap(Vector2i(6, 2))
    await process_frame
    eq(s.get_action(), &"idle", "no path to a rock: stays idle")
    # a new order while walking is followed after the current step
    m.handle_tile_tap(goal + Vector2i(4, 0))
    await create_timer(0.1).timeout
    m.handle_tile_tap(goal + Vector2i(0, 2))
    ok(await wait_until(func() -> bool: return s.get_action() == &"idle"), "idle after the redirected order")
    eq(s.tile, goal + Vector2i(0, 2), "ended at the second order's tile")
    ok(s.position.is_equal_approx(scene.grid_service.tile_to_world(Vector2(s.tile))), "no drift after the redirect")
    # a step onto another soldier is refused
    var neighbor := m.spawn("player", "redops", s.tile + Vector2i(1, 0))
    ok(neighbor != null, "spawned a neighbor")
    ok(not m._can_soldier_step(s, s.tile, neighbor.tile), "cannot step onto a soldier")
    ok(m._can_soldier_step(s, s.tile, s.tile + Vector2i(0, 1)), "can step onto a free tile")
    m.select(null)
    eq(s.selected, false, "deselected")


func _test_attack() -> void:
    var m := scene.battle_unit_manager
    var shooter := _soldier("player", "liquidator")
    # a target two tiles away in the open
    var tile := shooter.tile + Vector2i(2, 0)
    var target := m.spawn("enemy", "liquidator", tile, "W")
    ok(target != null, "spawned a target")
    ok(target.status_label.text.contains(str(tile)) and target.status_label.text.contains("W"), "a soldier spawned facing the default still shows its tile")
    var north := m.spawn("player", "redops", Vector2i(10, 11), "N")
    ok(north.status_label.text.contains("(10, 11)"), "label right when the facing equals the default")
    m.select(shooter)
    var hp_before := target.hp
    var fired := []
    shooter.attack_fired.connect(func(_a: Soldier, _t: Soldier) -> void: fired.append(true))
    var shots := []
    m.shot_resolved.connect(func(a: Soldier, t: Soldier, d: int, c: int) -> void: shots.append([d, c]))
    m.handle_tile_tap(tile)
    await process_frame
    eq(shooter.get_action(), &"attack", "attacking")
    ok(shooter.status_label.text.contains("ATTACKING"), "status label says attacking")
    ok(await wait_until(func() -> bool: return shooter.get_action() == &"idle"), "idle after the volley")
    eq(fired.size(), 1, "one shot")
    eq(target.hp, hp_before - 20, "AK47 does 20 in the open")
    eq(shots[0], [20, CoverLevel.NONE], "shot reported")
    ok(target.info_label.text.contains("80"), "target label shows its hp")
    eq(shooter.facing, scene.grid_service.get_orientation(shooter.tile, target.tile), "shooter faces the target")
    # cover: a fence between shooter and target halves... 25% off for half cover
    var wall_a := shooter.tile + Vector2i(1, 0)
    scene.edge_service.add(wall_a, tile, "fence")
    hp_before = target.hp
    m.handle_tile_tap(tile)
    ok(await wait_until(func() -> bool: return shooter.get_action() == &"idle" and target.hp < hp_before), "second volley")
    eq(hp_before - target.hp, 15, "half cover: 20 * 0.75")
    scene.edge_service.remove(wall_a, tile)
    # a wall blocks the shot: the shooter walks around to get a line
    scene.edge_service.add(wall_a, tile, "wall")
    hp_before = target.hp
    var tile_before := shooter.tile
    m.handle_tile_tap(tile)
    ok(await wait_until(func() -> bool: return target.hp < hp_before, 12.0), "walks to a place with a line of sight, then shoots")
    ok(shooter.tile != tile_before, "the shooter moved to get a line")
    ok(scene.vision_service.has_line_of_sight(shooter.tile, tile), "and now has one")
    scene.edge_service.remove(wall_a, tile)
    # friendly fire is refused
    var friend := _soldier("player", "redops")
    eq(m.command_attack(shooter, friend), false, "no attacking your own team")
    await wait_until(func() -> bool: return shooter.get_action() == &"idle")


func _test_doors() -> void:
    var door_a := Vector2i(7, 5)
    var door_b := Vector2i(7, 6)
    var edge := scene.edge_service.get_edge(door_a, door_b)
    ok(not edge.is_open, "door starts closed")
    ok(scene.edge_service.is_move_blocked(door_a, door_b), "closed door blocks")
    scene.combat_map_manager.toggle_all_doors()
    ok(edge.is_open, "door opened")
    ok(not scene.edge_service.is_move_blocked(door_a, door_b), "open door lets through")
    eq(scene.combat_map.walls_sw.get_cell_atlas_coords(door_a), Vector2i(4, 0), "door tile redrawn open")
    eq(scene.combat_map.walls_se.get_cell_atlas_coords(Vector2i(5, 8)), Vector2i(4, 0), "west door redrawn open")
    scene.combat_map_manager.toggle_all_doors()
    ok(not edge.is_open, "door closed again")
    eq(scene.combat_map.walls_sw.get_cell_atlas_coords(door_a), Vector2i(3, 0), "door tile redrawn closed")
    # a destroyed wall disappears from the map
    scene.edge_service.damage(Vector2i(6, 5), Vector2i(6, 6), 999)
    eq(scene.combat_map.walls_sw.get_cell_atlas_coords(Vector2i(6, 5)), Vector2i(-1, -1), "destroyed wall erased")
    # walking through the open door
    scene.combat_map_manager.toggle_all_doors()
    var path := scene.pathfinding_service.find_path(Vector2i(7, 4), Vector2i(7, 7))
    ok(path.size() > 0, "a path exists into the building")
    for i in range(1, path.size()):
        ok(not scene.edge_service.is_move_blocked(path[i - 1], path[i]), "step %d of the path is legal" % i)


func _test_death() -> void:
    var m := scene.battle_unit_manager
    var shooter := _soldier("player", "pioneer")
    var victim := m.spawn("enemy", "liquidator", shooter.tile + Vector2i(3, 0), "W")
    victim.hp = 30
    m.select(shooter)
    var died := []
    m.soldier_died.connect(func(s: Soldier) -> void: died.append(s))
    m.handle_tile_tap(victim.tile)
    ok(await wait_until(func() -> bool: return not victim.is_alive()), "sniper kills a 30 hp target")
    await process_frame
    eq(victim.get_action(), &"dead", "dead action")
    ok(victim.status_label.text.begins_with("DEAD"), "status label says dead")
    ok(not scene.occupancy_service.has_entity(victim), "dead soldier leaves the occupancy")
    ok(scene.occupancy_service.is_free(victim.tile), "its tile is free again")
    eq(died.size(), 1, "death reported once")
    victim.take_damage(10)
    eq(victim.hp, 0, "no more damage to the dead")
    victim.order_move([victim.tile] as Array[Vector2i])
    eq(victim.get_action(), &"dead", "the dead take no orders")
    m.handle_tile_tap(victim.tile)
    ok(m.selected == shooter or m.selected == null, "tapping a free tile after death does not crash")
