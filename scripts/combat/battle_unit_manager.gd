extends Node
class_name BattleUnitManager
# The soldiers of a tile based battle: it deploys them, keeps the occupancy up to date as they
# walk, works out their paths, resolves their shots, and keeps track of the selected one.
#
# Soldiers only emit signals and run their own actions (see Soldier); this manager is the one that
# places them in TileOccupancyService and decides what a shot does.

signal selection_changed(soldier: Soldier) # null: nothing is selected
signal soldier_spawned(soldier: Soldier)
signal soldier_died(soldier: Soldier)
## The soldier left the battle alive (it boarded its train): it is gone from `soldiers`.
signal soldier_removed(soldier: Soldier)
signal shot_resolved(attacker: Soldier, target: Soldier, damage: int, cover: int)
## The path or attack preview appeared, changed or went away (see show_preview, show_attack_preview).
signal preview_changed
## The way a tap is understood changed (see ActionMode).
signal mode_changed(mode: int)

## What a tap on a tile means for the selected unit.
##   AUTO   : a free tile is a move, an enemy is an attack (the default)
##   MOVE   : every tile is a move
##   ATTACK : only an enemy is a target
enum ActionMode { AUTO, MOVE, ATTACK }

const SOLDIER_SCENE: PackedScene = preload("res://scenes/units/soldier.tscn")
## Where bullets leave and arrive, above the feet of a soldier (px).
const BULLET_HEIGHT := -24.0
## Share of the damage that gets through, by CoverLevel.
const COVER_DAMAGE := {CoverLevel.NONE: 1.0, CoverLevel.HALF: 0.75, CoverLevel.FULL: 0.5}

## The team the player commands. Soldiers of other teams can only be attacked.
var player_team := Soldier.TEAM_PLAYER

## false: every shot that is not blocked hits (for tests and for debugging). true: a shot hits with
## the chance given by get_hit_chance().
var roll_hits := true
var rng := RandomNumberGenerator.new()

# Injected by the scene
var unit_container: Node2D
var grid_service: GridService
var occupancy_service: TileOccupancyService
var pathfinding_service: PathfindingService
var vision_service: VisionService
var cover_service: CoverService
## Decides what orders are allowed (see TurnManager and RtsManager). Optional: without it, anything goes.
var flow_manager: CombatFlowManager
## Optional: where the bullets of the shots come from. Without it a shot is resolved at once.
var bullet_manager: BulletManager

var soldiers: Array[Soldier] = []
var selected: Soldier = null

## The path previewed for a soldier before it is ordered to walk it (see handle_tile_tap).
## Empty when there is none. It starts on the soldier's tile and ends on the tile that was tapped.
var preview_path: Array[Vector2i] = []
var preview_soldier: Soldier = null
## How many tiles of preview_path (from the start) the soldier can walk now, with the action
## points it has: the rest does not fit. All of them where there is no such limit.
var preview_reachable := 0
## The tile the previewed attack is aimed at (a soldier, a building, a wall, the ground: anything),
## valid while preview_attack_active. The shooter is preview_soldier. What the preview shows is
## worked out live: see get_attack_info().
var preview_attack_tile := Vector2i.ZERO
var preview_attack_active := false

## Multiplies the walking speed of every unit, those that join later too.
var unit_speed_factor := 1.0:
    set(value):
        unit_speed_factor = maxf(value, 0.1)
        for soldier in soldiers:
            soldier.speed_factor = unit_speed_factor

## false: nobody can shoot (the build scene): no attack mode, no attack preview, no order to shoot.
var attacks_enabled := true

## How the selected unit understands a tap on a tile.
var action_mode := ActionMode.AUTO

var _profiles := {} # Soldier -> MoveProfile
var _next_number := 0


# Call once, after the injection
func setup() -> void:
    assert(unit_container != null and grid_service != null and occupancy_service != null \
            and pathfinding_service != null and vision_service != null and cover_service != null,
            "BattleUnitManager: not injected")
    selection_changed.connect(func(_soldier: Soldier) -> void:
        clear_preview()
        set_action_mode(ActionMode.AUTO))
    if bullet_manager != null:
        bullet_manager.bullet_arrived.connect(_on_bullet_arrived)
    if flow_manager != null:
        flow_manager.status_changed.connect(clear_preview) # a new turn, action points spent...


#region deploying
## Puts a new soldier of this type on a free tile. Returns null (with a warning) if it can't.
func spawn(team: String, unit_type: String, tile: Vector2i, facing := "S") -> Soldier:
    if not UnitTypes.exists(unit_type):
        push_warning("BattleUnitManager: unknown unit type '%s'" % unit_type)
        return null
    var data := UnitTypes.make_unit(unit_type)
    var unit_id := "%s%d" % [team.left(1), _next_number]
    _next_number += 1
    return spawn_unit(team, unit_id, data, tile, facing)

