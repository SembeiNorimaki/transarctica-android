extends Node
class_name CombatUnitManager
# The soldiers of the combat scene: it opens a barracks' menu, deploys the soldiers the player
# picks, and keeps track of which one is selected.

signal selection_changed(soldier: Soldier) # null: nothing is selected

const SOLDIER_SCENE: PackedScene = preload("res://scenes/units/soldier.tscn") # adjust the path

# Injected by CombatScene
var unit_container: Node2D
var barracks_menu: BarracksMenu

var soldiers := {} # unit id -> Soldier
var selected: Soldier = null

var _open_barracks: BarracksWagon # the one whose soldiers the menu shows


# Call once, after the injection
func setup() -> void:
    barracks_menu.unit_clicked.connect(_on_menu_unit_clicked)


#region barracks
# Shows the soldiers of this barracks in the menu. `unit_ids` are the "unit_ids" of its data.
func open_barracks(barracks: BarracksWagon, unit_ids: Array) -> void:
    _open_barracks = barracks
    # Soldiers already on the battlefield are not in the wagon any more
    var waiting: Array = unit_ids.filter(func(id): return not soldiers.has(str(id)))
    barracks_menu.show_units(waiting)


func _on_menu_unit_clicked(unit_id: String) -> void:
    if deploy(unit_id, _open_barracks) != null:
        barracks_menu.remove_unit(unit_id)
#endregion


#region deploying
# Puts the soldier at the next free deployment position of the barracks.
# Returns null (with an error) if it can't.
func deploy(unit_id: String, barracks: BarracksWagon) -> Soldier:
    if unit_container == null or barracks == null:
        push_error("CombatUnitManager: unit_container not injected, or no barracks open")
        return null
    if soldiers.has(unit_id):
        push_error("CombatUnitManager: '%s' is already deployed" % unit_id)
        return null
    var unit_data: Dictionary = GameState.get_unit(unit_id)
    if unit_data.is_empty():
        push_error("CombatUnitManager: no unit '%s' in GameState" % unit_id)
        return null
    var slot := barracks.take_deploy_position()
    if slot < 0:
        push_warning("CombatUnitManager: the barracks has no free deployment position")
        return null

    var soldier := SOLDIER_SCENE.instantiate() as Soldier
    soldier.setup(unit_id, unit_data)
    soldier.clicked.connect(select)
    unit_container.add_child(soldier)
    soldier.global_position = barracks.get_deploy_position(slot)
    soldiers[unit_id] = soldier
    return soldier
#endregion


#region selection
# Selects this soldier; the one selected before is deselected. Tapping the selected one again deselects it.
func select(soldier: Soldier) -> void:
    if selected == soldier:
        soldier = null
    if is_instance_valid(selected):
        selected.selected = false
    selected = soldier
    if selected != null:
        selected.selected = true
    selection_changed.emit(selected)
#endregion
