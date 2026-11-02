extends Node
class_name ProjectileManager
# Owns the cannonballs: it spawns them when a cannon fires and puts them in the projectile container.
# It also turns the player's taps on cannon wagons into shots.
# Dependencies are injected by the scene. Register every train whose cannons should work.

const CANNONBALL_SCENE: PackedScene = preload("res://scenes/projectiles/cannonball.tscn")

## Seconds between the enemy cannons' shots. 0 = the enemy cannons never fire by themselves.
@export var enemy_fire_interval := 0.0

# Injected by the scene
var projectile_container: Node2D

var _enemy_cannons: Array[CannonWagon] = []
var _enemy_timer := 0.0


func register_train(train: HorizontalTrain) -> void:
    for wagon in train.wagons:
        var cannon := wagon as CannonWagon
        if cannon == null:
            continue
        cannon.fired.connect(_on_cannon_fired)
        if cannon.team == "enemy":
            _enemy_cannons.append(cannon)
    if train.team == "player" and not train.wagon_clicked.is_connected(_on_wagon_clicked):
        train.wagon_clicked.connect(_on_wagon_clicked)

func _process(delta: float) -> void:
    if enemy_fire_interval <= 0.0:
        return
    _enemy_timer += delta
    if _enemy_timer < enemy_fire_interval:
        return
    _enemy_timer = 0.0
    for cannon in _enemy_cannons:
        if is_instance_valid(cannon):
            cannon.try_fire()

func _on_wagon_clicked(wagon: GenericWagon) -> void:
    var cannon := wagon as CannonWagon
    if cannon != null and cannon.team == "player":
        cannon.try_fire()

func _on_cannon_fired(cannon: CannonWagon, origin: Vector2, direction: Vector2, power: int, speed: float) -> void:
    assert(projectile_container != null, "ProjectileManager: projectile_container not injected")
    var ball := CANNONBALL_SCENE.instantiate() as Cannonball
    ball.setup(direction, speed, power, "player" if cannon.team == "enemy" else "enemy")
    projectile_container.add_child(ball)
    ball.global_position = origin
