class_name ArenaParams
extends RoomGenParams

@export var inset: int = 8        ## tiles between the room wall and the blocker ring
@export var thickness: int = 2    ## ring band thickness in tiles
@export var gap_count: int = 4    ## openings carved through the ring
@export var gap_width: int = 4    ## width of each opening in tiles


func hash_fold(h: int) -> int:
	h = WgHash.fold_var(h, inset)
	h = WgHash.fold_var(h, thickness)
	h = WgHash.fold_var(h, gap_count)
	h = WgHash.fold_var(h, gap_width)
	return h
