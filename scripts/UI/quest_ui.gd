extends CanvasLayer
# Quest list and notifications. Meant to be an AUTOLOAD scene (Project Settings > Globals > Autoload,
# registered after QuestManager), so it is on screen in every scene.
# Don't give this script a class_name: it would clash with the autoload's name.
#
# It only shows what QuestManager holds. The one thing it asks of it is dismiss_completed().

const TITLE_SIZE := 13
const TEXT_SIZE := 10
const OBJECTIVE_SIZE := 11

# If these show as empty boxes on the device, the font lacks the glyphs: use "[x]" and "[ ]"
const CHECK_DONE := "☑"
const CHECK_TODO := "☐"
const TICK := "✓ "

const COLOR_MAIN := Color(0.95, 0.75, 0.2) # gold
const COLOR_SIDE := Color(0.3, 0.65, 0.9) # cyan
const COLOR_TEXT := Color(0.7, 0.7, 0.7)
const COLOR_TODO := Color(0.9, 0.9, 0.9)
const COLOR_TODO_BOX := Color(0.6, 0.6, 0.6)
const COLOR_DONE := Color(0.5, 0.8, 0.5, 0.8)
const COLOR_DONE_BOX := Color(0.2, 0.8, 0.3)
const COLOR_COMPLETED_TITLE := Color(0.5, 0.8, 0.5)
const COLOR_COMPLETED_TEXT := Color(0.5, 0.5, 0.5)
const COLOR_NOTIF_DONE := Color(0.12, 0.45, 0.22, 0.9) # green: completed
const COLOR_NOTIF_NEW := Color(0.75, 0.55, 0.1, 0.9) # gold: accepted

const DIALOG_SCENE: PackedScene = preload("res://scenes/menus/dialog_menu.tscn")

@onready var quest_list: Control = $Control/VBoxContainer/ScrollContainer/QuestList
@onready var notif_panel: ColorRect = $Notification/NotifPanel
@onready var notif_label: Label = $Notification/NotifPanel/NotifLabel

var _refresh_pending := false
var _notifications: Array[Dictionary] = [] # waiting to be shown: {message, is_completion}
var _showing := false
var _dialog: DialogMenu
var _dialog_queue: Array[Dictionary] = [] # {quest, is_intro}
var _dialog_running := false

func _ready() -> void:
    notif_panel.visible = false
    # quests_updated follows every change (accept, progress, complete), so it is the only refresh trigger
    process_mode = Node.PROCESS_MODE_ALWAYS # the dialogs and notifications keep working while the game is paused
    _dialog = DIALOG_SCENE.instantiate() as DialogMenu
    add_child(_dialog)
    _dialog.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE, 24)
    _dialog.grow_vertical = Control.GROW_DIRECTION_BEGIN # a taller dialog grows upward, not below the screen
    #_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT) # TEST: covers the whole screen
    QuestManager.quest_offered.connect(func(quest: Quest) -> void: _enqueue_dialog(quest, true))
    QuestManager.quest_outro_requested.connect(func(quest: Quest) -> void: _enqueue_dialog(quest, false))
    QuestManager.quests_updated.connect(_request_refresh)
    QuestManager.quest_accepted.connect(_on_quest_accepted)
    QuestManager.quest_completed.connect(_on_quest_completed)
    
    refresh_ui()

func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed:
        print("paused=", get_tree().paused, "  hovered=", get_viewport().gui_get_hovered_control())

func _debug_dialog() -> void:
    print("DIALOG visible=", _dialog.visible, " script=", _dialog.get_script().resource_path)
    _dialog.print_tree_pretty()

#region list
# Several signals can arrive in the same frame, so the list is rebuilt once
func _request_refresh() -> void:
    if _refresh_pending:
        return
    _refresh_pending = true
    refresh_ui.call_deferred()


func refresh_ui() -> void:
    _refresh_pending = false
    for child in quest_list.get_children():
        child.queue_free()

    var shown := 0
    for quest: Quest in QuestManager.active_quests.values():
        quest_list.add_child(_build_active_quest(quest))
        shown += 1

    var completed_shown := 0
    for quest_id in QuestManager.completed_quests:
        if QuestManager.dismissed_quests.has(quest_id):
            continue
        var data: Dictionary = QuestManager.quest_database.get(quest_id, {})
        if data.is_empty():
            continue # no longer in quests.json
        quest_list.add_child(_build_completed_quest(data))
        completed_shown += 1

    if shown + completed_shown == 0:
        var empty := _make_label("No active quests.", Color(0.5, 0.5, 0.5), TEXT_SIZE + 1, false)
        empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        quest_list.add_child(empty)
        return

    if completed_shown > 0:
        var clear_button := Button.new()
        clear_button.text = "Clear Completed"
        clear_button.add_theme_font_size_override("font_size", 11)
        clear_button.pressed.connect(QuestManager.dismiss_completed)
        quest_list.add_child(clear_button)


