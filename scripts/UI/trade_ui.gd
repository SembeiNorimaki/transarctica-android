extends Control
class_name TradeUI
# The menus of the trade scene: buy, sell and production. It decides which one is open, what it
# shows, and keeps it up to date while the inventories change. It never changes an inventory: when
# the player presses a button it emits a request, and TradeScene decides what that means.
#
# TradeScene calls setup() once with what it needs (the inventories to read, and the views to take
# the pictures from), then forwards the taps on the city's resources, wagons, soldiers and building
# to the toggle_* functions.
#
# Scene structure: this script on the Control that holds BuyMenu, SellMenu and ProductionMenu.

signal buy_requested(resource_name: String, qty: int)
signal sell_from_wagon_requested(wagon_index: int, qty: int)
signal buy_wagon_requested(wagon_type: String)
signal sell_wagon_requested(wagon_index: int)
signal recruit_requested(unit_type: String)
signal produce_requested(recipe_index: int, times: int)
signal refused(message: String) # something can't be opened: the scene can tell the player

@onready var buy_menu: BuyMenu = $BuyMenu
@onready var sell_menu: SellMenu = $SellMenu
@onready var production_menu: ProductionMenu = $ProductionMenu

# Injected by setup()
var _city: CityInventory
var _train: TrainInventory
var _train_view: HorizontalTrain
var _resources: TradeResourceManager
var _wagons: TradeWagonManager
var _units: TradeUnitManager


func _ready() -> void:
    # What the player presses goes up as a request
    buy_menu.buy_requested.connect(buy_requested.emit)
    buy_menu.buy_wagon_requested.connect(buy_wagon_requested.emit)
    buy_menu.recruit_requested.connect(recruit_requested.emit)
    sell_menu.sell_requested.connect(sell_from_wagon_requested.emit)
    sell_menu.sell_wagon_requested.connect(sell_wagon_requested.emit)
    production_menu.produce_requested.connect(produce_requested.emit)
    GameState.money_changed.connect(_on_money_changed)


# Call once, before the scene starts to use the menus. The inventories are only READ here.
func setup(city: CityInventory, train: TrainInventory, train_view: HorizontalTrain,
        resources: TradeResourceManager, wagons: TradeWagonManager, units: TradeUnitManager) -> void:
    _city = city
    _train = train
    _train_view = train_view
    _resources = resources
    _wagons = wagons
    _units = units

    _city.city_resource_amount_changed.connect(_on_city_resource_amount_changed)
    _city.city_wagon_amount_changed.connect(_on_city_wagon_amount_changed)
    _city.city_recruit_amount_changed.connect(_on_city_recruit_amount_changed)
    _city.city_prices_changed.connect(_on_city_prices_changed)
    _train.wagon_resource_amount_changed.connect(_on_wagon_resource_amount_changed)
    _train.unit_added.connect(_on_unit_added)
    _train.wagon_removed.connect(_on_wagon_indices_changed)
    _train.wagon_moved.connect(_on_wagon_indices_changed)


func close_all() -> void:
    buy_menu.close()
    sell_menu.close()
    production_menu.close()


#region opening (tapping the open one again closes it; only one menu is open at a time)
func toggle_resource(resource_name: String) -> void:
    production_menu.close()
    if buy_menu.visible and buy_menu.current_resource == resource_name:
        buy_menu.close()
        return
    sell_menu.close()
    var node := _resources.get_resource(resource_name)
    buy_menu.show_resource(
        resource_name,
        node.get_icon() if node != null else null,
        _city.get_available_qty(resource_name),
        _city.get_buy_price(resource_name))
    _refresh_buy_menu()


# A wagon of the player's train: the sell menu
func toggle_player_wagon(wagon: GenericWagon) -> void:
    production_menu.close()
    var index := _train_view.wagons.find(wagon)
    if index < 0:
        return
    if sell_menu.visible and sell_menu.current_wagon == index:
        sell_menu.close()
        return

    var wagon_type := _train.get_wagon_type(index)
    var resource_name := _train.get_wagon_current_resource(index)
    var sells_cargo := resource_name != "" and _city.can_player_sell(resource_name)
    if not sells_cargo and not TradeService.can_sell_wagon(_city, _train, index):
        refused.emit("The city doesn't buy anything from this wagon.")
        return

    buy_menu.close()
    if sells_cargo:
        var node := _resources.get_resource(resource_name)
        sell_menu.show_wagon(
            index,
            resource_name,
            node.get_icon() if node != null else null,
            _train.get_wagon_resource_qty(index),
            _city.get_sell_price(resource_name))
    else:
        sell_menu.show_empty_wagon(index, wagon_type, wagon.get_icon())
    _refresh_sell_menu()


