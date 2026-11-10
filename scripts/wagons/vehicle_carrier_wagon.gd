extends GenericWagon
class_name VehicleCarrierWagon
# A flatbed wagon that carries vehicles (like a barracks wagon carries soldiers). It has four spots,
# the Sprite2D children of Vehicles, left to right; the vehicles it holds stand on them, in the order
# of its unit ids. Each shows the picture of its vehicle seen from the side: the frames of
# assets/wagons/vehicles_east.png, which are the E frames of the vehicle atlas, one per type in the
# order of VEHICLE_FRAMES.
#
# The wagon only shows what it is told (HorizontalTrain.add_wagon calls set_unit_types); the vehicles
# themselves are units in GameState and the ids are in the wagon's unit_ids, as for soldiers.

## The unit types of the frames of the vehicle picture.
const VEHICLE_FRAMES: Array[String] = ["tank", "artillery", "buggy", "grav_tank", "speeder", "gunship"]

@onready var _spots: Array[Node] = $Vehicles.get_children()

## The unit type of each vehicle on the wagon, spot by spot.
var unit_types: Array[String] = []


func get_spot_count() -> int:
    return _spots.size()

## Puts these vehicles (unit types, one per spot) on the wagon. More than there are spots are ignored.
func set_unit_types(types: Array) -> void:
    unit_types.assign(types)
    _refresh_visuals()

## The spot sprite `index` shows a vehicle?
func is_spot_filled(index: int) -> bool:
    return index >= 0 and index < _spots.size() and (_spots[index] as Sprite2D).visible


func _refresh_visuals() -> void:
    super()
    if not is_node_ready():
        return
    for i in _spots.size():
        var spot := _spots[i] as Sprite2D
        var frame := VEHICLE_FRAMES.find(unit_types[i]) if i < unit_types.size() else -1
        spot.visible = frame >= 0
        if frame >= 0:
            spot.frame = frame
