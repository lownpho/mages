class_name DoorResource
extends Resource
## Data for a data-driven Door: which art `style` to show and where it leads (`target_scene`).
## Apply it to a Door instance with `Door.setup()`. The world generator uses this as a room
## type's RoomFeature `data`, paired with `door.tscn` as its `scene` (WgEntitySpawner calls
## setup after instancing). Hand-placed doors can ignore this and set their exports directly.

@export var style: Door.Style = Door.Style.WOOD
@export var target_scene: PackedScene = null
## Two-way warp doors instead name the world slot of the room holding their twin (DoorLinks
## fills this in at runtime). Vector2i.MAX = not a warp door.
@export var target_slot := Vector2i.MAX
## Stair doors instead move the player one dungeon floor: -1 up, +1 down, 0 = not a stair.
@export var floor_delta := 0
