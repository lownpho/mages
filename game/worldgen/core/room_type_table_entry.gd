class_name RoomTypeTableEntry
## One row of a biome's weighted room-type table. Typed Resource, not a
## Dictionary, so it serializes cleanly inside a .tres array and is editable in the inspector.
extends Resource

@export var type_id: StringName          ## a RoomTypeDef.id
@export var weight: int = 1              ## relative selection weight in weighted fill
@export var max_per_biome: int = 99      ## weight drops to 0 once this many are placed


func hash_fold(h: int) -> int:
	h = WgHash.fold_var(h, type_id)
	h = WgHash.fold_var(h, weight)
	h = WgHash.fold_var(h, max_per_biome)
	return h
