extends RefCounted
class_name WagonPictures
# The small pictures of what a wagon holds, for the views that list a train (TrainInfoPanel) and the
# one that shows a wagon of the battle (UnitHud). All static: it only cuts pictures out of sheets.

const RESOURCE_SHEET: Texture2D = preload("res://assets/resources/resources_120x46.png")
const RESOURCE_SHEET_COLUMNS := 3
const RESOURCE_SHEET_ROWS := 10 # 360 x 460 px: 3 columns of 120 px, 10 rows of 46 px (like the sprite in trade_resource.tscn)
## The placeholders of the maps: a column per team (player, enemy), a row per vehicle type (VehicleCarrierWagon.VEHICLE_FRAMES).
const VEHICLE_SHEET: Texture2D = preload("res://assets/combat/unitsFH_placeholder.png")
const VEHICLE_FRAME := Vector2(70, 54)
const SOLDIER_FRAMES: SpriteFrames = preload("res://assets/tilesets/unit.tres")


## The picture of a resource ("coal"...), or null if it has none.
static func resource_icon(resource_name: String) -> Texture2D:
    if resource_name.is_empty():
        return null
    var frame := ResourceTypes.frame_for(resource_name)
    if frame < 0:
        return null
    var cell := RESOURCE_SHEET.get_size() / Vector2(RESOURCE_SHEET_COLUMNS, RESOURCE_SHEET_ROWS)
    var atlas := AtlasTexture.new()
    atlas.atlas = RESOURCE_SHEET
    atlas.region = Rect2(Vector2(frame % RESOURCE_SHEET_COLUMNS, floori(frame / float(RESOURCE_SHEET_COLUMNS))) * cell, cell)
    return atlas


## A unit of this type: a vehicle seen from the side (as on the vehicle carrier), a soldier facing the viewer.
static func unit_icon(unit_type: String, team := "player") -> Texture2D:
    var row := VehicleCarrierWagon.VEHICLE_FRAMES.find(unit_type)
    if row < 0:
        return SOLDIER_FRAMES.get_frame_texture(&"S", 0)
    var atlas := AtlasTexture.new()
    atlas.atlas = VEHICLE_SHEET
    atlas.region = Rect2(Vector2(1.0 if team == "enemy" else 0.0, float(row)) * VEHICLE_FRAME, VEHICLE_FRAME)
    return atlas
