extends Node
# Headless test of CombatScene3: a square (and an isometric) map with two trains, deploying and
# boarding soldiers, 8 direction movement, and the AIs (CombatAI, TrainAI, UnitAI) in turn based
# and real time combat.
# It is a scene (not a -s script) because the scenes it tests use autoloads, which only exist
# when the project runs a scene.
# Run from the project folder:  godot --headless --path . res://tests/combat_scene3_test_run.tscn

const PLAYER := Soldier.TEAM_PLAYER
const ENEMY := Soldier.TEAM_ENEMY

var _failed := 0
var _checks := 0
var scene: CombatScene3


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


# A fresh scene. `rts`: real time instead of turn based. `ai`: the enemy AI plays. `iso`: the same
# map drawn with the isometric tile sets.
func _new_scene(rts: bool, ai: bool, iso := false) -> void:
    if scene != null:
        scene.queue_free()
        await get_tree().process_frame
        await get_tree().process_frame
    var s: CombatScene3 = load("res://scenes/core/combat_scene3.tscn").instantiate()
    var managers := s.get_node("Managers")
    if rts:
        var turn_manager := managers.get_node("TurnManager")
        managers.remove_child(turn_manager)
        turn_manager.free()
        var rts_manager := RtsManager.new()
        rts_manager.name = "RtsManager"
        managers.add_child(rts_manager)
    else:
        (managers.get_node("TurnManager") as TurnManager).auto_pass_computer_turns = not ai
    s.get_node("AI/CombatAI").enabled = ai
    if iso:
        _make_iso(s)
    get_tree().root.add_child(s)
    await get_tree().process_frame
    await get_tree().process_frame
    scene = s

# The painted cells of the square map, with the isometric tile sets (the tiles are in the same order)
func _make_iso(s: Node) -> void:
    var sets := {"Ground": "combat_ground", "Objects": "combat_objects", "Spawns": "combat_spawns",
            "Fog": "combat_fog", "WallsX": "combat_walls_se", "WallsY": "combat_walls_sw"}
    for layer_name: String in sets:
        (s.get_node("CombatMap/" + layer_name) as TileMapLayer).tile_set = load("res://assets/combat/%s.tres" % sets[layer_name])

func _speed(value: float) -> void:
    (scene.flow_manager as RtsManager).game_speed = value


# QuestManager asks the running scene for this (a test is the scene here): no quests are loaded
func skips_quests_when_debugging() -> bool:
    return true


func _run() -> void:
    await _test_quests_skipped()
    await _test_loading()
    await _test_deploy_and_move()
    await _test_boarding()
    await _test_turn_rules()
    await _test_outcome()
    await _test_train_ai()
    await _test_unit_ai()
    await _test_combat_ai_rts()
    await _test_combat_ai_turns()
    await _test_retreat_and_flee()
    await _test_isometric()
    await _test_overlays()
    await _test_modes_and_errors()
    print("%d checks, %d failed" % [_checks, _failed])
    print("ALL PASSED" if _failed == 0 else "FAILED")
    get_tree().quit(1 if _failed > 0 else 0)


func _deploy_all(team: String) -> void:
    for id in scene.deployment_manager.get_aboard(team):
        scene.deployment_manager.deploy(team, id)

func _field(team: String) -> Array[Soldier]:
    return scene.deployment_manager.get_field_soldiers(team)

# Is the soldier with this id on the battlefield? (Asked by id: a soldier that boarded is freed)
func _on_field(unit_id: String) -> bool:
    return scene.battle_unit_manager.soldiers.any(func(s: Soldier) -> bool: return s.unit_id == unit_id)

# True when the soldier with this id stands idle, or is not on the battlefield any more
func _idle_or_gone(unit_id: String) -> bool:
    for s in scene.battle_unit_manager.soldiers:
        if s.unit_id == unit_id:
            return s.get_action() == &"idle"
    return true

func _mean_row(soldiers: Array[Soldier]) -> float:
    var total := 0.0
    for s in soldiers:
        total += s.tile.y
    return total / maxf(soldiers.size(), 1)


