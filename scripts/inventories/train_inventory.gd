extends Node
class_name TrainInventory
# Runtime cargo of the player train: what each wagon holds, and the rules to load and unload it.
# The truth is the "wagons" list of the player train in GameState. This object applies the rules
# and writes every change back (single path, so both stay in sync).
#
# Wagon index = index in the train data's "wagons" array = index in HorizontalTrain.wagons.
# Wagon nodes are only views: they listen to the signals below.
#
# Create it in code: TrainInventory.new(), then load_from_game_state().
# Money is NOT here: it lives in GameState (get_money / add_money).
#
# wagons example:
# [ {"wagon_type": "MerchandiseWagon", "max_capacity": 10, "qty": 0, "resource_name": ""} ]

# Both signals carry the state AFTER the change ("" as resource when the wagon was emptied).
signal wagon_resource_type_changed(wagon_index: int, resource_name: String)
signal wagon_resource_amount_changed(wagon_index: int, resource_name: String, qty: int)

var wagons: Array[Dictionary] = []


#region setup
# Builds the wagons from the player train in GameState.
func load_from_game_state() -> bool:
    var train_data: Dictionary = GameState.get_player_train()
    var wagons_data: Array = train_data.get("wagons", [])
    if wagons_data.is_empty():
        push_error("TrainInventory: no wagons in the player train of GameState")
        return false

    wagons.clear()
    for wagon_data in wagons_data:
        var data: Dictionary = wagon_data
        _append_wagon(
            data.get("type", ""),
            data.get("cargo_name", ""),
            int(data.get("cargo_qty", 0))) # JSON numbers are floats
    return true


# Capacity comes from WagonTypes. Every wagon gets an entry, even with an unknown type,
# so the indices stay aligned with the train data.
func _append_wagon(wagon_type: String, cargo: String, qty: int) -> void:
    var capacity := 0
    if WagonTypes.TYPES.has(wagon_type):
        capacity = int(WagonTypes.TYPES[wagon_type].capacity)
    else:
        push_error("TrainInventory: unknown wagon type '%s'" % wagon_type)

    if qty > capacity:
        push_warning("TrainInventory: a %s holds %d but its capacity is %d" % [wagon_type, qty, capacity])
        qty = capacity

    wagons.append({
        "wagon_type": wagon_type,
        "max_capacity": capacity,
        "qty": qty,
        "resource_name": cargo if qty > 0 else "", # an empty wagon has no resource
    })
#endregion


#region wagon queries
func has_wagon(idx: int) -> bool:
    return idx >= 0 and idx < wagons.size()

func get_wagon_count() -> int:
    return wagons.size()

# Returns a copy
func get_wagon_info(idx: int) -> Dictionary:
    return wagons[idx].duplicate() if has_wagon(idx) else {}

func get_wagon_type(idx: int) -> String:
    return wagons[idx].wagon_type if has_wagon(idx) else ""

func get_wagon_capacity(idx: int) -> int:
    return wagons[idx].max_capacity if has_wagon(idx) else 0

func get_wagon_current_resource(idx: int) -> String:
    return wagons[idx].resource_name if has_wagon(idx) else ""

func get_wagon_resource_qty(idx: int) -> int:
    return wagons[idx].qty if has_wagon(idx) else 0

func get_wagon_free_space(idx: int) -> int:
    return wagons[idx].max_capacity - wagons[idx].qty if has_wagon(idx) else 0

# A wagon can store a resource if it is the right wagon type, and it is empty
# or already holds that same resource.
func wagon_can_store(wagon_idx: int, resource_name: String) -> bool:
    if not has_wagon(wagon_idx):
        return false
    var needed_type = ResourceTypes.wagon_type_for(resource_name) # "" if the resource is unknown
    var wagon: Dictionary = wagons[wagon_idx]
    if needed_type.is_empty() or wagon.wagon_type != needed_type:
        return false
    return wagon.resource_name == "" or ResourceTypes.same(wagon.resource_name, resource_name)

func get_wagons_idx_that_can_store(resource_name: String) -> Array:
    var result := []
    for i in wagons.size():
        if wagon_can_store(i, resource_name):
            result.append(i)
    return result

