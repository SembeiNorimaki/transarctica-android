extends Node
# Tests of the game's time: GameCalendar, GameClock, GameState's time, the top bar label, and the
# navigation scene (time passes there, even with the train stopped, and not while it is suspended).
# Needs a display for the navigation scene (its map loading waits for frames):
#   xvfb-run -a godot --rendering-driver opengl3 --path . res://tests/time_test_run.tscn

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

func wait_until(condition: Callable, timeout := 8.0) -> bool:
    var waited := 0.0
    while not condition.call() and waited < timeout:
        await seconds(0.05)
        waited += 0.05
    return condition.call()


func _run() -> void:
    _test_calendar()
    await _test_state_and_clock()
    await _test_top_bar()
    await _test_navigation_scene()
    print("%d checks, %d failed" % [_checks, _failed])
    print("ALL PASSED" if _failed == 0 else "FAILED")
    get_tree().quit(1 if _failed > 0 else 0)


func _date(day_number: int) -> String:
    var d := GameCalendar.date_of(day_number)
    return "%d-%d-%d" % [d["year"], d["month"], d["day"]]

func _test_calendar() -> void:
    eq(GameCalendar.format(0), "1 jan 2100, 00h00", "the game starts on 1 Jan 2100, midnight")
    eq(GameCalendar.format(8 * 60 + 5), "1 jan 2100, 08h05", "time of day")
    eq(GameCalendar.format(1440 + 13 * 60 + 45), "2 jan 2100, 13h45", "next day")
    eq(GameCalendar.format(1439), "1 jan 2100, 23h59", "the last minute of a day")
    eq(_date(30), "2100-1-31", "31 Jan")
    eq(_date(31), "2100-2-1", "1 Feb")
    eq(_date(58), "2100-2-28", "28 Feb 2100")
    eq(_date(59), "2100-3-1", "2100 is not a leap year: 1 Mar follows 28 Feb")
    eq(_date(364), "2100-12-31", "last day of 2100")
    eq(_date(365), "2101-1-1", "new year")
    eq(GameCalendar.is_leap_year(2100), false, "2100 is not leap (a century)")
    eq(GameCalendar.is_leap_year(2104), true, "2104 is leap")
    eq(GameCalendar.is_leap_year(2200), false, "2200 is not leap")
    eq(GameCalendar.is_leap_year(2400), true, "2400 is leap (divisible by 400)")
    var leap_start := 365 * 4 # 1 Jan 2104
    eq(_date(leap_start), "2104-1-1", "1 Jan 2104")
    eq(_date(leap_start + 59), "2104-2-29", "29 Feb 2104 exists")
    eq(_date(leap_start + 60), "2104-3-1", "then March")
    eq(_date(leap_start + 365), "2104-12-31", "a leap year has 366 days")
    eq(_date(leap_start + 366), "2105-1-1", "and then 2105")
    # a minute of every day belongs to exactly one date, in order
    var last := ""
    var in_order := true
    for day in range(0, 800):
        var text := _date(day)
        if text == last:
            in_order = false
        last = text
    ok(in_order, "no date repeats")
    eq(GameCalendar.format(-50), "1 jan 2100, 00h00", "negative time counts as the start")
    var all_lower := GameCalendar.format(123456).to_lower() == GameCalendar.format(123456)
    ok(all_lower, "the text is lower case: the game's font has no capitals")
    ok(not GameCalendar.format(123456).contains(":"), "and no colon")


