extends Area2D
class_name Cannonball
# A cannonball flies in a straight line. It looks for the Area2D of the OTHER team's wagons: when it
# touches one, the wagon loses `power` hp and the cannonball is gone. It does nothing else.
# Set it up with setup() before adding it to the tree.

signal hit(wagon: GenericWagon)

@export var max_distance := 3000.0 # it disappears after this far

var direction := Vector2.UP
var speed := 700.0
var power := 10
var target_team := "enemy"

var _travelled := 0.0


func setup(new_direction: Vector2, new_speed: float, new_power: int, new_target_team: String) -> void:
    direction = new_direction.normalized()
    speed = new_speed
    power = new_power
    target_team = new_target_team
    rotation = direction.angle() + PI / 2.0 # the sprite looks up

func _ready() -> void:
    collision_layer = 0
    collision_mask = GenericWagon.LAYER_ENEMY_TRAIN if target_team == "enemy" else GenericWagon.LAYER_PLAYER_TRAIN
    area_entered.connect(_on_area_entered)

func _physics_process(delta: float) -> void:
    var step := direction * speed * delta
    position += step
    _travelled += step.length()
    if _travelled >= max_distance:
        queue_free()

func _on_area_entered(other: Area2D) -> void:
    var wagon := other.get_parent() as GenericWagon
    if wagon == null or wagon.team != target_team:
        return
    if wagon.take_damage(power):
        hit.emit(wagon)
        set_deferred("monitoring", false) # one hit only, even if two areas touch it this frame
        queue_free()
