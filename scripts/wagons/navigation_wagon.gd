extends Node2D
class_name NavigationWagon

# Signals
signal tile_changed(wagon: NavigationWagon, old_tile: Vector2i, new_tile: Vector2i)
signal collided(wagon: NavigationWagon, other_wagon: NavigationWagon)

var grid_service: GridService # injected
var speed := 0.0
var orientation := ""
var heading := Vector2.RIGHT
var current_tile := Vector2i.ZERO
var _placed := false # nothing moves or emits before place_at()

const LAYER_PLAYER_TRAIN := 1 # layer numbers, as named in step 1
const LAYER_ENEMY_TRAIN := 2

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hit_area: Area2D = $HitArea
@onready var label: Label = $Label

func _ready() -> void:
    hit_area.area_entered.connect(_on_hit_area_entered)

# The player's area detects enemies. Enemy areas are only detected, so they never see each other.
func setup_collision(is_player: bool) -> void:
    hit_area.input_pickable = false
    hit_area.collision_layer = 0
    hit_area.collision_mask = 0
    if is_player:
        hit_area.set_collision_layer_value(LAYER_PLAYER_TRAIN, true)
        hit_area.set_collision_mask_value(LAYER_ENEMY_TRAIN, true)
    else:
        hit_area.set_collision_layer_value(LAYER_ENEMY_TRAIN, true)
    hit_area.set_deferred("monitoring", is_player)
    hit_area.set_deferred("monitorable", not is_player)

## Never emits tile_changed.
func place_at(tile: Vector2i, ori: String) -> void:
    position = grid_service.tile_to_world(Vector2(tile))
    current_tile = tile
    set_orientation(ori)
    _placed = true

func set_orientation(ori: String) -> void:
    heading = grid_service.orientation_to_heading(ori) # derived: can't desync
    if ori != orientation:
        orientation = ori
        sprite.play(ori)

# The wagon types have no navigation sprites yet: until they do, a wagon that is not the locomotive
# is the locomotive sprite, tinted, with the name of its type.
func set_placeholder(type_name: String) -> void:
    label.text = type_name
    sprite.modulate = Color(0.7, 0.8, 1.0)
    
func set_sprite_frames(frames: SpriteFrames) -> void:
    sprite.sprite_frames = frames
    if orientation != "":
        sprite.play(orientation) # a new SpriteFrames stops the current animation
        
## Called by the train. Sub-steps so no tile can be skipped.
func advance(delta: float) -> void:
    if not _placed:
        return
    var remaining := speed * delta
    var max_step := grid_service.tile_half_size.y * 0.5 # well below a tile's width
    while remaining > 0.0 and speed > 0.0:
        var step := minf(remaining, max_step)
        position += heading * step
        remaining -= step
        var tile := grid_service.world_to_tile(position)
        if tile != current_tile:
            var old := current_tile
            current_tile = tile
            tile_changed.emit(self, old, tile) # handler may change orientation or stop

func _on_hit_area_entered(area: Area2D) -> void:
    var other := area.get_parent() as NavigationWagon
    if other != null:
        collided.emit(self, other)