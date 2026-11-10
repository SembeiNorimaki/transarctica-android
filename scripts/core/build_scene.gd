extends CombatSceneBase
class_name BuildScene
# The strategic scene: the same battlefield as a combat scene, with no enemies, to build on. It is
# real time with no action points, so units go wherever they are told; nobody can shoot. The
# BuildBar has the tools: build buildings, roads and walls (see BuildManager).
#
# Controls, besides those of CombatSceneBase: with no tool, a tap selects one of your units and the
# next tap sends it there. With a tool, taps build instead (with Roads, drag to build a straight
# line of road); right click (or pressing the button
# again) puts the tool down. Only the units of the player's team are deployed.

## The units hurry here: nobody is waiting for the shots.
const UNIT_SPEED_FACTOR := 2.0

@onready var build_manager: BuildManager = $Managers/BuildManager
@onready var build_overlay: BuildOverlay = $CombatMap/Overlays/BuildOverlay
@onready var build_bar: BuildBar = $HUD/BuildBar


func _setup_scene() -> void:
    battle_unit_manager.attacks_enabled = false
    battle_unit_manager.unit_speed_factor = UNIT_SPEED_FACTOR
    if unit_hud != null:
        unit_hud.attack_button.hide()
    build_manager.combat_map_manager = combat_map_manager
    build_manager.setup()
    build_overlay.grid_service = grid_service
    build_overlay.build_manager = build_manager
    build_overlay.setup()
    build_bar.tool_selected.connect(_on_tool_selected)
    build_bar.building_type_selected.connect(build_manager.set_building_type)
    build_manager.tool_changed.connect(build_bar.set_tool)
    build_manager.message.connect(func(text: String) -> void: info_label.text = text)
    build_manager.set_building_type(build_manager.building_type)
    build_bar.set_building_type(build_manager.building_type)
    combat_input_manager.tile_hovered.connect(build_manager.set_hover)
    # with the road tool, dragging builds a line instead of moving the camera
    build_manager.tool_changed.connect(func(tool: int) -> void: combat_input_manager.drag_pans = tool != BuildManager.Tool.ROAD)
    combat_input_manager.drag_started.connect(build_manager.begin_drag)
    combat_input_manager.drag_moved.connect(build_manager.drag_to)
    combat_input_manager.drag_ended.connect(build_manager.end_drag)
    # the debug labels of many units on top of each other hide everything
    battle_unit_manager.soldier_spawned.connect(func(soldier: Soldier) -> void: soldier.show_debug_labels = false)


# Nobody to fight: only the units of the player
func _spawn_units() -> void:
    var own: Array[Dictionary] = []
    for spawn in combat_map_manager.get_spawns():
        if spawn["team"] == Soldier.TEAM_PLAYER:
            own.append(spawn)
    battle_unit_manager.spawn_all(own)


func _start_scene() -> void:
    info_label.text = "Select a unit and tap a tile to send it there, or choose what to build"


func _on_tool_selected(tool: int) -> void:
    if tool != BuildManager.Tool.NONE:
        battle_unit_manager.select(null)
    build_manager.set_tool(tool)

func _on_tile_tapped(tile: Vector2i) -> void:
    if not build_manager.handle_tile_tap(tile):
        battle_unit_manager.handle_tile_tap(tile)

func _on_tile_right_tapped(tile: Vector2i) -> void:
    if build_manager.tool != BuildManager.Tool.NONE:
        build_manager.set_tool(BuildManager.Tool.NONE)
    else:
        battle_unit_manager.handle_tile_right_tap(tile)
