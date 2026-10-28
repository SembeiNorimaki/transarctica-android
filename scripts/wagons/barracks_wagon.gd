extends GenericWagon
class_name BarracksWagon
# A wagon that carries soldiers. The Marker2D children of DeploymentPositions say where its
# soldiers are put on the battlefield, in order: the first marker is used first.

@onready var _markers: Array[Node] = $DeploymentPositions.get_children()

var _used: Array[bool] = [] # per marker: a soldier already stands there


func _ready() -> void:
    super() # GenericWagon refreshes its visuals
    _used.resize(_markers.size())
    _used.fill(false)


# Reserves the first marker that is free. Returns its index, or -1 if all are used.
func take_deploy_position() -> int:
    var i := _used.find(false)
    if i >= 0:
        _used[i] = true
    return i


# Where marker `index` is in the world
func get_deploy_position(index: int) -> Vector2:
    return (_markers[index] as Marker2D).global_position
