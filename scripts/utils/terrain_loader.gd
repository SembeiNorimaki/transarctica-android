@tool
extends Node2D
class_name TerrainLoader
# Map utility.
#   Step 1: reads a PNG with three colors and builds a matrix with one value per pixel:
#           black = 0, gray = 1, white = 2 (a height map with three levels).
#   Step 2: paints that matrix into the map's three TileMapLayers, one layer per level:
#           0 -> "terrain-1", 1 -> "terrain", 2 -> "terrain+1".
#
# In the editor: select the node, set "Image Path", and tick "Generate Now" (it unticks itself).
# "Load Now" only builds the matrix, so you can check it in the Output before painting.
# At runtime it loads the matrix in _ready() when "Image Path" is set (it doesn't paint).
#
# The PNG is read from the file itself, not from the imported texture, so the import settings
# (compression, filtering) can't change the pixels. That only works in the editor, because an
# exported game doesn't contain the original PNG.

const VALUE_BLACK := 0
const VALUE_GRAY := 1
const VALUE_WHITE := 2
# Neighbor bits
const N := 1
const W := 2
const E := 4
const S := 8
# Diagonal bits, in reading order like N, W, E, S
const NW := 1
const NE := 2
const SW := 4
const SE := 8

@onready var terrain_low: TileMapLayer = $terrain_low
@onready var terrain_mid: TileMapLayer = $terrain_mid
@onready var terrain_high: TileMapLayer = $terrain_high

# The layer of each value (indexed by value)
var LAYER_NAMES := [terrain_low, terrain_mid, terrain_high]

# Luminance of each reference color, indexed by value. A "gray" pixel may be 127 or 128, so a
# pixel only has to be within TOLERANCE of the nearest level.
const LEVELS := [0.0, 0.5, 1.0]
const TOLERANCE := 0.2

@export_file("*.png") var image_path := ""
@export var print_preview := true # print the matrix (the top left corner of big ones) after loading

@export_group("Painting")
@export var source_id := 0 # the source of the layers' TileSets
@export var atlas_coords := Vector2i(0, 0) # the tile that is painted
@export var clear_first := true # empty the three layers before painting (it removes what they had)

@export_group("Neighbors")
@export var outside_counts_as_neighbor := false # a cell beyond the map edge counts as "same" (no border at the map edge)
@export var print_neighbors := true

@export_group("Buttons")
@export var load_now := false:
    set(value):
        load_now = false # a button: it unticks itself
        if value and is_inside_tree():
            load_terrain()
@export var generate_now := false:
    set(value):
        generate_now = false
        if value and is_inside_tree() and load_terrain():
            apply_to_layers()

var matrix: Array[PackedByteArray] = [] # matrix[y][x]. Row 0 is the TOP row of the image
var width := 0
var height := 0
var counts := [0, 0, 0] # how many pixels have each value

var cardinal: Array[PackedByteArray] = [] # cardinal[y][x]: N=1 W=2 E=4 S=8. Only filled for cells with value 1
var diagonal: Array[PackedByteArray] = [] # diagonal[y][x]: NW=1 NE=2 SW=4 SE=8. Only filled for cells with value 1

func _ready() -> void:
    if not Engine.is_editor_hint() and image_path != "":
        load_terrain()


#region step 1: image to matrix
# Loads the image and builds the matrix. Returns false (with an error) if it can't.
func load_terrain(path := "") -> bool:
    if path == "":
        path = image_path
    matrix = []
    width = 0
    height = 0
    counts = [0, 0, 0]

    if path == "" or not FileAccess.file_exists(path):
        push_error("TerrainLoader: image not found: '%s'" % path)
        return false
    var image := Image.load_from_file(path)
    if image == null or image.is_empty():
        push_error("TerrainLoader: '%s' is not a valid image" % path)
        return false

    width = image.get_width()
    height = image.get_height()
    var unexpected := 0
    var first_unexpected := Vector2i(-1, -1)

    for y in height:
        var row := PackedByteArray()
        row.resize(width)
        for x in width:
            var color := image.get_pixel(x, y)
            var luminance := color.get_luminance()

            # The nearest of the three levels
            var value := 0
            var best_distance := INF
            for i in LEVELS.size():
                var distance := absf(luminance - LEVELS[i])
                if distance < best_distance:
                    best_distance = distance
                    value = i

            if best_distance > TOLERANCE or color.a < 0.5:
                unexpected += 1
                if first_unexpected.x < 0:
                    first_unexpected = Vector2i(x, y)
            row[x] = value
            counts[value] += 1
        matrix.append(row)

    if unexpected > 0:
        push_warning("TerrainLoader: %d pixels are not black, gray or white (the first at %s). They got the value of the nearest level." % [unexpected, first_unexpected])
    print("TerrainLoader: %s is %d x %d. black (0): %d, gray (1): %d, white (2): %d" % [path.get_file(), width, height, counts[0], counts[1], counts[2]])
    if print_preview:
        print_matrix()
    compute_neighbors()
    return true


