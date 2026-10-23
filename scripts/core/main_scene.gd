extends Node
# Root of the game. It starts with the menu, and starts the game (the navigation scene) once the
# player has chosen a new game or a slot to load. GameState is always set up BEFORE the navigation
# scene exists, so the scene builds itself from the right data.
#
# The navigation scene must NOT be placed in this scene in the editor: it is created in _start_game().

const MENU_SCENE: PackedScene = preload("res://scenes/core/menu_scene.tscn") # adjust the paths
const NAVIGATION_SCENE: PackedScene = preload("res://scenes/core/navigation_scene.tscn")

var _menu: MainMenu
var _navigation: Node


func _ready() -> void:
    show_menu()


# TODO: to come back to the menu from the game, also free _navigation, and any city or combat
# scene (SceneService.city_scene / combat_scene), before showing it again.
func show_menu() -> void:
    QuestUI.hide() # the quest list belongs to the game, not to the menu
    _menu = MENU_SCENE.instantiate() as MainMenu
    add_child(_menu)
    _menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _menu.size = get_viewport().get_visible_rect().size
    
    _menu.new_game_requested.connect(_on_new_game_requested)
    _menu.load_game_requested.connect(_on_load_game_requested)

    await get_tree().process_frame
    print("menu pos=", _menu.position, " size=", _menu.size, " viewport=", get_viewport().get_visible_rect().size)
    for c in _menu.get_children():
        if c is Control:
            print(c.name, " pos=", c.position, " size=", c.size)

func _on_new_game_requested(slot: int) -> void:
    if GameState.start_new_game(slot):
        _start_game()


func _on_load_game_requested(slot: int) -> void:
    if GameState.load_game(slot):
        _start_game()
    else:
        _menu.show_message("Could not load slot %d (see the Debugger)" % slot)


func _start_game() -> void:
    _menu.queue_free()
    _menu = null
    QuestUI.show()
    _navigation = NAVIGATION_SCENE.instantiate()
    _navigation.name = "NavigationScene"
    add_child(_navigation)
