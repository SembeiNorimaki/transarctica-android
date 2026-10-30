extends Node
# The debug buttons of the main menu, with real clicks: each opens its scene, and "back to menu"
# frees it and shows the menu again. Run with a display:
#   xvfb-run -a godot --rendering-driver opengl3 --path . res://tests/main_menu_debug_test_run.tscn

var _failed := 0
var _checks := 0
var main: Node

func ok(condition: bool, what: String) -> void:
    _checks += 1
    if not condition:
        _failed += 1
        print("FAIL: ", what)

func seconds(t: float) -> void:
    await get_tree().create_timer(t, true, false, true).timeout

func click(control: Control) -> void:
    var at := control.get_global_rect().get_center()
    for pressed in [true, false]:
        var event := InputEventMouseButton.new()
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = pressed
        event.position = at
        event.global_position = at
        get_viewport().push_input(event, true)
        await get_tree().process_frame
    await get_tree().process_frame

func _ready() -> void:
    _run.call_deferred()

func _menu() -> MainMenu:
    for child in main.get_children():
        if child is MainMenu:
            return child
    return null

func _find(type: Variant) -> Node:
    for child in main.get_children():
        if is_instance_of(child, type):
            return child
    return null

func _run() -> void:
    main = load("res://scenes/core/main_scene.tscn").instantiate()
    get_tree().root.add_child(main)
    await seconds(0.5)
    ok(_menu() != null, "the menu is shown")
    ok(not main.get_node("DebugLayer").visible, "no back button on the menu")

    var cases := [["debug_trade_button", TradeScene], ["debug_combat1_button", CombatSceneTest], ["debug_combat2_button", CombatScene3]]
    for case in cases:
        var menu := _menu()
        ok(menu != null, "menu before %s" % case[0])
        if menu == null:
            break
        await click(menu.get(case[0]))
        await seconds(1.0)
        ok(_find(case[1]) != null, "%s opens its scene" % case[0])
        ok(_menu() == null or _menu().is_queued_for_deletion(), "the menu is gone")
        ok(main.get_node("DebugLayer").visible, "the back button shows")
        if case[1] == TradeScene:
            var scene := _find(TradeScene) as TradeScene
            ok(scene.city_inventory.city_name == "Paris", "the trade scene is in Paris")
        await seconds(1.0)
        ok(not get_tree().paused, "the game is not paused (%s)" % case[0])
        await click(main.get_node("DebugLayer/BackButton"))
        await seconds(0.5)
        ok(_find(case[1]) == null, "%s is freed by the back button" % case[0])
        ok(_menu() != null, "the menu is back")
        ok(not main.get_node("DebugLayer").visible, "the back button hides")
        ok(Engine.time_scale == 1.0, "normal speed")
    print("%d checks, %d failed" % [_checks, _failed])
    print("ALL PASSED" if _failed == 0 else "FAILED")
    get_tree().quit(1 if _failed > 0 else 0)
