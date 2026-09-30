extends Node
#class_name AudioService

# ─────────────────────────────────────────────
#  AudioService  (autoload)
#
#  API – Music
#    play_music(stream, fade_in_duration)  → fades in a new track
#    stop_music(fade_out_duration)         → fades out the current track
#    crossfade_music(stream, duration)     → crossfades to a new track
#    set_music_volume(db)                  → sets the Music bus volume
#    pause_music()  / resume_music()
#
#  API – SFX
#    play_sfx(stream, volume_db, pitch)    → plays a one-shot SFX
#    play_sfx_at(stream, position, ...)    → positional SFX (AudioStreamPlayer2D)
#    set_sfx_volume(db)                    → sets the SFX bus volume
#
#  Audio Buses expected in the Godot project:
#    "Master"  (built-in)
#    "Music"   (add in Project → Audio Buses)
#    "SFX"     (add in Project → Audio Buses)
#
#  If those buses don't exist the service falls back gracefully to "Master".
# ─────────────────────────────────────────────

const SFX_POOL_SIZE: int = 16
const MUSIC_BUS: String = "Music"
const SFX_BUS: String = "SFX"
const DEFAULT_FADE_TIME: float = 1.0

# ── internal nodes ────────────────────────────
var _music_player_a: AudioStreamPlayer
var _music_player_b: AudioStreamPlayer
var _active_music: AudioStreamPlayer # whichever of A/B is currently "on"

var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_pool_index: int = 0

# ── tween handles ─────────────────────────────
var _music_tween: Tween


# ══════════════════════════════════════════════
#  Lifecycle
# ══════════════════════════════════════════════

func _ready() -> void:
    _setup_buses()
    _setup_music_players()
    _setup_sfx_pool()


func _setup_buses() -> void:
    # Ensure the Music and SFX buses exist; if not, create them.
    for bus_name in [MUSIC_BUS, SFX_BUS]:
        if AudioServer.get_bus_index(bus_name) == -1:
            var idx: int = AudioServer.bus_count
            AudioServer.add_bus(idx)
            AudioServer.set_bus_name(idx, bus_name)
            AudioServer.set_bus_send(idx, "Master")
            push_warning("AudioService: Created missing audio bus '%s'." % bus_name)


func _setup_music_players() -> void:
    _music_player_a = AudioStreamPlayer.new()
    _music_player_a.name = "MusicPlayerA"
    _music_player_a.bus = _resolve_bus(MUSIC_BUS)
    _music_player_a.autoplay = false
    add_child(_music_player_a)

    _music_player_b = AudioStreamPlayer.new()
    _music_player_b.name = "MusicPlayerB"
    _music_player_b.bus = _resolve_bus(MUSIC_BUS)
    _music_player_b.autoplay = false
    add_child(_music_player_b)

    _active_music = _music_player_a


func _setup_sfx_pool() -> void:
    for i in SFX_POOL_SIZE:
        var player := AudioStreamPlayer.new()
        player.name = "SFX_%d" % i
        player.bus = _resolve_bus(SFX_BUS)
        add_child(player)
        _sfx_pool.append(player)


# ══════════════════════════════════════════════
#  Music – Public API
# ══════════════════════════════════════════════

## Play a music track, optionally fading it in.
func play_music(stream: AudioStream, fade_in: float = DEFAULT_FADE_TIME, loop: bool = true) -> void:
    if stream == null:
        push_warning("AudioService.play_music: null stream provided.")
        return

    _kill_music_tween()

    _active_music.stream = stream
    _active_music.volume_db = -80.0
    _set_stream_loop(_active_music, loop)
    _active_music.play()

    if fade_in > 0.0:
        _music_tween = create_tween()
        _music_tween.tween_property(_active_music, "volume_db", 0.0, fade_in)
    else:
        _active_music.volume_db = 0.0


## Stop the current music, optionally fading it out.
func stop_music(fade_out: float = DEFAULT_FADE_TIME) -> void:
    if not _active_music.playing:
        return

    _kill_music_tween()

    if fade_out > 0.0:
        _music_tween = create_tween()
        _music_tween.tween_property(_active_music, "volume_db", -80.0, fade_out)
        _music_tween.tween_callback(_active_music.stop)
    else:
        _active_music.stop()


