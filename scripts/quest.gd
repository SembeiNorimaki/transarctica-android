extends RefCounted
class_name Quest
# A quest. Built by QuestManager from quests.json; the progress of its objectives is saved with the game.

var id := ""
var title := ""
var description := ""
var is_main_quest := false
var conditions := {} # when it is offered: {"city": name, "completed": [quest ids]}. Empty: at the start of a game
var rewards := {} # {"money": int, "wagon": wagon type}
var status := "active"
var objectives: Array[QuestObjective] = []
var intro := {} # dialog shown when the quest is offered: {character, text, choices}. Empty: none
var outro := {} # dialog shown when it is completed


func is_completed() -> bool:
    if objectives.is_empty():
        return false
    for objective in objectives:
        if not objective.is_completed:
            return false
    return true


# What changes while playing: {objective id: {current_qty, is_completed}}
func get_progress() -> Dictionary:
    var result := {}
    for objective in objectives:
        result[objective.id] = {"current_qty": objective.current_qty, "is_completed": objective.is_completed}
    return result


func apply_progress(progress: Dictionary) -> void:
    for objective in objectives:
        var data: Dictionary = progress.get(objective.id, {})
        objective.current_qty = int(data.get("current_qty", 0))
        objective.is_completed = bool(data.get("is_completed", false))