extends CanvasLayer
# class_name GameMenu
# The menu of a running game: a button in the top right corner opens it, and the game is paused
# while it is open. Continue, Save game, Load game, Settings, Exit game.
# It is only a VIEW for loading: it asks MainScene to load a slot (load_requested), because loading
# means building the scenes of the game again. Saving it does itself, through GameState.
#
# Scene structure (game_menu.tscn). Layer 50, Process Mode = Always:
#   GameMenu (CanvasLayer, this script)
#   `- Overlay (Control, Full Rect)
#      |- Dim (ColorRect, Full Rect)       dark, half transparent
#      |- CenterContainer (Full Rect)
#      |  `- ButtonsBox (VBoxContainer)
#      |     |- ContinueButton, SaveButton, LoadButton, SettingsButton, ExitButton
#      |     `- MessageLabel (Label)
#      `- SlotsMenu (instance of slots_menu.tscn, Full Rect)

signal load_requested(slot: int)

@onready var overlay: Control = $Overlay
@onready var buttons_box: VBoxContainer = $Overlay/CenterContainer/ButtonsBox
@onready var continue_button: Button = $Overlay/CenterContainer/ButtonsBox/ContinueButton
@onready var save_button: Button = $Overlay/CenterContainer/ButtonsBox/SaveButton
@onready var load_button: Button = $Overlay/CenterContainer/ButtonsBox/LoadButton
@onready var settings_button: Button = $Overlay/CenterContainer/ButtonsBox/SettingsButton
@onready var exit_button: Button = $Overlay/CenterContainer/ButtonsBox/ExitButton
@onready var message_label: Label = $Overlay/CenterContainer/ButtonsBox/MessageLabel
@onready var slots_menu: SlotsMenu = $Overlay/SlotsMenu

var _was_paused := false # whether the game was already paused when the menu opened (a dialog, for example)


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS # it must keep working while the game is paused
    overlay.hide()
    continue_button.pressed.connect(close_menu)
    save_button.pressed.connect(_on_save_pressed)
    load_button.pressed.connect(_on_load_pressed)
    settings_button.pressed.connect(_on_settings_pressed)
    exit_button.pressed.connect(_on_exit_pressed)
    slots_menu.slot_chosen.connect(_on_slot_chosen)
    slots_menu.closed.connect(_on_slots_closed)


#region open and close
func open_menu() -> void:
    if overlay.visible:
        return
    _was_paused = get_tree().paused
    get_tree().paused = true
    message_label.text = ""
    buttons_box.show()
    overlay.show()


# `force_unpause`: the game goes on whatever it was doing before (after a load, the old game is gone)
func close_menu(force_unpause := false) -> void:
    if not overlay.visible:
        return
    slots_menu.hide()
    overlay.hide()
    get_tree().paused = false if force_unpause else _was_paused


# A text under the buttons, e.g. "Game saved in slot 2."
func show_message(text: String) -> void:
    message_label.text = text


# Escape on the keyboard
func _unhandled_input(event: InputEvent) -> void:
    if visible and event.is_action_pressed("ui_cancel"):
        get_viewport().set_input_as_handled()
        _back_or_toggle()


# The Back button of Android (also needs Project Settings > Application > Config > Quit On Go Back = off)
func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:
        _back_or_toggle()


func _back_or_toggle() -> void:
    if slots_menu.visible:
        slots_menu.close()
    elif overlay.visible:
        close_menu()
    else:
        open_menu()
#endregion


#region buttons
func _on_save_pressed() -> void:
    buttons_box.hide()
    slots_menu.open(SlotsMenu.Mode.SAVE)


func _on_load_pressed() -> void:
    buttons_box.hide()
    slots_menu.open(SlotsMenu.Mode.LOAD)


func _on_settings_pressed() -> void:
    show_message("Settings are not available yet.")


func _on_exit_pressed() -> void:
    get_tree().quit()


func _on_slot_chosen(slot: int) -> void:
    match slots_menu.mode:
        SlotsMenu.Mode.SAVE:
            var saved := GameState.save_game(slot)
            slots_menu.close() # shows the buttons again
            if saved:
                message_label.text = "Game saved in slot %d." % slot
            else:
                message_label.text = "Could not save the game (see the Debugger)."
        SlotsMenu.Mode.LOAD:
            load_requested.emit(slot) # MainScene loads it, and closes this menu if it worked


func _on_slots_closed() -> void:
    buttons_box.show()
#endregion
