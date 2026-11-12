extends Node
# Headless test of the vehicle carrier wagon: its wagon type, its four spots, the vehicle pictures
# (the placeholder pictures of the map tileset), and the sample train of the trade scene that carries vehicles.
# It is a scene because the trade scene uses autoloads.
# Run:  godot --headless --path . res://tests/vehicle_carrier_test_run.tscn

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

func _run() -> void:
    _test_type_and_picture()
    _test_wagon()
    await _test_sample_train()
    print("%d checks, %d failed" % [_checks, _failed])
    print("ALL PASSED" if _failed == 0 else "FAILED")
    get_tree().quit(1 if _failed > 0 else 0)


func _test_type_and_picture() -> void:
    ok(WagonTypes.TYPES.has("VehicleCarrierWagon"), "the wagon type exists")
    var info: Dictionary = WagonTypes.TYPES["VehicleCarrierWagon"]
    eq(info["capacity"], 4, "it carries 4 vehicles")
    ok(info["stores"].has("Vehicles") and not info["stores"].has("Soldiers"), "it stores vehicles, not soldiers")
    # the picture: the placeholders of the maps, a column per team and a row per vehicle type
    var sheet := load("res://assets/combat/unitsFH_placeholder.png") as Texture2D
    eq(sheet.get_size(), Vector2(140, 378), "the placeholder pictures: 2 columns by 7 rows of 70x54")
    var wagon := (info["horizontal_scene"] as PackedScene).instantiate() as VehicleCarrierWagon
    for spot in wagon.get_node("Vehicles").get_children():
        eq((spot as Sprite2D).texture.resource_path, "res://assets/combat/unitsFH_placeholder.png", "a spot uses the placeholder pictures")
        eq([(spot as Sprite2D).hframes, (spot as Sprite2D).vframes], [2, 7], "as 2 columns by 7 rows")
    wagon.free()
    eq(VehicleCarrierWagon.VEHICLE_FRAMES, ["artillery", "tank", "buggy", "grav_tank", "speeder", "humvee"] as Array[String], "the rows are in the order of the pictures")
    for unit_type in VehicleCarrierWagon.VEHICLE_FRAMES:
        ok(UnitTypes.exists(unit_type), "%s is a unit type" % unit_type)

func _test_wagon() -> void:
    var wagon := (WagonTypes.TYPES["VehicleCarrierWagon"]["horizontal_scene"] as PackedScene).instantiate() as VehicleCarrierWagon
    ok(wagon != null, "the scene is a VehicleCarrierWagon")
    add_child(wagon)
    eq(wagon.get_spot_count(), 4, "it has 4 sprites for the spots")
    var xs: Array[float] = []
    for spot in wagon.get_node("Vehicles").get_children():
        ok(spot is Sprite2D, "a spot is a Sprite2D")
        xs.append((spot as Sprite2D).position.x)
    ok(xs[0] < xs[1] and xs[1] < xs[2] and xs[2] < xs[3], "left to right")
    wagon.set_unit_types([])
    for i in 4:
        ok(not wagon.is_spot_filled(i), "empty: spot %d shows nothing" % i)
    wagon.set_unit_types(["tank", "humvee"])
    ok(wagon.is_spot_filled(0) and wagon.is_spot_filled(1), "two vehicles: two spots filled")
    ok(not wagon.is_spot_filled(2) and not wagon.is_spot_filled(3), "and two empty")
    eq((wagon.get_node("Vehicles").get_child(0) as Sprite2D).frame_coords, Vector2i(0, 1), "the tank: player column, second row")
    eq((wagon.get_node("Vehicles").get_child(1) as Sprite2D).frame_coords, Vector2i(0, 5), "the humvee the last row")
    wagon.set_unit_types(["speeder", "buggy", "artillery", "grav_tank", "tank"])
    ok(wagon.is_spot_filled(3), "four fill it")
    eq((wagon.get_node("Vehicles").get_child(0) as Sprite2D).frame_coords, Vector2i(0, 4), "speeder")
    eq((wagon.get_node("Vehicles").get_child(3) as Sprite2D).frame_coords, Vector2i(0, 3), "grav tank")
    wagon.set_team("enemy")
    eq((wagon.get_node("Vehicles").get_child(3) as Sprite2D).frame_coords, Vector2i(1, 3), "an enemy wagon shows the other column")
    wagon.set_team("player")
    wagon.set_unit_types(["soldier-that-is-not-a-vehicle"])
    ok(not wagon.is_spot_filled(0), "something that is not a vehicle is not drawn")
    wagon.queue_free()

func _test_sample_train() -> void:
    var scene = load("res://scenes/core/trade_scene.tscn").instantiate()
    get_tree().root.add_child(scene)
    await get_tree().process_frame
    scene.initialize("Paris")
    await get_tree().process_frame
    var carriers: Array[VehicleCarrierWagon] = []
    for wagon in scene.player_train.wagons:
        if wagon is VehicleCarrierWagon:
            carriers.append(wagon)
    eq(carriers.size(), 2, "the sample train has two vehicle carriers")
    if carriers.size() == 2:
        eq(carriers[0].unit_types, ["tank", "artillery", "buggy", "speeder"] as Array[String], "the first carries 4 vehicles")
        eq(carriers[1].unit_types, ["grav_tank", "humvee"] as Array[String], "the second has two empty spots")
        for i in 4:
            ok(carriers[0].is_spot_filled(i), "first carrier, spot %d is filled" % i)
        ok(carriers[1].is_spot_filled(1) and not carriers[1].is_spot_filled(2), "second carrier: 2 filled, 2 free")
    var inventory: TrainInventory = scene.train_inventory
    var found := 0
    for i in inventory.get_wagon_count():
        if inventory.wagons[i].wagon_type == "VehicleCarrierWagon":
            found += 1
            ok(not inventory.is_barracks(i), "a carrier is not a barracks")
            eq(inventory.get_wagon_unit_free_space(i), 0, "no soldier fits in it")
            ok(inventory.get_unit_ids(i).size() >= 2, "its vehicle ids are kept")
    eq(found, 2, "the inventory has the two carriers")
    for unit_id in ["u20", "u21", "u22", "u23", "u24", "u25"]:
        ok(not GameState.get_unit(unit_id).is_empty() and UnitTypes.exists(str(GameState.get_unit(unit_id)["unit_type"])), "%s is a vehicle unit in GameState" % unit_id)
    scene.queue_free()
    await get_tree().process_frame
