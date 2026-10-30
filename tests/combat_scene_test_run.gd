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
        await create_timer(0.05, true, false, true).timeout
        waited += 0.05
    return condition.call()


func _run() -> void:
    scene = load("res://scenes/core/combat_scene_test.tscn").instantiate()
    root.add_child(scene)
    await process_frame
    await process_frame
    await _test_loading()
    await _test_fog()
    await _test_move()
    await _test_path_overlay()
    await _test_attack()
    await _test_doors()
    await _test_death()
    await _test_turns()
    await _test_rts()
    await _test_flow_manager_rules()
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
    _refill()
    # a new order while walking is followed after the current step
    m.handle_tile_tap(goal + Vector2i(4, 0))
    await create_timer(0.1, true, false, true).timeout
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


# A free, walkable tile exactly `distance` tiles away (Chebyshev) from `from`, with a line of sight
# to it if asked. The first one found, scanning the map in order.
func _tile_at(from: Vector2i, distance: int, need_sight := true) -> Vector2i:
    var rect := scene.grid_service.map_rect
    for y in range(rect.position.y, rect.end.y):
        for x in range(rect.position.x, rect.end.x):
            var tile := Vector2i(x, y)
            if maxi(absi(x - from.x), absi(y - from.y)) != distance:
                continue
            if not scene.terrain_service.is_walkable(tile) or not scene.occupancy_service.is_free(tile):
                continue
            if need_sight and not scene.vision_service.has_line_of_sight(from, tile):
                continue
            return tile
    push_error("no tile at distance %d from %s" % [distance, from])
    return from

# A free tile `distance` tiles away along one of the four axes, with a line of sight to it.
# Returns [tile, direction].
func _axis_tile(from: Vector2i, distance: int) -> Array:
    for dir in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
        var tile: Vector2i = from + dir * distance
        if scene.grid_service.is_inside_map(tile) and scene.terrain_service.is_walkable(tile) \
                and scene.occupancy_service.is_free(tile) and scene.vision_service.has_line_of_sight(from, tile):
            return [tile, dir]
    push_error("no axis tile")
    return [from, Vector2i.ZERO]

func _spawn_enemy_near(from: Vector2i, distance: int, unit_type := "liquidator") -> Soldier:
    var tile := _tile_at(from, distance)
    return scene.battle_unit_manager.spawn("enemy", unit_type, tile, scene.grid_service.get_orientation(tile, from))


func _refill() -> void:
    for s in scene.battle_unit_manager.soldiers:
        if s.is_alive():
            s.set_action_points(s.max_action_points)


func _test_attack() -> void:
    var m := scene.battle_unit_manager
    _refill()
    var shooter := _soldier("player", "liquidator")
    # a target two tiles away in the open
    var axis := _axis_tile(shooter.tile, 2)
    var tile: Vector2i = axis[0]
    var target := m.spawn("enemy", "liquidator", tile, scene.grid_service.get_orientation(tile, shooter.tile))
    ok(target != null, "spawned a target")
    ok(target.status_label.text.contains(str(tile)), "a spawned soldier shows its tile")
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
    _refill()
    var wall_a: Vector2i = shooter.tile + axis[1]
    scene.edge_service.add(wall_a, tile, "fence")
    hp_before = target.hp
    m.handle_tile_tap(tile)
    ok(await wait_until(func() -> bool: return shooter.get_action() == &"idle" and target.hp < hp_before), "second volley")
    eq(hp_before - target.hp, 15, "half cover: 20 * 0.75")
    scene.edge_service.remove(wall_a, tile)
    # a wall blocks the shot: the shooter walks around to get a line
    scene.edge_service.add(wall_a, tile, "wall")
    _refill()
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
    _refill()
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