## Puts the soldier described by `data` (see UnitTypes.make_unit; hp and so on are kept) on a free
## tile. Returns null (with a warning) if it can't.
func spawn_unit(team: String, unit_id: String, data: Dictionary, tile: Vector2i, facing := "S") -> Soldier:
    var footprint := UnitTypes.get_footprint(str(data.get("unit_type", "")))
    if not occupancy_service.is_footprint_free(tile, footprint, TileOccupancyService.LAYER_ALL):
        push_warning("BattleUnitManager: tile %s is not free for %s" % [tile, unit_id])
        return null
    data = data.duplicate()
    data["team"] = team
    var scene := SOLDIER_SCENE
    var scene_path := UnitTypes.get_scene_path(str(data.get("unit_type", "")))
    if scene_path != UnitTypes.SOLDIER_SCENE:
        scene = load(scene_path)
    var soldier := scene.instantiate() as Soldier
    soldier.setup(unit_id, data)
    soldier.grid_service = grid_service
    soldier.speed_factor = unit_speed_factor
    soldier.can_step = _can_soldier_step
    soldier.step_started.connect(_on_step_started)
    soldier.attack_fired.connect(_on_attack_fired)
    soldier.died.connect(_on_soldier_died)
    unit_container.add_child(soldier)
    soldier.place_at(tile, facing)
    occupancy_service.place(soldier, tile, soldier.footprint, TileOccupancyService.LAYER_UNIT)
    soldiers.append(soldier)
    soldier_spawned.emit(soldier)
    return soldier

## The soldier leaves the battle alive (it went back on its train). It is freed.
func remove_soldier(soldier: Soldier) -> void:
    if not soldiers.has(soldier):
        return
    soldiers.erase(soldier)
    _profiles.erase(soldier)
    occupancy_service.remove(soldier)
    if soldier == preview_soldier:
        clear_preview()
    if selected == soldier:
        select(null)
    soldier_removed.emit(soldier)
    soldier.queue_free()

## Deploys the soldiers of CombatMapManager.get_spawns(). A spawn marker may say which way its unit
## faces; otherwise the player's face north-west and the enemy's south-east, so they look at each
## other on a map laid out corner to corner.
func spawn_all(spawns: Array[Dictionary]) -> void:
    for spawn_data in spawns:
        var facing := "SE" if spawn_data["team"] == Soldier.TEAM_ENEMY else "NW"
        spawn(spawn_data["team"], spawn_data["unit_type"], spawn_data["tile"], str(spawn_data.get("facing", facing)))
#endregion


#region selection and orders
func select(soldier: Soldier) -> void:
    if selected == soldier:
        return
    if is_instance_valid(selected):
        selected.selected = false
    selected = soldier
    if selected != null:
        selected.selected = true
    selection_changed.emit(selected)

## What a tap on a tile means: a soldier of the player's team is selected. Then, depending on the
## action mode (AUTO: an enemy is attacked, a free tile is walked to):
##   move:   the path to the tile is previewed (see show_preview); tapping the same tile again walks it
##   attack: the shot at the tile (an enemy, a building, a wall, the ground) is previewed (see
##           show_attack_preview); tapping it again fires, blocked or not
func handle_tile_tap(tile: Vector2i) -> void:
    var tapped := occupancy_service.get_first_at(tile, TileOccupancyService.LAYER_UNIT) as Soldier
    if tapped != null and not tapped.visible:
        tapped = null # hidden in the fog: the player doesn't know it is there
    if tapped != null and tapped.team == player_team:
        clear_preview()
        select(null if tapped == selected else tapped)
        return
    if selected == null:
        return
    var mode := action_mode
    if not attacks_enabled:
        mode = ActionMode.MOVE
    elif mode == ActionMode.AUTO:
        mode = ActionMode.ATTACK if tapped != null else ActionMode.MOVE
    if mode == ActionMode.MOVE:
        if is_previewing(selected, tile):
            var walker := selected
            clear_preview()
            command_move(walker, tile)
        else:
            show_preview(selected, tile)
    elif is_attack_previewing(selected, tile):
        confirm_attack(selected, tile)
    else:
        show_attack_preview(selected, tile)

## Chooses how the selected unit understands taps (the HUD buttons). It is AUTO again when the
## selection changes.
func set_action_mode(mode: int) -> void:
    if mode == ActionMode.ATTACK and not attacks_enabled:
        mode = ActionMode.AUTO
    if mode == action_mode:
        return
    action_mode = mode
    clear_preview()
    mode_changed.emit(mode)

