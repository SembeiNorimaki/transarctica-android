extends Node2D
class_name GenericWagon
# Base script of the horizontal wagons (trade and combat).
# Static data (size, capacity, what it stores) comes from the WagonTypes entry of its type.
# Dynamic data (cargo, later hp) comes from the train data in GameState.
# HorizontalTrain passes both to apply_data().
#
# NOTE: this script does not read WagonTypes itself. WagonTypes preloads the wagon scenes,
# so a wagon script that reads it can create a cyclic reference.

signal clicked(wagon: GenericWagon)
signal cargo_changed(wagon: GenericWagon)

@onready var sprite: Sprite2D = $Sprite2D # kept: wagon variants may use it

var wagon_type := ""
var wagon_dim := Vector2i.ZERO # size in the horizontal view
var stores: Array = [] # cargo categories this wagon accepts
var cargo_type := ""
var cargo_amount := 0
var max_cargo_amount := 0 # capacity


# If a wagon variant overrides _ready(), it must call super() so the visuals are refreshed.
func _ready() -> void:
    _refresh_visuals()


# Override in wagon variants to show the cargo (crates, coal...).
func _refresh_visuals() -> void:
    pass


#region data
# Applies one entry of the train data's "wagons" array plus the WagonTypes entry of its type.
# Only sets variables, so it is safe to call BEFORE the wagon is in the tree.
func apply_data(wagon_data: Dictionary, type_info: Dictionary) -> void:
    wagon_type = wagon_data.get("type", "")
    wagon_dim = type_info.get("horizontal_size", Vector2i.ZERO)
    stores = type_info.get("stores", []).duplicate()
    max_cargo_amount = int(type_info.get("capacity", 0))

    cargo_type = wagon_data.get("cargo_name", "")
    var amount := int(wagon_data.get("cargo_qty", 0)) # JSON numbers are floats
    if amount > max_cargo_amount:
        push_warning("GenericWagon: %s holds %d but its capacity is %d" % [wagon_type, amount, max_cargo_amount])
    cargo_amount = clampi(amount, 0, max_cargo_amount)

    if is_node_ready():
        _refresh_visuals()


func set_wagon_type(t: String) -> void:
    wagon_type = t


func set_cargo_type(t: String) -> void:
    cargo_type = t

func set_cargo(resource_name: String, qty: int) -> void:
    cargo_type = resource_name
    cargo_amount = qty
    _refresh_visuals()

func get_icon() -> Texture2D:
    if sprite == null or sprite.texture == null:
        return null
    var cell := sprite.texture.get_size() / Vector2(sprite.hframes, sprite.vframes)
    var atlas := AtlasTexture.new()
    atlas.atlas = sprite.texture
    atlas.region = Rect2(Vector2(sprite.frame_coords) * cell, cell)
    return atlas
    
# Adds (positive) or removes (negative) cargo, limited to 0..capacity.
# Returns the amount that was actually added or removed.
func add_cargo_amount(amount: int) -> int:
    var new_amount := clampi(cargo_amount + amount, 0, max_cargo_amount)
    var changed := new_amount - cargo_amount
    if changed != 0:
        cargo_amount = new_amount
        if cargo_amount == 0:
            cargo_type = ""
        _refresh_visuals()
        cargo_changed.emit(self)
    return changed


func get_free_capacity() -> int:
    return max_cargo_amount - cargo_amount
#endregion


#region input
func _on_area_2d_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
    if _is_tap(event):
        clicked.emit(self)


func _is_tap(event: InputEvent) -> bool:
    if event is InputEventScreenTouch:
        return (event as InputEventScreenTouch).pressed
    if event is InputEventMouseButton:
        var mouse := event as InputEventMouseButton
        # Left button only (the wheel also sends button events), and ignore the mouse click
        # that Godot emulates from a touch, since the touch itself is handled above.
        return mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT \
                and mouse.device != InputEvent.DEVICE_ID_EMULATION
    return false
#endregion