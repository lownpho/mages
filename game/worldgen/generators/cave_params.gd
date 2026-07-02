class_name CaveParams
extends RoomGenParams

@export_range(0.0, 1.0, 0.01) var fill_prob: float = 0.45   ## initial wall-noise density
@export var iterations: int = 4                              ## 4-5 rule smoothing passes
@export var write_blockers: bool = false                     ## emit BLOCKER (trees) instead of WALL


func hash_fold(h: int) -> int:
	h = WgHash.fold_var(h, fill_prob)
	h = WgHash.fold_var(h, iterations)
	h = WgHash.fold_var(h, write_blockers)
	return h
