extends Control
class_name EventPopup
# A modal message for the navigation scene: a title, a text, and one or two buttons. It is only a
# VIEW: it shows what it is told and emits accepted or declined. It builds itself in code, so it
# needs no scene: EventPopup.new(), then add it to a CanvasLayer.
#
# While it is open it covers the screen and blocks the clicks to the map and the HUD behind it.

signal accepted
signal declined

const TEXT_WIDTH := 900.0

var _title_label: Label
var _text_label: Label
var _accept_button: Button
var _decline_button: Button


func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP
    hide()

    var dim := ColorRect.new()
    dim.color = Color(0, 0, 0, 0.55)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(dim)
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var center := CenterContainer.new()
    add_child(center)
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var panel := PanelContainer.new()
    center.add_child(panel)

    var margin := MarginContainer.new()
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 32)
    panel.add_child(margin)

    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 24)
    margin.add_child(box)

    _title_label = Label.new()
    _title_label.add_theme_font_size_override("font_size", 48)
    _title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(_title_label)

    _text_label = Label.new()
    _text_label.add_theme_font_size_override("font_size", 32)
    _text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _text_label.custom_minimum_size = Vector2(TEXT_WIDTH, 0.0)
    box.add_child(_text_label)

    var buttons := HBoxContainer.new()
    buttons.alignment = BoxContainer.ALIGNMENT_CENTER
    buttons.add_theme_constant_override("separation", 48)
    box.add_child(buttons)

    _accept_button = _make_button(buttons)
    _accept_button.pressed.connect(_on_accept_pressed)
    _decline_button = _make_button(buttons)
    _decline_button.pressed.connect(_on_decline_pressed)


func _make_button(parent: Control) -> Button:
    var button := Button.new()
    button.add_theme_font_size_override("font_size", 32)
    button.custom_minimum_size = Vector2(280, 90)
    parent.add_child(button)
    return button


# `decline_text` empty: only the accept button is shown.
# `can_accept` false: the accept button is there but disabled (e.g. not enough money).
func show_event(title: String, text: String, accept_text: String, can_accept := true, decline_text := "") -> void:
    _title_label.text = title
    _text_label.text = text
    _accept_button.text = accept_text
    _accept_button.disabled = not can_accept
    _decline_button.text = decline_text
    _decline_button.visible = not decline_text.is_empty()
    show()


func _on_accept_pressed() -> void:
    hide()
    accepted.emit()


func _on_decline_pressed() -> void:
    hide()
    declined.emit()