func get_wagon_capacity_for_resource(wagon_idx: int, resource_name: String) -> int:
    if not wagon_can_store(wagon_idx, resource_name):
        return 0
    return get_wagon_free_space(wagon_idx)
#endregion


#region whole-train queries
# Total units of this resource in all wagons
func get_total_qty_of(resource_name: String) -> int:
    var total := 0
    for wagon in wagons:
        if wagon.qty > 0 and ResourceTypes.same(wagon.resource_name, resource_name):
            total += wagon.qty
    return total

# Total free space for this resource: wagons already holding it plus empty wagons of the right type
func get_free_capacity_for(resource_name: String) -> int:
    var total := 0
    for i in wagons.size():
        total += get_wagon_capacity_for_resource(i, resource_name)
    return total
#endregion


#region changes (one wagon)
# Returns false, changing nothing, if it can't be done.
func add_resource_qty_to_wagon(wagon_idx: int, resource_name: String, qty: int) -> bool:
    if qty <= 0 or not wagon_can_store(wagon_idx, resource_name):
        return false
    if qty > get_wagon_free_space(wagon_idx):
        return false

    var wagon: Dictionary = wagons[wagon_idx]
    var type_changed: bool = wagon.resource_name == ""
    if type_changed:
        wagon.resource_name = resource_name
    wagon.qty += qty
    _commit(wagon_idx, type_changed)
    return true


# Returns false, changing nothing, if the wagon doesn't hold that much.
func remove_resource_qty_from_wagon(wagon_idx: int, qty: int) -> bool:
    if qty <= 0 or not has_wagon(wagon_idx):
        return false
    var wagon: Dictionary = wagons[wagon_idx]
    if qty > wagon.qty:
        return false

    wagon.qty -= qty
    var type_changed := false
    if wagon.qty == 0:
        wagon.resource_name = ""
        type_changed = true
    _commit(wagon_idx, type_changed)
    return true
#endregion


#region changes (whole train)
# Loads a resource into the train, spread over its wagons: wagons that already hold it first,
# then empty ones. All or nothing: returns false, changing nothing, if it doesn't all fit.
func add_resource_amount(resource_name: String, qty: int) -> bool:
    if qty <= 0 or qty > get_free_capacity_for(resource_name):
        return false

    var remaining := qty
    for fill_empty in [false, true]:
        for i in wagons.size():
            if remaining == 0:
                break
            if not wagon_can_store(i, resource_name):
                continue
            if (wagons[i].resource_name == "") != fill_empty:
                continue
            var amount := mini(remaining, get_wagon_free_space(i))
            if amount > 0 and add_resource_qty_to_wagon(i, resource_name, amount):
                remaining -= amount
    return remaining == 0


# Unloads a resource, taking from the least-filled wagons first so wagons become free.
# All or nothing: returns false, changing nothing, if the train doesn't hold that much.
func remove_resource_amount(resource_name: String, qty: int) -> bool:
    if qty <= 0 or qty > get_total_qty_of(resource_name):
        return false

    var holding: Array[int] = []
    for i in wagons.size():
        if wagons[i].qty > 0 and ResourceTypes.same(wagons[i].resource_name, resource_name):
            holding.append(i)
    holding.sort_custom(func(a: int, b: int) -> bool: return wagons[a].qty < wagons[b].qty)

    var remaining := qty
    for i in holding:
        if remaining == 0:
            break
        var amount := mini(remaining, wagons[i].qty)
        if remove_resource_qty_from_wagon(i, amount):
            remaining -= amount
    return remaining == 0
#endregion


# Writes the wagon to GameState, then announces it. The state is final when the signals fire.
func _commit(wagon_idx: int, type_changed: bool) -> void:
    var wagon: Dictionary = wagons[wagon_idx]
    GameState.set_wagon_cargo(wagon_idx, wagon.resource_name, wagon.qty)
    # TODO: quests (collected / delivered goods) should listen to these signals
    if type_changed:
        wagon_resource_type_changed.emit(wagon_idx, wagon.resource_name)
    wagon_resource_amount_changed.emit(wagon_idx, wagon.resource_name, wagon.qty)