## Crossfade from the current track to a new one.
func crossfade_music(stream: AudioStream, duration: float = DEFAULT_FADE_TIME, loop: bool = true) -> void:
    if stream == null:
        push_warning("AudioService.crossfade_music: null stream provided.")
        return

    _kill_music_tween()

    var outgoing: AudioStreamPlayer = _active_music
    var incoming: AudioStreamPlayer = _music_player_b if outgoing == _music_player_a else _music_player_a

    incoming.stream = stream
    incoming.volume_db = -80.0
    _set_stream_loop(incoming, loop)
    incoming.play()

    _active_music = incoming

    _music_tween = create_tween()
    _music_tween.set_parallel(true)
    _music_tween.tween_property(incoming, "volume_db", 0.0, duration)
    _music_tween.tween_property(outgoing, "volume_db", -80.0, duration)
    _music_tween.set_parallel(false)
    _music_tween.tween_callback(outgoing.stop)


## Pause the current music player.
func pause_music() -> void:
    _active_music.stream_paused = true


## Resume the current music player.
func resume_music() -> void:
    _active_music.stream_paused = false


## Set the volume of the Music bus in decibels.  Range: -80 (silent) → 0 (full).
func set_music_volume(db: float) -> void:
    var idx: int = AudioServer.get_bus_index(_resolve_bus(MUSIC_BUS))
    AudioServer.set_bus_volume_db(idx, db)


## Returns whether music is currently playing.
func is_music_playing() -> bool:
    return _active_music.playing and not _active_music.stream_paused


# ══════════════════════════════════════════════
#  SFX – Public API
# ══════════════════════════════════════════════

## Play a one-shot sound effect.  Returns the player used (so callers can adjust it if needed).
func play_sfx(stream: AudioStream, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer:
    if stream == null:
        push_warning("AudioService.play_sfx: null stream provided.")
        return null

    var player := _next_sfx_player()
    player.stream = stream
    player.volume_db = volume_db
    player.pitch_scale = pitch
    player.play()
    return player


## Play a positional 2-D sound effect.
## The caller is responsible for adding a parent node if a specific scene-local position is needed;
## this version adds the player directly to the AudioService node.
func play_sfx_at(stream: AudioStream, world_position: Vector2,
        volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer2D:
    if stream == null:
        push_warning("AudioService.play_sfx_at: null stream provided.")
        return null

    var player := AudioStreamPlayer2D.new()
    player.stream = stream
    player.volume_db = volume_db
    player.pitch_scale = pitch
    player.bus = _resolve_bus(SFX_BUS)
    player.position = world_position
    player.autoplay = false
    add_child(player)
    player.play()
    # Auto-remove when finished so we don't accumulate nodes.
    player.finished.connect(player.queue_free)
    return player


## Set the volume of the SFX bus in decibels.  Range: -80 (silent) → 0 (full).
func set_sfx_volume(db: float) -> void:
    var idx: int = AudioServer.get_bus_index(_resolve_bus(SFX_BUS))
    AudioServer.set_bus_volume_db(idx, db)


# ══════════════════════════════════════════════
#  Internals
# ══════════════════════════════════════════════

func _next_sfx_player() -> AudioStreamPlayer:
    var player := _sfx_pool[_sfx_pool_index]
    _sfx_pool_index = (_sfx_pool_index + 1) % SFX_POOL_SIZE
    # If the slot is still playing, it gets interrupted (oldest-first round-robin).
    if player.playing:
        player.stop()
    return player


func _kill_music_tween() -> void:
    if _music_tween and _music_tween.is_valid():
        _music_tween.kill()
    _music_tween = null


func _resolve_bus(preferred: String) -> String:
    return preferred if AudioServer.get_bus_index(preferred) != -1 else "Master"


func _set_stream_loop(player: AudioStreamPlayer, loop: bool) -> void:
    # AudioStreamMP3 / AudioStreamOggVorbis / AudioStreamWAV all expose `loop`.
    if player.stream == null:
        return
    if player.stream.has_method("set_loop"):
        player.stream.loop = loop
    elif "loop" in player.stream:
        player.stream.loop = loop