func _test_fog() -> void:
    var vis := scene.visibility_service
    var fog := scene.combat_map.fog
    var m := scene.battle_unit_manager
    var pioneer := _soldier("player", "pioneer")
    ok(vis.is_visible("player", pioneer.tile), "a soldier sees its own tile")
    eq(fog.get_cell_source_id(pioneer.tile), -1, "no fog on a visible tile")
    eq(fog.get_cell_atlas_coords(Vector2i(14, 10)), FogManager.UNEXPLORED_ATLAS, "far corner is unexplored fog")
    eq(vis.get_state("player", Vector2i(14, 10)), VisibilityService.State.UNEXPLORED, "far corner state")
    ok(not vis.is_visible("player", Vector2i(7, 7)), "inside the walled building: not seen")
    ok(vis.is_visible("player", pioneer.tile + Vector2i(1, 1)), "awareness circle around a soldier")
    for s in m.soldiers:
        if s.team == "enemy":
            ok(not s.visible, "enemy %s hidden in the fog" % s.unit_id)
        else:
            ok(s.visible, "own soldier %s shown" % s.unit_id)
    # an enemy stepping into view appears
    var near := m.spawn("enemy", "redops", pioneer.tile + Vector2i(2, 0), "W")
    await process_frame
    ok(near.visible, "an enemy on a visible tile is shown")
    scene.occupancy_service.remove(near)
    near.queue_free()
    m.soldiers.erase(near)
    # leaving a tile turns it into explored fog
    var scout := m.spawn("player", "liquidator", Vector2i(4, 9), "S")
    await process_frame
    var seen_tile := Vector2i(4, 9)
    ok(vis.is_visible("player", seen_tile), "scout sees its tile")
    scene.occupancy_service.remove(scout)
    m.soldiers.erase(scout)
    vis.remove_viewer(scout)
    scout.queue_free()
    eq(vis.get_state("player", seen_tile), VisibilityService.State.EXPLORED, "a tile nobody sees any more is explored")
    eq(fog.get_cell_atlas_coords(seen_tile), FogManager.EXPLORED_ATLAS, "explored fog drawn")
    # a door opening changes what is seen
    var viewer := m.spawn("player", "liquidator", Vector2i(7, 4), "S")
    await process_frame
    await process_frame
    var inside := Vector2i(7, 7)
    var before := vis.is_visible("player", inside)
    scene.edge_service.set_open(Vector2i(7, 5), Vector2i(7, 6), true)
    await process_frame
    await process_frame
    ok(vis.is_visible("player", inside), "after opening the door the inside of the building is seen (was %s)" % before)
    scene.edge_service.set_open(Vector2i(7, 5), Vector2i(7, 6), false)
    await process_frame
    await process_frame
    ok(not vis.is_visible("player", inside), "and not seen again once it closes")
    scene.occupancy_service.remove(viewer)
    m.soldiers.erase(viewer)
    vis.remove_viewer(viewer)
    viewer.queue_free()
    # the fog can be switched off
    scene.fog_manager.enabled = false
    await process_frame
    ok(not fog.visible, "fog layer hidden")
    ok(_soldier("enemy", "pioneer").visible, "enemies shown with the fog off")
    scene.fog_manager.enabled = true
    await process_frame
    ok(fog.visible and not _soldier("enemy", "pioneer").visible, "fog back on")


func _test_path_overlay() -> void:
    var m := scene.battle_unit_manager
    var s := _soldier("player", "redops")
    var overlay := scene.path_overlay
    eq(s.get_path_ahead().size(), 0, "no path ahead when idle")
    m.select(s)
    var goal := s.tile + Vector2i(0, 4)
    m.handle_tile_tap(goal)
    await process_frame
    await process_frame
    var ahead := s.get_path_ahead()
    ok(ahead.size() >= 3 and ahead[-1] == goal, "path ahead ends at the goal")
    eq(ahead[0], s.tile, "path ahead starts at the tile it is walking to")
    ok(overlay._was_drawing, "overlay redraws while a soldier walks")
    var seen_sizes := [ahead.size()]
    await create_timer(0.8, true, false, true).timeout
    seen_sizes.append(s.get_path_ahead().size())
    ok(seen_sizes[1] < seen_sizes[0], "path ahead shrinks as it walks")
    ok(await wait_until(func() -> bool: return s.get_action() == &"idle"), "arrived")
    await process_frame
    await process_frame
    eq(s.get_path_ahead().size(), 0, "path ahead empty on arrival")
    ok(not overlay._was_drawing, "overlay stops redrawing when nothing moves")
    # the target of a walk-then-shoot
    _refill()
    var enemy := _spawn_enemy_near(s.tile, 6)
    scene.fog_manager.enabled = false
    await process_frame
    m.select(s)
    m.handle_tile_tap(enemy.tile)
    await process_frame
    await process_frame
    eq(s.get_attack_target(), enemy, "the soldier's target is known while it walks to it")
    ok(await wait_until(func() -> bool: return s.get_action() == &"attack", 8.0), "then it attacks")
    eq(s.get_attack_target(), enemy, "and while it shoots")
    ok(await wait_until(func() -> bool: return s.get_action() == &"idle", 8.0), "and goes idle")
    scene.fog_manager.enabled = true
    scene.occupancy_service.remove(enemy)
    m.soldiers.erase(enemy)
    scene.visibility_service.remove_viewer(enemy)
    enemy.queue_free()
    overlay.show_all_paths = false
    overlay.queue_redraw()
    await process_frame
    overlay.show_all_paths = true
    m.select(null)


