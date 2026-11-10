extends Node2D
class_name GenericBuilding
# A building on the battlefield. The Buildings layer of a CombatMap only marks where buildings go
# (placeholder tiles, see data/combat_tiles.json); CombatMapManager puts one of these where each
# placeholder is. It has hit points: when they run out the building is destroyed, it turns into
# rubble, and CombatMapManager frees the tiles it covered, so units can walk and see through.
#
# Its picture is the one of the placeholder tile. The node stands on the tile where its sort line
# is, so units are drawn behind or in front of it like they are for any tile of the Y-sorted map.
# Call setup() after the building is in the tree.

signal damaged(building: GenericBuilding, amount: int)
signal destroyed(building: GenericBuilding)

@onready var sprite: Sprite2D = $Sprite2D
@onready var rubble: Polygon2D = $Rubble

var building_type := ""
## The first (north) tile; the building covers size.x * size.y tiles from there.
var tile := Vector2i.ZERO
var size := Vector2i.ONE
var max_hp := 100
var hp := 100
var is_destroyed := false


## data is an element of CombatMap.read_buildings(). `anchor_position` is where the center of its
## first tile is, in the coordinates of the parent node.
func setup(data: Dictionary, anchor_position: Vector2, tile_size: Vector2i) -> void:
    building_type = str(data["type"])
    tile = data["tile"]
    size = data["size"]
    max_hp = BuildingTypes.get_max_hp(building_type)
    hp = max_hp
    is_destroyed = false
    name = "%s_%d_%d" % [building_type, tile.x, tile.y]

    var sort_y := int(data.get("y_sort_origin", 0))
    position = anchor_position + Vector2(0, sort_y)
    sprite.texture = data.get("texture", null)
    sprite.position = -Vector2(data.get("texture_origin", Vector2.ZERO)) - Vector2(0, sort_y)
    sprite.modulate = Color.WHITE
    sprite.visible = true
    _build_rubble(tile_size, sort_y)
    rubble.visible = false


## The tiles it covers (while it stands: a destroyed building leaves them).
func get_tiles() -> Array[Vector2i]:
    return Footprint.rect(size.x, size.y).tiles_at(tile)

func get_hp_fraction() -> float:
    return float(hp) / float(maxi(max_hp, 1))

## Takes `amount` hp off. Returns true if this hit destroyed the building.
func take_damage(amount: int, _source: Variant = null) -> bool:
    if is_destroyed or amount <= 0:
        return false
    hp = maxi(hp - amount, 0)
    damaged.emit(self, amount)
    if hp > 0:
        sprite.modulate = Color.WHITE.lerp(Color(0.5, 0.46, 0.46), 1.0 - get_hp_fraction())
        return false
    is_destroyed = true
    sprite.visible = false
    rubble.visible = true
    destroyed.emit(self)
    return true


# The rubble: a dark patch over the ground where the building was, with a few chunks
func _build_rubble(tile_size: Vector2i, sort_y: int) -> void:
    for child in rubble.get_children():
        child.queue_free()
    var half := Vector2(tile_size) / 2.0
    var lift := Vector2(0, -sort_y)
    # centre based tile coordinates: tile (i, j) has its center at (i, j)
    var to_screen := func(a: float, b: float) -> Vector2: return Vector2((a - b) * half.x, (a + b) * half.y) + lift
    var w := float(size.x)
    var h := float(size.y)
    rubble.polygon = PackedVector2Array([
        to_screen.call(-0.42, -0.42), to_screen.call(w - 0.58, -0.42),
        to_screen.call(w - 0.58, h - 0.58), to_screen.call(-0.42, h - 0.58)])
    var rng := RandomNumberGenerator.new()
    rng.seed = tile.x * 7919 + tile.y * 104729 + size.x
    for i in 2 + size.x * size.y:
        var a := rng.randf_range(0.0, w - 1.0)
        var b := rng.randf_range(0.0, h - 1.0)
        var r := rng.randf_range(0.12, 0.26)
        var chunk := Polygon2D.new()
        chunk.polygon = PackedVector2Array([
            to_screen.call(a - r, b - r), to_screen.call(a + r, b - r),
            to_screen.call(a + r, b + r), to_screen.call(a - r, b + r)])
        var grey := rng.randf_range(0.26, 0.46)
        chunk.color = Color(grey, grey * 0.95, grey * 0.9, 1.0)
        rubble.add_child(chunk)
