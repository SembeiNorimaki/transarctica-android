extends SceneTree
# Headless tests of the tile grid foundation.
# Run from the project folder:  godot --headless --path . -s tests/grid_foundation_test.gd
# Prints "ALL PASSED" or the failures, and exits with code 1 on failure.

var _failed := 0
var _checks := 0


func _initialize() -> void:
    process_frame.connect(_run, CONNECT_ONE_SHOT) # the root is only in the tree from the first frame


func _run() -> void:
    _test_footprint()
    _test_min_heap()
    _test_grid_projection()
    _test_occupancy()
    _test_edges()
    _test_terrain()
    _test_vision()
    _test_cover()
    _test_pathfinding()
    _test_visibility()
    print("%d checks, %d failed" % [_checks, _failed])
    print("ALL PASSED" if _failed == 0 else "FAILED")
    quit(1 if _failed > 0 else 0)


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


func _grid(projection := GridService.TileProjection.ISOMETRIC) -> GridService:
    var g := GridService.new()
    g.set_projection(projection)
    g.set_tile_size(Vector2i(64, 32))
    g.set_map_rect(Rect2i(0, 0, 20, 20))
    return g


func _test_footprint() -> void:
    eq(Footprint.single().tiles_at(Vector2i(3, 4)), [Vector2i(3, 4)] as Array[Vector2i], "single footprint")
    var r := Footprint.rect(2, 3)
    eq(r.size(), 6, "rect size")
    ok(Vector2i(1, 2) in r.tiles_at(Vector2i.ZERO), "rect covers far corner")
    var turned := Footprint.rect(2, 1).rotated(1)
    ok(Vector2i(0, 1) in turned.offsets and Vector2i.ZERO in turned.offsets, "rotated a quarter turn")
    eq(Footprint.rect(2, 1).rotated(4).offsets, Footprint.rect(2, 1).offsets, "four quarter turns are identity")


func _test_min_heap() -> void:
    var h := MinHeap.new()
    for p in [5.0, 1.0, 3.0, 1.0, 4.0]:
        h.push("p%s" % p, p)
    h.push("late1", 1.0)
    var order := []
    while not h.is_empty():
        order.append(h.pop())
    eq(order, ["p1.0", "p1.0", "late1", "p3.0", "p4.0", "p5.0"], "heap order, FIFO on ties")


func _test_grid_projection() -> void:
    for proj in [GridService.TileProjection.ISOMETRIC, GridService.TileProjection.CARTESIAN]:
        var g := _grid(proj)
        for t in [Vector2i(0, 0), Vector2i(5, 3), Vector2i(19, 0), Vector2i(7, 19)]:
            eq(g.world_to_tile(g.tile_to_world(Vector2(t))), t, "round trip %s proj %d" % [t, proj])
    var c := _grid(GridService.TileProjection.CARTESIAN)
    eq(c.tile_to_world(Vector2(1, 2)), Vector2(32 + 64, 16 + 64), "cartesian world position")
    var iso := _grid()
    eq(iso.tile_to_world(Vector2(1, 0)), Vector2(32 + 32, 16 + 16), "isometric world position unchanged")
    ok(c.get_world_bounds().size.x > 0, "cartesian bounds")


