extends CanvasLayer
class_name NavigationHUD
# The fixed elements of the navigation screen. It is only a VIEW: it shows what it is told
# (set_fuel) or what GameState says (money), and emits a signal when the player presses something.
# NavigationScene decides what each press does.
#
# Scene structure (navigation_hud.tscn). Every container has Mouse Filter = Ignore, so a tap
# that is not on a button reaches the map:
#   NavigationHUD (CanvasLayer, this script)
#   `- Root (Control, Full Rect)
#      |- TopBar (MarginContainer, Top Wide)
#      |  `- HBoxContainer
#      |     |- FuelBar (ProgressBar) with FuelLabel (Label, Full Rect) inside
#      |     |- MoneyLabel (Label)
#      |     |- Spacer (Control, Expand)
#      |     |- QuestsButton, GameMenuButton
#      |- BottomBar (MarginContainer, Bottom Wide)
#      |  `- HBoxContainer: ButtonLeft, Spacer (Expand), ButtonRight
#      `- EventPopup (Control, event_popup.gd)   last, so it is drawn over everything

signal reverse_pressed # left button
signal gear_pressed # right button
signal quests_pressed
signal menu_pressed

@onready var fuel_bar: ProgressBar = $Root/TopBar/HBoxContainer/FuelBar
@onready var fuel_label: Label = $Root/TopBar/HBoxContainer/FuelBar/FuelLabel
@onready var money_label: Label = $Root/TopBar/HBoxContainer/MoneyLabel
@onready var quests_button: Button = $Root/TopBar/HBoxContainer/QuestsButton
@onready var menu_button: Button = $Root/TopBar/HBoxContainer/GameMenuButton
@onready var button_left: Button = $Root/BottomBar/HBoxContainer/ButtonLeft
@onready var button_right: Button = $Root/BottomBar/HBoxContainer/ButtonRight
@onready var event_popup: EventPopup = $Root/EventPopup

# One image with two frames side by side: the first is shown while the train is stopped, the
# second while it is driving. Swap the two images in the file if it looks the wrong way round.
@export var gear_atlas: Texture2D

var _icon_neutral: AtlasTexture
var _icon_drive: AtlasTexture

func _ready() -> void:
    _make_gear_icons()
    set_driving(false)

    button_left.pressed.connect(reverse_pressed.emit)
    button_right.pressed.connect(gear_pressed.emit)
    quests_button.pressed.connect(quests_pressed.emit)
    menu_button.pressed.connect(menu_pressed.emit)

    GameState.money_changed.connect(set_money)
    set_money(GameState.get_money())


func set_fuel(current: int, maximum: int) -> void:
    fuel_bar.max_value = maxf(maximum, 1.0)
    fuel_bar.value = current
    fuel_label.text = "NO COAL" if current <= 0 else "%d / %d" % [current, maximum]
    fuel_bar.modulate = Color.RED if current * 5 < maximum else Color.WHITE # below 20%


func set_money(amount: int) -> void:
    money_label.text = "Money: %d" % amount

# Called when the player train changes gear (or is rebuilt)
func set_driving(driving: bool) -> void:
    if _icon_neutral == null:
        return
    button_right.icon = _icon_drive if driving else _icon_neutral

func _make_gear_icons() -> void:
    if gear_atlas == null:
        push_warning("NavigationHUD: gear_atlas is not set")
        return
    var frame := Vector2(gear_atlas.get_width() * 0.5, gear_atlas.get_height())
    _icon_neutral = _frame(Rect2(Vector2.ZERO, frame))
    _icon_drive = _frame(Rect2(Vector2(frame.x, 0.0), frame))


func _frame(region: Rect2) -> AtlasTexture:
    var icon := AtlasTexture.new()
    icon.atlas = gear_atlas
    icon.region = region
    return icon