func _test_loading() -> void:
    await _new_scene(false, false)
    var g := scene.grid_service
    eq(g.projection, GridService.TileProjection.CARTESIAN, "the map is square")
    eq(g.tile_size, Vector2i(64, 64), "square tiles")
    eq(g.map_rect, Rect2i(0, 0, 24, 12), "map rect")
    eq(g.tile_center_offset, Vector2(32, 32), "origin offset of a square map")
    for tile in [Vector2i(0, 0), Vector2i(5, 3), Vector2i(23, 11), Vector2i(9, 7)]:
        eq(g.tile_to_world(Vector2(tile)), scene.combat_map.ground.map_to_local(tile), "tile %s is where the map draws it" % tile)
        eq(g.world_to_tile(scene.combat_map.ground.map_to_local(tile)), tile, "and back")
    eq(scene.terrain_service.get_type(Vector2i(3, 3)), "forest", "forest")
    eq(scene.terrain_service.get_type(Vector2i(10, 8)), "deep_water", "deep water")
    eq(scene.terrain_service.get_type(Vector2i(0, 5)), "road", "road")
    eq(scene.edge_service.get_edge_count(), 20, "edges read from the wall layers")
    eq(scene.edge_service.get_edge(Vector2i(15, 4), Vector2i(15, 5)).type, "door", "south door of the building")
    eq(scene.edge_service.get_edge(Vector2i(12, 3), Vector2i(13, 3)).type, "door", "west door of the building")
    eq(scene.edge_service.get_edge(Vector2i(7, 8), Vector2i(8, 8)).type, "fence", "fence")
    eq(scene.combat_map_manager.objects.size(), 10, "objects registered")
    eq(scene.battle_unit_manager.soldiers.size(), 0, "nobody is on the battlefield at the start")
    eq(scene.deployment_manager.get_aboard(PLAYER).size(), 5, "five soldiers in the player's barracks")
    eq(scene.deployment_manager.get_aboard(ENEMY).size(), 5, "five soldiers in the enemy's barracks")
    eq(scene.player_train.wagons.size(), 2, "player train: locomotive and barracks")
    eq(scene.enemy_train.wagons.size(), 2, "enemy train: locomotive and barracks")
    ok(scene.player_train.global_position.y > g.get_world_bounds().end.y, "the player's train is below the map")
    ok(scene.enemy_train.global_position.y < g.get_world_bounds().position.y, "the enemy's train is above the map")
    ok(scene.deployment_manager.get_barracks(PLAYER) is BarracksWagon, "the barracks wagon is known")
    eq(scene.deployment_manager.get_capacity(PLAYER), 5, "barracks capacity")
    var player_door := scene.deployment_manager.get_door_tile(PLAYER)
    var enemy_door := scene.deployment_manager.get_door_tile(ENEMY)
    eq(player_door, Vector2i(5, 11), "the player's door is in front of its barracks, bottom row")
    eq(enemy_door, Vector2i(15, 0), "the enemy's door is in front of its barracks, top row")
    eq(scene.deployment_manager.get_entry_facing(PLAYER), "N", "player soldiers face the map")
    eq(scene.deployment_manager.get_entry_facing(ENEMY), "S", "enemy soldiers face the map")
    ok(scene.flow_manager is TurnManager, "turn based by default")
    ok(scene.barracks_menu.get_child_count() == BarracksMenu.SLOT_COUNT, "barracks menu has its slots")
    ok(not scene.outcome_label.visible, "no outcome yet")
    eq(scene.outcome, "", "battle goes on")
    ok(scene.camera_service.world_bounds.has_point(scene.player_train.global_position), "the camera can see the player's train")
    ok(scene.camera_service.world_bounds.has_point(scene.enemy_train.global_position), "the camera can see the enemy's train")


func _test_deploy_and_move() -> void:
    await _new_scene(false, false)
    var dm := scene.deployment_manager
    ok(scene.barracks_menu._unit_ids[0] != "", "the menu shows the soldiers aboard")
    scene._on_menu_unit_clicked("p_u0")
    var first := scene.battle_unit_manager.soldiers[0]
    eq(first.team, PLAYER, "deployed soldier is the player's")
    eq(first.unit_id, "p_u0", "keeps its id")
    eq(first.tile, Vector2i(5, 11), "gets off at the door")
    eq(first.facing, "N", "faces the map")
    eq(scene.battle_unit_manager.selected, first, "the new soldier is selected")
    eq(dm.get_aboard(PLAYER).size(), 4, "one less aboard")
    ok(not scene.barracks_menu._unit_ids.has("p_u0"), "the menu forgot it")
    ok(scene.occupancy_service.get_anchor(first) == first.tile, "occupancy has it")
    ok(first.sprite.animation == &"N", "square map: the sprite faces north")
    # 8 directions
    var soldier := first
    var start := soldier.tile
    var target := start + Vector2i(-3, -3)
    ok(scene.terrain_service.is_walkable(target), "target is walkable")
    var path := scene.pathfinding_service.find_path(start, target, scene.battle_unit_manager.get_profile(soldier))
    eq(path.size(), 4, "a diagonal of 3 steps takes 3 steps, not 6")
    var all_diagonal := true
    for i in range(1, path.size()):
        var d := path[i] - path[i - 1]
        all_diagonal = all_diagonal and d.x != 0 and d.y != 0
    ok(all_diagonal, "every step is diagonal")
    ok(scene.battle_unit_manager.command_move(soldier, target), "move order accepted")
    ok(await wait_until(func() -> bool: return soldier.tile == target and soldier.get_action() == &"idle"), "arrives")
    ok(soldier.position.is_equal_approx(scene.grid_service.tile_to_world(Vector2(target))), "stands on the tile")
    eq(soldier.facing, "NW", "faces north-west after going that way")
    ok(soldier.sprite.animation == &"NW", "its sprite faces north-west")
    eq(scene.occupancy_service.get_anchor(soldier), target, "occupancy follows")
    for id in dm.get_aboard(PLAYER):
        dm.deploy(PLAYER, id)
    eq(_field(PLAYER).size(), 5, "all five deployed")
    var tiles := {}
    for s in _field(PLAYER):
        ok(s.tile.y >= 10 or s == first, "%s is in the entry zone" % s.unit_id)
        tiles[s.tile] = true
    eq(tiles.size(), 5, "all on different tiles")
    eq(dm.get_aboard(PLAYER).size(), 0, "barracks empty")
    ok(dm.deploy_next(PLAYER) == null, "nothing more to deploy")
    ok(scene.barracks_menu._unit_ids.all(func(id: String) -> bool: return id == ""), "menu empty")
    ok(not dm.can_deploy(PLAYER, "p_u0"), "an unknown or deployed unit can't be deployed")
    # all 8 headings give a different sprite direction
    var seen := {}
    for ori in GridService.ORIENTATIONS:
        seen[scene.grid_service.orientation_to_screen_direction(ori)] = true
    eq(seen.size(), 8, "8 orientations, 8 sprite directions")
    eq(scene.grid_service.orientation_to_screen_direction("NE"), "NE", "on a square map NE is up-right on screen")
    # a wall blocks a diagonal squeeze: the building's corner (north-west corner of tile (13,2))
    var corner := scene.edge_service
    ok(not scene.pathfinding_service.can_step(Vector2i(12, 1), Vector2i(13, 2), scene.battle_unit_manager.get_profile(soldier)),
            "can't cut the corner of a wall")
    ok(corner.get_edge_count() > 0, "edges exist")


