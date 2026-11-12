extends GenericWagon
class_name VehicleCarrierWagon
# A flatbed wagon that carries vehicles (like a barracks wagon carries soldiers). It has four spots,
# the Sprite2D children of Vehicles, left to right; the vehicles it holds stand on them, in the order
# of its unit ids. Each shows its vehicle looking east, the picture of the placeholder tileset of
# the maps: assets/combat/unitsFH_placeholder.png (a column per team, a row per type in the order
# of VEHICLE_FRAMES). The Sprite2Ds of the spots use it with hframes 2 and vframes 7.
#
# The wagon only shows what it is told (HorizontalTrain.add_wagon calls set_unit_types); the vehicles
# themselves are units in GameState and the ids are in the wagon's unit_ids, as for soldiers.

## The unit types of the frames of the vehicle picture.
const VEHICLE_FRAMES: Array[String] = ["artillery", "tank", "buggy", "grav_tank", "speeder", "humvee"]

@onready var _spots: Array[Node] = $Vehicles.get_children()

## The unit type of each vehicle on the wagon, spot by spot.
var unit_types: Array[String] = []


func get_spot_count() -> int:
    return _spots.size()

## Puts these vehicles (unit types, one per spot) on the wagon. More than there are spots are ignored.
func set_unit_types(types: Array) -> void:
    unit_types.assign(types)
    _refresh_visuals()

func set_team(new_team: String) -> void:
    super(new_team)
    _refresh_visuals() # the enemy's vehicles are in the other column

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
            spot.frame_coords = Vector2i(1 if team == "enemy" else 0, frame)
