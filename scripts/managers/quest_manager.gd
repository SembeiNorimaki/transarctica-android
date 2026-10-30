extends Node
# Autoload (register it AFTER GameState). Tracks the quests of the game: which are active,
# their progress, and which are done.
#
# Events come from the scenes (notify_*), and money from GameState's money_changed signal.
# Rewards go through GameState (add_money, add_wagon_to_player_train), whose signals keep
# any open scene up to date. Nothing here touches a scene.
# State is saved in GameState: written on game_saving, read on game_loaded.

signal quest_accepted(quest: Quest)
signal quest_objective_updated(quest: Quest, objective: QuestObjective)
signal quest_completed(quest: Quest)
signal quests_updated
signal quest_offered(quest: Quest) # its intro dialog should be shown
signal quest_outro_requested(quest: Quest) # its outro dialog should be shown

const QUESTS_FILE := "quests.json" # in the folder of the campaign being played (see Campaigns)
const QUESTS_ENABLED := true # false: no quest is offered (for debugging). The data and the saves are not touched.

var quest_database := {} # quest id -> data from quests.json
var active_quests := {} # quest id -> Quest
var completed_quests: Array[String] = []
var dismissed_quests: Array[String] = [] # completed quests the player cleared from the list (they stay in completed_quests)
var offered_quests: Array[String] = [] # offered, not accepted yet (the player has not said yes)

var _current_city := "" # the city the player is in right now ("" while navigating)
var _offers_held := false # true: nothing is offered yet (the intro of a new game is on screen)

func _ready() -> void:
    load_quest_database()
    GameState.money_changed.connect(_on_money_changed)
    GameState.game_saving.connect(_on_game_saving)
    GameState.game_loaded.connect(load_from_game_state)
    GameState.player_cargo_changed.connect(_refresh_train_objectives)

    if OS.is_debug_build():
        quest_objective_updated.connect(_print_progress)
        _validate_database.call_deferred() # deferred: GameState must have loaded its data
    _load_when_debugging.call_deferred()


#region database
# populates quest_database from the quests.json of the campaign being played
func load_quest_database() -> void:
    quest_database = {}
    var path := Campaigns.path(GameState.campaign_id, QUESTS_FILE)
    if not FileAccess.file_exists(path):
        push_warning("QuestManager: %s not found, there are no quests" % path)
        return
    var json = JSON.parse_string(FileAccess.get_file_as_string(path))
    if json is Dictionary:
        quest_database = json
    else:
        push_error("QuestManager: %s is not a valid JSON object" % path)

# Quests load when a game starts, because GameState emits game_loaded from the menu.
# Running a single scene for debugging (F6) has no menu, so load them here, unless the scene says
# it has no use for quests (a combat scene being tried on its own: skips_quests_when_debugging()).
func _load_when_debugging() -> void:
    var scene := get_tree().current_scene
    if scene != null and not scene.has_method("show_menu") and not scene.has_method("skips_quests_when_debugging"):
        load_from_game_state()
        
# Builds a quest from its database entry, without any progress. Null if it doesn't exist.
func _build_quest(quest_id: String) -> Quest:
    var data: Dictionary = quest_database.get(quest_id, {})
    if data.is_empty():
        return null

    var quest := Quest.new()
    quest.id = quest_id
    quest.title = str(data.get("title", "Untitled Quest"))
    quest.description = str(data.get("description", ""))
    quest.is_main_quest = bool(data.get("is_main_quest", false))
    quest.conditions = data.get("conditions", {})
    quest.rewards = data.get("rewards", {})
    quest.intro = data.get("intro", {})
    quest.outro = data.get("outro", {})

    for objective_data in data.get("objectives", []):
        var objective := QuestObjective.new()
        objective.id = str(objective_data.get("id", ""))
        objective.type = str(objective_data.get("type", ""))
        objective.description = str(objective_data.get("description", ""))
        objective.target_city = str(objective_data.get("target_city", ""))
        objective.target_resource = str(objective_data.get("target_resource", ""))
        objective.target_wagon = str(objective_data.get("target_wagon", ""))
        objective.target_qty = int(objective_data.get("target_qty", 0))
        quest.objectives.append(objective)
    return quest
