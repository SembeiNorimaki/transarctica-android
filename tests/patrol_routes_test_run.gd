extends Node
# Headless test of the patrol routes of the Routes layer of a combat map: reading the routes (open and
# closed, in order), the unit standing on a route becoming its patrol, and the AI walking the route
# (round and round, or to the end and back).
# It is a scene because the battle uses autoloads.
# Run:  godot --headless --path . res://tests/patrol_routes_test_run.tscn

var _failed := 0
var _checks := 0
var scene: CombatSceneCity
var map: CombatMap

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

func wait_until(condition: Callable, timeout := 8.0) -> bool:
    var waited := 0.0
    while not condition.call() and waited < timeout:
        await get_tree().create_timer(0.05, true, false, true).timeout
        waited += 0.05
    return condition.call()


func _run() -> void:
    _test_tileset()
    _test_reading()
    _test_units_on_routes()
    _test_guards()
    await _test_city_map()
    await _test_ai_walks_routes()
    print("%d checks, %d failed" % [_checks, _failed])
    print("ALL PASSED" if _failed == 0 else "FAILED")
    get_tree().quit(1 if _failed > 0 else 0)


const TILES: Array[String] = ["NS", "EW", "NE", "ES", "SW", "NW", "N", "E", "S", "W"]

# A fresh empty map to paint routes on
func _new_map() -> CombatMap:
    if map != null:
        map.free()
    map = load("res://scenes/maps/combat_map.tscn").instantiate()
    add_child(map)
    for layer in [map.routes, map.spawns]:
        layer.clear()
    return map

func _paint(tile: Vector2i, sides: String) -> void:
    map.routes.set_cell(tile, 0, Vector2i(TILES.find(sides), 0))

# A route from a list of tiles, painted the way the generator does it
func _paint_route(path: Array[Vector2i], cyclic: bool) -> void:
    var n := path.size()
    var names := {Vector2i(0, -1): "N", Vector2i(1, 0): "E", Vector2i(0, 1): "S", Vector2i(-1, 0): "W"}
    for i in n:
        var sides: Array[String] = []
        for j in [i - 1, i + 1]:
            if cyclic or (j >= 0 and j < n):
                sides.append(names[path[j % n] - path[i]])
        sides.sort_custom(func(a: String, b: String) -> bool: return "NESW".find(a) < "NESW".find(b))
        var key := "".join(sides)
        if key.length() == 2 and not TILES.has(key):
            key = key[1] + key[0]
        _paint(path[i], key)


func _test_tileset() -> void:
    var tileset: TileSet = load("res://assets/combat/combat_routes.tres")
    var source := tileset.get_source(0) as TileSetAtlasSource
    eq(source.get_tiles_count(), 10, "6 tiles with two sides and 4 ends")
    var seen := {}
    for i in source.get_tiles_count():
        var sides := str(source.get_tile_data(source.get_tile_id(i), 0).get_custom_data("route_sides"))
        seen[sides] = true
    for sides in TILES:
        ok(seen.has(sides), "tile %s" % sides)
    eq(tileset.tile_size, Vector2i(64, 32), "same tile size as the other layers")
    eq(tileset.tile_shape, TileSet.TILE_SHAPE_ISOMETRIC, "isometric")


func _test_reading() -> void:
    _new_map()
    eq(map.read_routes().size(), 0, "no routes on an empty layer")
    # an open route with a corner, painted in the middle of the list order
    var open: Array[Vector2i] = [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5), Vector2i(7, 6), Vector2i(7, 7)]
    _paint_route(open, false)
    var routes := map.read_routes()
    eq(routes.size(), 1, "one route")
    eq(routes[0]["tiles"], open, "its tiles in order, from the end that is further north")
    eq(routes[0]["cyclic"], false, "it is open")
    # the same painted backwards reads the same way
    _new_map()
    var backwards := open.duplicate()
    backwards.reverse()
    _paint_route(backwards, false)
    var again := map.read_routes()
    eq(again[0]["tiles"], open, "the order does not depend on how it was drawn")
    # a loop
    _new_map()
    var loop: Array[Vector2i] = [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 4), Vector2i(3, 4), Vector2i(2, 4), Vector2i(2, 3)]
    _paint_route(loop, true)
    routes = map.read_routes()
    eq(routes.size(), 1, "one loop")
    eq(routes[0]["cyclic"], true, "it is closed")
    eq(routes[0]["tiles"].size(), 8, "all its tiles")
    eq(routes[0]["tiles"][0], Vector2i(2, 2), "it starts at its smallest tile")
    for i in 8:
        var a: Vector2i = routes[0]["tiles"][i]
        var b: Vector2i = routes[0]["tiles"][(i + 1) % 8]
        eq(absi(a.x - b.x) + absi(a.y - b.y), 1, "tiles %d and %d are neighbors" % [i, (i + 1) % 8])
    # two routes that do not touch, and a single end tile
    _paint_route([Vector2i(10, 10), Vector2i(10, 11), Vector2i(10, 12)], false)
    _paint(Vector2i(20, 20), "N")
    routes = map.read_routes()
    eq(routes.size(), 3, "a loop, an open route and a lone tile")
    eq(map.get_route_at(Vector2i(10, 11))["tiles"].size(), 3, "the route at a tile")
    ok(map.get_route_at(Vector2i(30, 30)).is_empty(), "no route where nothing is painted")
    # sides that do not face each other do not join
    _new_map()
    _paint(Vector2i(1, 1), "E")   # points at (2,1)
    _paint(Vector2i(2, 1), "NS")  # does not point back
    eq(map.read_routes().size(), 2, "tiles whose sides do not face each other are two routes")
    # every one of the ten tiles reads
    _new_map()
    var x := 0
    for sides in TILES:
        _paint(Vector2i(x, 0), sides)
        x += 3
    eq(map.read_routes().size(), 10, "ten lone tiles")