func _test_occupancy() -> void:
    var occ := TileOccupancyService.new()
    var changes := []
    occ.tiles_changed.connect(func(t: Array[Vector2i]) -> void: changes.append(t.size()))
    var unit := Node.new()
    var house := Node.new()
    var crate := Node.new()
    occ.place(unit, Vector2i(2, 2))
    occ.place(house, Vector2i(5, 5), Footprint.rect(3, 2), TileOccupancyService.LAYER_STRUCTURE)
    occ.place(crate, Vector2i(2, 2), null, TileOccupancyService.LAYER_ITEM)
    eq(occ.get_entities_at(Vector2i(2, 2)).size(), 2, "two entities share a tile")
    eq(occ.get_entities_at(Vector2i(2, 2), TileOccupancyService.LAYER_UNIT), [unit], "filter by layer")
    eq(occ.get_entities_at(Vector2i(7, 6), TileOccupancyService.LAYER_STRUCTURE), [house], "house covers far tile")
    eq(occ.get_tiles_of(house).size(), 6, "house tiles")
    ok(occ.is_occupied(Vector2i(6, 6)), "occupied inside footprint")
    ok(not occ.is_occupied(Vector2i(8, 6)), "free outside footprint")
    ok(not occ.is_footprint_free(Vector2i(4, 4), Footprint.rect(2, 2)), "footprint overlapping house is not free")
    ok(occ.is_footprint_free(Vector2i(8, 5), Footprint.rect(2, 2)), "footprint beside house is free")
    ok(occ.is_footprint_free(Vector2i(5, 5), Footprint.rect(3, 2), TileOccupancyService.LAYER_ALL, house), "own tiles ignored")
    occ.move(house, Vector2i(10, 10))
    ok(not occ.is_occupied(Vector2i(5, 5)), "old tiles freed after move")
    ok(occ.is_occupied(Vector2i(12, 11)), "new tiles taken after move")
    eq(occ.get_anchor(house), Vector2i(10, 10), "anchor after move")
    occ.set_footprint(house, Footprint.rect(3, 2).rotated(1))
    ok(occ.is_occupied(Vector2i(9, 12)) and not occ.is_occupied(Vector2i(12, 11)), "turned footprint")
    occ.remove(unit)
    ok(not occ.has_entity(unit) and occ.get_entities_at(Vector2i(2, 2)) == [crate], "remove one of two")
    occ.bounds = Rect2i(0, 0, 10, 10)
    ok(not occ.is_free(Vector2i(10, 3)), "outside bounds is not free")
    ok(occ.is_free(Vector2i(3, 3)), "inside bounds is free")
    eq(occ.get_entities_in_rect(Rect2i(9, 9, 5, 5)), [house], "rect query, distinct")
    ok(changes.size() >= 6, "tiles_changed fired")
    # a node leaving the tree is removed automatically
    var host := Node.new()
    root.add_child(host)
    var child := Node.new()
    host.add_child(child)
    occ.place(child, Vector2i(15, 15))
    ok(child.is_inside_tree(), "test node is in the tree")
    host.remove_child(child)
    ok(not occ.has_entity(child), "node leaving the tree is removed")
    child.free()
    host.free()
    occ.clear()
    eq(occ.get_all_entities().size(), 0, "clear")
    for n in [unit, house, crate]:
        n.free()
    occ.free()


