class_name RoomGenBase
## Structure generator interface (spec §8.2). Generators run as pipeline step 4 and may write
## WALL/BLOCKER anywhere EXCEPT tiles marked in `protected` — the corridor star and openings
## are the connectivity guarantee. They consume only the attempt RNG passed in; parameters
## come from RoomTypeDef.generator_params (typed Resources, Task 6).
extends RefCounted


func run(_grid: PackedByteArray, _protected: PackedByteArray, _w: int, _h: int,
		_rng: RandomNumberGenerator, _spec: RoomSpec, _config: GenConfig) -> void:
	pass