func _test_turns() -> void:
    var tm := scene.flow_manager as TurnManager
    var m := scene.battle_unit_manager
    ok(tm != null, "the scene is turn based: it has a TurnManager")
    eq(scene.end_turn_button.visible, true, "End turn button shown")
    eq(scene.pause_button.visible, false, "Pause button hidden")
    eq(tm.get_mode_name(), "Turn based", "mode name")
    tm.computer_turn_delay = 0.2
    # make it a fresh turn 1 of the player
    tm.end_turn()
    await wait_until(func() -> bool: return tm.current_team == "player" and tm.turn_number >= 2)
    var turn := tm.turn_number
    eq(tm.current_team, "player", "player's turn")
    for s in m.soldiers:
        if s.team == "player" and s.is_alive():
            eq(s.action_points, s.max_action_points, "%s has full AP" % s.unit_id)
    var s := _soldier("player", "liquidator")
    ok(s.status_label.text.contains("AP 8.0/8.0"), "AP shown on the label")
    var enemy := _soldier("enemy", "liquidator")
    ok(not tm.can_command(enemy), "can't command the other team")
    eq(m.command_move(enemy, enemy.tile + Vector2i(0, -1)), false, "enemy refuses a move order")
    # walking spends AP: each step costs the terrain cost of the tile entered
    var start := s.tile
    var goal := _tile_at(start, 3)
    var path := scene.pathfinding_service.find_path(start, goal)
    var cost := tm.get_move_cost(s, path)
    ok(cost >= 3.0, "walking 3 tiles costs at least 3 (%s)" % cost)
    eq(m.command_move(s, goal), true, "walk 3 tiles")
    ok(await wait_until(func() -> bool: return s.get_action() == &"idle"), "arrived")
    ok(is_equal_approx(s.action_points, 8.0 - cost), "AP spent: 8 - %s = %s" % [cost, s.action_points])
    # too far: it walks only as far as AP allow
    s.set_action_points(5.0)
    var corners := [Vector2i(0, 0), Vector2i(15, 0), Vector2i(0, 11), Vector2i(15, 11)]
    corners.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.distance_to(s.tile) > b.distance_to(s.tile))
    var far: Vector2i = corners[0]
    var before_far := s.tile
    eq(m.command_move(s, far), true, "a long walk is cut to what AP allow")
    ok(await wait_until(func() -> bool: return s.get_action() == &"idle"), "stopped")
    ok(s.tile != far and s.tile != before_far, "walked part of the way")
    ok(s.action_points >= 0.0 and s.action_points < 5.0, "AP spent on the way (%s left)" % s.action_points)
    eq(tm.limit_move(s, scene.pathfinding_service.find_path(s.tile, far)).size() < 2, true, "it stopped because the next step costs more than what is left")
    s.set_action_points(0.0)
    eq(m.command_move(s, before_far), false, "no AP: refused")
    ok(s.event_label.text == "no AP", "player is told")
    # an attack costs the weapon's AP and needs them
    var other := _soldier("player", "redops")
    var target := _spawn_enemy_near(other.tile, 2)
    scene.fog_manager.enabled = false
    other.set_action_points(1.0)
    eq(m.command_attack(other, target), false, "1 AP is not enough for a shot (2)")
    other.set_action_points(2.0)
    eq(m.command_attack(other, target), true, "2 AP is enough")
    ok(await wait_until(func() -> bool: return other.get_action() == &"idle"), "shot done")
    ok(is_equal_approx(other.action_points, 0.0), "the shot cost 2 AP")
    # walking into range then shooting needs both
    scene.occupancy_service.remove(target)
    m.soldiers.erase(target)
    scene.visibility_service.remove_viewer(target)
    target.queue_free()
    var distant := _spawn_enemy_near(other.tile, 10)
    other.set_action_points(3.0)
    eq(m.command_attack(other, distant), false, "walking into range plus the shot costs more than 3 AP")
    target = distant
    # turn change by hand
    scene.fog_manager.enabled = true
    scene.occupancy_service.remove(target)
    m.soldiers.erase(target)
    scene.visibility_service.remove_viewer(target)
    target.queue_free()
    var seen := []
    tm.turn_started.connect(func(team: String, n: int) -> void: seen.append([team, n]))
    tm.end_turn()
    ok(await wait_until(func() -> bool: return tm.current_team == "enemy"), "turn passes to the enemy")
    ok(tm.is_computer_turn(), "enemy turn is the computer's")
    ok(tm.get_status_text().contains("computer"), "status text says computer")
    eq(m.command_move(s, s.tile + Vector2i(0, -1)), false, "can't command during the enemy turn")
    ok(await wait_until(func() -> bool: return tm.current_team == "player"), "and it comes back")
    eq(tm.turn_number, turn + 1, "turn number goes up when the first team plays again")
    eq(seen, [["enemy", turn], ["player", turn + 1]], "turn_started signals")
    eq(s.action_points, s.max_action_points, "AP refilled")
    # a team with nothing left to do ends its turn by itself
    for x in m.soldiers:
        if x.team == "player" and x.is_alive():
            x.set_action_points(0.0)
    ok(await wait_until(func() -> bool: return tm.current_team == "enemy", 3.0), "auto end of turn when out of AP")
    ok(await wait_until(func() -> bool: return tm.current_team == "player"), "player again")
    # a soldier who joins mid-turn waits for its team's turn
    var late := m.spawn("enemy", "liquidator", _tile_at(Vector2i(12, 11), 1, false), "N")
    eq(late.action_points, 0.0, "a late enemy has no AP in the player's turn")
    var late_friend := m.spawn("player", "liquidator", _tile_at(Vector2i(10, 11), 1, false), "N")
    eq(late_friend.action_points, late_friend.max_action_points, "a late friend has AP")


