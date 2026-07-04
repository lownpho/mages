class_name UnderConstructionResource
extends Resource
## Data for a data-driven UnderConstructionSign: the `message` floated above the sign when the
## player approaches. Apply it with `UnderConstructionSign.setup()`. The world generator uses this
## as a room type's `feature_data`, paired with `under_construction_sign.tscn` as its
## `feature_scene`. Hand-placed signs can ignore this and set their exports directly. Leave
## `message` empty to keep the sign's built-in default text.

@export_multiline var message := ""
