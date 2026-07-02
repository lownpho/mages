class_name LootTableEntry
## One loot option for a (room_type) loot table on a BiomeDef (spec §9 / §10.4). Typed array
## entry keyed by room_type, mirroring SpawnTableEntry.
extends Resource

@export var room_type: StringName        ## which RoomTypeDef this entry applies to
@export var item_id: StringName          ## item id (real item refs arrive later)
@export var weight: int = 1              ## weighted pick among entries sharing room_type


func hash_fold(h: int) -> int:
	h = WgHash.fold_var(h, room_type)
	h = WgHash.fold_var(h, item_id)
	h = WgHash.fold_var(h, weight)
	return h