func _test_boarding() -> void:
    await _new_scene(false, false)
    var dm := scene.deployment_manager
    var soldier := dm.deploy(PLAYER, "p_u1")
    eq(soldier.hp, 100, "full hp")
    soldier.take_damage(30)
    ok(not dm.board(soldier) == false, "a soldier at the door boards")
    ok(not scene.battle_unit_manager.soldiers.has(soldier), "it left the battle")
    ok(not scene.occupancy_service.has_entity(soldier) or not is_instance_valid(soldier), "and the occupancy")
    ok(dm.get_aboard(PLAYER).has("p_u1"), "it is aboard again")
    eq(dm.get_unit_data(PLAYER, "p_u1")["hp"], 70, "with its wounds")
    ok(scene.barracks_menu._unit_ids.has("p_u1"), "the menu shows it again")
    var again := dm.deploy(PLAYER, "p_u1")
    eq(again.hp, 70, "it comes out as wounded as it went in")
    # walking back
    var far := dm.deploy(PLAYER, "p_u2")
    ok(scene.battle_unit_manager.command_move(far, Vector2i(5, 8)), "walks away")
    ok(await wait_until(func() -> bool: return far.tile == Vector2i(5, 8) and far.get_action() == &"idle"), "arrived")
    ok(not dm.is_at_door(far), "away from the door")
    ok(not dm.board(far), "can't board from far away")
    scene.battle_unit_manager.select(far)
    scene._on_board_pressed()
    ok(await wait_until(func() -> bool: return not _on_field("p_u2")), "walks to the door and boards")
    ok(dm.get_aboard(PLAYER).has("p_u2"), "aboard")
    eq(scene.battle_unit_manager.selected, null, "nothing is selected any more")
    # no room
    for id in dm.get_aboard(PLAYER).duplicate():
        dm.deploy(PLAYER, id)
    var a := _field(PLAYER)[0]
    var capacity_before := dm.get_aboard(PLAYER).size()
    dm.get_barracks(PLAYER).max_cargo_amount = 0
    ok(not dm.order_board(a), "a full barracks takes nobody")
    dm.get_barracks(PLAYER).max_cargo_amount = 5
    eq(dm.get_aboard(PLAYER).size(), capacity_before, "nothing changed")
    # the entry zone
    dm.entry_depth = 0
    eq(dm.get_deploy_tile(PLAYER), DeploymentManager.NO_TILE, "no entry zone, no tile")
    dm.entry_depth = 2
    # a dead soldier can't board
    var dead := _field(PLAYER)[1]
    dead.take_damage(999)
    ok(not dm.board(dead), "a dead soldier doesn't board")
    ok(not dm.order_board(dead), "and isn't ordered to")


func _test_turn_rules() -> void:
    await _new_scene(false, false)
    var tm := scene.flow_manager as TurnManager
    var dm := scene.deployment_manager
    eq(tm.current_team, PLAYER, "the player starts")
    ok(dm.can_deploy(PLAYER, "p_u0"), "the player can deploy on its turn")
    ok(not dm.can_deploy(ENEMY, "e_u0"), "the enemy can't during the player's turn")
    var soldier := dm.deploy(PLAYER, "p_u0")
    eq(soldier.action_points, soldier.max_action_points, "a soldier deployed on its turn can act")
    ok(not dm.deploy(ENEMY, "e_u0"), "enemy deploy refused out of turn")
    tm.end_turn()
    ok(await wait_until(func() -> bool: return tm.current_team == ENEMY), "enemy turn")
    ok(not dm.can_deploy(PLAYER, "p_u1"), "the player can't deploy on the enemy's turn")
    ok(dm.can_deploy(ENEMY, "e_u0"), "the enemy can")
    ok(await wait_until(func() -> bool: return tm.current_team == PLAYER, 5.0), "with no AI the computer turn passes by itself")
    # an AI plays the computer turns when it is on: the turn does not pass by itself
    await _new_scene(false, true)
    tm = scene.flow_manager as TurnManager
    ok(not tm.auto_pass_computer_turns, "with an AI the turns don't pass by themselves")


