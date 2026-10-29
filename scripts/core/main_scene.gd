extends Node
# Root of the game. It starts with the menu, and starts the game (the navigation scene) once the
# player has chosen a new game or a slot to load. GameState is always set up BEFORE the navigation
# scene exists, so the scene builds itself from the right data.
#
# The navigation scene must NOT be placed in this scene in the editor: it is created in _start_game().

const MENU_SCENE: PackedScene = preload("res://scenes/core/menu_scene.tscn")
const NAVIGATION_SCENE: PackedScene = preload("res://scenes/core/navigation_scene.tscn")
const INTRO_SCENE: PackedScene = preload("res://scenes/UI/intro_screen.tscn")
const INTRO_LAYER := 120 # above the loading screen (100), which the navigation scene shows while it builds the map

var _menu: MainMenu
var _navigation: Node


func _ready() -> void:
    GameMenu.load_requested.connect(_on_ingame_load_requested)
    show_menu()


# TODO: to come back to the menu from the game, also free _navigation, and any city or combat
# scene (SceneService.city_scene / combat_scene), before showing it again.
func show_menu() -> void:
    QuestUI.hide() # the quest list belongs to the game, not to the menu
    GameMenu.hide() # the game menu belongs to the game, not to the main menu
    _menu = MENU_SCENE.instantiate() as MainMenu
    add_child(_menu)
    _menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _menu.size = get_viewport().get_visible_rect().size
    _menu.new_game_requested.connect(_on_new_game_requested)
    _menu.load_game_requested.connect(_on_load_game_requested)


func _on_new_game_requested(slot: int) -> void:
    var campaign_id := Campaigns.DEFAULT_ID # TODO: the menu will let the player choose
    QuestManager.hold_offers() # the first quest must not appear over the intro
    if GameState.start_new_game(slot, campaign_id):
        _start_game(Campaigns.get_info(campaign_id)["intro"])
    else:
        QuestManager.release_offers()


func _on_load_game_requested(slot: int) -> void:
    if GameState.load_game(slot):
        _start_game()
    else:
        _menu.show_message("Could not load slot %d (see the Debugger)" % slot)


# `intro` is {text, image} of the campaign (a NEW game). With a text, the intro covers the screen
# while the game loads, and the player taps to start. A loaded game has no intro: it just starts.
func _start_game(intro := {}) -> void:
    _menu.queue_free()
    _menu = null
    var navigation := NAVIGATION_SCENE.instantiate() as NavigationScene
    navigation.name = "NavigationScene"
    navigation.menu_requested.connect(GameMenu.open_menu)
    _navigation = navigation

    if str(intro.get("text", "")).is_empty():
        QuestUI.show()
        GameMenu.show()
        add_child(navigation)
        QuestManager.release_offers() # in case a new game had no intro
        return
    await _play_intro(navigation, intro)


# The intro is on screen while the navigation scene builds itself. It closes when the text is
# complete, the game is loaded AND the player taps. The game waits (paused) until then.
func _play_intro(navigation: NavigationScene, intro: Dictionary) -> void:
    var screen := INTRO_SCENE.instantiate() as IntroScreen
    screen.layer = INTRO_LAYER
    add_child(screen)
    var image_path := str(intro.get("image", ""))
    var image: Texture2D = load(image_path) if ResourceLoader.exists(image_path) else null
    screen.play(str(intro["text"]), image)
    screen.text_finished.connect(func() -> void:
        if not navigation.is_loaded:
            screen.set_prompt("Loading...")) # the text is complete but the game is not ready

    add_child(navigation) # it starts building the map now
    if not navigation.is_loaded:
        await navigation.loaded
    get_tree().paused = true # the trains must not move under the intro
    if not screen.is_finished():
        await screen.text_finished
    screen.set_prompt("Tap to continue")
    await screen.dismissed

    get_tree().paused = false
    screen.queue_free()
    QuestUI.show()
    GameMenu.show()
    QuestManager.release_offers() # now the first quest can appear

# Loading from the game menu: the running game is thrown away and built again from the slot,
# because the trains, the map and the cities are only created when a game starts.
func _on_ingame_load_requested(slot: int) -> void:
    var info := GameState.get_slot_info(slot)
    if not (info.get("exists", false) and info.get("valid", false)):
        GameMenu.show_message("Slot %d can't be loaded (see the Debugger)." % slot)
        return # the running game is not touched

    GameMenu.close_menu(true)
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
