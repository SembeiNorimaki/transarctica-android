extends Control
class_name UnitHud
# The panel at the bottom of a tile based battle for the selected unit: its picture, its hp and (in
# turn based combat) action points, and a button for each action. It is only a view: it shows what
# it is given (set_unit, set_mode) and emits mode_selected when the player presses a button; the
# scene connects that to BattleUnitManager.set_action_mode.
#
# The two buttons are switches: pressed, the taps are that action (a move, an attack); released
# again, the unit is back to the default (a free tile is a move, an enemy is an attack).

## The player chose how taps are understood: a BattleUnitManager.ActionMode.
signal mode_selected(mode: int)

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
    set_mode(BattleUnitManager.ActionMode.AUTO)
    refresh()

## Shows which button is pressed, without telling anybody.
func set_mode(mode: int) -> void:
    move_button.set_pressed_no_signal(mode == BattleUnitManager.ActionMode.MOVE)
    attack_button.set_pressed_no_signal(mode == BattleUnitManager.ActionMode.ATTACK)

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