#region path preview
## Is this the path being previewed for this soldier to this tile?
func is_previewing(soldier: Soldier, tile: Vector2i) -> bool:
    return preview_soldier == soldier and not preview_path.is_empty() and preview_path[-1] == tile

## Works out the path of the soldier to the tile and keeps it as the preview, for the path overlay to
## draw: green as far as the soldier's action points go, yellow beyond. Nothing is ordered.
## Returns false (and shows no preview) if the soldier can't be commanded or there is no path.
func show_preview(soldier: Soldier, tile: Vector2i) -> bool:
    if not _may_command(soldier):
        clear_preview()
        return false
    var path := pathfinding_service.find_path(soldier.tile, tile, get_profile(soldier))
    if path.size() < 2:
        soldier.show_event("no path")
        clear_preview()
        return false
    var reachable := path.size()
    if flow_manager != null:
        reachable = flow_manager.limit_move(soldier, path).size()
    preview_soldier = soldier
    preview_path = path
    preview_reachable = reachable
    preview_changed.emit()
    return true

func clear_preview() -> void:
    if preview_path.is_empty() and preview_soldier == null:
        return
    preview_path = []
    preview_soldier = null
    preview_reachable = 0
    preview_attack_active = false
    preview_changed.emit()

## Is this the attack of this soldier on this tile that is being previewed?
func is_attack_previewing(soldier: Soldier, tile: Vector2i) -> bool:
    return preview_soldier == soldier and preview_attack_active and preview_attack_tile == tile

## Keeps the shot of the soldier at the tile as the preview, for the path overlay to draw as a
## crosshair with the hit chance: red if the shot is blocked (then it can't hit anything there).
## Nothing is fired. Returns false (and shows no preview) if the soldier can't be commanded.
func show_attack_preview(soldier: Soldier, tile: Vector2i) -> bool:
    if not attacks_enabled or not _may_command(soldier) or tile == soldier.tile:
        clear_preview()
        return false
    preview_path = []
    preview_reachable = 0
    preview_soldier = soldier
    preview_attack_tile = tile
    preview_attack_active = true
    preview_changed.emit()
    return true

## Fires the previewed shot, blocked or not (a blocked shot hits what blocks it). Only a soldier
## with no AP left can't.
func confirm_attack(soldier: Soldier, tile: Vector2i) -> bool:
    clear_preview()
    return command_attack_tile(soldier, tile)

## Shoots at a tile from where the soldier stands.
func command_attack_tile(soldier: Soldier, tile: Vector2i) -> bool:
    if not attacks_enabled or not _may_command(soldier) or tile == soldier.tile:
        return false
    if flow_manager != null and not flow_manager.can_attack(soldier):
        flow_manager.refuse(soldier, "no AP")
        return false
    return soldier.order_attack_tile(tile)

## Where a shot of the soldier, from where it stands, would end up if fired at this tile:
## {"reached": bool (does it get to the tile?), "impact_tile": where it stops,
##  "impact_edge": [tile, tile] of the wall it hits, or [] , "reason": why it stops short ("" if it
##  doesn't: "out of range", "no line of sight")}
func trace_shot(soldier: Soldier, tile: Vector2i) -> Dictionary:
    var reach := float(soldier.get_weapon()["range"])
    var line := vision_service.get_line(soldier.tile, tile)
    var result := {"reached": true, "impact_tile": tile, "impact_edge": [], "reason": ""}
    for i in range(1, line.size()):
        if Vector2(soldier.tile).distance_to(Vector2(line[i])) > reach:
            return {"reached": false, "impact_tile": line[i - 1], "impact_edge": [], "reason": "out of range"}
        var edges := vision_service.edge_service
        if edges != null and (edges.is_view_blocked(line[i - 1], line[i]) or edges.is_fire_blocked(line[i - 1], line[i])):
            return {"reached": false, "impact_tile": line[i - 1], "impact_edge": [line[i - 1], line[i]], "reason": "no line of sight"}
        if i < line.size() - 1 and vision_service.tile_blocks_vision(line[i]):
            return {"reached": false, "impact_tile": line[i], "impact_edge": [], "reason": "no line of sight"}
    return result

