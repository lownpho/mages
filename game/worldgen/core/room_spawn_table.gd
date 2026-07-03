class_name RoomSpawnTable
## A biome's enemy options for ONE room type (spec §9 / §10.4): the room type named once,
## then its weighted entries. Typed ordered Resources, so both the table and its hash are
## deterministic and .tres-serializable.
extends Resource

@export var room_type: StringName                    ## which RoomTypeDef this table applies to
@export var enemies: Array[SpawnTableEntry] = []     ## weighted enemy options


func hash_fold(h: int) -> int:
	h = WgHash.fold_var(h, room_type)
	for e in enemies:
		h = e.hash_fold(h)
	return h
