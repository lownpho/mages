class_name PackMember
## One enemy type + count inside a SpawnTableEntry's mixed pack.
extends Resource

@export var enemy_id: StringName         ## scene id under characters/enemies/<id>/
@export var count_min: int = 1           ## min entities of this type in the pack
@export var count_max: int = 1           ## max entities of this type in the pack


func hash_fold(h: int) -> int:
	h = WgHash.fold_var(h, enemy_id)
	h = WgHash.fold_var(h, count_min)
	h = WgHash.fold_var(h, count_max)
	return h