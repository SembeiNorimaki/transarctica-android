extends Control
class_name UnitHud
# The panel at the bottom of a tile based battle for the selected unit: its picture, its hp and (in
# turn based combat) action points, and a button for each action. It is only a view: it shows what
# it is given (set_unit, set_mode) and emits mode_selected when the player presses a button; the
# scene connects that to BattleUnitManager.set_action_mode.
#
# The same panel shows a wagon of the player's train when it is selected (show_wagon): its picture, its
# hp and what it carries. If it carries units (a barracks, a vehicle carrier) each is a button that asks
# for it to get off (deploy_requested). Selecting a unit takes the wagon away, and the other way round.
#
# The two buttons are switches: pressed, the taps are that action (a move, an attack); released
# again, the unit is back to the default (a free tile is a move, an enemy is an attack).

## The player chose how taps are understood: a BattleUnitManager.ActionMode.
signal mode_selected(mode: int)

## The player pressed a unit of the wagon on show: it should get off the train.
signal deploy_requested(unit_id: String)

const SLOT_SIZE := Vector2(112, 76)

@onready var panel: PanelContainer = $Panel
@onready var icon: TextureRect = $Panel/Margin/Row/Icon
@onready var name_label: Label = $Panel/Margin/Row/Info/NameLabel
@onready var hp_label: Label = $Panel/Margin/Row/Info/HpRow/HpLabel
@onready var hp_bar: ProgressBar = $Panel/Margin/Row/Info/HpRow/HpBar
@onready var ap_row: HBoxContainer = $Panel/Margin/Row/Info/ApRow
@onready var ap_label: Label = $Panel/Margin/Row/Info/ApRow/ApLabel
@onready var ap_bar: ProgressBar = $Panel/Margin/Row/Info/ApRow/ApBar
@onready var move_button: Button = $Panel/Margin/Row/Buttons/MoveButton
@onready var attack_button: Button = $Panel/Margin/Row/Buttons/AttackButton

@onready var wagon_panel: PanelContainer = $WagonPanel
@onready var wagon_icon: TextureRect = $WagonPanel/Margin/Row/Icon
@onready var wagon_name_label: Label = $WagonPanel/Margin/Row/Info/NameLabel
@onready var wagon_hp_label: Label = $WagonPanel/Margin/Row/Info/HpRow/HpLabel
@onready var wagon_hp_bar: ProgressBar = $WagonPanel/Margin/Row/Info/HpRow/HpBar
@onready var cargo_icon: TextureRect = $WagonPanel/Margin/Row/Info/CargoRow/CargoIcon
@onready var cargo_label: Label = $WagonPanel/Margin/Row/Info/CargoRow/CargoLabel
@onready var slots: HBoxContainer = $WagonPanel/Margin/Row/Info/Slots

var _soldier: Soldier = null


func _ready() -> void:
    move_button.toggled.connect(_on_move_toggled)
    attack_button.toggled.connect(_on_attack_toggled)
    set_unit(null)


## Shows this unit (null: the panel is hidden).
func set_unit(soldier: Soldier) -> void:
    if is_instance_valid(_soldier):
        _soldier.hp_changed.disconnect(_on_unit_changed)
        _soldier.action_points_changed.disconnect(_on_unit_changed)
    _soldier = soldier
    if is_instance_valid(_soldier):
        _soldier.hp_changed.connect(_on_unit_changed)
        _soldier.action_points_changed.connect(_on_unit_changed)
        clear_wagon()
    set_mode(BattleUnitManager.ActionMode.AUTO)
    refresh()

## Shows which button is pressed, without telling anybody.
func set_mode(mode: int) -> void:
    move_button.set_pressed_no_signal(mode == BattleUnitManager.ActionMode.MOVE)
    attack_button.set_pressed_no_signal(mode == BattleUnitManager.ActionMode.ATTACK)

## Shows a wagon (null or an empty dictionary: the wagon is taken away). `info` has:
##   name: String, icon: Texture2D, hp, max_hp: int,
##   cargo_text: String and cargo_icon: Texture2D (what it carries; the icon may be null),
##   units: Array of {id: String, icon: Texture2D, label: String, enabled: bool}, one button each.
func show_wagon(info: Dictionary) -> void:
    if info.is_empty():
        clear_wagon()
        return
    wagon_panel.visible = true
    wagon_name_label.text = str(info.get("name", ""))
    wagon_icon.texture = info.get("icon")
    var max_hp := int(info.get("max_hp", 0))
    wagon_hp_label.text = "HP %d/%d" % [int(info.get("hp", 0)), max_hp]
    wagon_hp_bar.max_value = maxf(float(max_hp), 1.0)
    wagon_hp_bar.value = int(info.get("hp", 0))
    cargo_label.text = str(info.get("cargo_text", ""))
    cargo_icon.texture = info.get("cargo_icon")
    cargo_icon.visible = cargo_icon.texture != null
    for child in slots.get_children():
        slots.remove_child(child)
        child.queue_free()
    for unit: Dictionary in info.get("units", []):
        var button := Button.new()
        button.icon = unit.get("icon")
        button.expand_icon = true
        button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
        button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
        button.custom_minimum_size = SLOT_SIZE
        button.text = str(unit.get("label", ""))
        button.tooltip_text = "Get %s off the train" % str(unit.get("label", ""))
        button.disabled = not bool(unit.get("enabled", true))
        button.pressed.connect(deploy_requested.emit.bind(str(unit.get("id", ""))))
        slots.add_child(button)
    if is_instance_valid(_soldier): # one thing at a time: the unit goes
        set_unit(null)

func clear_wagon() -> void:
    wagon_panel.visible = false

func is_showing_wagon() -> bool:
    return wagon_panel.visible

func refresh() -> void:
    if not is_instance_valid(_soldier):
        panel.visible = false
        return
    panel.visible = true
    name_label.text = _soldier.unit_type.replace("_", " ").capitalize()
    hp_label.text = "HP %d/%d" % [_soldier.hp, _soldier.max_hp]
    hp_bar.max_value = maxf(float(_soldier.max_hp), 1.0)
    hp_bar.value = _soldier.hp
    ap_row.visible = _soldier.show_action_points
    ap_label.text = "AP %.1f/%.1f" % [_soldier.action_points, _soldier.max_action_points]
    ap_bar.max_value = maxf(_soldier.max_action_points, 1.0)
    ap_bar.value = _soldier.action_points
    icon.texture = _get_icon(_soldier)

## The picture of the unit: its sprite, facing the viewer.
func _get_icon(soldier: Soldier) -> Texture2D:
    var frames := soldier.sprite.sprite_frames
    if frames == null:
        return null
    for animation in [&"S", &"SE", &"E"]:
        if frames.has_animation(animation):
            return frames.get_frame_texture(animation, 0)
    return null


func _on_unit_changed(_soldier_changed: Soldier) -> void:
    refresh()

func _on_move_toggled(pressed: bool) -> void:
    if pressed:
        attack_button.set_pressed_no_signal(false)
    mode_selected.emit(BattleUnitManager.ActionMode.MOVE if pressed else BattleUnitManager.ActionMode.AUTO)

func _on_attack_toggled(pressed: bool) -> void:
    if pressed:
        move_button.set_pressed_no_signal(false)
    mode_selected.emit(BattleUnitManager.ActionMode.ATTACK if pressed else BattleUnitManager.ActionMode.AUTO)
