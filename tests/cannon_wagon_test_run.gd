extends Node
# Headless test of the cannon wagon: a click fires a cannonball (it uses ammunition and has to
# reload), player cannonballs fly up and enemy ones down, and a hit takes the cannonball's power
# off the wagon's hp.
# It is a scene because the wagons use the WagonTypes autoload.
# Run:  godot --headless --path . res://tests/cannon_wagon_test_run.tscn

var _failed := 0
var _checks := 0

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

func wait_until(condition: Callable, timeout := 6.0) -> bool:
    var waited := 0.0
    while not condition.call() and waited < timeout:
        await seconds(0.05)
        waited += 0.05
    return condition.call()

func _run() -> void:
    await _test_standalone()
    await _test_combat_scene3()
    print("%d checks, %d failed" % [_checks, _failed])
    print("ALL PASSED" if _failed == 0 else "FAILED")
    get_tree().quit(1 if _failed > 0 else 0)


var _sv: Viewport
var _world: Node2D
var _projectiles: Node2D
var _manager: ProjectileManager
var _htm: HorizontalTrainManager

func _train_data(ammo: int) -> Dictionary:
    return {"wagons": [
        {"type": "LocomotiveWagon"},
        {"type": "CannonWagon", "cargo_name": "Ammunition", "cargo_qty": ammo},
    ]}

func _make_train(y: float, team: HorizontalTrainManager.Team, ammo: int) -> HorizontalTrain:
    var train: HorizontalTrain = load("res://scenes/trains/horizontal_train.tscn").instantiate()
    train.position = Vector2(400, y)
    _world.add_child(train)
    _htm.setup_train(train, _train_data(ammo), team)
    return train

func _click_at(at: Vector2) -> void:
    var motion := InputEventMouseMotion.new()
    motion.position = at
    motion.global_position = at
    _sv.push_input(motion, true)
    await get_tree().physics_frame
    for pressed in [true, false]:
        var event := InputEventMouseButton.new()
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = pressed
        event.position = at
        event.global_position = at
        _sv.push_input(event, true)
        await get_tree().physics_frame
    await get_tree().physics_frame