func _test_outcome() -> void:
    await _new_scene(true, false)
    var dm := scene.deployment_manager
    _deploy_all(ENEMY)
    _deploy_all(PLAYER)
    eq(_field(ENEMY).size(), 5, "enemies out")
    var results := []
    scene.battle_finished.connect(func(r: String) -> void: results.append(r))
    for s in _field(ENEMY):
        s.take_damage(999)
    eq(scene.outcome, "victory", "all enemies dead: victory")
    ok(scene.outcome_label.visible and scene.outcome_label.text.begins_with("VICTORY"), "the label says so")
    ok(scene.flow_manager.battle_over, "the flow manager knows")
    eq(results, ["victory"], "signal once")
    var p := _field(PLAYER)[0]
    ok(not scene.flow_manager.can_command(p), "nobody can be commanded now")
    ok(not scene.battle_unit_manager.command_move(p, p.tile + Vector2i(0, -1)), "orders are refused")
    ok(not scene.flow_manager.can_team_act(PLAYER), "and no one deploys")
    ok(scene.flow_manager.get_status_text().contains("battle over"), "status text says the battle is over")
    # defeat: the player loses everybody (one aboard counts as alive)
    await _new_scene(true, false)
    dm = scene.deployment_manager
    _deploy_all(PLAYER)
    var field := _field(PLAYER)
    for i in field.size() - 1:
        field[i].take_damage(999)
    eq(scene.outcome, "", "one soldier left: the battle goes on")
    field[4].take_damage(999)
    eq(scene.outcome, "defeat", "nobody left: defeat")
    ok(scene.outcome_label.text.begins_with("DEFEAT"), "label")
    # soldiers aboard keep a team alive
    await _new_scene(true, false)
    _deploy_all(PLAYER)
    var all := _field(PLAYER)
    var door_soldier: Soldier = null
    for s in all:
        if scene.deployment_manager.is_at_door(s):
            door_soldier = s
            break
    ok(door_soldier != null, "somebody stands at the door")
    for s in all:
        if s != door_soldier:
            s.take_damage(999)
    ok(scene.deployment_manager.board(door_soldier), "the last one boards")
    eq(scene.outcome, "", "aboard is not dead: the battle goes on")
    ok(not scene.deployment_manager.is_team_defeated(PLAYER), "not defeated")


func _test_train_ai() -> void:
    await _new_scene(true, false)
    var dm := scene.deployment_manager
    var ai := scene.combat_ai
    var train_ai := ai.train_ai
    eq(train_ai.team, ENEMY, "train AI plays the enemy")
    train_ai.deploy_interval = 0.0
    train_ai.set_orders(2, false, false)
    ok(train_ai.is_busy(), "wants to deploy: busy")
    eq(train_ai.think(), 1, "deploys one")
    eq(train_ai.think(), 1, "and another")
    eq(train_ai.think(), 0, "and stops at two")
    eq(_field(ENEMY).size(), 2, "two enemies out")
    ok(not train_ai.is_busy(), "done")
    for s in _field(ENEMY):
        ok(s.tile.y <= 1, "enemy soldiers get off at the top")
        eq(s.facing, "S", "facing the map")
    train_ai.set_orders(5, false, false)
    for i in 5:
        train_ai.think()
    eq(_field(ENEMY).size(), 5, "up to what is wanted")
    eq(dm.get_aboard(ENEMY).size(), 0, "barracks empty")
    # recall
    train_ai.set_orders(0, true, true)
    ok(not train_ai.is_busy(), "recalling is not waiting")
    train_ai.think()
    ok(await wait_until(func() -> bool: return _field(ENEMY).is_empty()), "everybody is back aboard")
    eq(dm.get_aboard(ENEMY).size(), 5, "five aboard")
    ok(not train_ai.is_departing, "the train waits until nobody is outside")
    var x_before := scene.enemy_train.position.x
    train_ai.think()
    ok(train_ai.is_departing, "all aboard: the train leaves")
    ok(train_ai.is_busy(), "busy leaving")
    var departed := []
    train_ai.departed.connect(func() -> void: departed.append(true))
    ok(await wait_until(func() -> bool: return train_ai.has_departed, 15.0), "the train drives away")
    ok(scene.enemy_train.position.x > x_before, "to the right")
    eq(departed.size(), 1, "reports once")
    eq(train_ai.think(), 0, "nothing more to do")
    ok(await wait_until(func() -> bool: return scene.outcome == "victory", 2.0), "a fled train is a victory for the other side")
    ok(scene.outcome_label.text.contains("fled"), "label says it fled")