#endregion


#region quest flow
# Offers every quest whose conditions are met now. Call it when something that conditions depend on
# changes. `arrived_city` is the city the player has just arrived in ("" for the other moments), the
# only moment when a "city" condition is true. A quest that was offered and declined is offered again.
func check_offers(arrived_city := "") -> void:
    if not QUESTS_ENABLED or _offers_held:
        return
    for quest_id in quest_database:
        if active_quests.has(quest_id) or completed_quests.has(quest_id):
            continue
        if _conditions_met(quest_database[quest_id].get("conditions", {}), arrived_city):
            offer_quest(quest_id)


# Call BEFORE a new game starts if its first quests must not appear over the intro...
func hold_offers() -> void:
    _offers_held = true


# ...and this when the player is ready: the quests that are due are offered now.
func release_offers() -> void:
    _offers_held = false
    check_offers.call_deferred()


func _conditions_met(conditions: Dictionary, arrived_city: String) -> bool:
    if conditions.has("city") and str(conditions["city"]) != arrived_city:
        return false
    for required in conditions.get("completed", []):
        if not completed_quests.has(str(required)):
            return false
    return true
# Offers a quest to the player. With an intro dialog, the player decides (a choice with
# "accept": true starts it). Without one, it starts right away.
func offer_quest(quest_id: String) -> void:
    if active_quests.has(quest_id) or completed_quests.has(quest_id):
        return
    var quest := _build_quest(quest_id)
    if quest == null:
        push_error("QuestManager: quest '%s' is not in the database" % quest_id)
        return
    if quest.intro.is_empty():
        accept_quest(quest_id)
        return
    if not offered_quests.has(quest_id):
        offered_quests.append(quest_id)
    quest_offered.emit(quest)

func accept_quest(quest_id: String) -> void:
    if active_quests.has(quest_id) or completed_quests.has(quest_id):
        return
    var quest := _build_quest(quest_id)
    if quest == null:
        push_error("QuestManager: quest '%s' is not in the database" % quest_id)
        return

    active_quests[quest_id] = quest
    offered_quests.erase(quest_id)
    quest_accepted.emit(quest)
    quests_updated.emit()
    _refresh_train_objectives()
    # The player may already be in the target city
    if _current_city != "":
        process_event(QuestObjective.TYPE_REACH_CITY, {"city_name": _current_city})


func process_event(event_type: String, event_data: Dictionary) -> void:
    var changed := false
    var completed_now: Array[Quest] = []

    for quest: Quest in active_quests.values():
        var quest_changed := false
        for objective in quest.objectives:
            if objective.update_progress(event_type, event_data):
                quest_changed = true
                quest_objective_updated.emit(quest, objective)
        if quest_changed:
            changed = true
            if quest.is_completed():
                completed_now.append(quest)

    if changed:
        quests_updated.emit()
    for quest in completed_now:
        complete_quest(quest)


func complete_quest(quest: Quest) -> void:
    if not active_quests.has(quest.id):
        return # already completed (a reward can trigger a nested event)
    active_quests.erase(quest.id)
    completed_quests.append(quest.id)
    quest.status = "completed"
    quest_completed.emit(quest)

    claim_rewards(quest)

    if not quest.outro.is_empty():
        quest_outro_requested.emit(quest)
    # Deferred, so the UI can react to the completion before the quests it unlocks appear
    check_offers.call_deferred()
    quests_updated.emit()

func dismiss_completed() -> void:
    for quest_id in completed_quests:
        if not dismissed_quests.has(quest_id):
            dismissed_quests.append(quest_id)
    quests_updated.emit()
    
func claim_rewards(quest: Quest) -> void:
    if quest.rewards.has("money"):
        GameState.add_money(int(quest.rewards["money"])) # money_changed updates any open scene

    if quest.rewards.has("wagon"):
        var wagon_type := str(quest.rewards["wagon"])
        if WagonTypes.TYPES.has(wagon_type):
            GameState.add_wagon_to_player_train({"type": wagon_type, "cargo_name": "", "cargo_qty": 0})
        else:
            push_error("QuestManager: the reward of '%s' is an unknown wagon type '%s'" % [quest.id, wagon_type])
#endregion


