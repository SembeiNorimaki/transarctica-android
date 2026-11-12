extends Node
# Headless test of the player's train in the city battle: it comes in at its initial speed and brakes at
# the marker, its units start aboard, tapping a wagon shows it in the bottom panel (cargo, or the units
# that get off when pressed), and the deployed units are on the map.
# It is a scene because the battle uses autoloads.
# Run:  godot --headless --path . res://tests/city_train_test_run.tscn

var _failed := 0
var _checks := 0
var scene: CombatSceneCity

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

func _new_scene(from_train := true) -> void:
    if scene != null:
        scene.queue_free()
        await get_tree().process_frame
    scene = load("res://scenes/core/combat_scene_city.tscn").instantiate()
    scene.player_units_from_train = from_train
    get_tree().root.add_child(scene)
    await get_tree().process_frame
    await get_tree().process_frame
    get_tree().paused = false

func _run() -> void:
    await _new_scene()
    await _test_arrival()
    await _test_units_aboard()
    _test_wagon_panel()
    await _test_deploying()
    await _test_turns()
    await _new_scene(false)
    _test_without_train_units()
    scene.queue_free()
    await get_tree().process_frame
    print("%d checks, %d failed" % [_checks, _failed])
    print("ALL PASSED" if _failed == 0 else "FAILED")
    get_tree().quit(1 if _failed > 0 else 0)


func _wagon(wagon_type: String, nth := 0) -> GenericWagon:
    for wagon in scene.player_train.wagons:
        if wagon.wagon_type == wagon_type:
            if nth == 0:
                return wagon
            nth -= 1
    return null

func _field(team: String) -> Array[Soldier]:
    var result: Array[Soldier] = []
    for soldier in scene.battle_unit_manager.soldiers:
        if soldier.team == team:
            result.append(soldier)
    return result


# The train comes in at its initial speed and brakes when it reaches the marker
func _test_arrival() -> void:
    var train := scene.player_train
    ok(train.visible, "the player's train is in the scene")
    eq(train.wagons.size(), GameState.get_player_train().get("wagons", []).size(), "with all the wagons of the player's train")
    eq(train.gear, "D", "it starts driving")
    eq(train.speed, scene.train_initial_speed, "at its initial speed")
    ok(train.global_position.x < scene.brake_marker.global_position.x, "before the marker")
    ok(train.global_position.x - train.train_length * train.global_scale.x < scene.brake_marker.global_position.x - 1000.0, "the tail is out of the way of the camera")
    var below_map := scene.grid_service.get_world_bounds().end.y
    ok(train.global_position.y > below_map, "it stands below the map, not over its tiles")
    await wait_until(func() -> bool: return train.global_position.x >= scene.brake_marker.global_position.x, 8.0)
    await get_tree().process_frame
    await get_tree().process_frame
    eq(train.gear, "N", "at the marker it brakes")
    ok(train.speed < scene.train_initial_speed, "and slows down")
    ok(await wait_until(func() -> bool: return is_zero_approx(train.speed), 6.0), "until it stops")
    var braking := scene.train_initial_speed * scene.train_initial_speed / (2.0 * train.deceleration)
    ok(absf(train.global_position.x - (scene.brake_marker.global_position.x + braking)) < 40.0, "where the speed and the brakes say (%d)" % int(train.global_position.x))
    ok(not scene.get("_train_arriving"), "and it has arrived")


# The player's units start aboard; the enemy's are on the map
func _test_units_aboard() -> void:
    eq(_field("player").size(), 0, "no player unit on the map")
    eq(_field("enemy").size(), 9, "the enemy has its 9 units")
    var expected := 0
    for wagon_data: Dictionary in GameState.get_player_train().get("wagons", []):
        expected += wagon_data.get("unit_ids", []).size()
    ok(expected > 0, "the player's train carries units")
    eq(scene.wagon_deploy_manager.count_aboard(), expected, "all of them are aboard")
    var carrier := _wagon("VehicleCarrierWagon")
    eq(scene.wagon_deploy_manager.get_aboard(carrier), carrier.unit_ids, "the carrier has its units")
    ok(scene.wagon_deploy_manager.carries_units(carrier) and not scene.wagon_deploy_manager.carries_units(_wagon("TenderWagon")), "a carrier takes units out, a tender does not")


