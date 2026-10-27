extends CanvasLayer
class_name LoadingScreen
# A full screen cover with a title, a progress bar and the name of the current step. It is only a
# VIEW: whoever loads says how far it is.
#
# While a script is busy the window can't redraw, so report() waits until the frame is drawn.
# Call it BETWEEN the steps, with `await`:
#   loading_screen.begin("Loading map...")
#   await loading_screen.report(0.2, "Reading the map...")
#   ... one heavy step ...
#   await loading_screen.report(0.6, "Building the rails...")
#   loading_screen.finish()
#
# Scene structure (loading_screen.tscn). Layer 100, Process Mode = Always:
#   LoadingScreen (CanvasLayer, this script)
#   |- Dim (ColorRect, Full Rect, opaque, Mouse Filter = Stop)
#   `- CenterContainer (Full Rect)
#      `- VBoxContainer
#         |- TitleLabel (Label)
#         |- ProgressBar
#         `- StatusLabel (Label)

@export var print_times := true # print how long each step took (to find what is slow)

@onready var title_label: Label = $CenterContainer/VBoxContainer/TitleLabel
@onready var bar: ProgressBar = $CenterContainer/VBoxContainer/ProgressBar
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel

var _start_ms := 0
var _steps: Array[Dictionary] = [] # [{name, ms}] in the order the steps first appeared
var _step_index := {} # step name -> index in _steps
var _current := "" # the step that is running now
var _current_start := 0


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    bar.min_value = 0.0
    bar.max_value = 1.0
    hide()

func begin(title := "Loading...") -> void:
    title_label.text = title
    status_label.text = ""
    bar.value = 0.0
    _steps.clear()
    _step_index.clear()
    _current = ""
    _start_ms = Time.get_ticks_msec()
    _current_start = _start_ms
    show()


# `fraction` goes from 0.0 to 1.0. Waits until the screen has been drawn.
# `text` names the step that STARTS now. The time until the next different `text` counts for it.
# A step that reports several times with the same text is one step.
func report(fraction: float, text := "") -> void:
    bar.value = clampf(fraction, 0.0, 1.0)
    if text != "":
        status_label.text = text
        if text != _current:
            _close_step()
            _current = text
            _current_start = Time.get_ticks_msec()
    await RenderingServer.frame_post_draw


func finish() -> void:
    _close_step()
    _current = ""
    if print_times:
        _print_stats()
    hide()


# Adds the time since the step started to its total (a step can come back more than once)
func _close_step() -> void:
    if _current == "":
        return
    var ms := Time.get_ticks_msec() - _current_start
    if _step_index.has(_current):
        _steps[_step_index[_current]]["ms"] += ms
    else:
        _step_index[_current] = _steps.size()
        _steps.append({"name": _current, "ms": ms})


func _print_stats() -> void:
    var total := maxi(Time.get_ticks_msec() - _start_ms, 1)
    var counted := 0
    print("---- Loading times ----")
    for step in _steps:
        var ms: int = step["ms"]
        var percent := 100.0 * ms / total
        counted += ms
        print("%s %6d ms  %5.1f%%  %s" % [String(step["name"]).rpad(30), ms, percent, "#".repeat(roundi(percent / 2.0))])
    var other := total - counted
    if other > 0:
        print("%s %6d ms  %5.1f%%" % ["(not in a step)".rpad(30), other, 100.0 * other / total])
    print("%s %6d ms" % ["TOTAL".rpad(30), total])