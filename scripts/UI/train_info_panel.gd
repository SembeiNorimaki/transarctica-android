extends Control
class_name TrainInfoPanel
# A scrollable list of the wagons of a train, in order, one row per wagon with 3 columns:
#   1. a picture of the wagon
#   2. a picture of what it holds (the resource, or a soldier for a barracks)
#   3. text: name, hp, and the content
#
# It is only a VIEW. By default it shows the player train, read from GameState, and it rebuilds
# itself when it becomes visible and when the cargo of the player train changes. To show another
# train (an enemy, for the combat scene) call show_train() with its data; show_player_train()
# goes back to the player's.
#
# Scene structure:
#   TrainInfoPanel (Control, this script)
#   └── ScrollContainer
#       └── Grid (GridContainer, columns = 3, "Access as Unique Name" ON)

const RESOURCE_SHEET: Texture2D = preload("res://assets/resources/resources_120x46.png")
const RESOURCE_SHEET_COLUMNS := 3
const RESOURCE_SHEET_ROWS := 10 # 360 x 460 px: 3 columns of 120 px, 10 rows of 46 px (like the sprite in trade_resource.tscn)
const SOLDIER_FRAMES: SpriteFrames = preload("res://assets/tilesets/unit.tres")

@export var font_size := 28
@export var wagon_picture_size := Vector2(256, 96) # the 1st column
@export var content_picture_size := Vector2(120, 96) # the 2nd column
@export var text_min_width := 360.0 # the 3rd column wraps its text at this width
@export var column_gap := 24
@export var row_gap := 16

@onready var grid: GridContainer = %Grid

var _train_data := {} # empty: follow the player train
var _wagon_icons := {} # wagon type -> Texture2D (the wagon scenes are only instantiated once)


func _ready() -> void:
    grid.columns = 3
    grid.add_theme_constant_override("h_separation", column_gap)
    grid.add_theme_constant_override("v_separation", row_gap)
    grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    visibility_changed.connect(_on_visibility_changed)
    GameState.player_cargo_changed.connect(_on_player_cargo_changed)
    GameState.game_loaded.connect(_on_player_cargo_changed)
    if is_visible_in_tree():
        refresh()


#region public
# Shows this train. `train_data` has the structure of GameState.get_player_train().
func show_train(train_data: Dictionary) -> void:
    _train_data = train_data
    refresh()


func show_player_train() -> void:
    _train_data = {}
    refresh()


# Builds the rows again from the data
func refresh() -> void:
    var data: Dictionary = _train_data if not _train_data.is_empty() else GameState.get_player_train()
    for child in grid.get_children():
        grid.remove_child(child)
        child.queue_free()

    var wagons: Array = data.get("wagons", [])
    for i in wagons.size():
        _add_row(wagons[i], data)
#endregion


#region rows
func _add_row(wagon: Dictionary, train_data: Dictionary) -> void:
    var wagon_type := str(wagon.get("type", ""))
    grid.add_child(_make_picture(_get_wagon_icon(wagon_type), wagon_picture_size))
    grid.add_child(_make_picture(_get_content_icon(wagon), content_picture_size))
    grid.add_child(_make_text(_describe(wagon, train_data)))


func _make_picture(texture: Texture2D, min_size: Vector2) -> TextureRect:
    var rect := TextureRect.new()
    rect.texture = texture
    rect.custom_minimum_size = min_size
    rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    return rect # TextureRect ignores the mouse by default, so dragging over it scrolls


func _make_text(text: String) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", font_size)
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.custom_minimum_size = Vector2(text_min_width, 0.0)
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    return label