func _test_edges() -> void:
    var es := EdgeOccupancyService.new()
    var changed := [0]
    es.edge_changed.connect(func(_a: Vector2i, _b: Vector2i) -> void: changed[0] += 1)
    var a := Vector2i(3, 3)
    var b := Vector2i(4, 3)
    ok(es.add(a, b, "wall") != null, "add wall")
    ok(es.get_edge(b, a) == es.get_edge(a, b), "edge is the same both ways")
    ok(es.is_move_blocked(a, b) and es.is_move_blocked(b, a), "wall blocks walking both ways")
    ok(es.is_view_blocked(a, b), "wall blocks sight")
    eq(es.get_cover(a, b), CoverLevel.FULL, "wall gives full cover")
    ok(es.add(a, Vector2i(5, 5), "wall") == null, "non adjacent refused")
    ok(es.add(a, Vector2i(3, 4), "nonsense") == null, "unknown type refused")
    # corner rule: wall between (3,3)-(4,3); diagonal (3,3)->(4,4) passes that corner
    ok(es.is_move_blocked(a, Vector2i(4, 4)), "no cutting the corner of a wall")
    ok(not es.is_view_blocked(a, Vector2i(4, 4)), "can peek past one wall on a diagonal")
    es.add(a, Vector2i(3, 4), "wall")
    ok(es.is_view_blocked(a, Vector2i(4, 4)), "both routes walled: diagonal sight blocked")
    # door
    es.add(Vector2i(8, 8), Vector2i(8, 9), "door")
    ok(es.is_move_blocked(Vector2i(8, 8), Vector2i(8, 9)), "closed door blocks")
    ok(es.set_open(Vector2i(8, 9), Vector2i(8, 8), true), "open door")
    ok(not es.is_move_blocked(Vector2i(8, 8), Vector2i(8, 9)) and not es.is_view_blocked(Vector2i(8, 8), Vector2i(8, 9)), "open door lets through")
    eq(es.get_cover(Vector2i(8, 8), Vector2i(8, 9)), CoverLevel.NONE, "open door gives no cover")
    ok(not es.set_open(a, b, true), "a wall cannot open")
    # damage
    var destroyed := []
    es.edge_destroyed.connect(func(_a: Vector2i, _b: Vector2i, e: Edge) -> void: destroyed.append(e.type))
    ok(not es.damage(a, b, 39), "wall survives 39")
    ok(es.damage(a, b, 1), "wall destroyed at 40")
    ok(not es.has_edge(a, b) and destroyed == ["wall"], "destroyed edge removed and signalled")
    ok(not es.is_move_blocked(a, b), "walkable once destroyed")
    es.add_run(Vector2i(0, 0), Vector2i(1, 0), 4, Vector2i(0, 1), "fence")
    eq(es.get_edges_of(Vector2i(2, 0)).size(), 1, "run of fences")
    EdgeTypes.register("sandbags", {"blocks_movement": true, "cover": CoverLevel.HALF})
    ok(es.add(Vector2i(6, 6), Vector2i(7, 6), "sandbags") != null, "custom edge type")
    EdgeTypes.reset()
    ok(changed[0] >= 8, "edge_changed fired")
    es.free()


func _test_terrain() -> void:
    var ts := TerrainService.new()
    eq(ts.get_cost(Vector2i(1, 1)), 1.0, "default grass cost")
    ts.set_tile(Vector2i(1, 1), "forest")
    eq(ts.get_cost(Vector2i(1, 1)), 2.0, "forest cost")
    eq(ts.get_cover(Vector2i(1, 1)), CoverLevel.HALF, "forest cover")
    ts.set_rect(Rect2i(5, 5, 2, 2), "rock")
    ok(not ts.is_walkable(Vector2i(6, 6)) and ts.get_cost(Vector2i(6, 6)) == INF, "rock not walkable")
    ok(ts.blocks_vision(Vector2i(5, 5)), "rock blocks sight")
    ts.set_tile(Vector2i(1, 1), "grass")
    eq(ts.get_type(Vector2i(1, 1)), "grass", "reset to default")
    eq(ts.get_min_cost(), 1.0, "min cost")
    TerrainTypes.register("ice", {"cost": 0.5, "elevation": 2})
    ts.set_tile(Vector2i(2, 2), "ice")
    eq(ts.get_elevation(Vector2i(2, 2)), 2, "custom terrain elevation")
    eq(ts.get_min_cost(), 0.5, "min cost follows data")
    TerrainTypes.reset()
    # from a TileMapLayer custom data layer
    var tile_set := TileSet.new()
    tile_set.add_custom_data_layer()
    tile_set.set_custom_data_layer_name(0, "terrain")
    tile_set.set_custom_data_layer_type(0, TYPE_STRING)
    var src := TileSetAtlasSource.new()
    src.texture = ImageTexture.create_from_image(Image.create(32, 16, false, Image.FORMAT_RGBA8))
    src.texture_region_size = Vector2i(16, 16)
    src.create_tile(Vector2i(0, 0))
    src.create_tile(Vector2i(1, 0))
    tile_set.add_source(src)
    src.get_tile_data(Vector2i(0, 0), 0).set_custom_data("terrain", "mud")
    var layer := TileMapLayer.new()
    layer.tile_set = tile_set
    layer.set_cell(Vector2i(3, 3), 0, Vector2i(0, 0))
    layer.set_cell(Vector2i(4, 3), 0, Vector2i(1, 0))
    var fresh := TerrainService.new()
    eq(fresh.load_from_layer(layer), 1, "one tile read from the layer")
    eq(fresh.get_type(Vector2i(3, 3)), "mud", "mud read from the layer")
    eq(fresh.get_type(Vector2i(4, 3)), "grass", "empty custom data keeps default")
    layer.free()
    fresh.free()
    ts.free()


