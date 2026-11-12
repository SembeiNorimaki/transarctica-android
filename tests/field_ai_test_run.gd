extends Node
# Headless test of the enemy's AI in the city battle (FieldAI): the roles of the units (patrol or
# guard), the alert mode when a unit sees an enemy or is shot, engaging, the leash, calming down and
# going back to the role. It is a scene because the battle uses autoloads.
# Run:  godot --headless --path . res://tests/field_ai_test_run.tscn

var _failed := 0
var _checks := 0
var scene: CombatSceneCity
var ai: FieldAI
var turns: TurnManager
var units: BattleUnitManager
var origin := Vector2i.ZERO # the top left of an open area of the map
const AREA := Vector2i(20, 8) # the city has an avenue this size: no buildings, no walls

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


# A fresh battle with nobody in it, and an open area to put the test units in
func _new_scene(ai_enabled := true) -> void:
    if scene != null:
        scene.queue_free()
        await get_tree().process_frame
    scene = load("res://scenes/core/combat_scene_city.tscn").instantiate()
    scene.get_node("AI/FieldAI").enabled = ai_enabled
    get_tree().root.add_child(scene)
    await get_tree().process_frame
    await get_tree().process_frame
    get_tree().paused = false
    ai = scene.field_ai
    ai.think_interval = 0.05
    ai.seed_random(11)
    turns = scene.flow_manager
    units = scene.battle_unit_manager
    units.roll_hits = false # a shot at somebody it reaches hits
    for soldier in units.soldiers.duplicate():
        units.remove_soldier(soldier)
    origin = _find_open_area()

func _find_open_area() -> Vector2i:
    var rect := scene.grid_service.map_rect
    for y in range(rect.position.y, rect.end.y - AREA.y):
        for x in range(rect.position.x, rect.end.x - AREA.x):
            var clear := true
            for dy in AREA.y:
                for dx in AREA.x:
                    var tile := Vector2i(x + dx, y + dy)
                    clear = clear and scene.terrain_service.is_walkable(tile) and scene.occupancy_service.is_free(tile)
                if not clear:
                    break
            if clear and scene.vision_service.has_line_of_sight(Vector2i(x, y), Vector2i(x + AREA.x - 1, y + AREA.y - 1)) \
                    and scene.vision_service.has_line_of_sight(Vector2i(x, y + AREA.y - 1), Vector2i(x + AREA.x - 1, y)):
                return Vector2i(x, y)
    return Vector2i(-1, -1)

func _at(dx: int, dy: int) -> Vector2i:
    return origin + Vector2i(dx, dy)

func _spawn(team: String, unit_type: String, tile: Vector2i, facing: String, role := "") -> Soldier:
    var soldier := units.spawn(team, unit_type, tile, facing, role)
    ok(soldier != null, "%s %s spawned at %s" % [team, unit_type, tile])
    return soldier

# Hands the turn over: the player's ends, the enemy's is played by the AI, and the player's comes back
func _enemy_turn() -> bool:
    var number := turns.turn_number
    turns.end_turn()
    return await wait_until(func() -> bool: return turns.turn_number > number and turns.current_team == Soldier.TEAM_PLAYER, 20.0)

func _enemy_turns(count: int) -> void:
    for i in count:
        ok(await _enemy_turn(), "the enemy's turn %d ends by itself" % (i + 1))


func _run() -> void:
    await _new_scene()
    ok(origin != Vector2i(-1, -1), "an open area of %dx%d tiles at %s" % [AREA.x, AREA.y, origin])
    _test_roles()
    await _test_guard()
    await _test_patrol()
    await _test_sees_an_enemy()
    await _test_does_not_see()
    await _test_leash()
    await _test_chase()
    await _test_calming_down()
    await _test_shot_from_afar()
    await _test_ai_off()
    scene.queue_free()
    await get_tree().process_frame
    print("%d checks, %d failed" % [_checks, _failed])
    print("ALL PASSED" if _failed == 0 else "FAILED")
    get_tree().quit(1 if _failed > 0 else 0)


# Fast units patrol; soldiers, tanks and artillery guard; a unit may be told otherwise
func _test_roles() -> void:
    for unit_type in ["speeder", "buggy", "humvee"]:
        eq(UnitTypes.default_role(unit_type), "patrol", "a %s patrols" % unit_type)
    for unit_type in ["artillery", "tank", "grav_tank", "liquidator", "pioneer", "redops"]:
        eq(UnitTypes.default_role(unit_type), "guard", "a %s guards" % unit_type)
    eq(_spawn("enemy", "speeder", _at(1, 1), "E").role, "patrol", "a speeder on the map patrols")
    eq(_spawn("enemy", "artillery", _at(5, 1), "E").role, "guard", "an artillery on the map guards")
    eq(_spawn("enemy", "tank", _at(9, 1), "E", "patrol").role, "patrol", "a tank can be told to patrol")
    eq(_spawn("enemy", "buggy", _at(13, 1), "E", "guard").role, "guard", "and a buggy to guard")
    eq(ai.get_units().size(), 4, "the AI has the 4 units of its team")
    _spawn("player", "tank", _at(17, 5), "W")
    eq(ai.get_units().size(), 4, "and none of the player's")
    _clear()
    eq(ai.get_units().size(), 0, "a unit that leaves the battle is forgotten")

