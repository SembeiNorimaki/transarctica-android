class_name Campaigns
extends RefCounted
# The campaigns of the game. A campaign is a folder in data/campaigns with the data of ONE story:
#
#   data/campaigns/<id>/
#       campaign.json       name, description, map, start_money, intro (see get_info)
#       cities.json         the cities at the start (same structure as GameState's cities)
#       player_train.json   the player train at the start
#       enemy_trains.json   the enemy trains at the start ({} for none)
#       units.json          the soldiers at the start ({} for none)
#       quests.json         the quests of the story
#       events.json         the events of the map (bridges, tunnels...)
#
# GameState.campaign_id says which one is being played, and it is saved with the game. Everything
# else asks this class for the path of a file, so a campaign is a folder, and no code changes
# when you add one.

const ROOT := "res://data/campaigns"
const DEFAULT_ID := "tutorial" # a new game starts here until the menu lets the player choose
const FILE_INFO := "campaign.json"

const DEFAULT_MAP := "world_1"
const DEFAULT_MONEY := 100


# "res://data/campaigns/tutorial/quests.json"
static func path(campaign_id: String, file_name: String) -> String:
    return "%s/%s/%s" % [ROOT, campaign_id, file_name]


static func exists(campaign_id: String) -> bool:
    return not campaign_id.is_empty() and FileAccess.file_exists(path(campaign_id, FILE_INFO))


# The ids of all the campaigns, sorted (the folder names)
static func list_ids() -> Array[String]:
    var ids: Array[String] = []
    for folder in DirAccess.get_directories_at(ROOT):
        if exists(folder):
            ids.append(folder)
    ids.sort()
    return ids


# campaign.json with the missing fields filled in:
#   id           the folder name
#   name         what the menu shows
#   description  one or two sentences for the menu
#   map          the map scene of the story (scenes/maps/<map>.tscn)
#   start_money  the money of a new game
#   intro        {text, image}: shown while the game loads. image is a path ("" = black background)
static func get_info(campaign_id: String) -> Dictionary:
    var info := {
        "id": campaign_id,
        "name": campaign_id.capitalize(),
        "description": "",
        "map": DEFAULT_MAP,
        "start_money": DEFAULT_MONEY,
        "intro": {"text": "", "image": ""},
    }
    var file_path := path(campaign_id, FILE_INFO)
    if not FileAccess.file_exists(file_path):
        push_error("Campaigns: %s not found" % file_path)
        return info
    var data = JSON.parse_string(FileAccess.get_file_as_string(file_path))
    if not (data is Dictionary):
        push_error("Campaigns: %s must contain a JSON object" % file_path)
        return info

    for key in ["name", "description", "map"]:
        if data.has(key):
            info[key] = str(data[key])
    if data.has("start_money"):
        info["start_money"] = int(data["start_money"]) # JSON numbers are floats
    if data.get("intro") is Dictionary:
        info["intro"]["text"] = str(data["intro"].get("text", ""))
        info["intro"]["image"] = str(data["intro"].get("image", ""))
    return info