func _build_active_quest(quest: Quest) -> VBoxContainer:
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 4)
    box.add_child(_make_label(quest.title, COLOR_MAIN if quest.is_main_quest else COLOR_SIDE, TITLE_SIZE))
    box.add_child(_make_label(quest.description, COLOR_TEXT, TEXT_SIZE))

    var spacer := Control.new()
    spacer.custom_minimum_size = Vector2(0, 2)
    box.add_child(spacer)

    for objective in quest.objectives:
        box.add_child(_build_objective(objective))
    box.add_child(_make_separator())
    return box


func _build_objective(objective: QuestObjective) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 6)

    var done := objective.is_completed
    row.add_child(_make_label(CHECK_DONE if done else CHECK_TODO, COLOR_DONE_BOX if done else COLOR_TODO_BOX, OBJECTIVE_SIZE, false))

    var text := objective.description
    if _shows_progress(objective) and not done:
        text += " (%d/%d)" % [objective.current_qty, objective.target_qty]
    var label := _make_label(text, COLOR_DONE if done else COLOR_TODO, TEXT_SIZE)
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(label)
    return row


# A completed quest is shown from its database entry (the manager only keeps its id)
func _build_completed_quest(data: Dictionary) -> VBoxContainer:
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 4)
    box.add_child(_make_label(TICK + str(data.get("title", "Untitled Quest")), COLOR_COMPLETED_TITLE, TITLE_SIZE))
    box.add_child(_make_label(str(data.get("description", "")), COLOR_COMPLETED_TEXT, TEXT_SIZE))
    box.add_child(_make_separator())
    return box


func _shows_progress(objective: QuestObjective) -> bool:
    return objective.type in [QuestObjective.TYPE_DELIVER_GOODS, QuestObjective.TYPE_COLLECT_GOODS, QuestObjective.TYPE_EARN_MONEY]


func _make_label(text: String, color: Color, size: int, wrap_ := true) -> Label:
    var label := Label.new()
    label.text = text
    if wrap_:
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.add_theme_color_override("font_color", color)
    label.add_theme_font_size_override("font_size", size)
    return label


func _make_separator() -> HSeparator:
    var separator := HSeparator.new()
    separator.modulate = Color(1, 1, 1, 0.15)
    return separator
#endregion


#region notifications
func _on_quest_accepted(quest: Quest) -> void:
    _queue_notification("Accepted Quest:\n" + quest.title, false)


func _on_quest_completed(quest: Quest) -> void:
    _queue_notification("Quest Completed:\n" + quest.title, true)


# They are shown one after another: finishing a quest usually accepts the next one right away
func _queue_notification(message: String, is_completion: bool) -> void:
    _notifications.append({"message": message, "is_completion": is_completion})
    if not _showing:
        _show_next_notification()


func _show_next_notification() -> void:
    if _notifications.is_empty():
        _showing = false
        return
    _showing = true

    var item: Dictionary = _notifications.pop_front()
    notif_label.text = item["message"]
    notif_panel.color = COLOR_NOTIF_DONE if item["is_completion"] else COLOR_NOTIF_NEW
    notif_panel.modulate.a = 0.0
    notif_panel.visible = true

    var tween := create_tween()
    tween.tween_property(notif_panel, "modulate:a", 1.0, 0.3)
    tween.tween_interval(2.5)
    tween.tween_property(notif_panel, "modulate:a", 0.0, 0.5)
    tween.tween_callback(_on_notification_finished)


func _on_notification_finished() -> void:
    notif_panel.visible = false
    _show_next_notification()
#endregion

#region quest dialogs
# They are shown one after another, and the game is paused while they are open
func _enqueue_dialog(quest: Quest, is_intro: bool) -> void:
    _dialog_queue.append({"quest": quest, "is_intro": is_intro})
    if not _dialog_running:
        _run_dialogs()


func _run_dialogs() -> void:
    _dialog_running = true
    while not _dialog_queue.is_empty():
        while not visible: # the main menu hides this layer: wait until the game shows it
            await visibility_changed
        var item: Dictionary = _dialog_queue.pop_front()
        var quest: Quest = item["quest"]
        get_tree().paused = true
        if item["is_intro"]:
            await _show_intro(quest)
        else:
            await _show_outro(quest)

    get_tree().paused = false
    _dialog_running = false


func _show_intro(quest: Quest) -> void:
    _debug_dialog.call_deferred()
    if not QuestManager.offered_quests.has(quest.id):
        return # it was accepted or completed while it was waiting
    var choices := _choices_of(quest.intro)
    var chosen: String = await _dialog.ask(
            str(quest.intro.get("text", "")), choices, Characters.portrait(str(quest.intro.get("character", ""))))
    for choice in choices:
        if str(choice.get("id", choice.get("text", ""))) == chosen and bool(choice.get("accept", false)):
            QuestManager.accept_quest(quest.id)
            return


func _show_outro(quest: Quest) -> void:
    await _dialog.ask(
            str(quest.outro.get("text", "")), _choices_of(quest.outro), Characters.portrait(str(quest.outro.get("character", ""))))


# The choices of the data, or a single OK button if it has none
func _choices_of(dialog: Dictionary) -> Array:
    var choices: Array = dialog.get("choices", [])
    return choices if not choices.is_empty() else [ {"id": "ok", "text": "OK", "accept": true}]
#endregion