func _clear() -> void:
    for soldier in units.soldiers.duplicate():
        units.remove_soldier(soldier)


# A guard stays at its post and turns around
func _test_guard() -> void:
    var tank := _spawn("enemy", "tank", _at(4, 4), "E")
    var facing := tank.facing
    var moved := false
    tank.step_started.connect(func(_s: Soldier, _a: Vector2i, _b: Vector2i) -> void: moved = true)
    await _enemy_turns(7)
    ok(not moved, "a guard does not walk")
    eq(tank.tile, _at(4, 4), "it is at its post")
    ok(tank.facing != facing, "it has turned around (%s -> %s)" % [facing, tank.facing])
    eq(ai.get_mode(tank), FieldAI.Mode.NORMAL, "and it is calm")
    _clear()


# A patrol walks a round of stops around its post
func _test_patrol() -> void:
    var speeder := _spawn("enemy", "speeder", _at(10, 4), "E")
    var home := speeder.tile
    var visited := {}
    speeder.step_finished.connect(func(_s: Soldier, tile: Vector2i) -> void: visited[tile] = true)
    var turns_played := 0
    while turns_played < 14 and visited.size() < 8:
        await _enemy_turn()
        turns_played += 1
    ok(visited.size() >= 8, "a patrol walks (%d tiles in %d turns)" % [visited.size(), turns_played])
    var route := ai.get_route(speeder)
    ok(route.size() >= 2, "it has a round of %d stops" % route.size())
    for stop in route:
        ok(Vector2(stop).distance_to(Vector2(home)) <= ai.patrol_radius * 1.5 + 1.0, "stop %s is near the post" % stop)
    var far := 0.0
    for tile: Vector2i in visited:
        far = maxf(far, Vector2(tile).distance_to(Vector2(home)))
    ok(far <= ai.patrol_radius * 1.5 + 3.0, "it keeps near its post (%.1f tiles at most)" % far)
    eq(ai.get_home(speeder), home, "its post is where it started")
    eq(ai.get_mode(speeder), FieldAI.Mode.NORMAL, "and it is calm")
    _clear()


# An enemy in the view of a unit makes it alert and it shoots
func _test_sees_an_enemy() -> void:
    var tank := _spawn("enemy", "tank", _at(3, 4), "E")
    var target := _spawn("player", "buggy", _at(9, 4), "W") # in front of it, 6 tiles
    var alerts: Array = []
    var on_alert := func(unit: Soldier, tile: Vector2i) -> void: alerts.append([unit, tile])
    ai.alerted.connect(on_alert)
    var shots := [0]
    var count := func(attacker: Soldier, _t: Soldier, _d: int, _c: int) -> void:
        if attacker == tank:
            shots[0] += 1
    units.shot_resolved.connect(count)
    ok(ai.get_visible_enemies(tank).has(target), "the tank sees the buggy")
    eq(ai.get_mode(tank), FieldAI.Mode.NORMAL, "it is calm before the AI looks")
    await _enemy_turn()
    eq(ai.get_mode(tank), FieldAI.Mode.ALERT, "it is alert")
    eq(alerts.size(), 1, "once")
    if alerts.size() == 1:
        eq(alerts[0], [tank, target.tile], "at the place of the enemy")
    ok(shots[0] >= 1, "it shot at it (%d shots)" % shots[0])
    ok(target.hp < target.max_hp, "and hit it (%d hp of %d)" % [target.hp, target.max_hp])
    eq(tank.tile, _at(3, 4), "from its post, which is in range")
    units.shot_resolved.disconnect(count)
    ai.alerted.disconnect(on_alert)
    _clear()


# What is out of the view does not alert: behind it, beyond the range, out of the cone
func _test_does_not_see() -> void:
    var tank := _spawn("enemy", "tank", _at(8, 4), "E") # views 10 tiles, 100 degrees
    var behind := _spawn("player", "liquidator", _at(2, 4), "N") # 6 tiles behind
    ok(not ai.get_visible_enemies(tank).has(behind), "the tank does not see what is behind it")
    await _enemy_turn()
    eq(ai.get_mode(tank), FieldAI.Mode.NORMAL, "it is not alert")
    units.remove_soldier(behind)
    var far := _spawn("player", "liquidator", _at(19, 4), "N") # in front, 11 tiles: past its 10
    ok(not ai.get_visible_enemies(tank).has(far), "nor what is beyond its view range")
    units.remove_soldier(far)
    var side := _spawn("player", "liquidator", _at(8, 0), "N") # 4 tiles to its side: a quarter round off
    ok(not ai.get_visible_enemies(tank).has(side), "nor what is to its side")
    units.remove_soldier(side)
    var close := _spawn("player", "liquidator", _at(6, 4), "N") # 2 tiles behind: right next to it
    ok(ai.get_visible_enemies(tank).has(close), "but it notices what is right next to it")
    await _enemy_turn()
    eq(ai.get_mode(tank), FieldAI.Mode.ALERT, "and goes alert")
    _clear()