## What a shot of the soldier at the tile would be like now:
## {"tile", "distance": tiles, "hit_chance": 0..1 (0 if blocked), "cover": CoverLevel, "in_range": bool,
##  "line_of_sight": bool, "has_ap": bool, "blocked": bool (it does not get to the tile),
##  "reason": why it is blocked or can't be fired ("" if it is not), "impact_tile", "impact_edge",
##  "impact_position": where the bullet stops, in world coordinates, "target": the Soldier there or null}
func get_attack_info(soldier: Soldier, tile: Vector2i) -> Dictionary:
    var weapon := soldier.get_weapon()
    var distance := Vector2(soldier.tile).distance_to(Vector2(tile))
    var trace := trace_shot(soldier, tile)
    var has_ap := flow_manager == null or flow_manager.can_attack(soldier)
    var blocked: bool = not trace["reached"]
    var reason := str(trace["reason"])
    if reason == "" and not has_ap:
        reason = "no AP"
    var edge: Array = trace["impact_edge"]
    var impact_tile: Vector2i = trace["impact_tile"]
    var impact_position := grid_service.tile_to_world(Vector2(impact_tile))
    if edge.size() == 2:
        impact_position = (grid_service.tile_to_world(Vector2(edge[0])) + grid_service.tile_to_world(Vector2(edge[1]))) / 2.0
    return {
        "tile": tile, "distance": distance,
        "hit_chance": 0.0 if blocked else get_hit_chance(soldier, soldier.tile, tile),
        "cover": cover_service.get_cover(soldier.tile, tile),
        "in_range": distance <= float(weapon["range"]), "line_of_sight": trace["reason"] != "no line of sight",
        "has_ap": has_ap, "blocked": blocked, "reason": reason,
        "impact_tile": impact_tile, "impact_edge": edge, "impact_position": impact_position,
        "target": occupancy_service.get_first_at(tile, TileOccupancyService.LAYER_UNIT) as Soldier,
    }

## The chance that a shot of this soldier, from this tile, hits what is on the tile: the weapon's
## accuracy, which falls to half of it at the end of the weapon's range.
func get_hit_chance(soldier: Soldier, from_tile: Vector2i, tile: Vector2i) -> float:
    var weapon := soldier.get_weapon()
    var reach := maxf(float(weapon["range"]), 1.0)
    var distance := Vector2(from_tile).distance_to(Vector2(tile))
    var chance := float(weapon["accuracy"]) * (1.0 - 0.5 * clampf(distance / reach, 0.0, 1.0))
    return clampf(chance, 0.05, 1.0)
#endregion

## What a right click on a tile means: the selected unit turns to look at it. It costs nothing.
## A unit that is walking or shooting keeps going.
func handle_tile_right_tap(tile: Vector2i) -> void:
    if selected != null:
        command_face(selected, tile)

func command_face(soldier: Soldier, tile: Vector2i) -> bool:
    if not _may_command(soldier) or soldier.get_action() != &"idle":
        return false
    return soldier.look_at_tile(tile)

func command_move(soldier: Soldier, tile: Vector2i) -> bool:
    if not _may_command(soldier):
        return false
    var path := pathfinding_service.find_path(soldier.tile, tile, get_profile(soldier))
    if path.size() < 2:
        soldier.show_event("no path")
        return false
    if flow_manager != null:
        var allowed := flow_manager.limit_move(soldier, path)
        if allowed.size() < 2:
            flow_manager.refuse(soldier, "no AP")
            return false
        path = allowed # the flow may let it walk only part of the way
    soldier.order_move(path)
    return true

## Shoots from where it stands if the target is in range and in sight, otherwise walks towards the
## target until it is, then shoots.
func command_attack(soldier: Soldier, target: Soldier) -> bool:
    if not attacks_enabled or target.team == soldier.team or not target.is_alive() or not _may_command(soldier):
        return false
    if can_shoot(soldier, soldier.tile, target):
        if flow_manager != null and not flow_manager.can_attack(soldier):
            flow_manager.refuse(soldier, "no AP")
            return false
        soldier.order_attack(target)
        return true
    var profile := get_profile(soldier)
    profile.goal_may_be_occupied = true
    var path := pathfinding_service.find_path(soldier.tile, target.tile, profile)
    profile.goal_may_be_occupied = false
    for i in path.size():
        if can_shoot(soldier, path[i], target):
            var walk: Array[Vector2i] = []
            walk.assign(path.slice(0, i + 1))
            if flow_manager != null and not flow_manager.can_attack(soldier, flow_manager.get_move_cost(soldier, walk)):
                flow_manager.refuse(soldier, "no AP")
                return false
            soldier.order_move(walk, target)
            return true
    soldier.show_event("can't reach")
    return false

