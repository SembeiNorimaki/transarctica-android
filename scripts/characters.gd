class_name Characters
# The people who talk to the player: id -> {name, portrait}, from data/characters.json.
# Static, so any script can ask for them: Characters.portrait("comrad"). The file is read the
# first time it is needed, and the pictures are loaded once.

const PATH := "res://data/characters.json"

static var _data := {}
static var _loaded := false
static var _portraits := {} # id -> Texture2D


static func has(character_id: String) -> bool:
    _ensure_loaded()
    return _data.has(character_id)


# The name to show for a character, or "" if it doesn't exist
static func display_name(character_id: String) -> String:
    _ensure_loaded()
    return str(_data.get(character_id, {}).get("name", ""))


# The picture of a character, or null (no character, or the file is missing)
static func portrait(character_id: String) -> Texture2D:
    _ensure_loaded()
    if character_id.is_empty():
        return null
    if _portraits.has(character_id):
        return _portraits[character_id]
    var path := str(_data.get(character_id, {}).get("portrait", ""))
    if path.is_empty() or not ResourceLoader.exists(path):
        push_warning("Characters: no portrait for '%s' (%s)" % [character_id, path])
        return null
    _portraits[character_id] = load(path) as Texture2D
    return _portraits[character_id]


static func _ensure_loaded() -> void:
    if _loaded:
        return
    _loaded = true
    if not FileAccess.file_exists(PATH):
        push_warning("Characters: %s not found" % PATH)
        return
    var json = JSON.parse_string(FileAccess.get_file_as_string(PATH))
    if json is Dictionary:
        _data = json
    else:
        push_error("Characters: %s is not a valid JSON object" % PATH)