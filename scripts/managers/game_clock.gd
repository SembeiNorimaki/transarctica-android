extends Node
class_name GameClock
# The clock of the game. It lives in the navigation scene, so time passes while the player is on the
# map, whether or not the train moves, and stops when the scene is suspended (inside a city or a
# fight) or the game is paused. The time itself (minutes since 1 Jan 2100) is in GameState, which
# saves it; this node only makes it advance.

## A day starts when the time passes 00:00.
signal day_passed(day: int)

@export var enabled := true
## Game minutes per second of play. 10: an hour in 6 seconds, a day in 2 minutes 24 seconds.
@export var minutes_per_second := 10.0

var _fraction := 0.0 # the part of a minute not counted yet


func _process(delta: float) -> void:
    if not enabled or minutes_per_second <= 0.0:
        return
    _fraction += delta * minutes_per_second
    var whole := int(_fraction)
    if whole > 0:
        _fraction -= whole
        advance_minutes(whole)


## Moves the time forward (also for the game's own use: sleeping, waiting...). Says "day_passed"
## once for each midnight passed.
func advance_minutes(minutes: int) -> void:
    var left := minutes
    while left > 0:
        # In steps up to each midnight, so whoever hears "day_passed" finds the time of that day
        var to_midnight := GameCalendar.MINUTES_PER_DAY - GameState.get_game_minutes() % GameCalendar.MINUTES_PER_DAY
        var step := mini(left, to_midnight)
        GameState.add_game_minutes(step)
        left -= step
        if step == to_midnight:
            day_passed.emit(GameState.get_game_day())