# The value at a pixel, or -1 if it is outside the image
func get_value(x: int, y: int) -> int:
    if x < 0 or y < 0 or x >= width or y >= height:
        return -1
    return matrix[y][x]


func get_value_at(tile: Vector2i) -> int:
    return get_value(tile.x, tile.y)


# One line of digits per row, to check the matrix against the image
func print_matrix(max_cols := 80, max_rows := 40) -> void:
    for y in mini(height, max_rows):
        var line := ""
        for x in mini(width, max_cols):
            line += str(matrix[y][x])
        print(line)
    if width > max_cols or height > max_rows:
        print("... (showing %d x %d of %d x %d)" % [mini(width, max_cols), mini(height, max_rows), width, height])
#endregion


#region step 2: matrix to tilemap layers
# Paints the matrix: cell (x, y) goes to the layer of its value, as the tile at atlas_coords.
# Each cell is painted in ONE layer only. Returns false (with an error) if it can't.
func apply_to_layers() -> bool:
    if matrix.is_empty():
        push_error("TerrainLoader: there is no matrix yet. Load the terrain first.")
        return false
    var layers := _find_layers()
    if layers.is_empty():
        return false

    if clear_first:
        for layer in layers:
            layer.clear()

    var painted := [0, 0, 0]
    for y in height:
        for x in width:
            var value := matrix[y][x]
            layers[value].set_cell(Vector2i(x, y), source_id, atlas_coords)
            painted[value] += 1

    print("TerrainLoader: painted %d x %d cells. %s: %d, %s: %d, %s: %d" % [
        width, height,
        LAYER_NAMES[0], painted[0], LAYER_NAMES[1], painted[1], LAYER_NAMES[2], painted[2]])
    _mark_scene_unsaved()
    return true


func _find_layers() -> Array[TileMapLayer]:
    var result: Array[TileMapLayer] = [terrain_low, terrain_mid, terrain_high]
    for i in result.size():
        if result[i] == null:
            push_error("TerrainLoader: layer reference for '%s' is null. Check the node paths, then reload the scene." % LAYER_NAMES[i])
            return []
    return result


# Changes made by a script don't mark the scene as modified, so Ctrl+S could say there is nothing to save
func _mark_scene_unsaved() -> void:
    if Engine.is_editor_hint() and Engine.has_singleton("EditorInterface"):
        var editor := Engine.get_singleton("EditorInterface")
        if editor.has_method("mark_scene_as_unsaved"):
            editor.call("mark_scene_as_unsaved")
#endregion


#region step 3: neighbors of the gray cells (terrain_mid)
# For every cell with value 1, which of its 8 neighbors also have value 1 (a neighbor with value 0
# or 2 counts as different). All 4 cardinals = 15, all 4 diagonals = 15.
func compute_neighbors() -> bool:
    if matrix.is_empty():
        push_error("TerrainLoader: there is no matrix yet. Load the terrain first.")
        return false
    cardinal = []
    diagonal = []
    for y in height:
        var c_row := PackedByteArray()
        var d_row := PackedByteArray()
        c_row.resize(width)
        d_row.resize(width)
        for x in width:
            if matrix[y][x] == VALUE_GRAY:
                c_row[x] = (N if _same(x, y - 1) else 0) \
                        | (W if _same(x - 1, y) else 0) \
                        | (E if _same(x + 1, y) else 0) \
                        | (S if _same(x, y + 1) else 0)
                d_row[x] = (NW if _same(x - 1, y - 1) else 0) \
                        | (NE if _same(x + 1, y - 1) else 0) \
                        | (SW if _same(x - 1, y + 1) else 0) \
                        | (SE if _same(x + 1, y + 1) else 0)
        cardinal.append(c_row)
        diagonal.append(d_row)
    if print_neighbors:
        _print_masks()
    return true


func _same(x: int, y: int) -> bool:
    var value := get_value(x, y)
    if value == -1:
        return outside_counts_as_neighbor
    return value == VALUE_GRAY


# -1 if the cell is not a value 1 cell (or is outside the map)
func get_cardinal(x: int, y: int) -> int:
    if get_value(x, y) != VALUE_GRAY:
        return -1
    return cardinal[y][x]


func get_diagonal(x: int, y: int) -> int:
    if get_value(x, y) != VALUE_GRAY:
        return -1
    return diagonal[y][x]


# One hex digit per cell ("." where the value is not 1): cardinal masks first, then diagonal masks
func _print_masks(max_cols := 80, max_rows := 40) -> void:
    for pair in [["cardinal", cardinal], ["diagonal", diagonal]]:
        print("TerrainLoader: %s masks" % pair[0])
        for y in mini(height, max_rows):
            var line := ""
            for x in mini(width, max_cols):
                line += "%X" % pair[1][y][x] if matrix[y][x] == VALUE_GRAY else "."
            print(line)
#endregion
