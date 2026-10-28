extends CanvasLayer
class_name IntroScreen
# A picture and a text that appears character by character. It is only a VIEW: it shows what it
# is told and says when the text is complete. A tap shows the rest of the text at once.

signal text_finished # all the text is visible (typed, or skipped by a tap)

@export var chars_per_second := 30.0 # 0 or less: all at once

@onready var picture: TextureRect = $Root/Picture
@onready var text_label: Label = $Root/Text

var _tween: Tween
var _finished := true


func _ready() -> void:
    $Root.gui_input.connect(_on_gui_input)


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
    if InputUtils.is_tap(event):
        _finish()
