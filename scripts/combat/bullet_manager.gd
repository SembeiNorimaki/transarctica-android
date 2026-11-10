extends Node
class_name BulletManager
# Fires the bullets of a tile based battle. A bullet is a node in the bullet container (a node of the
# scene, above the units); this manager only makes them and tells when each one arrives, so a shot
# can be resolved at the moment its bullet gets there. Any number of bullets fly at once, which is
# what a real time battle needs.

## A bullet was fired.
signal bullet_fired(bullet: Bullet)
## A bullet got where it was going. bullet.payload is what was given to fire(). It is freed after
## this signal.
signal bullet_arrived(bullet: Bullet)

const BULLET_SCENE: PackedScene = preload("res://scenes/projectiles/bullet.tscn")

@export var bullet_speed := 1400.0
## How far (px) a bullet that misses flies wide of the target, and past it.
@export var miss_spread := 36.0
@export var miss_overshoot := 70.0

# Injected by the scene
var bullet_container: Node2D

## The bullets in flight.
var bullets: Array[Bullet] = []

var _rng := RandomNumberGenerator.new()


func setup() -> void:
    assert(bullet_container != null, "BulletManager: not injected")


## Fires a bullet from `from` to `to` (positions in the bullet container's coordinates). A bullet that
## `hits` goes exactly to `to`; one that doesn't flies past it, a little to the side.
func fire(from: Vector2, to: Vector2, hits: bool, payload := {}) -> Bullet:
    var aim := to
    if not hits:
        var direction := (to - from).normalized()
        if direction == Vector2.ZERO:
            direction = Vector2.RIGHT
        var side := direction.orthogonal() * _rng.randf_range(-miss_spread, miss_spread)
        aim = to + side + direction * miss_overshoot
    var bullet := BULLET_SCENE.instantiate() as Bullet
    bullet.speed = bullet_speed
    bullet_container.add_child(bullet)
    bullet.launch(from, aim, payload)
    bullet.arrived.connect(_on_bullet_arrived)
    bullets.append(bullet)
    bullet_fired.emit(bullet)
    return bullet

## Is any bullet still flying?
func has_bullets() -> bool:
    return not bullets.is_empty()


func _on_bullet_arrived(bullet: Bullet) -> void:
    bullets.erase(bullet)
    bullet_arrived.emit(bullet)
    bullet.queue_free()