func _test_unit_ai() -> void:
    await _new_scene(true, false)
    var dm := scene.deployment_manager
    var unit_ai := scene.combat_ai.unit_ai
    var bum := scene.battle_unit_manager
    var enemy := dm.deploy(ENEMY, "e_u0")
    var mine := dm.deploy(PLAYER, "p_u0")
    # move the soldiers: the enemy near the middle, the player's soldier far away
    scene.occupancy_service.move(enemy, Vector2i(5, 5)); enemy.place_at(Vector2i(5, 5), "S")
    scene.occupancy_service.move(mine, Vector2i(5, 10)); mine.place_at(Vector2i(5, 10), "N")
    scene.fog_manager.update_viewer(enemy)
    scene.fog_manager.update_viewer(mine)
    # the enemy faces south and sees the player's soldier 5 tiles away
    ok(unit_ai.get_visible_enemies(enemy).has(mine), "the AI sees what its soldiers see")
    var hidden := dm.deploy(PLAYER, "p_u1")
    scene.occupancy_service.move(hidden, Vector2i(20, 10)); hidden.place_at(Vector2i(20, 10), "N")
    scene.fog_manager.update_viewer(hidden)
    ok(not unit_ai.get_visible_enemies(enemy).has(hidden), "and not what they don't")
    unit_ai.set_orders(UnitAI.Stance.ATTACK, Vector2i(5, 11), Vector2i(15, 0))
    eq(unit_ai.pick_target(enemy, unit_ai.get_visible_enemies(enemy)), mine, "target")
    var orders := unit_ai.think()
    eq(orders, 1, "one soldier, one order")
    ok(enemy.get_action() != &"idle", "it attacks")
    ok(await wait_until(func() -> bool: return mine.hp < mine.max_hp or enemy.hp < enemy.max_hp), "shots are exchanged")
    # wounded: runs for the train
    var wounded := dm.deploy(ENEMY, "e_u1")
    wounded.take_damage(80)
    unit_ai.set_orders(UnitAI.Stance.ATTACK, Vector2i(5, 11), Vector2i(15, 0))
    # defend: a soldier far from home walks back
    var defender := dm.deploy(ENEMY, "e_u2")
    scene.occupancy_service.move(defender, Vector2i(20, 8)); defender.place_at(Vector2i(20, 8), "E")
    unit_ai.set_orders(UnitAI.Stance.DEFEND, Vector2i(5, 11), Vector2i(15, 0))
    enemy.take_damage(999)
    wounded.take_damage(999)
    mine.take_damage(999) # nobody is left to fight: the defender only goes home
    hidden.take_damage(999)
    scene.fog_manager.update_viewer(defender)
    eq(unit_ai.think(), 1, "the defender goes home")
    for i in 6: # a few tiles at a time
        await wait_until(func() -> bool: return defender.get_action() == &"idle", 3.0)
        unit_ai.think()
    await wait_until(func() -> bool: return defender.get_action() == &"idle", 3.0)
    ok(Vector2(defender.tile).distance_to(Vector2(15, 0)) <= unit_ai.defend_radius + 0.01, "and holds there")
    eq(unit_ai.think(), 0, "a defender at home with nobody around does nothing")
    # attack with nothing in sight: advance to the objective
    unit_ai.set_orders(UnitAI.Stance.ATTACK, Vector2i(5, 10), Vector2i(15, 0))
    var y_before := defender.tile.y
    eq(unit_ai.think(), 1, "an attacker advances")
    ok(await wait_until(func() -> bool: return defender.get_action() == &"idle" and defender.tile.y > y_before), "closer to the objective")
    ok(defender.tile.y - y_before <= unit_ai.advance_steps, "no more than advance_steps at once")
    # retreat
    unit_ai.set_orders(UnitAI.Stance.RETREAT, Vector2i(5, 10), Vector2i(15, 0))
    eq(unit_ai.think(), 1, "a retreating soldier walks to the train")
    for i in 8:
        await wait_until(func() -> bool: return _idle_or_gone("e_u2"), 4.0)
        if not _on_field("e_u2"):
            break
        unit_ai.think()
    ok(not _on_field("e_u2"), "and boards")
    ok(dm.get_aboard(ENEMY).has("e_u2"), "it is aboard")


func _test_combat_ai_rts() -> void:
    await _new_scene(true, true)
    _speed(4.0)
    var ai := scene.combat_ai
    var dm := scene.deployment_manager
    ok(await wait_until(func() -> bool: return not _field(ENEMY).is_empty(), 6.0), "the AI starts deploying")
    var counts := {}
    ok(await wait_until(func() -> bool:
            counts[_field(ENEMY).size()] = true
            return _field(ENEMY).size() == 5, 10.0), "and ends up with all five out")
    ok(counts.size() >= 2, "they got off one by one")
    eq(ai.stance, UnitAI.Stance.ATTACK, "equal forces: it attacks")
    ok(ai.get_status_text().contains("ATTACK"), "the HUD text says so")
    ok(scene.ai_label.text.contains("ATTACK") or scene.ai_label.text.begins_with("AI"), "the label shows the AI")
    var row_before := _mean_row(_field(ENEMY))
    ok(await wait_until(func() -> bool: return _mean_row(_field(ENEMY)) > row_before + 3.0, 15.0), "the enemy advances towards the player's train")
    # the player defends itself
    _deploy_all(PLAYER)
    ok(await wait_until(func() -> bool:
            for s in scene.battle_unit_manager.soldiers:
                if s.hp < s.max_hp:
                    return true
            return false, 30.0), "a fight starts")
    ok(await wait_until(func() -> bool: return scene.outcome != "" or _field(ENEMY).size() < 5 or _field(PLAYER).size() < 5, 40.0),
            "and somebody falls")
    ok(dm.count_alive(ENEMY) + dm.count_alive(PLAYER) >= 1, "bookkeeping")
    # the AI only gives orders the player could give: nobody acts after the battle
    scene.flow_manager.end_battle()
    var enemies_before := _field(ENEMY)
    ok(not scene.flow_manager.can_command(enemies_before[0]) if not enemies_before.is_empty() else true, "no orders after the end")
    _speed(1.0)


