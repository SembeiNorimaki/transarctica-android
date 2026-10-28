@tool
extends RefCounted
class_name TerrainLoader
# Map tool (no node, no scene). Give it an image and the terrain layers, and it fills them.
#   Step 1: load_image(path) reads a PNG that uses four colors and builds a matrix with one value
#           per pixel: terrain low = 0, mid = 1, high = 2 (a height map with three levels).
#           Pixels with the rails color are counted (rails_pixels), see the TEMPORARY note below.
#   Step 2: paint(low, mid, high) paints that matrix, one layer per level, choosing for each cell
#           the slope tile (TerrainTiles) that fits the height of its four vertices.
#
# Use:
#   var loader := TerrainLoader.new()
#   if loader.load_image("res://maps/world.png"):
#       loader.paint(terrain_low, terrain_mid, terrain_high)
#
# The PNG is read from the file itself, not from the imported texture, so the import settings
# (compression, filtering) can't change the pixels. That only works in the editor, because an
# exported game doesn't contain the original PNG.

const VALUE_LOW := 0
const VALUE_MID := 1
const VALUE_HIGH := 2
const RAILS_INDEX := 3 # the 4th color of the palette
const LAYER_NAMES := ["low", "mid", "high"]

# The cells that share each vertex of a cell, as offsets from it (Diamond Down layout)
const VERTEX_N := [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]
const VERTEX_W := [Vector2i(-1, 0), Vector2i(0, 1), Vector2i(-1, 1)]
const VERTEX_E := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(1, -1)]
const VERTEX_S := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]

# The colors of the image, 0-255 per channel
var terrain_low_color := Color8(0, 0, 0)
var terrain_mid_color := Color8(128, 128, 128)
var terrain_high_color := Color8(255, 255, 255)
var rails_color := Color8(255, 0, 0)
var color_tolerance := 20.0 # how far a pixel may be from a color (distance in RGB, 0-441) and still count as it

# Options (set them before loading / painting)
var print_preview := false # print the matrix (the top left corner of big ones) after loading
var source_id := 0 # the source of the layers' TileSets
var atlas_coords := Vector2i(0, 0) # the tile painted when paint_borders is off
var paint_borders := true # true: slope tiles by vertex height. false: every cell gets atlas_coords
var border_atlas_coords := Vector2i(1, 0) # marker for a slope that has no tile yet in TerrainTiles
var clear_first := true # empty the three layers before painting (it removes what they had)

var matrix: Array[PackedByteArray] = [] # matrix[y][x]. Row 0 is the TOP row of the image
var width := 0
var height := 0
var counts := [0, 0, 0] # how many pixels have each value
var rails_pixels := 0 # how many pixels have the rails color
var rails_cells: Array[Vector2i] = [] # the cells that have the rails color

#region step 1: image to matrix
# Loads the image and builds the matrix. Returns false (with an error) if it can't.
func load_image(path: String) -> bool:
    matrix = []
    width = 0
    height = 0
    counts = [0, 0, 0]
    rails_pixels = 0
    rails_cells.clear()

    if path == "" or not FileAccess.file_exists(path):
        push_error("TerrainLoader: image not found: '%s'" % path)
        return false
    var image := Image.load_from_file(path)
    if image == null or image.is_empty():
        push_error("TerrainLoader: '%s' is not a valid image" % path)
        return false

    width = image.get_width()
    height = image.get_height()
    var palette: Array[Color] = [terrain_low_color, terrain_mid_color, terrain_high_color, rails_color]
    var unexpected := 0
    var first_unexpected := Vector2i(-1, -1)
    var seen := {} # "ff0000" -> how many pixels have exactly that color

    for y in height:
        var row := PackedByteArray()
        row.resize(width)
        for x in width:
            var color := image.get_pixel(x, y)
            var hex := color.to_html(false)
            seen[hex] = seen.get(hex, 0) + 1

            # The nearest of the four colors: low, mid, high, rails
            var nearest := 0
            var best_distance := INF
            for i in palette.size():
                var distance := _color_distance(color, palette[i])
                if distance < best_distance:
                    best_distance = distance
                    nearest = i

            if best_distance > color_tolerance or color.a < 0.5:
                unexpected += 1
                if first_unexpected.x < 0:
                    first_unexpected = Vector2i(x, y)

            var value: int
            if nearest == RAILS_INDEX:
                # TEMPORARY, until the terrain under the rails is decided: it takes the value of the pixel before it
                rails_pixels += 1
                rails_cells.append(Vector2i(x, y))
                value = row[x - 1] if x > 0 else VALUE_MID
            else:
                value = nearest
            row[x] = value
            counts[value] += 1
        matrix.append(row)

    if print_preview:
        print_matrix()
    _print_summary(path, seen, unexpected, first_unexpected)
    return true