func _test_state_and_clock() -> void:
    GameState.start_new_game(GameState.DEBUG_SLOT)
    await get_tree().process_frame
    get_tree().paused = false # a new game starts its quests, which pause the game on their dialog
    eq(GameState.get_game_minutes(), 0, "a new game is at the start of the time")
    eq(GameState.get_game_day(), 0, "day 0")
    var seen := []
    GameState.game_time_changed.connect(func(m: int) -> void: seen.append(m))
    GameState.add_game_minutes(90)
    eq(GameState.get_game_minutes(), 90, "minutes are added")
    eq(seen, [90], "and announced")
    GameState.add_game_minutes(0)
    GameState.add_game_minutes(-5)
    eq(GameState.get_game_minutes(), 90, "time never goes back")

    var clock := GameClock.new()
    clock.minutes_per_second = 60.0 # a minute a frame-ish, to be quick
    var days := []
    clock.day_passed.connect(func(d: int) -> void: days.append(d))
    add_child(clock)
    var start := GameState.get_game_minutes()
    await seconds(0.5)
    ok(GameState.get_game_minutes() > start + 3, "the clock moves the time as time goes by")
    clock.enabled = false
    var manual := GameState.get_game_minutes()
    clock._process(0.5) # disabled: nothing
    eq(GameState.get_game_minutes(), manual, "a disabled clock does not count")
    clock.enabled = true
    clock._fraction = 0.0 # (the real frames may have left a part of a minute)
    clock._process(0.5) # half a second at 60 minutes a second
    eq(GameState.get_game_minutes(), manual + 30, "the rate is minutes_per_second")
    clock._process(0.01) # 0.6 of a minute: kept, not lost
    clock._process(0.01)
    eq(GameState.get_game_minutes(), manual + 31, "fractions of a minute add up")
    clock.enabled = false
    var stopped := GameState.get_game_minutes()
    await seconds(0.3)
    eq(GameState.get_game_minutes(), stopped, "a disabled clock stops")
    clock.enabled = true

    # midnights
    clock.enabled = false
    GameState.start_new_game(GameState.DEBUG_SLOT)
    await get_tree().process_frame
    get_tree().paused = false
    days.clear()
    clock.advance_minutes(1439)
    eq(days, [], "no midnight yet")
    clock.advance_minutes(1)
    eq(days, [1], "midnight: day 1")
    clock.advance_minutes(3000)
    eq(days, [1, 2, 3], "two more midnights")
    eq(GameState.get_game_day(), 3, "the state agrees")
    clock.advance_minutes(0)
    eq(days.size(), 3, "no time, no midnight")

    # while the game is paused (a menu), or the node disabled (the scene suspended), it stands still
    clock.enabled = true
    clock.minutes_per_second = 600.0
    get_tree().paused = true
    var before := GameState.get_game_minutes()
    await seconds(0.3)
    eq(GameState.get_game_minutes(), before, "paused: no time passes")
    get_tree().paused = false
    clock.process_mode = Node.PROCESS_MODE_DISABLED
    await seconds(0.3)
    eq(GameState.get_game_minutes(), before, "disabled node: no time passes")
    clock.process_mode = Node.PROCESS_MODE_INHERIT
    await seconds(0.3)
    ok(GameState.get_game_minutes() > before, "and it goes on afterwards")
    clock.queue_free()
    await get_tree().process_frame

    # a game with no time in its save (an older one) starts at the beginning: the field is optional
    var player := {"money": 5, "train": {"wagons": []}}
    eq(GameState._validate_player(player), "", "a save with no game_minutes is valid")


func _test_top_bar() -> void:
    GameState.start_new_game(GameState.DEBUG_SLOT)
    await get_tree().process_frame
    get_tree().paused = false
    var bar: TopBar = load("res://scenes/UI/top_bar.tscn").instantiate()
    add_child(bar)
    await get_tree().process_frame
    eq(bar.date_label.text, "1 jan 2100, 00h00", "the top bar shows the date and time")
    GameState.add_game_minutes(1440 * 40 + 9 * 60 + 30)
    eq(bar.date_label.text, "10 feb 2100, 09h30", "and follows the time")
    ok(bar.date_label.mouse_filter != Control.MOUSE_FILTER_STOP, "the label does not take taps")
    bar.queue_free()
    await get_tree().process_frame


func _test_navigation_scene() -> void:
    GameState.start_new_game(GameState.DEBUG_SLOT)
    await get_tree().process_frame
    get_tree().paused = false
    var scene: NavigationScene = load("res://scenes/core/navigation_scene.tscn").instantiate()
    get_tree().root.add_child(scene)
    ok(await wait_until(func() -> bool: return scene.is_loaded, 60.0), "the navigation map is built")
    get_tree().paused = false
    ok(scene.game_clock is GameClock, "the navigation scene has its GameClock")
    scene.game_clock.minutes_per_second = 300.0

    var train := scene.navigation_train_manager.player_train
    ok(is_instance_valid(train) and not train.is_driving(), "the train is stopped")
    var t0 := GameState.get_game_minutes()
    await seconds(0.5)
    var t1 := GameState.get_game_minutes()
    ok(t1 > t0 + 30, "time passes with the train stopped (%d minutes)" % (t1 - t0))
    scene.game_clock.enabled = false
    await get_tree().process_frame
    eq(scene.hud.top_bar.date_label.text, GameCalendar.format(GameState.get_game_minutes()), "the HUD's top bar shows the date and time")
    var seen_days := []
    scene.global_economy_manager.day_passed.connect(func(d: int) -> void: seen_days.append(d))
    var day := GameState.get_game_day()
    scene.game_clock.advance_minutes(1440 * 2)
    eq(seen_days, [day + 1, day + 2], "each midnight the world economy lives a day")
    scene.game_clock.enabled = true

    # in a city or a fight the scene is suspended: no time passes
    scene.suspend()
    var frozen := GameState.get_game_minutes()
    await seconds(0.6)
    eq(GameState.get_game_minutes(), frozen, "suspended (a city or a fight): time stands still")
    scene.resume()
    get_tree().paused = false
    await seconds(0.5)
    ok(GameState.get_game_minutes() > frozen + 30, "back on the map: time passes again")
    scene.queue_free()
    await get_tree().process_frame
