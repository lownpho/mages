class_name RoomGenParams
## Base for typed per-generator parameter Resources (spec §8.2: parameters live in the room
## type registry, not in code — and spec §4.4: they are config, so they fold into CONFIG_HASH).
extends Resource


func hash_fold(h: int) -> int:
	return h