# A guard goes after an enemy only as far as its leash lets it
func _test_leash() -> void:
    var grav := _spawn("enemy", "grav_tank", _at(2, 3), "E") # 2x2, range 10
    grav.view_range = 14 # so that it sees what is out of its range
    var target := _spawn("player", "liquidator", _at(13, 4), "W") # 11 tiles: out of range
    var home := grav.tile
    ai.guard_leash = 0.0
    ok(ai.get_visible_enemies(grav).has(target), "the grav tank sees the liquidator, beyond its range of 10")
    await _enemy_turn()
    eq(ai.get_mode(grav), FieldAI.Mode.ALERT, "it is alert")
    eq(grav.tile, home, "but with no leash it holds its post")
    eq(grav.facing, "E", "watching it")
    eq(target.hp, target.max_hp, "and does not shoot, out of range")
    ai.guard_leash = 4.0
    await _enemy_turn()
    ok(grav.tile != home, "with a leash of 4 it goes after it")
    ok(Vector2(grav.tile).distance_to(Vector2(home)) <= 4.0 + 1.0, "but not far (%s from %s)" % [grav.tile, home])
    ok(target.hp < target.max_hp, "and shoots when it is in range")
    _clear()


# A fast unit chases further
func _test_chase() -> void:
    var speeder := _spawn("enemy", "speeder", _at(2, 4), "E") # view 11, gun range 6
    var target := _spawn("player", "liquidator", _at(14, 4), "W") # 12 tiles: out of view
    ok(not ai.get_visible_enemies(speeder).has(target), "the speeder does not see it yet")
    speeder.view_range = 12
    ok(ai.get_visible_enemies(speeder).has(target), "now it does, beyond its gun's range")
    var home := speeder.tile
    var turns_played := 0
    while turns_played < 5 and target.hp == target.max_hp:
        await _enemy_turn()
        turns_played += 1
    ok(target.hp < target.max_hp, "it went after it and shot it (%d turns)" % turns_played)
    ok(speeder.tile != home, "it left its post")
    eq(ai.get_mode(speeder), FieldAI.Mode.ALERT, "and is alert")
    _clear()


# The enemy is gone: it looks where it was, calms down and goes back to its post
func _test_calming_down() -> void:
    var tank := _spawn("enemy", "tank", _at(3, 4), "E")
    var target := _spawn("player", "buggy", _at(9, 4), "W")
    var calmed := []
    var on_calm := func(unit: Soldier) -> void: calmed.append(unit)
    ai.calmed.connect(on_calm)
    await _enemy_turn()
    eq(ai.get_mode(tank), FieldAI.Mode.ALERT, "alert")
    units.remove_soldier(target)
    var number := 0
    while ai.is_alert(tank) and number < 15:
        await _enemy_turn()
        number += 1
    eq(ai.get_mode(tank), FieldAI.Mode.NORMAL, "it calms down when the enemy is gone (%d turns)" % number)
    eq(calmed, [tank], "and says so")
    await _enemy_turns(2)
    eq(tank.tile, _at(3, 4), "it is at its post")
    ai.calmed.disconnect(on_calm)
    _clear()


# A unit that is shot by somebody it does not see is alert too
func _test_shot_from_afar() -> void:
    var tank := _spawn("enemy", "tank", _at(3, 4), "E")
    var gun := _spawn("player", "artillery", _at(3, 7), "N") # behind its side: out of the view of the tank
    ok(not ai.get_visible_enemies(tank).has(gun), "the tank does not see the artillery")
    eq(ai.get_mode(tank), FieldAI.Mode.NORMAL, "calm")
    units.shot_resolved.emit(gun, tank, 100, 0)
    eq(ai.get_mode(tank), FieldAI.Mode.ALERT, "being shot makes it alert")
    # it goes to look where the shot came from, if that is not too far from its post
    var home := tank.tile
    await _enemy_turn()
    ok(tank.tile != home, "and goes to see where it came from (%s)" % tank.tile)
    _clear()


# With the AI off the enemy's turn passes by itself, as before
func _test_ai_off() -> void:
    await _new_scene(false)
    ok(turns.auto_pass_computer_turns, "with the AI off the enemy's turn passes by itself")
    await _new_scene(true)
    ok(not turns.auto_pass_computer_turns, "with the AI on it ends its turn itself")
    eq(scene.field_ai.team, Soldier.TEAM_ENEMY, "the AI plays the enemy")