func _test_standalone() -> void:
    _sv = get_viewport()
    _sv.physics_object_picking = true
    _world = Node2D.new()
    add_child(_world)
    _projectiles = Node2D.new()
    _world.add_child(_projectiles)
    _htm = HorizontalTrainManager.new()
    add_child(_htm)
    _manager = ProjectileManager.new()
    add_child(_manager)
    _manager.projectile_container = _projectiles

    var player := _make_train(600, HorizontalTrainManager.Team.PLAYER, 3)
    var enemy := _make_train(100, HorizontalTrainManager.Team.ENEMY, 3)
    _manager.register_train(player)
    _manager.register_train(enemy)
    await get_tree().physics_frame

    var pc := player.wagons[1] as CannonWagon
    var ec := enemy.wagons[1] as CannonWagon
    ok(pc != null and ec != null, "the cannon wagons are CannonWagon")
    eq(pc.team, "player", "player cannon team")
    eq(ec.team, "enemy", "enemy cannon team")
    eq(pc.area.collision_layer, GenericWagon.LAYER_PLAYER_TRAIN, "player wagon area on the player layer")
    eq(ec.area.collision_layer, GenericWagon.LAYER_ENEMY_TRAIN, "enemy wagon area on the enemy layer")
    eq(pc.max_hp, 80, "hp comes from the wagon type")
    eq(pc.hp, 80, "starts with full hp")
    eq(pc.get_ammo(), 3, "ammunition is the wagon's cargo")
    eq(pc.get_fire_direction(), Vector2.UP, "player cannons shoot up")
    eq(ec.get_fire_direction(), Vector2.DOWN, "enemy cannons shoot down")
    pc.reload_time = 0.4
    ec.reload_time = 0.4
    pc.ball_power = 15
    ec.ball_power = 25

    # A real click on the wagon's Area2D fires
    var click_pos := pc.area.global_position
    await _click_at(click_pos)
    eq(pc.get_ammo(), 2, "a click on the cannon fires: one cannonball used")
    eq(_projectiles.get_child_count(), 1, "a cannonball exists")
    var ball := _projectiles.get_child(0) as Cannonball
    var y0 := ball.global_position.y
    await get_tree().physics_frame
    await get_tree().physics_frame
    ok(ball.global_position.y < y0, "a player cannonball flies up")
    ok(pc.get_reload_fraction() > 0.0, "the cannon is reloading")

    # While it reloads, another click does nothing
    await _click_at(click_pos)
    eq(pc.get_ammo(), 2, "no shot while reloading")

    # The ball reaches the enemy cannon
    ok(await wait_until(func() -> bool: return ec.hp < 80), "the cannonball hits the enemy wagon")
    eq(ec.hp, 65, "the hit takes the cannonball's power (15) off the hp")
    eq(pc.hp, 80, "the player's own wagon is not hurt")
    ok(await wait_until(func() -> bool: return _projectiles.get_child_count() == 0), "the cannonball is gone after the hit")

    # Reloaded: fires again. Enemy shoots down on the player's cannon
    ok(await wait_until(func() -> bool: return pc.can_fire()), "reloaded")
    ok(ec.try_fire(), "the enemy cannon fires")
    var enemy_ball := _projectiles.get_child(0) as Cannonball
    var ey := enemy_ball.global_position.y
    await get_tree().physics_frame
    await get_tree().physics_frame
    ok(enemy_ball.global_position.y > ey, "an enemy cannonball flies down")
    ok(await wait_until(func() -> bool: return pc.hp < 80), "it hits the player's wagon")
    eq(pc.hp, 55, "enemy power (25)")
    eq(ec.hp, 65, "enemy's own wagon is not hurt by its ball")

    # Out of ammunition
    ok(await wait_until(func() -> bool: return pc.can_fire()), "reloaded again")
    ok(pc.try_fire(), "second cannonball")
    ok(await wait_until(func() -> bool: return pc.can_fire()), "reloaded a third time")
    ok(pc.try_fire(), "third and last cannonball")
    eq(pc.get_ammo(), 0, "no ammunition left")
    ok(await wait_until(func() -> bool: return pc.get_reload_fraction() == 0.0), "reload finished")
    ok(not pc.try_fire(), "can't fire without ammunition")
    await _click_at(click_pos)
    eq(pc.get_ammo(), 0, "a click without ammunition fires nothing")

    # Destruction: hp can't go below 0, a wreck can't be clicked or hit
    var destroyed_count := [0]
    ec.destroyed.connect(func(_w: GenericWagon) -> void: destroyed_count[0] += 1)
    ok(ec.take_damage(1000), "a big hit")
    eq(ec.hp, 0, "hp stops at 0")
    ok(ec.is_destroyed, "destroyed")
    eq(destroyed_count[0], 1, "destroyed is emitted once")
    ok(not ec.take_damage(10), "a wreck takes no more damage")
    ok(not ec.area.input_pickable, "a wreck is not clickable")
    ok(not ec.try_fire(), "a wreck doesn't fire")
    eq(destroyed_count[0], 1, "still once")

    _world.queue_free()
    _htm.queue_free()
    _manager.queue_free()
    await get_tree().process_frame


func _test_combat_scene3() -> void:
    var scene: CombatScene3 = load("res://scenes/core/combat_scene3.tscn").instantiate()
    get_tree().root.add_child(scene)
    await get_tree().process_frame
    await get_tree().process_frame
    get_tree().paused = false
    var pm := scene.projectile_manager
    ok(pm.projectile_container == scene.projectiles, "the scene injects the projectile container")

    var pc: CannonWagon = null
    var ec: CannonWagon = null
    for w in scene.player_train.wagons:
        if w is CannonWagon:
            pc = w
    for w in scene.enemy_train.wagons:
        if w is CannonWagon:
            ec = w
    ok(pc != null and ec != null, "both debug trains have a cannon wagon")
    if pc == null or ec == null:
        scene.queue_free()
        return
    eq(ec.team, "enemy", "enemy train's wagons are enemy")
    # Line the enemy up with the player's cannon, and tap the wagon (the train reports the tap)
    scene.enemy_train.position.x = scene.player_train.position.x
    await get_tree().physics_frame
    var ammo := pc.get_ammo()
    scene.player_train.wagon_clicked.emit(pc)
    eq(pc.get_ammo(), ammo - 1, "tapping the cannon in the scene fires")
    eq(scene.projectiles.get_child_count(), 1, "the cannonball is in the scene's container")
    var hp := ec.hp
    ok(await wait_until(func() -> bool: return ec.hp < hp, 8.0), "it reaches and hurts the enemy cannon wagon")
    scene.queue_free()
    await get_tree().process_frame
    await get_tree().process_frame
