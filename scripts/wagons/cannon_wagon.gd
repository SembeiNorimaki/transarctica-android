extends GenericWagon
class_name CannonWagon
# A wagon with a cannon. Its cargo is the cannonballs ("Ammunition"). Each shot uses one and the
# cannon has to reload before the next. Player cannons shoot up, enemy ones down.
# The wagon does not create the cannonball: it emits `fired` and the ProjectileManager spawns it.

signal fired(wagon: CannonWagon, origin: Vector2, direction: Vector2, power: int, speed: float)

@export var reload_time := 2.0 # seconds
@export var ball_power := 10 # hp the cannonball takes off the wagon it hits
@export var ball_speed := 700.0 # pixels per second

@onready var muzzle: Marker2D = $Muzzle

var _cooldown := 0.0 # seconds until the cannon is loaded again


func _process(delta: float) -> void:
    _cooldown = maxf(_cooldown - delta, 0.0)


func get_ammo() -> int:
    return cargo_amount

# 0 when it is loaded, 1 right after a shot
func get_reload_fraction() -> float:
    return clampf(_cooldown / reload_time, 0.0, 1.0) if reload_time > 0.0 else 0.0

func can_fire() -> bool:
    return not is_destroyed and _cooldown <= 0.0 and cargo_amount > 0

func get_fire_direction() -> Vector2:
    return Vector2.DOWN if team == "enemy" else Vector2.UP

# Shoots if it is loaded and has a cannonball. Returns whether it fired.
func try_fire() -> bool:
    if not can_fire():
        return false
    cargo_amount -= 1
    _cooldown = reload_time
    _refresh_visuals()
    fired.emit(self, muzzle.global_position, get_fire_direction(), ball_power, ball_speed)
    return true