# Tapping a wagon shows it in the bottom panel
func _test_wagon_panel() -> void:
    var hud := scene.unit_hud
    ok(not hud.is_showing_wagon(), "no wagon shown at first")
    var tender := _wagon("TenderWagon")
    tender.clicked.emit(tender)
    ok(hud.is_showing_wagon(), "tapping a wagon shows it")
    ok(not hud.panel.visible, "instead of a unit")
    eq(hud.wagon_name_label.text, "Tender Wagon", "its name")
    eq(hud.wagon_hp_label.text, "HP %d/%d" % [tender.hp, tender.max_hp], "its hp")
    eq(hud.cargo_label.text, "%s %d / %d" % [tender.cargo_type.capitalize(), tender.cargo_amount, tender.max_cargo_amount], "what it carries")
    ok(hud.cargo_icon.visible and hud.cargo_icon.texture != null, "with the picture of the resource")
    eq(hud.slots.get_child_count(), 0, "a tender has no units to get off")
    ok(hud.wagon_icon.texture != null, "and its picture")
    var empty := _wagon("MerchandiseWagon")
    empty.clicked.emit(empty)
    eq(hud.cargo_label.text, "Empty (0 / %d)" % empty.max_cargo_amount, "an empty wagon says so")
    ok(not hud.cargo_icon.visible, "without a picture of cargo")
    empty.clicked.emit(empty)
    ok(not hud.is_showing_wagon(), "tapping it again closes the panel")

    var carrier := _wagon("VehicleCarrierWagon")
    carrier.clicked.emit(carrier)
    eq(hud.wagon_name_label.text, "Vehicle Carrier Wagon", "a carrier")
    eq(hud.cargo_label.text, "Vehicles %d / 4" % carrier.unit_ids.size(), "says how many vehicles it has")
    eq(hud.slots.get_child_count(), carrier.unit_ids.size(), "a button for each")
    for i in hud.slots.get_child_count():
        var button := hud.slots.get_child(i) as Button
        ok(button.icon != null and not button.disabled, "button %d has the picture of its vehicle and can be pressed" % i)
        var unit_type := str(GameState.get_unit(carrier.unit_ids[i]).get("unit_type", ""))
        eq(button.text, unit_type.replace("_", " ").capitalize(), "button %d is the %s" % [i, unit_type])


