@tool
extends Node2D
class_name GenericWorldMap
# Base of every navigation map. The layers are painted in the editor; the terrain can be
# generated from a 3 color image (black / gray / white = low / mid / high).
#
# In the editor: set "Image Path" and tick "Generate Terrain" (it unticks itself).
# "Check Image" only reads the image and prints the matrix, so you can check it before painting.

@onready var terrain_low: TileMapLayer = $"Terrain-1"
@onready var terrain_mid: TileMapLayer = $"Terrain"
@onready var terrain_high: TileMapLayer = $"Terrain+1"
@onready var rails_layer: TileMapLayer = $"Rails"

@export_file("*.png") var image_path := ""

@export_group("Painting")
@export var source_id := 0
@export var atlas_coords := Vector2i(0, 0)
@export var clear_first := true # empty the three terrain layers before painting
@export var print_preview := true

@export var border_atlas_coords := Vector2i(1, 0)
@export var paint_borders := true

@export_group("Image colors")
@export var terrain_low_color := Color8(0, 0, 0)
@export var terrain_mid_color := Color8(128, 128, 128)
@export var terrain_high_color := Color8(255, 255, 255)
@export var rails_color := Color8(255, 0, 0)
@export_range(0.0, 441.0) var color_tolerance := 20.0

@export_group("Rails")
@export var rails_terrain_set := 0
@export var rails_terrain := 0

@export_group("Buttons")
@export var check_image := false:
    set(value):
        check_image = false # a button: it unticks itself
        if value and is_inside_tree():
            _make_loader().load_image(image_path)
@export var generate_terrain := false:
    set(value):
        generate_terrain = false
        if value and is_inside_tree():
            generate_terrain_from_image()


# Reads the image and fills the three terrain layers. Returns false (with an error) if it can't.
func generate_terrain_from_image() -> bool:
    var loader := _make_loader()
    if not loader.load_image(image_path):
        return false
    if not loader.paint(terrain_low, terrain_mid, terrain_high):
        return false
    if not loader.paint_rails(rails_layer, rails_terrain_set, rails_terrain):
        return false
    _mark_scene_unsaved()
    return true
    

func _make_loader() -> TerrainLoader:
    var loader := TerrainLoader.new()
    loader.source_id = source_id
    loader.atlas_coords = atlas_coords
    loader.clear_first = clear_first
    loader.print_preview = print_preview
    loader.terrain_low_color = terrain_low_color
    loader.terrain_mid_color = terrain_mid_color
    loader.terrain_high_color = terrain_high_color
    loader.rails_color = rails_color
    loader.color_tolerance = color_tolerance
    return loader


# Changes made by a script don't mark the scene as modified, so Ctrl+S could say there is nothing to save
func _mark_scene_unsaved() -> void:
    if Engine.is_editor_hint() and Engine.has_singleton("EditorInterface"):
        var editor := Engine.get_singleton("EditorInterface")
        if editor.has_method("mark_scene_as_unsaved"):
            editor.call("mark_scene_as_unsaved")
