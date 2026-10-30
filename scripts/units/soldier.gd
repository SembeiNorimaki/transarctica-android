extends CharacterBody2D
class_name Soldier
# A soldier on the battlefield. Its data comes from GameState's unit (see UnitTypes.make_unit);
# the StateMachine child says what it is doing: IdleState, MoveState, AttackState or DeadState.
#
# On a tile grid (CombatSceneTest) the soldier is placed with place_at() and given orders with
# order_move() / order_attack(). It never touches the other services: it only emits signals
# (step_started, attack_fired, died...) and the managers react. The one thing it asks is
# `can_step`, a rule injected by the manager, checked before every step.

signal clicked(soldier: Soldier)
signal action_changed(soldier: Soldier, action: StringName)
signal facing_changed(soldier: Soldier)
signal step_started(soldier: Soldier, from_tile: Vector2i, to_tile: Vector2i)
signal step_finished(soldier: Soldier, tile: Vector2i)
signal attack_fired(soldier: Soldier, target: Soldier)
signal hp_changed(soldier: Soldier)
signal died(soldier: Soldier)

const TEAM_PLAYER := "player"
const TEAM_ENEMY := "enemy"
const SELECTED_COLOR := Color(1.0, 1.0, 0.45)
const ENEMY_COLOR := Color(1.0, 0.45, 0.45)
const DEAD_COLOR := Color(0.35, 0.35, 0.35)

## Labels above the head: who it is, what it is doing, and the last event.
@export var show_debug_labels := true:
    set(value):
        show_debug_labels = value
        if is_node_ready():
            $Labels.visible = value

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var state_machine: StateMachine = $StateMachine
@onready var info_label: Label = $Labels/InfoLabel
@onready var status_label: Label = $Labels/StatusLabel
@onready var event_label: Label = $Labels/EventLabel

var unit_id := ""
var unit_type := ""
var team := TEAM_PLAYER
var hp := 0
var max_hp := 0
var weapon_type := ""
var move_speed := 3.0 # tiles per second
var view_range := 8 # tiles
var view_angle := 120.0 # degrees
var max_action_points := 8.0
## Action points left this turn. Only used (and shown) in turn based combat: see TurnManager.
var action_points := 0.0
var show_action_points := false

var tile := Vector2i.ZERO # the tile it stands on, or is walking to
var facing := "N" # one of GridService.ORIENTATIONS

# Injected by the manager
var grid_service: GridService
## func(unit: Soldier, from: Vector2i, to: Vector2i) -> bool. Asked before every step.
var can_step: Callable

var selected := false:
    set(value):
        selected = value
        _update_color()

var _event_tween: Tween


func _ready() -> void:
    sprite.play(StringName(facing)) # deployed facing north
    $Area2D.input_event.connect(_on_area_input_event)
    state_machine.state_changed.connect(_on_state_changed)
    $Labels.visible = show_debug_labels
    event_label.text = ""
    _update_color()
    refresh_labels()


# `data` is GameState.get_unit(unit_id). Safe to call before the node is in the tree.
# "team" in data (player/enemy) is optional and defaults to the player's.
func setup(id: String, data: Dictionary) -> void:
    unit_id = id
    unit_type = str(data.get("unit_type", ""))
    hp = int(data.get("hp", 0))
    max_hp = int(data.get("max_hp", hp))
    weapon_type = str(data.get("weapon_type", ""))
    team = str(data.get("team", TEAM_PLAYER))
    if UnitTypes.exists(unit_type):
        var stats := UnitTypes.combat_stats(unit_type)
        move_speed = float(stats["move_speed"])
        view_range = int(stats["view_range"])
        view_angle = float(stats["view_angle"])
        max_action_points = float(stats["max_ap"])
    if is_node_ready():
        _update_color()
        refresh_labels()


#region on the grid
## Puts the soldier on a tile, facing a direction. Needs grid_service.
func place_at(new_tile: Vector2i, orientation := "S") -> void:
    assert(grid_service != null, "Soldier: grid_service not injected")
    tile = new_tile
    position = grid_service.tile_to_world(Vector2(tile))
    face(orientation)
    refresh_labels()

func face(orientation: String) -> void:
    if orientation == "" or orientation == facing:
        return
    facing = orientation
    if sprite != null:
        sprite.play(StringName(facing))
    refresh_labels()
    facing_changed.emit(self)

func face_towards(target_tile: Vector2i) -> void:
    face(grid_service.get_orientation(tile, target_tile))
#endregion


