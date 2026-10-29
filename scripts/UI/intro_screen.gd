extends CanvasLayer
class_name IntroScreen
# A picture and a text that appears character by character. It is only a VIEW: it shows what it
# is told and says when it happens. A tap shows the rest of the text at once; a tap after that
# says the player is done (dismissed). Whoever shows it decides what to do then.
# It keeps working while the game is paused.

signal text_finished # all the text is visible (typed, or skipped by a tap)
signal dismissed # the player tapped when the text was already complete

@export var chars_per_second := 30.0 # 0 or less: all at once

@onready var picture: TextureRect = $Root/Picture
@onready var text_label: Label = $Root/Text

var _tween: Tween
var _finished := true
var _prompt: Label # a line at the bottom: "Loading..." / "Tap to continue"


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    $Root.gui_input.connect(_on_gui_input)
    _prompt = Label.new()
    _prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 48)
    _prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
    _prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
    _prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _prompt.add_theme_font_override("font", text_label.get_theme_font("font"))
    _prompt.add_theme_font_size_override("font_size", 36)
    _prompt.hide()
    $Root.add_child(_prompt)


# The line at the bottom of the screen. An empty text hides it.
func set_prompt(text: String) -> void:
    _prompt.text = text
    _prompt.visible = not text.is_empty()


# `image` can be null: only the black background
func play(text: String, image: Texture2D = null) -> void:
    picture.texture = image
    text_label.text = text
    _finished = false
    show()
    if chars_per_second <= 0.0 or text.is_empty():
        _finish()
        return
    text_label.visible_ratio = 0.0
    if _tween != null:
        _tween.kill()
    _tween = create_tween()
    _tween.tween_property(text_label, "visible_ratio", 1.0, text.length() / chars_per_second)
    _tween.finished.connect(_finish)


func is_finished() -> bool:
    return _finished


func _finish() -> void:
    if _finished:
        return
    _finished = true
    if _tween != null:
        _tween.kill()
        _tween = null
    text_label.visible_ratio = 1.0
    text_finished.emit()


func _on_gui_input(event: InputEvent) -> void:
    if not InputUtils.is_tap(event):
        return
    if _finished:
        dismissed.emit()
    else:
        _finish()
