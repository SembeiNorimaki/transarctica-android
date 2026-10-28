extends Node
# Root of the game. It starts with the menu, and starts the game (the navigation scene) once the
# player has chosen a new game or a slot to load. GameState is always set up BEFORE the navigation
# scene exists, so the scene builds itself from the right data.
#
# The navigation scene must NOT be placed in this scene in the editor: it is created in _start_game().

@onready var game_menu: GameMenu = $GameMenu

const MENU_SCENE: PackedScene = preload("res://scenes/core/menu_scene.tscn")
const NAVIGATION_SCENE: PackedScene = preload("res://scenes/core/navigation_scene.tscn")

var _menu: MainMenu
var _navigation: Node


func _ready() -> void:
    game_menu.load_requested.connect(_on_ingame_load_requested)
    show_menu()


# TODO: to come back to the menu from the game, also free _navigation, and any city or combat
# scene (SceneService.city_scene / combat_scene), before showing it again.
func show_menu() -> void:
    QuestUI.hide() # the quest list belongs to the game, not to the menu
    game_menu.hide() # the game menu belongs to the game, not to the main menu
    _menu = MENU_SCENE.instantiate() as MainMenu
    add_child(_menu)
    _menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _menu.size = get_viewport().get_visible_rect().size
    _menu.new_game_requested.connect(_on_new_game_requested)
    _menu.load_game_requested.connect(_on_load_game_requested)


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
    game_menu.show()
    var navigation := NAVIGATION_SCENE.instantiate() as NavigationScene
    navigation.name = "NavigationScene"
    navigation.menu_requested.connect(game_menu.open_menu)
    _navigation = navigation
    add_child(navigation)

# Loading from the game menu: the running game is thrown away and built again from the slot,
# because the trains, the map and the cities are only created when a game starts.
func _on_ingame_load_requested(slot: int) -> void:
    var info := GameState.get_slot_info(slot)
    if not (info.get("exists", false) and info.get("valid", false)):
        game_menu.show_message("Slot %d can't be loaded (see the Debugger)." % slot)
        return # the running game is not touched

    game_menu.close_menu(true)
    _unload_game()
    if GameState.load_game(slot):
        _start_game()
    else:
        show_menu() # it should not happen after the check above, but the old game is already gone


func _unload_game() -> void:
    SceneService.reset()
    if is_instance_valid(_navigation):
        remove_child(_navigation) # now, so the new scene can take the name "NavigationScene"
        _navigation.queue_free()
    _navigation = null
