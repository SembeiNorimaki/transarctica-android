extends Node
# Headless test of the vehicle carrier wagon: its wagon type, its four spots, the vehicle pictures
# (the E frames of the vehicle atlas), and the sample train of the trade scene that carries vehicles.
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
    # the picture: one E frame of the atlas for each vehicle type
    var strip := (load("res://assets/wagons/vehicles_east.png") as Texture2D).get_image()
    var atlas := (load("res://assets/tilesets/imgs/vehicles.png") as Texture2D).get_image()
    var frame_width := atlas.get_width() / 8
    var frame_height := atlas.get_height() / 6
    eq(strip.get_size(), Vector2i(frame_width * 6, frame_height), "the picture has 6 frames, one per vehicle")
    for row in 6:
        var east := atlas.get_region(Rect2i(2 * frame_width, row * frame_height, frame_width, frame_height)) # column 2 looks east
        var mine := strip.get_region(Rect2i(row * frame_width, 0, frame_width, frame_height))
        ok(_same_picture(east, mine), "frame %d (%s) is the E frame of its row of the atlas" % [row, VehicleCarrierWagon.VEHICLE_FRAMES[row]])
    for unit_type in VehicleCarrierWagon.VEHICLE_FRAMES:
        ok(UnitTypes.exists(unit_type), "%s is a unit type" % unit_type)

# The same pixels (what a fully transparent pixel holds does not matter)
func _same_picture(a: Image, b: Image) -> bool:
    if a.get_size() != b.get_size():
        return false
    for y in a.get_height():
        for x in a.get_width():
            var pa := a.get_pixel(x, y)
            var pb := b.get_pixel(x, y)
            if pa.a != pb.a or (pa.a > 0.0 and pa != pb):
                return false
    return true

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
    wagon.set_unit_types(["tank", "gunship"])
    ok(wagon.is_spot_filled(0) and wagon.is_spot_filled(1), "two vehicles: two spots filled")
    ok(not wagon.is_spot_filled(2) and not wagon.is_spot_filled(3), "and two empty")
    eq((wagon.get_node("Vehicles").get_child(0) as Sprite2D).frame, 0, "the tank is the first frame")
    eq((wagon.get_node("Vehicles").get_child(1) as Sprite2D).frame, 5, "the gunship the last")
    wagon.set_unit_types(["speeder", "buggy", "artillery", "grav_tank", "tank"])
    ok(wagon.is_spot_filled(3), "four fill it")
    eq((wagon.get_node("Vehicles").get_child(0) as Sprite2D).frame, 4, "speeder")
    eq((wagon.get_node("Vehicles").get_child(3) as Sprite2D).frame, 3, "grav tank")
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
        eq(carriers[1].unit_types, ["grav_tank", "gunship"] as Array[String], "the second has two empty spots")
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