# Pressing a unit of the wagon gets it off the train
func _test_deploying() -> void:
    var hud := scene.unit_hud
    var manager := scene.wagon_deploy_manager
    var carrier := _wagon("VehicleCarrierWagon")
    var ids := carrier.unit_ids.duplicate()
    var first: String = ids[0]
    var first_type := str(GameState.get_unit(first).get("unit_type", ""))
    (hud.slots.get_child(0) as Button).pressed.emit()
    var soldier: Soldier = null
    for candidate in _field("player"):
        if candidate.unit_id == first:
            soldier = candidate
    ok(soldier != null, "the vehicle is on the map")
    if soldier != null:
        eq(soldier.unit_type, first_type, "it is the %s" % first_type)
        eq(soldier.team, "player", "of the player")
        ok(soldier.hp == soldier.max_hp, "with its hp")
        var area := manager.deploy_area
        var tiles := scene.occupancy_service.get_tiles_of(soldier)
        eq(tiles.size(), UnitTypes.get_footprint(first_type).size(), "it covers the tiles of its type")
        for tile in tiles:
            ok(area.has_point(tile) and scene.terrain_service.is_walkable(tile), "tile %s is in the deploy area" % tile)
        ok(soldier.visible, "it is visible")
    eq(manager.get_aboard(carrier), ids.slice(1), "it is no longer aboard")
    eq(hud.slots.get_child_count(), ids.size() - 1, "its button is gone")
    ok(hud.is_showing_wagon(), "the panel still shows the wagon (more can get off)")
    eq(hud.cargo_label.text, "Vehicles %d / 4" % (ids.size() - 1), "with the new count")
    var spots_filled := 0
    for i in carrier.get_spot_count():
        if carrier.is_spot_filled(i):
            spots_filled += 1
    eq(spots_filled, ids.size() - 1, "and the wagon has one vehicle less on it")
    eq(GameState.get_unit(first).get("unit_type"), first_type, "the campaign's unit is not touched")
    eq(carrier.unit_ids, ids, "nor the wagon's data")

    # a unit selected: the unit is in the panel; a wagon tapped: the unit is not selected any more
    if soldier != null:
        scene.battle_unit_manager.select(soldier)
        ok(not hud.is_showing_wagon() and hud.panel.visible, "selecting a unit takes the wagon away")
        carrier.clicked.emit(carrier)
        ok(hud.is_showing_wagon() and not hud.panel.visible, "tapping the wagon shows it again")
        ok(scene.battle_unit_manager.selected == null, "and nobody is selected")

    # everything gets off, each on its own free tiles
    for wagon in scene.player_train.wagons:
        manager.deploy_all(wagon)
    eq(manager.count_aboard(), 0, "everything got off")
    var seen := {}
    var overlaps := 0
    for unit in _field("player"):
        for tile in scene.occupancy_service.get_tiles_of(unit):
            if seen.has(tile):
                overlaps += 1
            seen[tile] = true
    eq(overlaps, 0, "no two units share a tile")
    var expected := 0
    for wagon_data: Dictionary in GameState.get_player_train().get("wagons", []):
        expected += wagon_data.get("unit_ids", []).size()
    eq(_field("player").size(), expected, "all the units of the train are on the map")
    var gone := true
    for wagon in scene.player_train.wagons:
        if wagon is VehicleCarrierWagon:
            for i in wagon.get_spot_count():
                gone = gone and not wagon.is_spot_filled(i)
    ok(gone, "the carriers are empty")
    eq(hud.slots.get_child_count(), 0, "the panel has no buttons")
    ok(manager.deploy(carrier, first) == null, "a unit that is not aboard can't get off")
    # every vehicle can leave the deploy area
    for unit in _field("player"):
        var path := scene.pathfinding_service.find_path(unit.tile, manager.exit_tile, scene.battle_unit_manager.get_profile(unit))
        ok(path.size() > 3, "%s (%s) can walk to the avenue (%d steps)" % [unit.unit_id, unit.unit_type, path.size()])


# Units get off on the player's turn only
func _test_turns() -> void:
    await _new_scene()
    var manager := scene.wagon_deploy_manager
    var carrier := _wagon("VehicleCarrierWagon")
    var id: String = carrier.unit_ids[0]
    ok(manager.can_deploy(carrier, id), "on the player's turn a unit can get off")
    scene.flow_manager.end_turn()
    ok(not manager.can_deploy(carrier, id), "not on the enemy's")
    ok(manager.deploy(carrier, id) == null, "so it does not")
    carrier.clicked.emit(carrier)
    scene.flow_manager.status_changed.emit()
    var disabled := true
    for button in scene.unit_hud.slots.get_children():
        disabled = disabled and (button as Button).disabled
    ok(disabled and scene.unit_hud.slots.get_child_count() > 0, "and the buttons are disabled")


func _test_without_train_units() -> void:
    eq(_field("player").size(), 9, "with player_units_from_train off the player's units are those of the map")
    ok(scene.wagon_deploy_manager.count_aboard() > 0, "(the train still carries its own units)")