# The text of one wagon
func _describe(wagon: Dictionary, train_data: Dictionary) -> String:
    var wagon_type := str(wagon.get("type", ""))
    var lines: Array[String] = [wagon_type.capitalize()] # "MerchandiseWagon" -> "Merchandise Wagon"
    if wagon.has("hp"):
        lines.append("HP %d / %d" % [int(wagon.get("hp", 0)), int(wagon.get("max_hp", wagon.get("hp", 0)))])

    var info: Dictionary = WagonTypes.TYPES.get(wagon_type, {})
    var capacity := int(info.get("capacity", 0))

    if wagon_type == "LocomotiveWagon":
        if train_data.has("max_speed"):
            lines.append("Max speed %d" % int(train_data["max_speed"]))
    elif info.get("stores", []).has("Soldiers"):
        lines.append("Soldiers %d / %d" % [wagon.get("unit_ids", []).size(), capacity])
        for unit_id in wagon.get("unit_ids", []):
            lines.append("  " + _describe_unit(str(unit_id)))
    elif capacity > 0:
        var cargo := str(wagon.get("cargo_name", ""))
        var qty := int(wagon.get("cargo_qty", 0))
        if cargo.is_empty() or qty <= 0:
            lines.append("Empty (0 / %d)" % capacity)
        else:
            lines.append("%s %d / %d" % [cargo.capitalize(), qty, capacity])
    return "\n".join(lines)


func _describe_unit(unit_id: String) -> String:
    var unit: Dictionary = GameState.get_unit(unit_id)
    if unit.is_empty():
        return unit_id + " (?)"
    return "%s  HP %d / %d" % [str(unit.get("unit_type", "?")).capitalize(), int(unit.get("hp", 0)), int(unit.get("max_hp", 0))]
#endregion


#region pictures
# The picture of a wagon type: the sprite of its horizontal scene. It is read from a temporary
# instance that is never added to the tree, so no script of the wagon runs.
func _get_wagon_icon(wagon_type: String) -> Texture2D:
    if _wagon_icons.has(wagon_type):
        return _wagon_icons[wagon_type]
    var icon: Texture2D = null
    var scene: PackedScene = WagonTypes.TYPES.get(wagon_type, {}).get("horizontal_scene")
    if scene != null:
        var instance := scene.instantiate()
        var sprite := instance.get_node_or_null("Sprite2D") as Sprite2D
        if sprite != null and sprite.texture != null:
            var cell := sprite.texture.get_size() / Vector2(sprite.hframes, sprite.vframes)
            var atlas := AtlasTexture.new()
            atlas.atlas = sprite.texture
            atlas.region = Rect2(Vector2(sprite.frame_coords) * cell, cell)
            icon = atlas
        instance.free()
    else:
        push_warning("TrainInfoPanel: no picture for wagon type '%s'" % wagon_type)
    _wagon_icons[wagon_type] = icon
    return icon


# What the wagon holds: the resource it carries, or a soldier for a barracks with soldiers
func _get_content_icon(wagon: Dictionary) -> Texture2D:
    if not wagon.get("unit_ids", []).is_empty():
        return SOLDIER_FRAMES.get_frame_texture(&"S", 0)
    var cargo := str(wagon.get("cargo_name", ""))
    if cargo.is_empty() or int(wagon.get("cargo_qty", 0)) <= 0:
        return null
    var frame := ResourceTypes.frame_for(cargo)
    if frame < 0:
        return null
    var cell := RESOURCE_SHEET.get_size() / Vector2(RESOURCE_SHEET_COLUMNS, RESOURCE_SHEET_ROWS)
    var atlas := AtlasTexture.new()
    atlas.atlas = RESOURCE_SHEET
    atlas.region = Rect2(Vector2(frame % RESOURCE_SHEET_COLUMNS, floori(frame / float(RESOURCE_SHEET_COLUMNS))) * cell, cell)
    return atlas
#endregion


#region updates
func _on_visibility_changed() -> void:
    if is_visible_in_tree():
        refresh()


# Only the player train follows the game state; a train shown with show_train() stays as given
func _on_player_cargo_changed() -> void:
    if _train_data.is_empty() and is_visible_in_tree():
        refresh()
#endregion
