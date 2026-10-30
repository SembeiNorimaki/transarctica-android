extends Node
# Headless test with real mouse clicks (events sent to the window), of:
#  - the trade scene's bottom buttons: right starts and stops the train, left reverses it
#  - the navigation scene's FOLLOW CAMERA button
# It is a scene because the scenes it tests use autoloads.
# Run:  godot --headless --path . res://tests/train_buttons_test_run.tscn

var _failed := 0
var _checks := 0


# QuestManager asks the running scene for this: the test has no use for quests
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

# A real click: the mouse goes down and up in the middle of the control
func click(control: Control) -> void:
    var at := control.get_global_rect().get_center()
    var motion := InputEventMouseMotion.new() # the pointer arrives first, as it does for a real one
    motion.position = at
    motion.global_position = at
    get_viewport().push_input(motion, true) # in the viewport's own coordinates
    await get_tree().process_frame
    for pressed in [true, false]:
        var event := InputEventMouseButton.new()
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = pressed
        event.position = at
        event.global_position = at
        get_viewport().push_input(event, true)
        await get_tree().process_frame
    await get_tree().process_frame


func _run() -> void:
    await _test_trade_buttons()
    await _test_camera_follow()
    print("%d checks, %d failed" % [_checks, _failed])
    print("ALL PASSED" if _failed == 0 else "FAILED")
    get_tree().quit(1 if _failed > 0 else 0)


func _test_trade_buttons() -> void:
    var scene: TradeScene = load("res://scenes/core/trade_scene.tscn").instantiate()
    get_tree().root.add_child(scene)
    await get_tree().process_frame
    scene.initialize("Paris")
    var train := scene.player_train
    ok(await wait_until(func() -> bool: return scene._phase == TradeScene.Phase.TRADING, 15.0), "the train arrives and the trading begins")
    ok(await wait_until(func() -> bool: return absf(train.speed) < 1.0, 10.0), "and stops")
    var bar := scene.hud.bottom_bar
    eq(train.gear, "N", "in neutral")
    var x0 := train.position.x

    await click(bar.button_right)
    eq(train.gear, "D", "right button: the train starts (drive)")
    await seconds(0.6)
    ok(train.position.x > x0 + 20.0, "and moves to the right")
    ok(train.is_driving(), "is_driving")

    await click(bar.button_right)
    eq(train.gear, "N", "right button again: it stops")
    ok(await wait_until(func() -> bool: return absf(train.speed) < 1.0, 6.0), "it brakes to a halt")

    await click(bar.button_left)
    eq(train.gear, "N", "left button on a stopped train: still stopped")
    eq(train.direction, -1, "but it will go the other way")
    var x1 := train.position.x
    await click(bar.button_right)
    eq(train.gear, "R", "right button: it starts in reverse")
    await seconds(0.6)
    ok(train.position.x < x1 - 20.0, "and moves to the left")

    await click(bar.button_left)
    eq(train.gear, "D", "left button while driving: it turns round")
    await seconds(1.5)
    ok(train.speed > 0.0, "and goes to the right")
    await click(bar.button_left)
    eq(train.gear, "R", "and back")
    await click(bar.button_right)
    eq(train.gear, "N", "stop")
    ok(await wait_until(func() -> bool: return absf(train.speed) < 1.0, 6.0), "halt")

    # the buttons do nothing while the train drives itself (leaving the city)
    scene._phase = TradeScene.Phase.OUTRO
    await click(bar.button_right)
    eq(train.gear, "N", "no start during the outro")
    scene._phase = TradeScene.Phase.TRADING
    scene.queue_free()
    await get_tree().process_frame
    await get_tree().process_frame


func _test_camera_follow() -> void:
    var scene: NavigationScene = load("res://scenes/core/navigation_scene.tscn").instantiate()
    get_tree().root.add_child(scene)
    ok(await wait_until(func() -> bool: return scene.is_loaded, 60.0), "the navigation map is built")
    await seconds(0.5)
    get_tree().paused = false
    var manager := scene.navigation_train_manager
    var train := manager.player_train
    ok(is_instance_valid(train) and not train.wagons.is_empty(), "the navigation scene has a player train")
    var cam := scene.camera_service.cam
    var button := scene.hud.button_camera
    ok(button.toggle_mode, "the camera button is a toggle")
    ok(not manager.camera_lock_to_engine, "the camera does not follow at first")

    await click(scene.hud.button_right)
    ok(await wait_until(func() -> bool: return train.is_driving(), 3.0), "the train is driving")
    var camera_before := cam.global_position
    await seconds(1.0)
    var engine := train.wagons[0].global_position
    ok(engine.distance_to(camera_before) > 5.0 or train.wagons[0].global_position != Vector2.ZERO, "the train moved")
    ok(cam.global_position.distance_to(camera_before) < 1.0, "the camera does not follow by itself")

    await click(button)
    ok(button.button_pressed, "the button is down")
    ok(manager.camera_lock_to_engine, "the click turns the camera follow on")
    await seconds(0.3)
    ok(cam.global_position.distance_to(train.wagons[0].global_position) < 3.0, "the camera is on the train")
    var seen_a := cam.global_position
    await seconds(1.0)
    var seen_b := cam.global_position
    ok(seen_a.distance_to(seen_b) > 5.0, "and goes with it as it moves")
    ok(cam.global_position.distance_to(train.wagons[0].global_position) < 3.0, "staying on it")

    await click(button)
    ok(not manager.camera_lock_to_engine, "a second click turns it off")
    var parked := cam.global_position
    await seconds(0.8)
    ok(cam.global_position.distance_to(parked) < 1.0, "the camera stays where it was")
    ok(train.wagons[0].global_position.distance_to(parked) > 5.0, "while the train goes on")
    scene.queue_free()
    await get_tree().process_frame
