extends Control
class_name MainMenu
# The first screen. It only asks the player what to do and emits it: MainScene decides what
# happens next. The SlotsMenu is a child of this scene (hidden until it is opened).
#
# The child nodes are found by unique name ("Access as Unique Name", the % icon).

signal new_game_requested(slot: int)
signal load_game_requested(slot: int)
## A debug button: the scene to run on its own. "trade", "combat1" (turn based test map) or "combat2" (square map).
signal debug_scene_requested(scene_id: String)

@onready var buttons_box: VBoxContainer = $VBoxContainer
@onready var new_game_button: Button = $VBoxContainer/NewGameButton
@onready var load_game_button: Button = $VBoxContainer/LoadGameButton

@onready var debug_trade_button: Button = $VBoxContainer/DebugTradeButton
@onready var debug_combat1_button: Button = $VBoxContainer/DebugCombat1Button
@onready var debug_combat2_button: Button = $VBoxContainer/DebugCombat2Button

@onready var slots_menu: SlotsMenu = $SlotsMenu
# Optional: a Label named MessageLabel, for errors
@onready var message_label: Label = get_node_or_null("%MessageLabel")


func _ready() -> void:
    new_game_button.pressed.connect(_on_new_game_pressed)
    load_game_button.pressed.connect(_on_load_game_pressed)
    debug_trade_button.pressed.connect(debug_scene_requested.emit.bind("trade"))
    debug_combat1_button.pressed.connect(debug_scene_requested.emit.bind("combat1"))
    debug_combat2_button.pressed.connect(debug_scene_requested.emit.bind("combat2"))
    slots_menu.slot_chosen.connect(_on_slot_chosen)
    slots_menu.closed.connect(_on_slots_closed)
    if message_label != null:
        message_label.text = ""
    _refresh()


# Loading needs at least one save
func _refresh() -> void:
    var any_save := false
    for slot in range(1, GameState.SLOT_COUNT + 1):
        any_save = any_save or GameState.has_save(slot)
    load_game_button.disabled = not any_save


func show_message(text: String) -> void:
    if message_label != null:
        message_label.text = text
    else:
        print(text)

func _on_slots_closed() -> void:
    buttons_box.show()
    _refresh()

# A new game goes into the first empty slot. If all of them are used, the player picks one to overwrite.
# (The old save stays on disk until the new game is saved over it.)
func _on_new_game_pressed() -> void:
    buttons_box.hide()
    slots_menu.open(SlotsMenu.Mode.NEW_GAME)


func _on_load_game_pressed() -> void:
    buttons_box.hide()
    slots_menu.open(SlotsMenu.Mode.LOAD)


func _on_slot_chosen(slot: int) -> void:
    if slots_menu.mode == SlotsMenu.Mode.NEW_GAME:
        new_game_requested.emit(slot)
    else:
        load_game_requested.emit(slot)