func _test_combat_ai_turns() -> void:
    await _new_scene(false, true)
    var tm := scene.flow_manager as TurnManager
    var ai := scene.combat_ai
    eq(tm.current_team, PLAYER, "the player's turn first")
    await get_tree().create_timer(1.0, true, false, true).timeout
    eq(_field(ENEMY).size(), 0, "the AI does nothing during the player's turn")
    tm.end_turn()
    ok(await wait_until(func() -> bool: return tm.current_team == ENEMY), "enemy turn")
    ok(await wait_until(func() -> bool: return not _field(ENEMY).is_empty(), 5.0), "the AI deploys during its turn")
    ok(await wait_until(func() -> bool: return tm.current_team == PLAYER and tm.turn_number == 2, 25.0), "and ends its turn by itself")
    var out := _field(ENEMY).size()
    ok(out >= 1, "soldiers are out")
    for s in _field(ENEMY):
        ok(s.action_points < s.max_action_points + 0.01, "AP are spent or kept, never above max")
    var moved := false
    for s in _field(ENEMY):
        if s.tile.y > 1:
            moved = true
    ok(moved, "they moved in their turn")
    var rows := _mean_row(_field(ENEMY))
    tm.end_turn()
    ok(await wait_until(func() -> bool: return tm.current_team == ENEMY and tm.turn_number == 2), "enemy turn again")
    ok(await wait_until(func() -> bool: return tm.current_team == PLAYER and tm.turn_number == 3, 25.0), "the AI plays every turn")
    ok(_mean_row(_field(ENEMY)) > rows or _field(ENEMY).size() > out, "and gets further")
    eq(ai.stance, UnitAI.Stance.ATTACK, "attacking")
    # the AI never moves a soldier out of turn
    var snapshot := {}
    for s in _field(ENEMY):
        snapshot[s] = s.tile
    await get_tree().create_timer(1.0, true, false, true).timeout
    for s: Soldier in snapshot:
        eq(s.tile, snapshot[s], "%s stays put on the player's turn" % s.unit_id)


func _test_retreat_and_flee() -> void:
    await _new_scene(true, true)
    _speed(4.0)
    var ai := scene.combat_ai
    ai.min_stance_time = 0.0
    ok(await wait_until(func() -> bool: return _field(ENEMY).size() == 5, 12.0), "enemy out")
    for s in _field(ENEMY):
        s.take_damage(s.hp - 5)
    ok(await wait_until(func() -> bool: return ai.stance == UnitAI.Stance.RETREAT, 4.0), "badly hurt: it retreats")
    ok(ai.fleeing, "and it will not come back")
    ok(ai.strength_ratio < ai.retreat_ratio, "because the forces are very unequal")
    ok(await wait_until(func() -> bool: return _field(ENEMY).is_empty(), 25.0), "all soldiers go back to the train")
    eq(scene.deployment_manager.get_aboard(ENEMY).size(), 5, "all five aboard")
    for id in scene.deployment_manager.get_aboard(ENEMY):
        ok(scene.deployment_manager.get_unit_data(ENEMY, id)["hp"] <= 5, "%s keeps its wounds" % id)
    ok(await wait_until(func() -> bool: return scene.combat_ai.train_ai.has_departed, 20.0), "the train leaves")
    ok(await wait_until(func() -> bool: return scene.outcome == "victory", 3.0), "which wins the battle")
    ok(not ai.enabled, "the AI is off at the end")
    _speed(1.0)


func _test_isometric() -> void:
    await _new_scene(true, true, true)
    _speed(4.0)
    eq(scene.grid_service.projection, GridService.TileProjection.ISOMETRIC, "the same scene on an isometric map")
    eq(scene.grid_service.tile_size, Vector2i(64, 32), "isometric tiles")
    for tile in [Vector2i(0, 0), Vector2i(5, 3), Vector2i(23, 11)]:
        eq(scene.grid_service.tile_to_world(Vector2(tile)), scene.combat_map.ground.map_to_local(tile), "tile %s" % tile)
    var dm := scene.deployment_manager
    var player_door := dm.get_door_tile(PLAYER)
    var enemy_door := dm.get_door_tile(ENEMY)
    eq(player_door.y, 11, "the player's door is on the bottom row of tiles")
    eq(enemy_door.y, 0, "the enemy's on the top row")
    var best := INF
    var wagon_position := scene.combat_map.to_local(dm.get_barracks(PLAYER).global_position)
    for x in 24:
        best = minf(best, scene.grid_service.tile_to_world(Vector2(x, 11)).distance_to(wagon_position))
    eq(scene.grid_service.tile_to_world(Vector2(player_door)).distance_to(wagon_position), best, "the door is the edge tile nearest to the wagon")
    var soldier := dm.deploy(PLAYER, "p_u0")
    ok(soldier != null and soldier.tile.y >= 10, "a soldier gets off on an isometric map")
    var target := soldier.tile + Vector2i(-2, -2)
    var path := scene.pathfinding_service.find_path(soldier.tile, target, scene.battle_unit_manager.get_profile(soldier))
    eq(path.size(), 3, "8 directions on an isometric map too")
    ok(scene.battle_unit_manager.command_move(soldier, target), "order")
    ok(await wait_until(func() -> bool: return soldier.tile == target and soldier.get_action() == &"idle"), "arrives")
    ok(soldier.position.is_equal_approx(scene.grid_service.tile_to_world(Vector2(target))), "on its tile")
    ok(dm.order_board(soldier), "goes back")
    ok(await wait_until(func() -> bool: return not _on_field("p_u0")), "and boards")
    # the AI plays there too
    ok(await wait_until(func() -> bool: return _field(ENEMY).size() == 5, 12.0), "the AI deploys")
    var row := _mean_row(_field(ENEMY))
    ok(await wait_until(func() -> bool: return _mean_row(_field(ENEMY)) > row + 3.0, 15.0), "and advances")
    _speed(1.0)


