extends Control
class_name Minimap
# A small picture of the whole map: the three terrain levels, the rails, the cities (their entrance),
# the player's train and the part of the map that the camera shows. It is only a VIEW: it draws what
# it is told (build, set_player_tile, set_view_rect) and decides nothing.
#
# It is cartesian: one pixel per tile, x to the right and y down, as the tiles are numbered. The
# picture is made once, so the cost is one small image and not one node per tile.
#
# Scene structure (minimap.tscn): a single Control with this script, Clip Contents on,
# Texture Filter = Nearest, Custom Minimum Size around 200 x 200 (the map is about square).

@export var level_colors: Array[Color] = [
    Color(0.16, 0.36, 0.55), # level 0 (Terrain-1): water
    Color(0.35, 0.55, 0.30), # level 1 (Terrain): land
    Color(0.85, 0.87, 0.90), # level 2 (Terrain+1): high
]
@export var rails_color := Color(0.12, 0.12, 0.12)
@export var city_color := Color(1.0, 0.85, 0.2)
@export var player_color := Color(1.0, 0.2, 0.2)
@export var view_color := Color(1.0, 1.0, 1.0, 0.9)
@export var background_color := Color(0.04, 0.05, 0.07, 0.85)
@export var border_color := Color(0.8, 0.8, 0.8, 0.9)

var _grid: GridService # only to turn the camera's world rectangle into tiles
var _texture: ImageTexture
var _image_size := Vector2.ONE # size of the picture in pixels = size of the map in tiles (+ a margin)
var _origin := Vector2i.ZERO # the tile at the top left corner of the picture
var _city_points := PackedVector2Array() # in picture pixels
var _player_point := Vector2.ZERO # in picture pixels
var _has_player := false
var _view_points := PackedVector2Array() # the corners of the camera, in picture pixels
var _view_rect := Rect2() # the camera in world coordinates, to know when it changed


#region api
# `levels[i]` is the array of cells (Vector2i) of level i (0 = lowest). A later level is painted over an earlier one.
# `rail_tiles` and `city_tiles` are arrays of Vector2i.
func build(grid: GridService, levels: Array, rail_tiles: Array, city_tiles: Array) -> void:
    clear()
    _grid = grid

    var lowest := Vector2i(1 << 30, 1 << 30)
    var highest := Vector2i(- (1 << 30), - (1 << 30))
    for cells: Array in levels:
        for cell: Vector2i in cells:
            lowest = Vector2i(mini(lowest.x, cell.x), mini(lowest.y, cell.y))
            highest = Vector2i(maxi(highest.x, cell.x), maxi(highest.y, cell.y))
    if lowest.x > highest.x:
        push_warning("Minimap: the map has no cells")
        return

    _origin = lowest - Vector2i.ONE # a margin of one pixel
    var pixels := highest - lowest + Vector2i(3, 3)
    _image_size = Vector2(pixels)
    var image := Image.create(pixels.x, pixels.y, false, Image.FORMAT_RGBA8)

    for level in levels.size():
        var color := level_colors[mini(level, level_colors.size() - 1)]
        for cell: Vector2i in levels[level]:
            image.set_pixelv(cell - _origin, color)
    for tile: Vector2i in rail_tiles:
        var pixel := tile - _origin
        if pixel.x >= 0 and pixel.y >= 0 and pixel.x < pixels.x and pixel.y < pixels.y:
            image.set_pixelv(pixel, rails_color)
    for tile: Vector2i in city_tiles:
        _city_points.append(_tile_to_point(tile))

    _texture = ImageTexture.create_from_image(image)
    queue_redraw()


# For when the map is unloaded
func clear() -> void:
    _texture = null
    _city_points = PackedVector2Array()
    _view_points = PackedVector2Array()
    _view_rect = Rect2()
    _has_player = false
    queue_redraw()


func set_player_tile(tile: Vector2i) -> void:
    _player_point = _tile_to_point(tile)
    _has_player = true
    queue_redraw()


# What the camera shows, in world coordinates. On the map it is a diamond, because the game view is isometric.
func set_view_rect(world_rect: Rect2) -> void:
    if _texture == null or _grid == null or world_rect == _view_rect:
        return
    _view_rect = world_rect
    _view_points = PackedVector2Array()
    var corners := [
        world_rect.position,
        Vector2(world_rect.end.x, world_rect.position.y),
        world_rect.end,
        Vector2(world_rect.position.x, world_rect.end.y),
    ]
    for corner: Vector2 in corners:
        _view_points.append(_tile_to_point(_grid.world_to_tile(corner)))
    _view_points.append(_view_points[0]) # close the shape
    queue_redraw()
#endregion


#region drawing
func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), background_color)
    if _texture != null:
        var k := _fit()
        var offset := _offset(k)
        draw_texture_rect(_texture, Rect2(offset, _image_size * k), false)
        for point in _city_points:
            draw_circle(offset + point * k, 2.5, city_color)
        if _view_points.size() > 1:
            var line := PackedVector2Array()
            for point in _view_points:
                line.append(offset + point * k)
            draw_polyline(line, view_color, 1.0)
        if _has_player:
            var p := offset + _player_point * k
            draw_circle(p, 4.0, Color.BLACK)
            draw_circle(p, 3.0, player_color)
    draw_rect(Rect2(Vector2.ZERO, size), border_color, false, 2.0)


# The centre of a tile, in picture pixels
func _tile_to_point(tile: Vector2i) -> Vector2:
    return Vector2(tile - _origin) + Vector2(0.5, 0.5)


# How much the picture is enlarged to fit the control (the shape of the picture stays)
func _fit() -> float:
    return minf(size.x / _image_size.x, size.y / _image_size.y)


# Where the picture starts inside the control: it is centered
func _offset(k: float) -> Vector2:
    return (size - _image_size * k) * 0.5
#endregion