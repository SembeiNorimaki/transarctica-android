class_name VisibilityService
extends Node
# Which tiles each team sees right now and has seen before. Generic: it knows nothing about
# soldiers, cones or walls. Whoever looks (a viewer: any Object) reports the tiles it sees with
# set_viewer(); a tile is VISIBLE to a team while at least one of its viewers sees it, EXPLORED once
# it has been seen and is not any more, and UNEXPLORED before that.
#
# VisionService works out WHAT a viewer sees; this service remembers it, per team.

enum State { UNEXPLORED, EXPLORED, VISIBLE }

## Tiles that became visible to a team / stopped being visible to it. Only fires if something changed.
signal visibility_changed(team: String, shown: Array[Vector2i], hidden: Array[Vector2i])
## Tiles a team saw for the first time.
signal tiles_explored(team: String, tiles: Array[Vector2i])

var _viewers: Dictionary = {} # viewer -> {"team": String, "tiles": Dictionary tile -> true}
var _counts: Dictionary = {} # team -> {tile: how many viewers see it}
var _explored: Dictionary = {} # team -> {tile: true}


## Replaces what this viewer sees. A viewer that changes team is moved to the new one.
func set_viewer(viewer: Object, team: String, tiles: Array[Vector2i]) -> void:
    if _viewers.has(viewer) and _viewers[viewer]["team"] != team:
        remove_viewer(viewer)
    var seen := {}
    for tile in tiles:
        seen[tile] = true
    var old: Dictionary = _viewers[viewer]["tiles"] if _viewers.has(viewer) else {}
    var counts := _team_counts(team)
    var explored := _team_explored(team)
    var shown: Array[Vector2i] = []
    var hidden: Array[Vector2i] = []
    var newly_explored: Array[Vector2i] = []
    for tile: Vector2i in old:
        if not seen.has(tile):
            counts[tile] -= 1
            if counts[tile] == 0:
                counts.erase(tile)
                hidden.append(tile)
    for tile: Vector2i in seen:
        if not old.has(tile):
            counts[tile] = counts.get(tile, 0) + 1
            if counts[tile] == 1:
                shown.append(tile)
            if not explored.has(tile):
                explored[tile] = true
                newly_explored.append(tile)
    _viewers[viewer] = {"team": team, "tiles": seen}
    _emit(team, shown, hidden, newly_explored)

## The viewer is gone (dead, left the battle): its tiles stop being seen.
func remove_viewer(viewer: Object) -> void:
    if not _viewers.has(viewer):
        return
    var team: String = _viewers[viewer]["team"]
    var counts := _team_counts(team)
    var hidden: Array[Vector2i] = []
    for tile: Vector2i in _viewers[viewer]["tiles"]:
        counts[tile] -= 1
        if counts[tile] == 0:
            counts.erase(tile)
            hidden.append(tile)
    _viewers.erase(viewer)
    _emit(team, [] as Array[Vector2i], hidden, [] as Array[Vector2i])

func has_viewer(viewer: Object) -> bool:
    return _viewers.has(viewer)

## Forgets everything: nobody sees anything and nothing is explored.
func clear() -> void:
    var teams := _counts.keys()
    var hidden_by_team := {}
    for team: String in teams:
        var hidden: Array[Vector2i] = []
        for tile: Vector2i in _counts[team]:
            hidden.append(tile)
        hidden_by_team[team] = hidden
    _viewers.clear()
    _counts.clear()
    _explored.clear()
    for team: String in teams:
        if not hidden_by_team[team].is_empty():
            visibility_changed.emit(team, [] as Array[Vector2i], hidden_by_team[team])


#region queries
func get_state(team: String, tile: Vector2i) -> State:
    if _counts.get(team, {}).has(tile):
        return State.VISIBLE
    if _explored.get(team, {}).has(tile):
        return State.EXPLORED
    return State.UNEXPLORED

func is_visible(team: String, tile: Vector2i) -> bool:
    return _counts.get(team, {}).has(tile)

func is_explored(team: String, tile: Vector2i) -> bool:
    return _explored.get(team, {}).has(tile)

func get_visible_tiles(team: String) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    for tile: Vector2i in _counts.get(team, {}):
        result.append(tile)
    return result

func get_explored_tiles(team: String) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    for tile: Vector2i in _explored.get(team, {}):
        result.append(tile)
    return result
#endregion


func _team_counts(team: String) -> Dictionary:
    if not _counts.has(team):
        _counts[team] = {}
    return _counts[team]

func _team_explored(team: String) -> Dictionary:
    if not _explored.has(team):
        _explored[team] = {}
    return _explored[team]

func _emit(team: String, shown: Array[Vector2i], hidden: Array[Vector2i], newly_explored: Array[Vector2i]) -> void:
    if not shown.is_empty() or not hidden.is_empty():
        visibility_changed.emit(team, shown, hidden)
    if not newly_explored.is_empty():
        tiles_explored.emit(team, newly_explored)
