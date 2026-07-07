class_name SpawnTableEntry
## One weighted enemy option inside a room type's spawn pool (RoomTypeDef.enemies).
extends Resource

@export var enemy_id: StringName         ## scene id under characters/enemies/<id>/
@export var weight: int = 1              ## weighted pick among this pool's entries
@export var group_min: int = 1           ## min entities per spawned group
@export var group_max: int = 1           ## max entities per spawned group


func hash_fold(h: int) -> int:
	h = WgHash.fold_var(h, enemy_id)
	h = WgHash.fold_var(h, weight)
	h = WgHash.fold_var(h, group_min)
	h = WgHash.fold_var(h, group_max)
	return h
