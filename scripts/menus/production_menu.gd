extends PanelContainer
class_name ProductionMenu
# The menu of an industry: its recipes, and a button to run each one. It is only a VIEW: it shows
# what it is told and emits produce_requested. TradeScene decides whether the production happens.
#
# Scene structure (production_menu.tscn):
#   ProductionMenu (PanelContainer, this script)
#   `- VBoxContainer
#      |- Title (Label)          the name of the place
#      |- Rows (VBoxContainer)   one row per recipe: filled by this script
#      `- CloseButton (Button)

signal produce_requested(recipe_index: int, times: int)
signal closed

@onready var title_label: Label = $VBoxContainer/Title
@onready var rows: VBoxContainer = $VBoxContainer/Rows
@onready var close_button: Button = $VBoxContainer/CloseButton

var _recipes: Array = [] # [{name, inputs: {resource: qty}, outputs: {resource: qty}}]


func _ready() -> void:
    close_button.pressed.connect(close)
    hide()


# Opens the menu. `batches[i]` is how many times recipe i can run right now.
func show_recipes(place_name: String, recipes: Array, batches: Array[int]) -> void:
    title_label.text = place_name
    _recipes = recipes
    _rebuild_rows(batches)
    show()


# The stock changed: only the buttons change, the recipes are the same
func set_batches(batches: Array[int]) -> void:
    if visible:
        _rebuild_rows(batches)


func close() -> void:
    if not visible:
        return
    hide()
    closed.emit()


func _rebuild_rows(batches: Array[int]) -> void:
    for child in rows.get_children():
        rows.remove_child(child)
        child.queue_free()

    for i in _recipes.size():
        var recipe: Dictionary = _recipes[i]
        var max_batches := batches[i] if i < batches.size() else 0

        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 12)
        rows.add_child(row)

        var label := Label.new()
        label.text = "%s:  %s  ->  %s" % [recipe.name, _describe(recipe.inputs), _describe(recipe.outputs)]
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(label)

        var one := Button.new()
        one.text = "Produce"
        one.disabled = max_batches < 1
        one.pressed.connect(produce_requested.emit.bind(i, 1))
        row.add_child(one)

        var all := Button.new()
        all.text = "Max (%d)" % max_batches
        all.disabled = max_batches < 2 # with 0 or 1 it is the same as "Produce"
        all.pressed.connect(produce_requested.emit.bind(i, max_batches))
        row.add_child(all)


# {"wood": 2, "coal": 1} -> "wood x2, coal x1"; a recipe without inputs -> "nothing"
func _describe(amounts: Dictionary) -> String:
    if amounts.is_empty():
        return "nothing"
    var parts: Array[String] = []
    for resource_name in amounts:
        parts.append("%s x%d" % [resource_name, amounts[resource_name]])
    return ", ".join(parts)