func _free_scene() -> void:
    scene.queue_free()
    await process_frame
    await process_frame


# The same battle in real time: the TurnManager is replaced by an RtsManager
func _test_rts() -> void:
    await _free_scene()
    var packed: PackedScene = load("res://scenes/core/combat_scene_test.tscn")
    scene = packed.instantiate()
    scene.get_node("Managers/TurnManager").free()
    var rts := RtsManager.new()
    rts.name = "RtsManager"
    scene.get_node("Managers").add_child(rts)
    root.add_child(scene)
    await process_frame
    await process_frame
    var m := scene.battle_unit_manager
    ok(scene.flow_manager == rts, "the scene runs in real time")
    eq(scene.end_turn_button.visible, false, "no End turn button in real time")
    eq(scene.pause_button.visible, true, "Pause button shown")
    eq(rts.get_status_text(), "Real time", "status text")
    var s := _soldier("player", "liquidator")
    ok(not s.status_label.text.contains("AP"), "no AP in real time")
    # no AP limit: a long walk is allowed
    var long_goal := _tile_at(s.tile, 9, false)
    var long_path := scene.pathfinding_service.find_path(s.tile, long_goal)
    eq(m.command_move(s, long_goal), true, "a long walk is allowed")
    await process_frame
    eq(s.get_path_ahead().size(), long_path.size() - 1, "the whole path")
    ok(await wait_until(func() -> bool: return s.get_action() == &"idle", 10.0), "arrived")
    # the enemy can be commanded too (no turns), and fights back on its own
    scene.fog_manager.enabled = false
    var victim := _soldier("player", "redops")
    var hp := victim.hp
    var shooter := _spawn_enemy_near(victim.tile, 3)
    ok(await wait_until(func() -> bool: return victim.hp < hp, 6.0), "an idle soldier shoots an enemy it sees (auto engage)")
    # pause
    rts.set_paused(true)
    eq(Engine.time_scale, 0.0, "paused: time stands still")
    ok(rts.get_status_text().contains("PAUSED"), "status text says paused")
    var walker := _soldier("player", "liquidator")
    var from := walker.position
    m.command_move(walker, walker.tile + Vector2i(1, 0))
    await create_timer(0.5, true, false, true).timeout
    eq(walker.position, from, "no movement while paused")
    eq(walker.get_action(), &"move", "but the order was accepted")
    rts.set_paused(false)
    ok(await wait_until(func() -> bool: return walker.get_action() == &"idle"), "it walks once resumed")
    rts.game_speed = 2.0
    eq(Engine.time_scale, 2.0, "game speed")
    rts.game_speed = 1.0
    shooter.take_damage(1000)
    await _free_scene()
    eq(Engine.time_scale, 1.0, "time scale restored when the manager leaves")


func _test_flow_manager_rules() -> void:
    var packed: PackedScene = load("res://scenes/core/combat_scene_test.tscn")
    # both at once: not allowed, the second is removed
    scene = packed.instantiate()
    var extra := RtsManager.new()
    extra.name = "RtsManager"
    scene.get_node("Managers").add_child(extra)
    root.add_child(scene)
    await process_frame
    await process_frame
    var count := 0
    for child in scene.get_node("Managers").get_children():
        if child is CombatFlowManager:
            count += 1
    eq(count, 1, "only one of TurnManager / RtsManager survives")
    ok(scene.flow_manager is TurnManager, "the first one is kept")
    await _free_scene()
    # none: the scene still works, with everything allowed
    scene = packed.instantiate()
    scene.get_node("Managers/TurnManager").free()
    root.add_child(scene)
    await process_frame
    await process_frame
    ok(scene.flow_manager != null and not (scene.flow_manager is TurnManager) and not (scene.flow_manager is RtsManager), "fallback flow manager")
    var s := _soldier("player", "liquidator")
    eq(scene.battle_unit_manager.command_move(s, s.tile + Vector2i(0, 2)), true, "orders work without a mode")
    await _free_scene()
    scene = null
