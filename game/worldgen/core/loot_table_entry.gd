class_name LootTableEntry
## One weighted loot option inside a RoomLootTable (spec §9 / §10.4).
extends Resource

@export var item_id: StringName          ## item id (real item refs arrive later)
@export var weight: int = 1              ## weighted pick among this table's entries


func hash_fold(h: int) -> int:
	h = WgHash.fold_var(h, item_id)
	h = WgHash.fold_var(h, weight)
	return h
