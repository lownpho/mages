class_name ScatterParams
extends RoomGenParams

@export var count_per_slot: int = 10   ## clumps per room slot (scales with merged size)
@export var min_spacing: int = 4       ## minimum tile distance between clump CENTERS
@export var clump_min: int = 1         ## blockers per clump; 1/1 = lone blockers (classic scatter)
@export var clump_max: int = 1


func hash_fold(h: int) -> int:
	h = WgHash.fold_var(h, count_per_slot)
	h = WgHash.fold_var(h, min_spacing)
	h = WgHash.fold_var(h, clump_min)
	h = WgHash.fold_var(h, clump_max)
	return h
