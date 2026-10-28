extends CanvasLayer
class_name TradeHUD
# The HUD of the city scene. It collects the signals of its parts and relays them to TradeScene.

signal quests_pressed
signal menu_pressed

@onready var top_bar: TopBar = $UI/TopBar
@onready var bottom_bar: BottomBar = $UI/BottomBar
@onready var trade_ui: TradeUI = $UI/TradeUI
@onready var exit_button: Button = $UI/ExitButton


func _ready() -> void:
    top_bar.quests_pressed.connect(quests_pressed.emit)
    top_bar.menu_pressed.connect(menu_pressed.emit)
