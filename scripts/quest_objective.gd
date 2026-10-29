extends RefCounted
class_name QuestObjective
# One objective of a quest. What to do comes from quests.json, so a change of text or targets
# applies to old saves too. Only the progress (current_qty, is_completed) is saved with the game.

const TYPE_REACH_CITY := "reach_city" # target_city
const TYPE_DELIVER_GOODS := "deliver_goods" # sell target_qty of target_resource (to target_city, "" = any)
const TYPE_COLLECT_GOODS := "collect_goods" # buy target_qty of target_resource
const TYPE_EARN_MONEY := "earn_money" # have target_qty money

const TYPE_OWN_WAGON := "own_wagon" # target_wagon, target_qty: wagons of that type in the train

const TYPES := [TYPE_REACH_CITY, TYPE_DELIVER_GOODS, TYPE_COLLECT_GOODS, TYPE_EARN_MONEY, TYPE_OWN_WAGON]

var id := ""
var type := ""
var description := ""
var target_city := ""
var target_resource := ""
var target_wagon := ""
var target_qty := 0
var current_qty := 0
var is_completed := false


# Returns true if the objective changed.
func update_progress(event_type: String, event_data: Dictionary) -> bool:
    if is_completed or event_type != type:
        return false
    var old_qty := current_qty

    match type:
        TYPE_REACH_CITY:
            if _same(target_city, str(event_data.get("city_name", ""))):
                current_qty = 1
                is_completed = true
        TYPE_DELIVER_GOODS:
            var city_ok := target_city == "" or _same(target_city, str(event_data.get("city_name", "")))
            if city_ok and ResourceTypes.same(target_resource, str(event_data.get("resource_name", ""))):
                current_qty = mini(current_qty + int(event_data.get("qty", 0)), target_qty)
        TYPE_COLLECT_GOODS:
            # The event carries the total the train holds right now
            if ResourceTypes.same(target_resource, str(event_data.get("resource_name", ""))):
                current_qty = clampi(int(event_data.get("qty", 0)), 0, target_qty)
        TYPE_OWN_WAGON:
            # The event carries how many wagons of that type the train has right now
            if _same(target_wagon, str(event_data.get("wagon_type", ""))):
                current_qty = clampi(int(event_data.get("qty", 0)), 0, target_qty)
        TYPE_EARN_MONEY:
            # Progress never goes down, even if the player spends the money again
            current_qty = maxi(current_qty, mini(int(event_data.get("money", 0)), target_qty))

    if type != TYPE_REACH_CITY:
        is_completed = current_qty >= target_qty
    return current_qty != old_qty or is_completed


func _same(a: String, b: String) -> bool:
    return a.to_lower() == b.to_lower()
