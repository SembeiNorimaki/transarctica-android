extends CanvasLayer
class_name TradeHUD
# The HUD of the city scene. It collects the signals of its parts and relays them to TradeScene.

signal quests_pressed
signal menu_pressed
signal reverse_pressed # left button
signal gear_pressed # right button

@onready var top_bar: TopBar = $UI/TopBar
@onready var bottom_bar: BottomBar = $UI/BottomBar
@onready var trade_ui: TradeUI = $UI/TradeUI
@onready var exit_button: Button = $UI/ExitButton


func _ready() -> void:
    top_bar.quests_pressed.connect(quests_pressed.emit)
    top_bar.menu_pressed.connect(menu_pressed.emit)
    bottom_bar.left_pressed.connect(reverse_pressed.emit)
    bottom_bar.right_pressed.connect(gear_pressed.emit)
