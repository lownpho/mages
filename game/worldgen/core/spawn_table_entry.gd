class_name SpawnTableEntry
## One enemy option for a (room_type) spawn table on a BiomeDef (spec §9 / §10.4). Modeled as
## a flat typed array entry keyed by room_type rather than a Dictionary-of-arrays, so it stays
## deterministic and .tres-serializable.
extends Resource

@export var room_type: StringName        ## which RoomTypeDef this entry applies to
@export var enemy_id: StringName         ## scene id under characters/enemies/<id>/ (no scene ref yet)
@export var weight: int = 1              ## weighted pick among entries sharing room_type
@export var group_min: int = 1           ## min entities per spawned group
@export var group_max: int = 1           ## max entities per spawned group


func hash_fold(h: int) -> int:
	h = WgHash.fold_var(h, room_type)
	h = WgHash.fold_var(h, enemy_id)
	h = WgHash.fold_var(h, weight)
	h = WgHash.fold_var(h, group_min)
	h = WgHash.fold_var(h, group_max)
	return h