#region events (called by the scenes)
func notify_city_reached(city_name: String) -> void:
    _current_city = city_name
    process_event(QuestObjective.TYPE_REACH_CITY, {"city_name": city_name})
    check_offers.call_deferred(city_name) # after the outros of the quests this arrival completed


func notify_city_left() -> void:
    _current_city = ""


# The player SOLD goods to a city
func notify_goods_delivered(city_name: String, resource_name: String, qty: int) -> void:
    process_event(QuestObjective.TYPE_DELIVER_GOODS, {"city_name": city_name, "resource_name": resource_name, "qty": qty})


# The player BOUGHT goods
# func notify_goods_collected(resource_name: String, qty: int) -> void:
#     process_event(QuestObjective.TYPE_COLLECT_GOODS, {"resource_name": resource_name, "qty": qty})


func _on_money_changed(money: int) -> void:
    process_event(QuestObjective.TYPE_EARN_MONEY, {"money": money})
#endregion


#region saving
# GameState is about to write the save file: hand over the progress
func _on_game_saving() -> void:
    var active := {}
    for quest_id in active_quests:
        active[quest_id] = active_quests[quest_id].get_progress()
    GameState.set_quests({"active": active, "completed": completed_quests.duplicate(), "dismissed": dismissed_quests.duplicate(), "offered": offered_quests.duplicate()})

# Rebuilds the quests from GameState (at start, and after a load)
func load_from_game_state() -> void:
    load_quest_database() # the campaign may have changed
    active_quests.clear()
    completed_quests.clear()
    dismissed_quests.clear()
    offered_quests.clear()

    var saved: Dictionary = GameState.get_quests()

    for quest_id in saved.get("completed", []):
        completed_quests.append(str(quest_id))
    for quest_id in saved.get("dismissed", []):
        dismissed_quests.append(str(quest_id))
    for quest_id in saved.get("offered", []):
        offered_quests.append(str(quest_id))
    
    var saved_active: Dictionary = saved.get("active", {})
    for quest_id in saved_active:
        var quest := _build_quest(str(quest_id))
        if quest == null:
            push_warning("QuestManager: the saved quest '%s' is not in the database, so it was dropped" % quest_id)
            continue
        quest.apply_progress(saved_active[quest_id])
        active_quests[str(quest_id)] = quest

    # A new game: offer the first quest. Otherwise offer again what was offered but not accepted.
    if QUESTS_ENABLED:
        check_offers.call_deferred() # a new game offers the quests with no conditions
    quests_updated.emit()
    _refresh_train_objectives()
#endregion

# Units of a resource in the player train, counted from the data
func count_in_train(resource_name: String) -> int:
    var total := 0
    for wagon in GameState.get_player_train().get("wagons", []):
        if ResourceTypes.same(str(wagon.get("cargo_name", "")), resource_name):
            total += int(wagon.get("cargo_qty", 0))
    return total

# Wagons of a type in the player train, counted from the data
func count_wagons_in_train(wagon_type: String) -> int:
    var total := 0
    for wagon in GameState.get_player_train().get("wagons", []):
        if str(wagon.get("type", "")).to_lower() == wagon_type.to_lower():
            total += 1
    return total

# "collect_goods" and "own_wagon" objectives follow what the train holds, so refresh them when it changes
func _refresh_train_objectives() -> void:
    var resources := {}
    var wagon_types := {}
    for quest: Quest in active_quests.values():
        for objective in quest.objectives:
            if objective.is_completed:
                continue
            if objective.type == QuestObjective.TYPE_COLLECT_GOODS:
                resources[objective.target_resource] = true
            elif objective.type == QuestObjective.TYPE_OWN_WAGON:
                wagon_types[objective.target_wagon] = true
    for resource_name in resources:
        process_event(QuestObjective.TYPE_COLLECT_GOODS, {"resource_name": resource_name, "qty": count_in_train(resource_name)})
    for wagon_type in wagon_types:
        process_event(QuestObjective.TYPE_OWN_WAGON, {"wagon_type": wagon_type, "qty": count_wagons_in_train(wagon_type)})