#region orders
## Walk a path that starts at the soldier's tile. If `then_attack` is given, shoot it on arrival.
func order_move(path: Array[Vector2i], then_attack: Soldier = null) -> void:
    if not is_alive():
        return
    if state_machine.is_in_state(&"MoveState"):
        (state_machine.current_state as UnitMoveState).redirect(path, then_attack)
    else:
        state_machine.set_state(&"MoveState", {"path": path, "then_attack": then_attack})

func order_attack(target: Soldier) -> void:
    if not is_alive():
        return
    if state_machine.is_in_state(&"MoveState"):
        # finish the step in progress, then shoot
        var stay: Array[Vector2i] = [tile]
        (state_machine.current_state as UnitMoveState).redirect(stay, target)
    else:
        state_machine.set_state(&"AttackState", {"target": target})

func order_stop() -> void:
    if not is_alive():
        return
    if state_machine.is_in_state(&"MoveState"):
        var stay: Array[Vector2i] = [tile]
        (state_machine.current_state as UnitMoveState).redirect(stay, null)
    else:
        state_machine.set_state(&"IdleState")
#endregion


#region status
## The tiles it is going to walk, in order, from the one it is walking to now. Empty if it is not moving.
func get_path_ahead() -> Array[Vector2i]:
    if state_machine != null and state_machine.current_state is UnitMoveState:
        return (state_machine.current_state as UnitMoveState).get_path_ahead()
    return []

## Who it is going to shoot, or is shooting. null if nobody.
func get_attack_target() -> Soldier:
    if state_machine == null:
        return null
    if state_machine.current_state is UnitMoveState:
        return (state_machine.current_state as UnitMoveState).get_target()
    if state_machine.current_state is UnitAttackState:
        return (state_machine.current_state as UnitAttackState).get_target()
    return null

func set_action_points(value: float, show := true) -> void:
    action_points = value
    show_action_points = show
    refresh_labels()

func is_alive() -> bool:
    return hp > 0

## The action it is doing now: &"idle", &"move", &"attack" or &"dead".
func get_action() -> StringName:
    if state_machine == null or state_machine.current_state == null:
        return &"idle"
    return StringName(String(state_machine.current_state.name).trim_suffix("State").to_lower())

func get_weapon() -> Dictionary:
    return WeaponTypes.get_def(weapon_type)

func take_damage(amount: int, _source: Soldier = null) -> void:
    if not is_alive() or amount <= 0:
        return
    hp = maxi(hp - amount, 0)
    show_event("-%d" % amount)
    hp_changed.emit(self)
    refresh_labels()
    if hp == 0:
        state_machine.set_state(&"DeadState")

# Called by DeadState
func on_death() -> void:
    if grid_service != null:
        position = grid_service.tile_to_world(Vector2(tile)) # a step in progress is dropped
    selected = false
    sprite.rotation = PI * 0.5
    $CollisionShape2D.set_deferred("disabled", true)
    $Area2D.input_pickable = false
    _update_color()
    refresh_labels()
    died.emit(self)
#endregion


#region labels
func refresh_labels() -> void:
    if info_label == null:
        return
    info_label.text = "%s %s | HP %d/%d" % [team, unit_type, hp, max_hp]
    var state_text := "IDLE"
    if state_machine != null and state_machine.current_state is UnitState:
        state_text = (state_machine.current_state as UnitState).describe()
    status_label.text = "%s | %s | %s" % [state_text, tile, facing]
    if show_action_points:
        status_label.text += " | AP %.1f/%.1f" % [action_points, max_action_points]

## A short message above the soldier that fades away ("-20", "blocked"...).
func show_event(text: String) -> void:
    if event_label == null:
        return
    event_label.text = text
    event_label.modulate = Color.WHITE
    if _event_tween != null:
        _event_tween.kill()
    _event_tween = create_tween()
    _event_tween.tween_interval(0.8)
    _event_tween.tween_property(event_label, "modulate:a", 0.0, 0.6)
#endregion


func _update_color() -> void:
    if sprite == null:
        return
    if not is_alive() and max_hp > 0:
        sprite.modulate = DEAD_COLOR
    elif selected:
        sprite.modulate = SELECTED_COLOR
    else:
        sprite.modulate = ENEMY_COLOR if team == TEAM_ENEMY else Color.WHITE

func _on_state_changed(_previous: StringName, _next: StringName) -> void:
    refresh_labels()
    action_changed.emit(self, get_action())

func _on_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
    if InputUtils.is_tap(event):
        clicked.emit(self)