## Could this soldier, standing on `from_tile`, hit the target?
func can_shoot(soldier: Soldier, from_tile: Vector2i, target: Soldier) -> bool:
    var weapon := soldier.get_weapon()
    var distance := Vector2(from_tile).distance_to(Vector2(target.tile))
    return distance <= float(weapon["range"]) and vision_service.has_line_of_sight(from_tile, target.tile)
#endregion


## The movement rules of this soldier (it never blocks itself).
func get_profile(soldier: Soldier) -> MoveProfile:
    if not _profiles.has(soldier):
        var profile := MoveProfile.new()
        profile.ignore = soldier
        profile.footprint = soldier.footprint
        _profiles[soldier] = profile
    return _profiles[soldier]

func _may_command(soldier: Soldier) -> bool:
    if not soldier.is_alive():
        return false
    if flow_manager != null and not flow_manager.can_command(soldier):
        flow_manager.refuse(soldier, "not now")
        return false
    return true

func _can_soldier_step(soldier: Soldier, from: Vector2i, to: Vector2i) -> bool:
    return pathfinding_service.can_step(from, to, get_profile(soldier))

func _on_step_started(soldier: Soldier, _from: Vector2i, to: Vector2i) -> void:
    occupancy_service.move(soldier, to)
    if soldier == preview_soldier:
        clear_preview()

# The soldier fired. What happens is decided now (the cover, whether it hits, where the bullet
# stops); a bullet flies there and the damage is done when it gets there: to the soldier, building or
# wall that it hits.
func _on_attack_fired(attacker: Soldier, target: Soldier) -> void:
    var tile := attacker.attack_tile
    if target != null:
        if not is_instance_valid(target) or not target.is_alive():
            return
        if not can_shoot(attacker, attacker.tile, target):
            attacker.show_event("no shot")
            return
        tile = target.tile
    var info := get_attack_info(attacker, tile)
    var cover := int(info["cover"])
    var damage := roundi(float(attacker.get_weapon()["damage"]) * float(COVER_DAMAGE[cover]))
    var reached: bool = not info["blocked"]
    var hits: bool = reached and (not roll_hits or rng.randf() < float(info["hit_chance"]))
    attacker.show_event("fire!")
    var shot := {"attacker": attacker, "target": target, "tile": tile, "damage": damage, "cover": cover,
        "hits": hits, "reached": reached, "reason": info["reason"], "impact_tile": info["impact_tile"], "impact_edge": info["impact_edge"]}
    if bullet_manager == null:
        _resolve_shot(shot)
        return
    var aim := Vector2(0, BULLET_HEIGHT)
    var end: Vector2 = info["impact_position"]
    if reached:
        end = target.position if target != null else grid_service.tile_to_world(Vector2(tile))
    # a shot that is stopped goes exactly where it is stopped; one that misses flies past
    bullet_manager.fire(attacker.position + aim, end + aim, hits or not reached, shot)

func _on_bullet_arrived(bullet: Bullet) -> void:
    _resolve_shot(bullet.payload)

# The bullet is there: damage to what it hits
func _resolve_shot(shot: Dictionary) -> void:
    var attacker := shot.get("attacker") as Soldier
    if not is_instance_valid(attacker):
        return
    var target := shot.get("target") as Soldier
    var damage := 0
    var amount := int(shot["damage"])
    if shot["reached"]:
        if target == null:
            target = occupancy_service.get_first_at(shot["tile"], TileOccupancyService.LAYER_UNIT) as Soldier
        var building := occupancy_service.get_first_at(shot["tile"], TileOccupancyService.LAYER_STRUCTURE) as GenericBuilding
        if shot["hits"]:
            if target != null and target.is_alive() and target.team != attacker.team:
                target.take_damage(amount, attacker)
                damage = amount
            elif building != null:
                building.take_damage(amount, attacker)
                damage = amount
        elif is_instance_valid(target):
            target.show_event("miss")
    else:
        # stopped on the way: a wall or a building takes the hit
        var edge: Array = shot["impact_edge"]
        var blocker := occupancy_service.get_first_at(shot["impact_tile"], TileOccupancyService.LAYER_STRUCTURE) as GenericBuilding
        if edge.size() == 2 and vision_service.edge_service != null:
            vision_service.edge_service.damage(edge[0], edge[1], amount)
            damage = amount
        elif blocker != null and shot["reason"] == "no line of sight":
            blocker.take_damage(amount, attacker)
            damage = amount
    shot_resolved.emit(attacker, target, damage, int(shot["cover"]))

func _on_soldier_died(soldier: Soldier) -> void:
    occupancy_service.remove(soldier)
    if soldier == preview_soldier:
        clear_preview()
    if selected == soldier:
        select(null)
    soldier_died.emit(soldier)
