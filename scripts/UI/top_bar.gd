extends MarginContainer
class_name TopBar
# The top bar of the HUDs: the date and time, fuel, money, and the quests and game menu buttons. It is only a VIEW.
# It reads the money and the coal by itself from GameState, so every HUD that has it shows them
# with no wiring. It emits a signal when a button is pressed; the HUD decides what that does.

signal quests_pressed
signal menu_pressed


@onready var date_label: Label = $HBoxContainer/DateLabel
@onready var fuel_label: Label = $HBoxContainer/FuelPanel/FuelLabel
@onready var money_label: Label = $HBoxContainer/MoneyPanel/MoneyLabel
@onready var quests_button: Button = $HBoxContainer/QuestsButton
@onready var menu_button: Button = $HBoxContainer/GameMenuButton


func _ready() -> void:
    quests_button.pressed.connect(quests_pressed.emit)
    menu_button.pressed.connect(menu_pressed.emit)
    GameState.money_changed.connect(_show_money)
    GameState.player_cargo_changed.connect(_show_fuel) # driving burns coal, trading buys it
    GameState.game_time_changed.connect(_show_time)
    GameState.game_loaded.connect(_refresh)
    _refresh()


func _refresh() -> void:
    _show_money(GameState.get_money())
    _show_fuel()
    _show_time(GameState.get_game_minutes())


func _show_time(minutes: int) -> void:
    date_label.text = GameCalendar.format(minutes)


func _show_money(amount: int) -> void:
    money_label.text = "%d" % amount


func _show_fuel() -> void:
    var fuel := FuelManager.read_fuel()
    fuel_label.text = "%d" % fuel.x
