extends Node
class_name EventsManager
# Events of the navigation map: special tiles that do something when the player train enters them.
#
# The MAP says where: an "Events" TileMapLayer, where the atlas position of each tile is the id of
# the event (id = atlas_y * 10 + atlas_x, like the CitiesIds layer).
# The DATA says what: data/events.json links an id to its info (see that file).
#
# Event types:
#   bridge, tunnel: usually on the end of a rail. If the player pays, the rails listed in "Tiles"
#                   are added to the map (and an optional picture in the Bridges or Tunnels layer).
#   progress:       something happens in the story: it can accept a quest, set a flag, give money.
#
# This node only decides WHAT happens. NavigationScene shows it to the player (a pop-up) and tells
# this node the answer, with accept(). The state (which events are done) lives in GameState, so
# it is saved, and the map is changed again after a load, because the map is rebuilt from its file.
#
# Create it in code: EventsManager.new(), add it to the scene, then set rail_service.

# The player train entered the tile of an event that can happen. The pop-up should open.
# event = {id, tile, type, name, text, cost, accept_text, optional}
signal event_triggered(event: Dictionary)
signal event_completed(event_id: int, tile: Vector2i)

const EVENTS_FILE := "events.json" # in the folder of the campaign being played (see Campaigns)

const TYPE_BRIDGE := "bridge"
const TYPE_TUNNEL := "tunnel"
const TYPE_PROGRESS := "progress"
const TYPES := [TYPE_BRIDGE, TYPE_TUNNEL, TYPE_PROGRESS]

# Names of the layers of the map scene
const LAYER_EVENTS := "Events"
const LAYER_RAILS := "Rails"
const LAYER_BRIDGES := "Bridges"
const LAYER_TUNNELS := "Tunnels"

# Injected by NavigationScene
var rail_service: RailService

var _definitions := {} # event id (int) -> info (the dictionary of events.json)
var _events := {} # tile -> event id. Only the events that can still happen on this map
var _map_name := ""
var _map: Node2D


func _ready() -> void:
    _load_definitions()


#region loading
func _load_definitions() -> void:
    _definitions.clear()
    var events_path := Campaigns.path(GameState.campaign_id, EVENTS_FILE)
    if not FileAccess.file_exists(events_path):
        push_error("EventsManager: %s not found" % events_path)
        return
    var data = JSON.parse_string(FileAccess.get_file_as_string(events_path))
    if not (data is Dictionary):
        push_error("EventsManager: %s must contain a JSON object" % events_path)
        return
    for key in data:
        if str(key).begins_with("_"):
            continue # comments
        var problem := _validate(str(key), data[key])
        if not problem.is_empty():
            push_error("EventsManager: event '%s' in %s: %s (skipped)" % [key, events_path, problem])
            continue
        _definitions[int(key)] = data[key]


# "" if the event info is fine, or what is wrong with it
func _validate(key: String, info) -> String:
    if not key.is_valid_int():
        return "the key must be an integer id"
    if not (info is Dictionary):
        return "it must be an object"
    if not TYPES.has(info.get("Type", "")):
        return "'Type' must be one of %s" % [TYPES]
    if info["Type"] == TYPE_PROGRESS:
        return ""
    var tiles = info.get("Tiles", [])
    if not (tiles is Array) or tiles.is_empty():
        return "a %s needs a non-empty 'Tiles' list" % info["Type"]
    for entry in tiles:
        if not (entry is Dictionary) or not (entry.get("Tile") is Array) or entry["Tile"].size() < 2:
            return "every entry of 'Tiles' needs a 'Tile': [x, y]"
        if not RailService.RAILNAME_TO_ATLAS.has(entry.get("Rail", "")):
            return "'Rail' '%s' is not a rail name (see RailService.RAILNAME_TO_ATLAS)" % entry.get("Rail", "")
        if entry.has("Overlay") and (not (entry["Overlay"] is Array) or entry["Overlay"].size() < 2):
            return "'Overlay' must be an atlas position [x, y]"
    return ""
#endregion