#region debug
func _print_progress(quest: Quest, objective: QuestObjective) -> void:
    print("Quest '%s': %s %d/%d%s" % [quest.title, objective.description, objective.current_qty, objective.target_qty, " (done)" if objective.is_completed else ""])


func _validate_database() -> void:
    for problem in find_database_problems():
        push_warning("QuestManager: %s" % problem)


# Everything in quests.json that doesn't match the rest of the game's data
func find_database_problems() -> Array[String]:
    var problems: Array[String] = []
    
    for quest_id in quest_database:
        var data: Dictionary = quest_database[quest_id]
        var objectives: Array = data.get("objectives", [])
        if objectives.is_empty():
            problems.append("'%s' has no objectives" % quest_id)

        var seen_ids := {}
        for objective_data in objectives:
            var objective_id := str(objective_data.get("id", ""))
            if objective_id == "" or seen_ids.has(objective_id):
                problems.append("'%s' has an objective with a missing or repeated id '%s'" % [quest_id, objective_id])
            seen_ids[objective_id] = true
            problems.append_array(_objective_problems(quest_id, objective_data))

        var conditions: Dictionary = data.get("conditions", {})
        if conditions.has("city") and GameState.get_city_by_name(str(conditions["city"])).is_empty():
            problems.append("'%s' has the condition city '%s', which doesn't exist" % [quest_id, conditions["city"]])
        for required in conditions.get("completed", []):
            if not quest_database.has(str(required)):
                problems.append("'%s' needs the quest '%s' completed, which doesn't exist" % [quest_id, required])
            elif str(required) == quest_id:
                problems.append("'%s' needs itself completed" % quest_id)

        var rewards: Dictionary = data.get("rewards", {})
        if rewards.has("wagon") and not WagonTypes.TYPES.has(str(rewards["wagon"])):
            problems.append("'%s' rewards the unknown wagon '%s'" % [quest_id, rewards["wagon"]])
        if rewards.has("money") and int(rewards["money"]) <= 0:
            problems.append("'%s' has a money reward of %s" % [quest_id, rewards["money"]])

        for part in ["intro", "outro"]:
            var dialog: Dictionary = data.get(part, {})
            if dialog.is_empty():
                continue
            if not Characters.has(str(dialog.get("character", ""))):
                problems.append("'%s' %s has the unknown character '%s'" % [quest_id, part, dialog.get("character", "")])
            if str(dialog.get("text", "")).is_empty():
                problems.append("'%s' %s has no text" % [quest_id, part])
            var choices: Array = dialog.get("choices", [])
            if part == "intro" and not choices.is_empty():
                var can_accept := false
                for choice in choices:
                    can_accept = can_accept or bool(choice.get("accept", false))
                if not can_accept:
                    problems.append("'%s' intro has choices but none has \"accept\": true, so it can't be accepted" % quest_id)
        
    return problems


func _objective_problems(quest_id: String, data: Dictionary) -> Array[String]:
    var problems: Array[String] = []
    var type := str(data.get("type", ""))
    var city := str(data.get("target_city", ""))
    var resource := str(data.get("target_resource", ""))
    var qty := int(data.get("target_qty", 0))
    var where := "'%s' objective '%s'" % [quest_id, data.get("id", "?")]

    if not QuestObjective.TYPES.has(type):
        problems.append("%s has the unknown type '%s'" % [where, type])
        return problems
    if city != "" and GameState.get_city_by_name(city).is_empty():
        problems.append("%s targets the unknown city '%s'" % [where, city])
    if type == QuestObjective.TYPE_REACH_CITY and city == "":
        problems.append("%s needs a target_city" % where)
    if type in [QuestObjective.TYPE_DELIVER_GOODS, QuestObjective.TYPE_COLLECT_GOODS]:
        if not ResourceTypes.is_known(resource):
            problems.append("%s targets the unknown resource '%s'" % [where, resource])
    if type == QuestObjective.TYPE_OWN_WAGON:
        var wagon := str(data.get("target_wagon", ""))
        if not WagonTypes.TYPES.has(wagon):
            problems.append("%s targets the unknown wagon '%s'" % [where, wagon])
    if type != QuestObjective.TYPE_REACH_CITY and qty <= 0:
        problems.append("%s needs a target_qty above 0" % where)
    return problems
#endregion
