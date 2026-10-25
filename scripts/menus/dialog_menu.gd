extends Control
class_name DialogMenu
# A message box for the player: a text, optionally the picture of whoever speaks, and optionally
# some choice buttons. It is only a VIEW: it shows what it is told and says what the player chose.
# It decides nothing, so it works for a character that talks, a notice, or a yes/no question.
#
# Scene structure (mark Portrait, Text and Buttons with "Access as Unique Name"):
#   DialogMenu (Control, this script)
#   |- Background (ColorRect, Full Rect, Mouse Filter = Ignore)
#   `- MarginContainer (Full Rect)
#      `- HBoxContainer
#         |- %Portrait (TextureRect)
#         `- VBoxContainer (Size Flags Horizontal = Fill + Expand)
#            |- %Text (RichTextLabel, Size Flags Vertical = Fill + Expand)
#            `- %Buttons (HBoxContainer)
#
# Use, from any script that holds the dialog:
#   await dialog.say("The bridge is closed.", comrad_face)             # no buttons: tap to close
#   var answer: String = await dialog.ask("Help us?", [
#           {"id": "yes", "text": "Accept"},
#           {"id": "no", "text": "Decline"}], comrad_face)
#   var only: String = await dialog.ask("Pay 100?", [{"id": "pay", "text": "Pay", "disabled": not can_pay}])
#
# `choices`: an Array. Each entry is a Dictionary {id, text, disabled?} or just a String (it is
# used as both id and text). Any number: none, one, two, more.

# The id of the pressed choice, or "" if the dialog closed without one (a tap on a dialog that has no choices)
signal closed(choice_id: String)

@export var chars_per_second := 40.0 # typing speed. 0 or less: the whole text appears at once
@export var hide_when_closed := true

@onready var _portrait: TextureRect = $MarginContainer/HBoxContainer/Portrait
@onready var _text: RichTextLabel = $MarginContainer/HBoxContainer/Text
@onready var _buttons: VBoxContainer = $MarginContainer/HBoxContainer/Buttons

var _tween: Tween # exists only while the text is being typed
var _choices: Array[Dictionary] = []
var _open := false


func _ready() -> void:
    _text.bbcode_enabled = true
    _text.scroll_active = false
    _text.mouse_filter = Control.MOUSE_FILTER_IGNORE # so a tap on the text reaches this node
    _portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hide()


#region api
# Shows a text and waits until the player taps it away.
func say(text: String, portrait: Texture2D = null, speed := -1.0) -> void:
    show_dialog(text, portrait, [], speed)
    await closed


# Shows a text with choices and returns the id of the one the player pressed.
func ask(text: String, choices: Array, portrait: Texture2D = null, speed := -1.0) -> String:
    show_dialog(text, portrait, choices, speed)
    return await closed


# The non-waiting version: use it when you prefer to connect to `closed` yourself.
# `portrait` null: no picture. `speed` below 0: use chars_per_second.
func show_dialog(text: String, portrait: Texture2D = null, choices: Array = [], speed := -1.0) -> void:
    if _open:
        _close("") # a new dialog replaces the one that was open

    _open = true
    _choices = _read_choices(choices)
    _portrait.texture = portrait
    _portrait.visible = portrait != null
    _clear_buttons()
    _text.text = text
    show()

    var cps := chars_per_second if speed < 0.0 else speed
    if cps <= 0.0 or text.is_empty():
        _finish_typing()
        return
    _text.visible_ratio = 0.0
    var count := maxi(_text.get_total_character_count(), 1) # BBCode tags don't count
    _tween = create_tween()
    _tween.tween_property(_text, "visible_ratio", 1.0, count / cps)
    _tween.finished.connect(_finish_typing)

    print("DIALOG shown: visible=", visible, " is_visible_in_tree=", is_visible_in_tree(),
        " global_rect=", get_global_rect(), " min_size=", get_combined_minimum_size(),
        " parent=", get_parent().name, " text_len=", _text.text.length(),
        " portrait_visible=", _portrait.visible)


func is_open() -> bool:
    return _open


# Closes it from the outside (e.g. the scene is changing). Emits closed with "".
func dismiss() -> void:
    _close("")
#endregion


#region internals
# A tap shows the rest of the text if it is still being typed; if it is all there and the dialog
# has no choices, the tap closes it. With choices, only a button closes it.
func _gui_input(event: InputEvent) -> void:
    if not _open:
        return
    var click := event as InputEventMouseButton # a touch also arrives as a mouse click
    if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
        return
    accept_event()
    if _tween != null:
        _finish_typing()
    elif _choices.is_empty():
        _close("")


# All the text is visible: the buttons appear now, so nobody answers before reading
func _finish_typing() -> void:
    if _tween != null:
        _tween.kill()
        _tween = null
    _text.visible_ratio = 1.0
    _build_buttons()


func _build_buttons() -> void:
    _clear_buttons()
    for choice in _choices:
        var button := Button.new()
        button.text = choice["text"]
        button.disabled = choice["disabled"]
        button.pressed.connect(_close.bind(choice["id"]))
        _buttons.add_child(button)


func _clear_buttons() -> void:
    for button in _buttons.get_children():
        _buttons.remove_child(button)
        button.queue_free()


func _close(choice_id: String) -> void:
    if not _open:
        return
    _open = false
    if _tween != null:
        _tween.kill()
        _tween = null
    _clear_buttons()
    if hide_when_closed:
        hide()
    closed.emit(choice_id)


func _read_choices(choices: Array) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for choice in choices:
        if choice is Dictionary:
            var text := str(choice.get("text", choice.get("id", "")))
            result.append({
                "id": str(choice.get("id", text)),
                "text": text,
                "disabled": bool(choice.get("disabled", false)),
            })
        else:
            result.append({"id": str(choice), "text": str(choice), "disabled": false})
    return result
#endregion