func _make_world(projection := GridService.TileProjection.ISOMETRIC) -> Dictionary:
    var w := {}
    w.grid = _grid(projection)
    w.terrain = TerrainService.new()
    w.edges = EdgeOccupancyService.new()
    w.occ = TileOccupancyService.new()
    w.vision = VisionService.new()
    w.vision.grid_service = w.grid
    w.vision.terrain_service = w.terrain
    w.vision.edge_service = w.edges
    w.vision.occupancy_service = w.occ
    w.path = PathfindingService.new()
    w.path.grid_service = w.grid
    w.path.terrain_service = w.terrain
    w.path.edge_service = w.edges
    w.path.occupancy_service = w.occ
    w.cover = CoverService.new()
    w.cover.vision_service = w.vision
    w.cover.edge_service = w.edges
    w.cover.terrain_service = w.terrain
    return w

func _free_world(w: Dictionary) -> void:
    for k in w:
        if w[k] is Node:
            w[k].free()


func _test_vision() -> void:
    var w := _make_world()
    var v: VisionService = w.vision
    var origin := Vector2i(10, 10)
    var cone := v.get_cone_tiles(origin, "E", 90.0, 5)
    ok(origin in cone, "origin in its own cone")
    ok(Vector2i(15, 10) in cone and Vector2i(13, 12) in cone, "ahead and 45 degrees")
    ok(not (Vector2i(10, 15) in cone) and not (Vector2i(5, 10) in cone), "side and behind are out")
    ok(not (Vector2i(16, 10) in cone), "beyond range is out")
    var diag := v.get_cone_tiles(origin, "NE", 90.0, 4)
    ok(Vector2i(12, 8) in diag and not (Vector2i(14, 6) in diag), "diagonal facing reaches diagonally")
    eq(v.get_cone_tiles(origin, "N", 360.0, 3).size(), 29, "full circle of radius 3 has 29 tiles")
    eq(v.get_cone_offsets("E", 90.0, 5).size(), v.get_cone_offsets("E", 90.0, 5).size(), "cached cone")
    # symmetry of the line
    for pair in [[Vector2i(0, 0), Vector2i(7, 3)], [Vector2i(2, 9), Vector2i(8, 1)], [Vector2i(4, 4), Vector2i(4, 9)]]:
        var fwd := v.get_line(pair[0], pair[1])
        var back := v.get_line(pair[1], pair[0])
        back.reverse()
        eq(fwd, back, "line symmetric %s" % [pair])
        eq(fwd[0], pair[0], "line starts at origin")
        eq(fwd[-1], pair[1], "line ends at target")
    # blockers
    var a := Vector2i(2, 5)
    var b := Vector2i(8, 5)
    ok(v.has_line_of_sight(a, b), "clear sight")
    w.edges.add(Vector2i(5, 5), Vector2i(6, 5), "wall")
    ok(not v.has_line_of_sight(a, b) and not v.has_line_of_sight(b, a), "wall blocks sight both ways")
    ok(v.has_line_of_sight(a, Vector2i(5, 5)), "can see the tile in front of the wall")
    w.edges.set_open(Vector2i(5, 5), Vector2i(6, 5), true) # wall can't open
    w.edges.remove(Vector2i(5, 5), Vector2i(6, 5))
    w.edges.add(Vector2i(5, 5), Vector2i(6, 5), "door")
    ok(not v.has_line_of_sight(a, b), "closed door blocks sight")
    w.edges.set_open(Vector2i(5, 5), Vector2i(6, 5), true)
    ok(v.has_line_of_sight(a, b), "open door lets sight through")
    w.terrain.set_tile(Vector2i(5, 5), "rock")
    ok(not v.has_line_of_sight(a, b), "rock blocks sight")
    ok(v.has_line_of_sight(a, Vector2i(5, 5)), "the rock itself is visible")
    w.terrain.set_tile(Vector2i(5, 5), "grass")
    var truck := Node.new()
    w.occ.place(truck, Vector2i(5, 5), null, TileOccupancyService.LAYER_STRUCTURE)
    ok(not v.has_line_of_sight(a, b), "structure blocks sight")
    var soldier := Node.new()
    w.occ.place(soldier, Vector2i(5, 5), null, TileOccupancyService.LAYER_UNIT)
    w.occ.remove(truck)
    ok(v.has_line_of_sight(a, b), "a unit does not block sight")
    # visible tiles and can_see
    var visible := v.get_visible_tiles(a, "E", 90.0, 6)
    ok(Vector2i(8, 5) in visible and a in visible, "visible set has target and origin")
    ok(v.can_see(a, "E", 90.0, 6, b) and not v.can_see(a, "W", 90.0, 6, b), "facing matters")
    ok(not v.can_see(Vector2i(1, 1), "N", 360.0, 6, Vector2i(1, -2)), "outside the map is not seen")
    v.precompute(90.0, 4)
    soldier.free()
    truck.free()
    _free_world(w)