# Distance between two colors in 0-255 RGB units (the alpha is checked apart)
func _color_distance(a: Color, b: Color) -> float:
    return Vector3(a.r8 - b.r8, a.g8 - b.g8, a.b8 - b.b8).length()


# One block, printed last, so it is not lost under the matrix: what was expected and what was found
func _print_summary(path: String, seen: Dictionary, unexpected: int, first_unexpected: Vector2i) -> void:
    var keys := seen.keys()
    keys.sort_custom(func(a, b): return seen[a] > seen[b])
    var found: Array[String] = []
    for key in keys.slice(0, 8):
        found.append("%s: %d" % [key, seen[key]])
    print("TerrainLoader: %s is %d x %d" % [path.get_file(), width, height])
    print("  palette (hex): low %s, mid %s, high %s, rails %s, tolerance %s" % [
            terrain_low_color.to_html(false), terrain_mid_color.to_html(false),
            terrain_high_color.to_html(false), rails_color.to_html(false), color_tolerance])
    print("  colors in the image (hex: pixels): %s" % ", ".join(found))
    print("  low: %d, mid: %d, high: %d, rails pixels: %d" % [counts[0], counts[1], counts[2], rails_pixels])
    if unexpected > 0:
        push_warning("TerrainLoader: %d pixels are none of the 4 colors (the first at %s). They got the value of the nearest one." % [unexpected, first_unexpected])


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
# Paints the matrix: cell (x, y) goes to the layer of its value, with the tile of its vertices.
# Each cell is painted in ONE layer only. Returns false (with an error) if it can't.
func paint(low: TileMapLayer, mid: TileMapLayer, high: TileMapLayer) -> bool:
    if matrix.is_empty():
        push_error("TerrainLoader: there is no matrix yet. Load an image first.")
        return false
    var layers: Array[TileMapLayer] = [low, mid, high]
    for i in layers.size():
        if layers[i] == null:
            push_error("TerrainLoader: the '%s' layer is null" % LAYER_NAMES[i])
            return false

    if clear_first:
        for layer in layers:
            layer.clear()

    var painted := [0, 0, 0]
    var slopes := 0
    var missing := {} # names that have no tile yet: name -> how many cells
    for y in height:
        for x in width:
            var value := matrix[y][x]
            var coords := atlas_coords
            if paint_borders:
                var tile_name := tile_name_at(x, y)
                coords = TerrainTiles.coords_for(tile_name, value == VALUE_LOW) # the lowest level is the water
                if coords == TerrainTiles.NONE:
                    missing[tile_name] = missing.get(tile_name, 0) + 1
                    coords = border_atlas_coords # a visible marker for "no tile for this yet"
                elif tile_name != "nwes":
                    slopes += 1
            layers[value].set_cell(Vector2i(x, y), source_id, coords)
            painted[value] += 1

    print("TerrainLoader: painted %d x %d cells (%d with a slope). low: %d, mid: %d, high: %d" % [width, height, slopes, painted[0], painted[1], painted[2]])
    if not missing.is_empty():
        push_warning("TerrainLoader: no tile for %s (painted with the border tile %s)" % [missing, border_atlas_coords])
    return true

# Paints the rails with the terrain (autotile) of the layer's TileSet: the tile of each cell is chosen
# from the rail cells around it. `terrain_set` and `terrain` are the indexes in the TileSet.
func paint_rails(layer: TileMapLayer, terrain_set := 0, terrain := 0) -> bool:
    if matrix.is_empty():
        push_error("TerrainLoader: there is no matrix yet. Load an image first.")
        return false
    if layer == null:
        push_error("TerrainLoader: the rails layer is null")
        return false
    if layer.tile_set == null or terrain_set >= layer.tile_set.get_terrain_sets_count() \
            or terrain >= layer.tile_set.get_terrains_count(terrain_set):
        push_error("TerrainLoader: the TileSet of '%s' has no terrain %d in terrain set %d" % [layer.name, terrain, terrain_set])
        return false

    if clear_first:
        layer.clear()
    layer.set_cells_terrain_connect(rails_cells, terrain_set, terrain)
    print("TerrainLoader: painted %d rail cells (the layer has %d cells now)" % [rails_cells.size(), layer.get_used_cells().size()])
    return true

# The name of the tile of this cell ("nwes", "NWes"...), see TerrainTiles.
func tile_name_at(x: int, y: int) -> String:
    return TerrainTiles.name_for(
        _vertex_is_up(x, y, VERTEX_N),
        _vertex_is_up(x, y, VERTEX_W),
        _vertex_is_up(x, y, VERTEX_E),
        _vertex_is_up(x, y, VERTEX_S))


# Up when any cell that shares the vertex is higher than this one. A cell beyond the map edge is ignored.
func _vertex_is_up(x: int, y: int, offsets: Array) -> bool:
    var value := get_value(x, y)
    for offset: Vector2i in offsets:
        if get_value(x + offset.x, y + offset.y) > value: # -1 (outside) is never higher
            return true
    return false
#endregion