func _test_units_on_routes() -> void:
    _new_map()
    var open: Array[Vector2i] = [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5), Vector2i(8, 5)]
    _paint_route(open, false)
    map.spawns.set_cell(Vector2i(7, 5), 1, Vector2i(1, 4)) # an enemy speeder on the route
    map.spawns.set_cell(Vector2i(6, 5), 1, Vector2i(1, 2)) # an enemy buggy on the same route
    map.spawns.set_cell(Vector2i(1, 1), 1, Vector2i(1, 2)) # and one that is not on any route
    var spawns := map.read_spawns()
    eq(spawns.size(), 3, "three markers")
    var on_route: Array[Dictionary] = []
    var off_route: Array[Dictionary] = []
    for spawn in spawns:
        if spawn.has("route"):
            on_route.append(spawn)
        else:
            off_route.append(spawn)
    eq(on_route.size(), 1, "only one unit is put on a route")
    eq(on_route[0]["tile"], Vector2i(6, 5), "the first one in reading order")
    eq(on_route[0]["role"], "patrol", "it is a patrol")
    eq(on_route[0]["route"], open, "with the route")
    eq(on_route[0]["route_cyclic"], false, "that is open")
    eq(off_route.size(), 2, "the others are what they were")
    ok(not (off_route[0].get("role", "") == "patrol" and off_route[0]["tile"] == Vector2i(7, 5)), "the second one on the route is not a patrol of it")
    map.free()
    map = null


func _test_guards() -> void:
    var tileset: TileSet = load("res://assets/combat/combat_guards.tres")
    eq((tileset.get_source(0) as TileSetAtlasSource).get_tiles_count(), 1, "one guard post tile")
    eq(tileset.tile_size, Vector2i(64, 32), "same tile size as the other layers")
    _new_map()
    ok(map.guards != null, "the map has a Guards layer")
    map.guards.set_cell(Vector2i(3, 3), 0, Vector2i.ZERO)
    map.guards.set_cell(Vector2i(5, 5), 0, Vector2i.ZERO)
    _paint_route([Vector2i(5, 5), Vector2i(6, 5)], false)
    map.spawns.set_cell(Vector2i(3, 3), 1, Vector2i(1, 4)) # an enemy speeder (a patrol by type) on a guard post
    map.spawns.set_cell(Vector2i(8, 8), 1, Vector2i(1, 4)) # one on nothing
    map.spawns.set_cell(Vector2i(5, 5), 1, Vector2i(1, 2)) # a buggy on a guard post that is also a route
    var by_tile := {}
    for spawn in map.read_spawns():
        by_tile[spawn["tile"]] = spawn
    eq(by_tile[Vector2i(3, 3)].get("role", ""), "guard", "a unit on a guard post guards")
    ok(not by_tile[Vector2i(3, 3)].has("route"), "and has no route")
    eq(by_tile[Vector2i(8, 8)].get("role", ""), "", "a unit on nothing is what its type says")
    eq(by_tile[Vector2i(5, 5)].get("role", ""), "patrol", "on a route that wins")
    map.free()
    map = null

func _test_city_map() -> void:
    scene = load("res://scenes/core/combat_scene_city.tscn").instantiate()
    scene.player_units_from_train = false
    get_tree().root.add_child(scene)
    await get_tree().process_frame
    await get_tree().process_frame
    get_tree().paused = false
    var city: CombatMap = scene.combat_map
    ok(city.routes != null, "the city has a Routes layer")
    ok(not city.routes.visible, "hidden during the battle")
    var routes := city.read_routes()
    eq(routes.size(), 2, "the city has two routes")
    var loops := 0
    for route in routes:
        loops += 1 if route["cyclic"] else 0
    eq(loops, 1, "one is a loop")
    var patrols := 0
    for soldier in scene.battle_unit_manager.soldiers:
        if not soldier.patrol_route.is_empty():
            patrols += 1
            ok(soldier.role == "patrol", "%s on a route is a patrol" % soldier.unit_id)
            ok(soldier.patrol_route.has(soldier.tile), "and stands on its route")
    eq(patrols, 2, "one unit on each route")
    var posts := 0
    for soldier in scene.battle_unit_manager.soldiers:
        if soldier.unit_type == "humvee" and soldier.team == "enemy":
            posts += 1
            eq(soldier.role, "guard", "the enemy humvee, a patrol by type, guards its post")
    eq(posts, 1, "one enemy humvee")
    ok(not city.guards.visible, "the guard posts are hidden during the battle")


