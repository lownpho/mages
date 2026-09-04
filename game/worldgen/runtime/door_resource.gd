class_name DoorResource
extends Resource
## Data for a data-driven Door: which art `style` to show and where it leads (`target_scene`).
## Apply it to a Door instance with `Door.setup()`. The world generator uses this as a room
## type's RoomFeature `data`, paired with `door.tscn` as its `scene` (WgEntitySpawner calls
## setup after instancing). Hand-placed doors can ignore this and set their exports directly.

@export var style: Door.Style = Door.Style.WOOD
@export var target_scene: PackedScene = null
## One-way warp doors instead name the world slot of the room they lead to (DoorLinks fills this
## in at runtime). Vector2i.MAX = not a warp door.
@export var target_slot := Vector2i.MAX
## An authored GATE door names a BIOME instead, and DoorLinks resolves it to one fixed ordinary
## room in that biome per seed — a hand-placed one-way way in, where `target_slot` doors are
## rolled. Ignored once `target_slot` is set; &"" = not a gate. A gate whose biome is missing from
## the world is dropped rather than placed as a dead door.
@export var target_biome: StringName = &""
## Stair doors instead move the player one dungeon floor: -1 up, +1 down, 0 = not a stair.
@export var floor_delta := 0