# A wagon the city sells
func toggle_city_wagon(wagon_type: String) -> void:
    production_menu.close()
    if buy_menu.visible and buy_menu.current_wagon_type == wagon_type:
        buy_menu.close()
        return
    sell_menu.close()
    var wagon := _wagons.get_wagon(wagon_type)
    buy_menu.show_wagon(
        wagon_type,
        wagon.get_icon() if wagon != null else null,
        _city.get_wagon_available_qty(wagon_type),
        _city.get_wagon_buy_price(wagon_type))
    _refresh_buy_menu()


# A soldier the city recruits
func toggle_city_unit(unit_type: String) -> void:
    production_menu.close()
    if buy_menu.visible and buy_menu.current_unit_type == unit_type:
        buy_menu.close()
        return
    sell_menu.close()
    var unit := _units.get_unit(unit_type)
    buy_menu.show_unit(
        unit_type,
        unit.get_icon() if unit != null else null,
        _city.get_recruit_qty(unit_type),
        _city.get_recruit_price(unit_type))
    _refresh_buy_menu()


# The building of the place (an industry)
func toggle_production() -> void:
    if production_menu.visible:
        production_menu.close()
        return
    buy_menu.close()
    sell_menu.close()
    production_menu.show_recipes(_city.city_name, _city.get_recipes(), _recipe_batches())
#endregion


#region keeping the open menu in sync with the inventories
func _on_city_resource_amount_changed(_resource_name: String, _qty: int) -> void:
    _refresh_buy_menu()
    _refresh_sell_menu()
    _refresh_production_menu()


# The economy changed a price: what the open menus show (and what can be afforded) follows
func _on_city_prices_changed(_resource_name: String) -> void:
    _refresh_buy_menu()
    _refresh_sell_menu()


func _on_wagon_resource_amount_changed(_wagon_index: int, _resource_name: String, _qty: int) -> void:
    _refresh_buy_menu()
    _refresh_sell_menu()


# The last wagon of a type was bought: it leaves the city, so its menu closes
func _on_city_wagon_amount_changed(wagon_type: String, qty: int) -> void:
    if qty == 0 and buy_menu.current_wagon_type == wagon_type:
        buy_menu.close()
    else:
        _refresh_buy_menu()


func _on_city_recruit_amount_changed(unit_type: String, qty: int) -> void:
    if qty == 0 and buy_menu.current_unit_type == unit_type:
        buy_menu.close()
    else:
        _refresh_buy_menu()


# The barracks has one soldier more and fewer places: the button may have to be disabled
func _on_unit_added(_wagon_index: int, _unit_id: String) -> void:
    _refresh_buy_menu()


# The indices after the wagon changed, so an open menu would point at the wrong wagon
func _on_wagon_indices_changed(_from_index: int, _to_index := 0) -> void:
    sell_menu.close()


func _on_money_changed(_money: int) -> void:
    _refresh_buy_menu()


func _refresh_buy_menu() -> void:
    if _city == null:
        return
    if buy_menu.current_unit_type != "":
        var unit_type := buy_menu.current_unit_type
        buy_menu.set_qty(_city.get_recruit_qty(unit_type))
        buy_menu.set_can_buy(TradeService.can_recruit(_city, _train, unit_type))
        return

    if buy_menu.current_wagon_type != "":
        var wagon_type := buy_menu.current_wagon_type
        buy_menu.set_qty(_city.get_wagon_available_qty(wagon_type))
        buy_menu.set_can_buy(TradeService.can_buy_wagon(_city, wagon_type))
        return

    var resource_name := buy_menu.current_resource
    if resource_name == "":
        return
    buy_menu.set_qty(_city.get_available_qty(resource_name))
    buy_menu.set_price(_city.get_buy_price(resource_name)) # the economy may have changed it
    buy_menu.set_can_buy(TradeService.max_buyable(_city, _train, resource_name) > 0)


func _refresh_sell_menu() -> void:
    if _city == null:
        return
    var index := sell_menu.current_wagon
    if index < 0:
        return
    var wagon_type := _train.get_wagon_type(index)
    var can_sell_wagon := TradeService.can_sell_wagon(_city, _train, index)
    sell_menu.set_wagon_offer(_city.get_wagon_sell_price(wagon_type) if can_sell_wagon else -1)

    var qty := _train.get_wagon_resource_qty(index)
    if qty > 0:
        sell_menu.set_qty(qty)
        sell_menu.set_price(_city.get_sell_price(_train.get_wagon_current_resource(index)))
        sell_menu.set_can_sell(TradeService.max_sellable_from_wagon(_city, _train, index) > 0)
    elif can_sell_wagon:
        # emptied: only the wagon itself can be sold now
        sell_menu.show_empty_wagon(index, wagon_type, _train_view.wagons[index].get_icon())
    else:
        sell_menu.close()


func _refresh_production_menu() -> void:
    if production_menu.visible:
        production_menu.set_batches(_recipe_batches())


# What each recipe can do right now, in the order of the recipes
func _recipe_batches() -> Array[int]:
    var result: Array[int] = []
    for i in _city.get_recipes().size():
        result.append(_city.get_max_batches(i))
    return result
#endregion