# The enemy's units walk their routes
func _test_ai_walks_routes() -> void:
    var ai: FieldAI = scene.field_ai
    ai.think_interval = 0.05
    ai.seed_random(5)
    var units: BattleUnitManager = scene.battle_unit_manager
    var turns: TurnManager = scene.flow_manager
    var loop_unit: Soldier = null
    var open_unit: Soldier = null
    for soldier in units.soldiers:
        if soldier.patrol_route.is_empty():
            continue
        if soldier.patrol_cyclic:
            loop_unit = soldier
        else:
            open_unit = soldier
    ok(loop_unit != null and open_unit != null, "a unit on each kind of route")
    if loop_unit == null or open_unit == null:
        return
    var walked := {loop_unit: [], open_unit: []}
    for soldier: Soldier in walked:
        var steps: Array = walked[soldier]
        soldier.step_finished.connect(func(_s: Soldier, tile: Vector2i) -> void: steps.append(tile))
    for i in 14:
        var number := turns.turn_number
        turns.end_turn()
        await wait_until(func() -> bool: return turns.turn_number > number and turns.current_team == Soldier.TEAM_PLAYER, 20.0)
    # the loop: every step is on the route, it goes one way round, and it does the whole round
    var loop_steps: Array = walked[loop_unit]
    var loop_route := loop_unit.patrol_route
    ok(loop_steps.size() >= loop_route.size(), "the loop patrol walked a whole round (%d steps)" % loop_steps.size())
    var all_on := true
    var forward := true
    for i in loop_steps.size():
        all_on = all_on and loop_route.has(loop_steps[i])
        if i > 0:
            forward = forward and loop_route[posmod(loop_route.find(loop_steps[i - 1]) + 1, loop_route.size())] == loop_steps[i]
    ok(all_on, "it stays on its route")
    ok(forward, "and keeps going the same way round")
    # the open route: it reaches both ends and turns round
    var open_steps: Array = walked[open_unit]
    var route := open_unit.patrol_route
    ok(open_steps.has(route[0]) and open_steps.has(route[route.size() - 1]), "the other one reaches both ends of its route (%d steps)" % open_steps.size())
    var on_route := true
    var one_at_a_time := true
    for i in open_steps.size():
        on_route = on_route and route.has(open_steps[i])
        if i > 0:
            one_at_a_time = one_at_a_time and absi(route.find(open_steps[i]) - route.find(open_steps[i - 1])) == 1
    ok(on_route, "it stays on its route")
    ok(one_at_a_time, "tile by tile, turning round only at the ends")
    eq(ai.get_mode(open_unit), FieldAI.Mode.NORMAL, "it is calm")
    # an enemy in sight: it leaves the route to fight, and goes back to it when it is over
    var spot := Vector2i(-1, -1)
    for d in [Vector2i(0, 4), Vector2i(0, -4), Vector2i(4, 0), Vector2i(-4, 0), Vector2i(3, 3), Vector2i(-3, -3), Vector2i(3, -3), Vector2i(-3, 3)]:
        var tile: Vector2i = open_unit.tile + d
        if scene.grid_service.is_inside_map(tile) and scene.terrain_service.is_walkable(tile) and scene.occupancy_service.is_free(tile) \
                and scene.vision_service.has_line_of_sight(open_unit.tile, tile) and not open_unit.patrol_route.has(tile):
            spot = tile
            break
    var target: Soldier = units.spawn("player", "buggy", spot, "N") if spot.x >= 0 else null
    ok(target != null, "an enemy appears near the open route patrol")
    if target == null:
        scene.queue_free()
        return
    open_unit.look_at_tile(spot) # it looks at it
    for i in 8: # a few rounds at most
        if ai.get_mode(open_unit) == FieldAI.Mode.ALERT or not target.is_alive():
            break
        var number := turns.turn_number
        turns.end_turn()
        await wait_until(func() -> bool: return turns.turn_number > number and turns.current_team == Soldier.TEAM_PLAYER, 20.0)
    ok(ai.get_mode(open_unit) == FieldAI.Mode.ALERT or not target.is_alive(), "the patrol engaged it")
    if target != null and target.is_alive():
        units.remove_soldier(target)
    for i in 12:
        var number := turns.turn_number
        turns.end_turn()
        await wait_until(func() -> bool: return turns.turn_number > number and turns.current_team == Soldier.TEAM_PLAYER, 20.0)
    eq(ai.get_mode(open_unit), FieldAI.Mode.NORMAL, "calm again")
    ok(open_unit.patrol_route.has(open_unit.tile), "and back on its route")
    scene.queue_free()