func _test_cover() -> void:
    var w := _make_world()
    var c: CoverService = w.cover
    var target := Vector2i(6, 5)
    eq(c.get_cover(Vector2i(2, 5), target), CoverLevel.NONE, "open ground")
    w.edges.add(Vector2i(5, 5), target, "fence")
    eq(c.get_cover(Vector2i(2, 5), target), CoverLevel.HALF, "fence in front")
    eq(c.get_cover(Vector2i(10, 5), target), CoverLevel.NONE, "fence behind gives nothing")
    w.terrain.set_tile(target, "forest")
    eq(c.get_cover(Vector2i(10, 5), target), CoverLevel.HALF, "forest covers from any side")
    var dirs := c.get_directional_cover(target)
    eq(dirs["W"], CoverLevel.HALF, "directional cover west")
    eq(dirs.size(), 8, "eight directions")
    c.extra_cover = func(_s: Vector2i, _t: Vector2i) -> int: return CoverLevel.FULL
    eq(c.get_cover(Vector2i(10, 5), target), CoverLevel.FULL, "extra cover source")
    _free_world(w)


func _test_pathfinding() -> void:
    var w := _make_world()
    var p: PathfindingService = w.path
    var start := Vector2i(1, 1)
    var goal := Vector2i(6, 1)
    var path := p.find_path(start, goal)
    eq(path.size(), 6, "straight path length")
    eq(path[0], start, "path starts at start")
    eq(path[-1], goal, "path ends at goal")
    eq(p.find_path(start, start), [start] as Array[Vector2i], "path to self")
    eq(p.find_path(start, Vector2i(30, 30)).size(), 0, "goal outside the map")
    # diagonal costs more than an orthogonal step but less than two
    var diag := p.find_path(Vector2i(1, 1), Vector2i(4, 4))
    eq(diag.size(), 4, "pure diagonal")
    ok(absf(p.path_cost(diag) - 3.0 * 1.4142135) < 0.001, "diagonal cost")
    # 4 directions
    var profile := MoveProfile.new()
    profile.diagonals = false
    eq(p.find_path(Vector2i(1, 1), Vector2i(4, 4), profile).size(), 7, "4-connected path")
    # terrain cost: go around the mud
    w.terrain.set_rect(Rect2i(3, 0, 1, 3), "shallow_water")
    var around := p.find_path(start, goal)
    ok(not (Vector2i(3, 1) in around), "avoids expensive water when a cheap detour exists")
    w.terrain.set_rect(Rect2i(3, 0, 1, 3), "grass")
    # a wall edge forces a detour; a full wall makes it impossible
    for y in 20:
        w.edges.add(Vector2i(3, y), Vector2i(4, y), "wall")
    eq(p.find_path(start, goal).size(), 0, "sealed by a wall: no path")
    w.edges.set_open(Vector2i(3, 2), Vector2i(4, 2), true) # a wall does not open
    w.edges.remove(Vector2i(3, 2), Vector2i(4, 2))
    w.edges.add(Vector2i(3, 2), Vector2i(4, 2), "door")
    var closed_door := p.find_path(start, goal)
    eq(closed_door.size(), 0, "closed door does not let through")
    w.edges.set_open(Vector2i(3, 2), Vector2i(4, 2), true)
    var through := p.find_path(start, goal)
    ok(through.size() > 0 and Vector2i(3, 2) in through and Vector2i(4, 2) in through, "path goes through the open door")
    for i in range(1, through.size()):
        ok(not w.edges.is_move_blocked(through[i - 1], through[i]), "every step legal")
    # destroying the wall opens a shorter way (no stale graph)
    w.edges.damage(Vector2i(3, 1), Vector2i(4, 1), 999)
    eq(p.find_path(start, goal).size(), 6, "shorter path once the wall is destroyed")
    w.edges.clear()
    # units block, the mover does not block itself, goal may be occupied for attacks
    var mover := Node.new()
    var enemy := Node.new()
    w.occ.place(mover, start)
    w.occ.place(enemy, goal)
    var prof := MoveProfile.new()
    prof.ignore = mover
    eq(p.find_path(start, goal, prof).size(), 0, "occupied goal refused")
    prof.goal_may_be_occupied = true
    eq(p.find_path(start, goal, prof).size(), 6, "occupied goal allowed for attack moves")
    var wall_unit := Node.new()
    w.occ.place(wall_unit, Vector2i(3, 1))
    ok(not (Vector2i(3, 1) in p.find_path(start, goal, prof)), "path walks around a unit")
    # structures stop diagonal corner cutting, units do not
    var house := Node.new()
    w.occ.place(house, Vector2i(10, 10), null, TileOccupancyService.LAYER_STRUCTURE)
    ok(not p.can_step(Vector2i(9, 9), Vector2i(10, 10), prof), "cannot enter structure")
    ok(not p.can_step(Vector2i(9, 10), Vector2i(10, 11), prof) , "cannot cut the corner of a structure")
    ok(p.can_step(Vector2i(2, 1), Vector2i(3, 2), prof), "a unit on a corner does not stop a diagonal step")
    # reachable tiles
    var field := p.compute_field(Vector2i(15, 15), 2.0)
    var reach := p.get_reachable_tiles(field)
    ok(Vector2i(15, 15) in reach and Vector2i(17, 15) in reach, "start and two steps reachable")
    ok(not (Vector2i(18, 15) in reach), "three steps not reachable with 2 points")
    ok(Vector2i(16, 16) in reach and not (Vector2i(17, 17) in reach), "diagonal 1.41 in, 2.83 out")
    var field_path := p.path_in_field(field, Vector2i(17, 15))
    eq(field_path.size(), 3, "path inside a field")
    eq(p.path_in_field(field, Vector2i(0, 0)).size(), 0, "tile outside the field has no path")
    # elevation: a cliff is not a step
    TerrainTypes.register("cliff", {"elevation": 3})
    w.terrain.set_tile(Vector2i(16, 15), "cliff")
    ok(not p.can_step(Vector2i(15, 15), Vector2i(16, 15), MoveProfile.new()), "cannot climb 3 levels in a step")
    TerrainTypes.reset()
    # custom rules
    var custom := MoveProfile.new()
    custom.can_enter = func(t: Vector2i) -> bool: return t.y != 1 or t.x <= 2
    ok(not p.can_step(Vector2i(2, 1), Vector2i(3, 1), custom), "custom can_enter rule")
    custom.can_enter = Callable()
    custom.extra_cost = func(_t: Vector2i) -> float: return 5.0
    ok(absf(p.step_cost(Vector2i(0, 0), Vector2i(1, 0), custom) - 6.0) < 0.001, "extra cost added")
    # optimal on a random-ish maze: A* cost equals field cost (Dijkstra)
    var rng := RandomNumberGenerator.new()
    rng.seed = 7
    w.terrain.clear()
    for i in 70:
        w.terrain.set_tile(Vector2i(rng.randi_range(0, 19), rng.randi_range(0, 19)), ["rock", "mud", "forest"][rng.randi() % 3])
    var origin := Vector2i(0, 0)
    var big := p.compute_field(origin, 1000.0)
    var mismatches := 0
    for target: Vector2i in big["cost"]:
        var astar := p.find_path(origin, target)
        if astar.is_empty() or absf(p.path_cost(astar) - big["cost"][target]) > 0.001:
            mismatches += 1
    eq(mismatches, 0, "A* agrees with Dijkstra on every reachable tile")
    for n in [mover, enemy, wall_unit, house]:
        n.free()
    _free_world(w)


