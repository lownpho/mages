class_name RoomLootTable
## A biome's loot options for ONE room type (spec §9 / §10.4), mirroring RoomSpawnTable.
extends Resource

@export var room_type: StringName                    ## which RoomTypeDef this table applies to
@export var items: Array[LootTableEntry] = []        ## weighted loot options


func hash_fold(h: int) -> int:
	h = WgHash.fold_var(h, room_type)
	for e in items:
		h = e.hash_fold(h)
	return h
