extends Control
class_name SlotsMenu
# The four save slots. Each button shows what is in its slot. It has three modes:
#   LOAD:     only slots with a save can be chosen
#   SAVE:     every slot can be chosen (to save the game in it, overwriting what was there)
#   NEW_GAME: every slot can be chosen (to start a new game in it, overwriting what was there)
# It only emits the chosen slot: whoever opened it decides what to do with it.

signal slot_chosen(slot: int)
signal closed

enum Mode {LOAD, NEW_GAME, SAVE}

@onready var slot_buttons: Array[Button] = [
    $VBoxContainer/Slot1Button,
    $VBoxContainer/Slot2Button,
    $VBoxContainer/Slot3Button,
    $VBoxContainer/Slot4Button]
@onready var back_button: Button = $VBoxContainer/BackButton
@onready var title_label: Label = get_node_or_null("%Title")

var mode := Mode.LOAD


func _ready() -> void:
    for i in slot_buttons.size():
        slot_buttons[i].pressed.connect(_on_slot_pressed.bind(i + 1))
    if back_button != null:
        back_button.pressed.connect(close)
    hide()


func open(new_mode := Mode.LOAD) -> void:
    mode = new_mode
    if title_label != null:
        match mode:
            Mode.LOAD:
                title_label.text = "Load game"
            Mode.SAVE:
                title_label.text = "Save game (the slot will be overwritten)"
            Mode.NEW_GAME:
                title_label.text = "Choose a slot (it will be overwritten)"
    refresh()
    show()


func close() -> void:
    hide()
    closed.emit()


# Shows what each slot holds
func refresh() -> void:
    for i in slot_buttons.size():
        var slot := i + 1
        var info = GameState.get_slot_info(slot)
        slot_buttons[i].text = _describe(slot, info)
        # Loading needs a valid save. A new game can go in any slot.
        slot_buttons[i].disabled = mode == Mode.LOAD and not (info.get("exists", false) and info.get("valid", false))


func _describe(slot: int, info: Dictionary) -> String:
    if not info.get("exists", false):
        return "Slot %d: empty" % slot
    if not info.get("valid", false):
        return "Slot %d: damaged" % slot
    var saved_at := str(info.get("saved_at", "")).replace("T", " ").left(16) # "2026-11-02 18:40"
    return "Slot %d: %s, money %d" % [slot, saved_at, info.get("money", 0)]


func _on_slot_pressed(slot: int) -> void:
    slot_chosen.emit(slot)