#region map
# Call when a map is loaded, AFTER its rails are registered in RailService: the crossings that
# were already built in this game are built again here.
func setup(map_name: String, map: Node2D) -> void:
    _load_definitions() # the campaign may have changed since the last map
    _map_name = map_name
    _map = map
    _events.clear()

    var layer := map.get_node_or_null(LAYER_EVENTS) as TileMapLayer
    if layer == null:
        push_warning("EventsManager: the map has no '%s' layer, so it has no events" % LAYER_EVENTS)
        return
    layer.hide() # the tiles are markers for the map maker, not something for the player to see

    for tile in layer.get_used_cells():
        var atlas := layer.get_cell_atlas_coords(tile)
        var event_id := atlas.y * 10 + atlas.x
        if not _definitions.has(event_id):
            push_warning("EventsManager: unknown event id %d at tile %s" % [event_id, tile])
            continue
        var info: Dictionary = _definitions[event_id]
        if GameState.is_event_done(map_name, tile):
            if info["Type"] != TYPE_PROGRESS:
                _build_crossing(info) # done in an earlier visit or save: the map file doesn't have it
            continue
        _events[tile] = event_id
#endregion


#region triggering
# Connect to NavigationTrainManager.player_tile_changed
func on_player_tile_changed(tile: Vector2i) -> void:
    if not _events.has(tile):
        return
    var info: Dictionary = _definitions[_events[tile]]
    if not _requirements_met(info):
        return
    event_triggered.emit(_make_event(tile, _events[tile], info))


func _requirements_met(info: Dictionary) -> bool:
    var flag := str(info.get("RequiresFlag", ""))
    return flag.is_empty() or GameState.has_flag(flag)


func _make_event(tile: Vector2i, event_id: int, info: Dictionary) -> Dictionary:
    var type: String = info["Type"]
    var cost := int(info.get("Cost", 0))
    var accept_text := str(info.get("AcceptText", _default_accept_text(type)))
    if cost > 0:
        accept_text += " (%d)" % cost
    return {
        "id": event_id,
        "tile": tile,
        "type": type,
        "name": str(info.get("Name", "")),
        "text": str(info.get("Text", "")),
        "cost": cost,
        "accept_text": accept_text,
        "optional": bool(info.get("Optional", type != TYPE_PROGRESS)), # can the player say no?
    }


func _default_accept_text(type: String) -> String:
    match type:
        TYPE_BRIDGE:
            return "Build the bridge"
        TYPE_TUNNEL:
            return "Clear the tunnel"
    return "OK"
#endregion


#region answers
# The player said yes. Returns "" if it went well, or the reason it did not (the event stays open).
func accept(tile: Vector2i) -> String:
    if not _events.has(tile):
        return "That event is over."
    var event_id: int = _events[tile]
    var info: Dictionary = _definitions[event_id]

    var cost := int(info.get("Cost", 0))
    if cost > 0 and not GameState.add_money(-cost):
        return "Not enough money."

    if info["Type"] != TYPE_PROGRESS:
        _build_crossing(info)
    _apply_effects(info.get("Effects", {}))

    GameState.set_event_done(_map_name, tile)
    _events.erase(tile)
    event_completed.emit(event_id, tile)
    return ""


# What an event gives, besides what its type does. All keys are optional.
func _apply_effects(effects: Dictionary) -> void:
    if effects.has("AcceptQuest"):
        QuestManager.offer_quest(str(effects["AcceptQuest"]))
    if effects.has("SetFlag"):
        GameState.set_flag(str(effects["SetFlag"]))
    if effects.has("Money"):
        GameState.add_money(int(effects["Money"]))


# Adds the rails of a bridge or tunnel to the map and to the RailService, so trains can use them.
# The first tiles usually include the tile of the event itself, whose rail changes from an end
# of rail ("WX") to a straight one ("WE").
func _build_crossing(info: Dictionary) -> void:
    var rails_layer := _map.get_node_or_null(LAYER_RAILS) as TileMapLayer
    if rails_layer == null:
        push_error("EventsManager: the map has no '%s' layer" % LAYER_RAILS)
        return
    var overlay_layer := _map.get_node_or_null(LAYER_BRIDGES if info["Type"] == TYPE_BRIDGE else LAYER_TUNNELS) as TileMapLayer
    var rails_source := rails_layer.tile_set.get_source_id(0)

    for entry: Dictionary in info["Tiles"]:
        var tile := Vector2i(int(entry["Tile"][0]), int(entry["Tile"][1]))
        var atlas: Vector2i = RailService.RAILNAME_TO_ATLAS[entry["Rail"]]
        rails_layer.set_cell(tile, rails_source, atlas)
        rail_service.spawn_rail(tile, atlas)
        if entry.has("Overlay") and overlay_layer != null:
            var overlay_atlas := Vector2i(int(entry["Overlay"][0]), int(entry["Overlay"][1]))
            overlay_layer.set_cell(tile, overlay_layer.tile_set.get_source_id(0), overlay_atlas)
#endregion
