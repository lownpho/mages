class_name TemplateParams
extends RoomGenParams

@export var stamps: Array[RoomStamp] = []   ## hand-authored layouts; one is picked uniformly
@export var allow_mirror: bool = true
@export var allow_rotate: bool = true


func hash_fold(h: int) -> int:
	h = WgHash.fold_var(h, allow_mirror)
	h = WgHash.fold_var(h, allow_rotate)
	for s in stamps:
		if s != null:
			h = s.hash_fold(h)
	return h
