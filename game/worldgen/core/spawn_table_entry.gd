class_name SpawnTableEntry
## One weighted enemy option inside a room type's spawn pool (RoomTypeDef.enemies).
## When `members` is non-empty it defines a mixed pack — each member gets its own
## count_min..count_max enemies around the shared pack_centre.
extends Resource

@export var enemy_id: StringName         ## scene id under characters/enemies/<id>/
@export var weight: int = 1              ## weighted pick among this pool's entries
@export var group_min: int = 1           ## min entities per spawned group (single-type)
@export var group_max: int = 1           ## max entities per spawned group (single-type)
@export var pack_spread: float = 0.0     ## max tiles from pack centre (0 = no clustering)
@export var members: Array[PackMember] = []  ## mixed pack; overrides enemy_id/group_* when non-empty


func hash_fold(h: int) -> int:
	h = WgHash.fold_var(h, enemy_id)
	h = WgHash.fold_var(h, weight)
	h = WgHash.fold_var(h, group_min)
	h = WgHash.fold_var(h, group_max)
	h = WgHash.fold_var(h, pack_spread)
	for m in members:
		h = m.hash_fold(h)
	return h
