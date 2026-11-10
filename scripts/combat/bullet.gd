extends Node2D
class_name Bullet
# A bullet in flight in a tile based battle: it flies in a straight line from where it was fired to
# where it was aimed, at a constant speed, then emits `arrived` (BulletManager reacts) and goes away.
# It knows nothing about hits or damage: `payload` is whatever the one who fired it wants back.
# Any number of bullets can fly at the same time.

signal arrived(bullet: Bullet)

@export var speed := 1400.0 # px per second

## What the shooter wants back on arrival (who fired, at whom, the damage, whether it hits...).
var payload := {}
var from_position := Vector2.ZERO
var to_position := Vector2.ZERO

var _done := false


## Call after the bullet is in the tree. Positions are in the coordinates of its parent.
func launch(from: Vector2, to: Vector2, bullet_payload := {}) -> void:
    from_position = from
    to_position = to
    payload = bullet_payload
    position = from
    if from.distance_to(to) > 0.01:
        rotation = from.angle_to_point(to)
    _done = false


func _process(delta: float) -> void:
    if _done:
        return
    var left := position.distance_to(to_position)
    var step := speed * delta
    if step >= left:
        position = to_position
        _done = true
        arrived.emit(self)
    else:
        position += position.direction_to(to_position) * step


## The seconds it takes to fly from where it is to where it is going.
func get_flight_time() -> float:
    return position.distance_to(to_position) / maxf(speed, 1.0)