func _test_visibility() -> void:
    var v := VisibilityService.new()
    var events := []
    v.visibility_changed.connect(func(team: String, shown: Array[Vector2i], hidden: Array[Vector2i]) -> void: events.append([team, shown.size(), hidden.size()]))
    var explored_events := []
    v.tiles_explored.connect(func(team: String, tiles: Array[Vector2i]) -> void: explored_events.append([team, tiles.size()]))
    var a := Node.new()
    var b := Node.new()
    var enemy := Node.new()
    var area_a: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
    var area_b: Array[Vector2i] = [Vector2i(2, 0), Vector2i(3, 0)]
    eq(v.get_state("red", Vector2i(0, 0)), VisibilityService.State.UNEXPLORED, "unexplored at first")
    v.set_viewer(a, "red", area_a)
    eq(v.get_state("red", Vector2i(1, 0)), VisibilityService.State.VISIBLE, "visible")
    eq(events[0], ["red", 3, 0], "three tiles shown")
    eq(explored_events[0], ["red", 3], "three tiles explored")
    v.set_viewer(b, "red", area_b)
    eq(events[1], ["red", 1, 0], "only the new tile is shown")
    v.set_viewer(a, "red", [Vector2i(0, 0)] as Array[Vector2i])
    eq(events[2], ["red", 0, 1], "tile 1,0 hidden; tile 2,0 still seen by b")
    ok(v.is_visible("red", Vector2i(2, 0)), "a tile seen by someone else stays visible")
    eq(v.get_state("red", Vector2i(1, 0)), VisibilityService.State.EXPLORED, "hidden after being seen: explored")
    ok(v.is_explored("red", Vector2i(1, 0)) and not v.is_visible("red", Vector2i(1, 0)), "explored not visible")
    var explored_before := explored_events.size()
    v.set_viewer(a, "red", area_a)
    eq(explored_events.size(), explored_before, "seeing explored tiles again is not exploring")
    v.remove_viewer(b)
    ok(v.is_visible("red", Vector2i(2, 0)), "still seen by a")
    ok(not v.is_visible("red", Vector2i(3, 0)) and v.is_explored("red", Vector2i(3, 0)), "b's own tile fell back to explored")
    # teams are separate
    v.set_viewer(enemy, "blue", [Vector2i(0, 0)] as Array[Vector2i])
    ok(v.is_visible("blue", Vector2i(0, 0)) and not v.is_visible("blue", Vector2i(1, 0)), "blue sees its own tile only")
    eq(v.get_visible_tiles("red").size(), 3, "red visible list")
    eq(v.get_explored_tiles("red").size(), 4, "red explored list")
    # a viewer changing team
    v.set_viewer(enemy, "red", [Vector2i(9, 9)] as Array[Vector2i])
    ok(not v.is_visible("blue", Vector2i(0, 0)) and v.is_visible("red", Vector2i(9, 9)), "viewer moved to another team")
    v.clear()
    ok(not v.is_visible("red", Vector2i(0, 0)) and not v.is_explored("red", Vector2i(0, 0)), "clear forgets everything")
    ok(not v.has_viewer(a), "no viewers after clear")
    for n in [a, b, enemy, v]:
        n.free()
