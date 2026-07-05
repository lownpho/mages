class_name RoomTypeTableEntry
## One row of a biome's room-type table: a per-biome quota (min/max) plus a fill weight.
## min_per_biome placements are GUARANTEED (quota pass, before weighted fill); weight then
## competes for the remaining rooms until max_per_biome. min == max pins an exact count
## (e.g. exactly one boss room). Typed Resource, not a Dictionary, so it serializes cleanly
## inside a .tres array and is editable in the inspector.
extends Resource

@export var type_id: StringName          ## a RoomTypeDef.id
@export var weight: int = 1              ## relative selection weight in weighted fill
@export var min_per_biome: int = 0       ## guaranteed placements, satisfied before weighted fill
@export var max_per_biome: int = 99      ## weight drops to 0 once this many are placed


func hash_fold(h: int) -> int:
	h = WgHash.fold_var(h, type_id)
	h = WgHash.fold_var(h, weight)
	h = WgHash.fold_var(h, min_per_biome)
	h = WgHash.fold_var(h, max_per_biome)
	return h
