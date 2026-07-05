class_name RoomTypeDef
## A room type: which structure generator builds its interior and its population budget.
## Where a type may appear — and any per-biome guarantees (at least one, exactly one) — is
## decided solely by each biome's room_type_table quotas; listing it there is the opt-in.
## WORLD-unique types (one per world, placed at L1) are the exception: they use unique_scope
## + unique_allowed_biomes instead of the tables.
extends Resource

enum UniqueScope { NONE, WORLD }

@export var id: StringName                                     ## unique room-type identity
@export var generator: RoomGenBase = null                      ## structure generator + its params; null = leave the room empty
@export var unique_scope: UniqueScope = UniqueScope.NONE       ## NONE / WORLD
@export var unique_allowed_biomes: Array[StringName] = []      ## WORLD-unique placement only; ignored for NONE
@export var min_slots: int = 1                                 ## quota placement prefers rooms of >= this many merged slots (soft — falls back to any free room)
@export var footprint_blob := false                            ## interior becomes an organic blob pocket; corridors tunnel through the surrounding mass
@export var enemy_groups_min: int = 0                          ## population budget
@export var enemy_groups_max: int = 0
@export var scale_groups_with_size := true                     ## multiply the budget by merged slot area (w*h); off for exactly-one encounters (boss/rare/shrine)

## One specific scene (door, sign, altar, portal) placed at the room centre and instantiated by
## WgEntitySpawner. `feature_data` is an optional Resource applied to the instance via its
## `setup(data)` method (e.g. a DoorResource onto door.tscn) — scene and data are kept separate
## so one scene can be reused with different data. Deliberately NOT hashed (see hash_fold): like
## presentation these are an overlay on the finished room, not terrain, so swapping them never
## re-rolls a saved world.
@export var feature_scene: PackedScene = null
@export var feature_data: Resource = null


func hash_fold(h: int) -> int:
	h = WgHash.fold_var(h, id)
	h = WgHash.fold_var(h, unique_scope)
	# The generator is config too; fold a marker for null so present-vs-absent differs.
	if generator != null:
		h = generator.hash_fold(WgHash.fold_var(h, 1))
	else:
		h = WgHash.fold_var(h, 0)
	for b in unique_allowed_biomes:
		h = WgHash.fold_var(h, b)
	h = WgHash.fold_var(h, min_slots)
	h = WgHash.fold_var(h, footprint_blob)
	h = WgHash.fold_var(h, enemy_groups_min)
	h = WgHash.fold_var(h, enemy_groups_max)
	h = WgHash.fold_var(h, scale_groups_with_size)
	return h
