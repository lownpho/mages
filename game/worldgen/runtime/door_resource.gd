class_name DoorResource
extends Resource
## Data for a data-driven Door: which art `style` to show and where it leads (`target_scene`).
## Apply it to a Door instance with `Door.setup()`. The world generator uses this as a room
## type's `feature_data`, paired with `door.tscn` as its `feature_scene` (WgEntitySpawner calls
## setup after instancing). Hand-placed doors can ignore this and set their exports directly.

@export var style: Door.Style = Door.Style.WOOD
@export var target_scene: PackedScene = null
