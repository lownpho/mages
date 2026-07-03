class_name RoomGenBase
## Structure generator interface (spec §8.2). A generator is a Resource that carries its own
## tuning @exports, so a RoomTypeDef points at ONE object that says both WHAT runs and HOW —
## a null generator means "leave the room empty". Generators run as pipeline step 4 and may
## write WALL/BLOCKER anywhere EXCEPT tiles marked in `protected` — the corridor star and
## openings are the connectivity guarantee. They consume only the attempt RNG passed in.
## Generators are config (spec §4.4): hash_fold folds the class name (so two generators with
## identical fields still hash apart) and every exported field, in fixed order.
extends Resource


func run(_grid: PackedByteArray, _protected: PackedByteArray, _w: int, _h: int,
		_rng: RandomNumberGenerator, _spec: RoomSpec) -> void:
	pass


func hash_fold(h: int) -> int:
	return WgHash.fold_var(h, get_script().get_global_name())
