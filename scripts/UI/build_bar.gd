extends Control
class_name BuildBar
# The buttons of the build scene: Buildings, Roads and Walls (switches: one tool at a time, press
# the active one again to put it down) and, with Buildings, the list of what to build. It is only a
# view: it shows the tool it is given (set_tool) and emits what the player chooses; the scene
# connects it to BuildManager.

signal tool_selected(tool: int)
signal building_type_selected(building_type: String)

@onready var buildings_button: Button = $Panel/Margin/Column/Buttons/BuildingsButton
@onready var roads_button: Button = $Panel/Margin/Column/Buttons/RoadsButton
@onready var walls_button: Button = $Panel/Margin/Column/Buttons/WallsButton
@onready var building_select: OptionButton = $Panel/Margin/Column/BuildingSelect

var _types: Array[String] = []


func _ready() -> void:
    for building_type: String in BuildingTypes.TYPES:
        var size: Vector2i = BuildingTypes.get_size(building_type)
        building_select.add_item("%s (%dx%d)" % [building_type.capitalize(), size.x, size.y])
        _types.append(building_type)
    buildings_button.toggled.connect(func(on: bool) -> void: _toggled(on, BuildManager.Tool.BUILDING))
    roads_button.toggled.connect(func(on: bool) -> void: _toggled(on, BuildManager.Tool.ROAD))
    walls_button.toggled.connect(func(on: bool) -> void: _toggled(on, BuildManager.Tool.WALL))
    building_select.item_selected.connect(func(index: int) -> void: building_type_selected.emit(_types[index]))
    set_tool(BuildManager.Tool.NONE)


## Shows this tool as the active one (BuildManager.Tool).
func set_tool(tool: int) -> void:
    buildings_button.set_pressed_no_signal(tool == BuildManager.Tool.BUILDING)
    roads_button.set_pressed_no_signal(tool == BuildManager.Tool.ROAD)
    walls_button.set_pressed_no_signal(tool == BuildManager.Tool.WALL)
    building_select.visible = tool == BuildManager.Tool.BUILDING

func set_building_type(building_type: String) -> void:
    var index := _types.find(building_type)
    if index >= 0:
        building_select.select(index)


func _toggled(on: bool, tool: int) -> void:
    tool_selected.emit(tool if on else BuildManager.Tool.NONE)