func _test_modes_and_errors() -> void:
    # real time without the AI: the enemy stays aboard
    await _new_scene(true, false)
    ok(scene.flow_manager is RtsManager, "real time")
    await get_tree().create_timer(1.0, true, false, true).timeout
    eq(_field(ENEMY).size(), 0, "no AI: the enemy stays in its train")
    ok(scene.end_turn_button.visible == false and scene.pause_button.visible, "real time HUD")
    ok(scene.deployment_manager.deploy("nobody", "x") == null, "an unknown team can't deploy")
    ok(scene.deployment_manager.get_aboard("nobody").is_empty(), "and has nobody aboard")


func _test_quests_skipped() -> void:
    # The first frames of the game: a debug scene must not get a quest dialog that pauses it
    for i in 5:
        await get_tree().process_frame
    ok(not get_tree().paused, "the game is not paused by a quest dialog")
    ok(QuestManager.active_quests.is_empty() and QuestManager.offered_quests.is_empty(), "no quest was loaded or offered")


func _test_overlays() -> void:
    await _new_scene(false, false)
    var g := scene.grid_service
    ok(scene.vision_overlay is VisionOverlay and scene.nav_graph_overlay is NavGraphOverlay, "both overlays are in the scene")
    ok(not scene.vision_overlay.visible and not scene.nav_graph_overlay.visible, "hidden until asked for")
    scene.sight_button.pressed.emit()
    scene.graph_button.pressed.emit()
    ok(scene.vision_overlay.visible and scene.nav_graph_overlay.visible, "the buttons show them")
    scene.sight_button.pressed.emit()
    ok(not scene.vision_overlay.visible, "and hide them")
    scene.sight_button.pressed.emit()

    # --- the navigation graph
    var graph := scene.nav_graph_overlay
    var ps := scene.pathfinding_service
    var profile := MoveProfile.new()
    profile.blocked_by = TileOccupancyService.LAYER_STRUCTURE | TileOccupancyService.LAYER_OBSTACLE
    var inconsistent := 0
    var asymmetric := 0
    var nodes := 0
    for y in 12:
        for x in 24:
            var a := Vector2i(x, y)
            if not graph.get_connections(a).is_empty():
                nodes += 1
            for offset in GridService.NEIGHBORS_8:
                var b := a + offset
                var reason := ps.get_step_block_reason(a, b, profile)
                if ps.can_step(a, b, profile) != (reason == ""):
                    inconsistent += 1
                if g.is_inside_map(b) and graph._is_node(a) and graph._is_node(b) \
                        and ps.can_step(a, b, profile) != ps.can_step(b, a, profile):
                    asymmetric += 1
    eq(inconsistent, 0, "get_step_block_reason agrees with can_step on every step of the map")
    eq(asymmetric, 0, "the graph is symmetric: if A connects to B, B connects to A")
    ok(nodes > 200, "most tiles are nodes")
    eq(graph.get_connections(Vector2i(19, 1)).size(), 8, "an open tile connects to its 8 neighbors")
    eq(graph.get_connections(Vector2i(0, 0)).size(), 3, "a corner of the map has 3")
    ok(graph.get_connections(Vector2i(10, 8)).is_empty(), "deep water is not a node")
    ok(not graph.get_connections(Vector2i(5, 8)).has(Vector2i(6, 8)), "nobody connects to a rock")
    ok(graph.get_connections(Vector2i(14, 3)).is_empty(), "a tile with a crate is not a node")
    ok(not graph.get_connections(Vector2i(14, 2)).has(Vector2i(14, 3)), "and nobody connects to it")
    eq(graph.get_missing_reason(Vector2i(13, 2), Vector2i(13, 1)), "wall", "a wall of the building cuts the connection")
    ok(not graph.get_connections(Vector2i(13, 2)).has(Vector2i(13, 1)), "so it is not in the graph")
    eq(graph.get_missing_reason(Vector2i(14, 1), Vector2i(14, 2)), "wall", "a window can't be walked through")
    eq(graph.get_missing_reason(Vector2i(7, 8), Vector2i(8, 8)), "wall", "nor a fence")
    eq(graph.get_missing_reason(Vector2i(15, 5), Vector2i(15, 4)), "wall", "a closed door is a wall")
    eq(graph.get_missing_reason(Vector2i(12, 1), Vector2i(13, 2)), "wall", "a diagonal across the wall's corner is cut (wall)")
    eq(graph.get_missing_reason(Vector2i(9, 5), Vector2i(10, 4)), "", "ground next to a rock is fine")
    eq(graph.get_missing_reason(Vector2i(9, 4), Vector2i(8, 3)), "tile", "a rock is not a tile to enter")
    eq(graph.get_missing_reason(Vector2i(9, 2), Vector2i(8, 3)), "tile", "(the rock again, from the other side)")
    eq(graph.get_missing_reason(Vector2i(7, 4), Vector2i(8, 5)), "corner", "a diagonal past a rock cuts its corner")
    ok(not graph.get_connections(Vector2i(7, 4)).has(Vector2i(8, 5)), "and is not in the graph")
    scene.combat_map_manager.set_all_doors_open(true)
    eq(graph.get_missing_reason(Vector2i(15, 5), Vector2i(15, 4)), "", "an open door joins the nodes")
    ok(graph.get_connections(Vector2i(15, 4)).has(Vector2i(15, 5)), "and appears in the graph")
    # soldiers are not part of the map's graph
    var soldier := scene.deployment_manager.deploy(PLAYER, "p_u0")
    ok(graph.get_connections(Vector2i(4, 10)).has(Vector2i(5, 11)), "a soldier standing on a tile doesn't remove it from the graph")
    # the edge costs
    ok(ps.step_cost(Vector2i(0, 0), Vector2i(1, 1), profile) > ps.step_cost(Vector2i(0, 0), Vector2i(1, 0), profile), "diagonals cost more")

    # --- the sight lines
    var vision := scene.vision_service
    eq(vision.get_line_block_index(Vector2i(5, 5), Vector2i(5, 5)), -1, "a tile sees itself")
    eq(vision.get_line_block_index(Vector2i(8, 0), Vector2i(8, 2)), -1, "open ground: the whole line is seen")
    eq(vision.get_line_block_index(Vector2i(8, 0), Vector2i(8, 3)), -1, "the rock itself is seen")
    eq(vision.get_line_block_index(Vector2i(8, 0), Vector2i(8, 5)), 4, "the line is cut right behind the rock")
    eq(vision.get_line_block_index(Vector2i(13, 0), Vector2i(13, 3)), 2, "a wall cuts the line where it is crossed")
    eq(vision.get_line_block_index(Vector2i(14, 0), Vector2i(14, 3)), -1, "a window lets the sight through")
    scene.combat_map_manager.set_all_doors_open(false)
    eq(vision.get_line_block_index(Vector2i(15, 6), Vector2i(15, 3)), 2, "a closed door hides the room")
    scene.combat_map_manager.set_all_doors_open(true)
    eq(vision.get_line_block_index(Vector2i(15, 6), Vector2i(15, 3)), -1, "an open door doesn't")
    var mismatches := 0
    for y in 12:
        for x in 24:
            var target := Vector2i(x, y)
            if vision.has_line_of_sight(Vector2i(5, 5), target) != (vision.get_line_block_index(Vector2i(5, 5), target) == -1):
                mismatches += 1
            if vision.get_line_block_index(Vector2i(5, 5), target) >= vision.get_line(Vector2i(5, 5), target).size():
                mismatches += 1
    eq(mismatches, 0, "the block index agrees with has_line_of_sight and is inside the line")

    # --- drawing: the overlays draw for a selected soldier without errors, for both outlines
    scene.battle_unit_manager.select(soldier)
    scene.vision_overlay.set_probe(Vector2i(5, 6))
    await get_tree().process_frame
    await get_tree().process_frame
    ok(scene.vision_overlay.get_probe_text().begins_with("line of sight"), "the probe says what the line does")
    # the trace: a straight run of tiles, and what cut it
    var t := vision.trace_line_of_sight(Vector2i(13, 0), Vector2i(13, 3))
    eq(t["line"], [Vector2i(13, 0), Vector2i(13, 1), Vector2i(13, 2), Vector2i(13, 3)] as Array[Vector2i], "the Bresenham line is the column of tiles")
    eq(t["cause"], "edge", "a wall cuts it")
    eq([t["crossed_from"], t["crossed_to"]], [Vector2i(13, 1), Vector2i(13, 2)], "at the border the line could not cross")
    t = vision.trace_line_of_sight(Vector2i(8, 0), Vector2i(8, 5))
    eq(t["cause"], "tile", "a rock cuts it")
    eq(t["crossed_from"], Vector2i(8, 3), "it is the rock")
    t = vision.trace_line_of_sight(Vector2i(8, 0), Vector2i(8, 2))
    eq([t["cut"], t["cause"]], [-1, ""], "open ground: clear")
    # a line that is not straight: a shallow one steps sideways now and then, and crosses what is there
    t = vision.trace_line_of_sight(Vector2i(10, 0), Vector2i(15, 2))
    eq(t["line"].size(), 6, "a shallow line has one tile per column")
    for i in range(1, t["line"].size()):
        var step: Vector2i = t["line"][i] - t["line"][i - 1]
        ok(absi(step.x) <= 1 and absi(step.y) <= 1 and step != Vector2i.ZERO, "consecutive tiles of a line are neighbors")
    scene.vision_overlay.set_probe(Vector2i(8, 5))
    ok(scene.vision_overlay.get_probe_text() != "", "the probe has a text")
    eq(g.get_tile_outline(Vector2i(2, 3)).size(), 5, "a tile outline is a closed polygon")
    ok(g.get_tile_outline(Vector2i(2, 3))[0] == g.get_tile_outline(Vector2i(2, 3))[4], "closed")
    var square := g.get_tile_outline(Vector2i(0, 0))
    eq(square[1].x - square[0].x, 64.0, "a square tile is 64 wide")
    scene.nav_graph_overlay.queue_redraw()
    await get_tree().process_frame
