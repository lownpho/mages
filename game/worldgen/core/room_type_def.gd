class_name RoomTypeDef
## A room type: one .tres is the COMPLETE, hand-authored room — which biome owns it, where on
## the difficulty ramp it appears, how rare it is, which generator carves it, and its own enemy
## pool + budget. Every room type belongs to exactly one biome (`biome`); registering the .tres
## in gen_config.room_types is the only other wiring. WORLD-unique types (one per world, placed
## at L1) are the exception: they leave `biome` empty and use unique_scope + unique_allowed_biomes.
extends Resource

enum UniqueScope { NONE, WORLD }

@export var id: StringName                                     ## unique room-type identity (convention: <biome>_<name>)
@export var biome: StringName                                  ## the ONE biome this room appears in (&"" only for WORLD-unique types)
@export var generator: RoomGenBase = null                      ## structure generator + its params; null = leave the room empty
@export var unique_scope: UniqueScope = UniqueScope.NONE       ## NONE / WORLD
@export var unique_allowed_biomes: Array[StringName] = []      ## WORLD-unique placement only; ignored for NONE
@export var min_slots: int = 1                                 ## quota placement prefers rooms of >= this many merged slots (soft — falls back to any free room)

## Difficulty tier 0..3 — dictates WHERE the room is placed: the biome's entrance-depth range
## splits into quarters (RoomSpec.tier()), weighted fill only assigns a type to rooms of tier
## >= difficulty (descending fallback), and quota placements pick the free room nearest their
## tier. 0 = spawn-adjacent breather, 3 = the boss's quarter.
@export_range(0, 3) var difficulty: int = 0
@export var footprint_blob := false                            ## interior becomes an organic blob pocket; corridors tunnel through the surrounding mass

@export_group("Placement")
@export var weight: int = 1              ## relative chance in the biome's weighted fill (0 = quota-only)
@export var min_per_biome: int = 0       ## guaranteed placements, satisfied before weighted fill; min == max pins an exact count
@export var max_per_biome: int = 99      ## fill weight drops to 0 once this many are placed

@export_group("Population")
@export var enemies: Array[SpawnTableEntry] = []               ## this room's own weighted enemy pool ([] = never spawns)
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
	h = WgHash.fold_var(h, biome)
	h = WgHash.fold_var(h, unique_scope)
	# The generator is config too; fold a marker for null so present-vs-absent differs.
	if generator != null:
		h = generator.hash_fold(WgHash.fold_var(h, 1))
	else:
		h = WgHash.fold_var(h, 0)
	for b in unique_allowed_biomes:
		h = WgHash.fold_var(h, b)
	h = WgHash.fold_var(h, min_slots)
	h = WgHash.fold_var(h, difficulty)
	h = WgHash.fold_var(h, weight)
	h = WgHash.fold_var(h, min_per_biome)
	h = WgHash.fold_var(h, max_per_biome)
	h = WgHash.fold_var(h, footprint_blob)
	for e in enemies:
		h = e.hash_fold(h)
	h = WgHash.fold_var(h, enemy_groups_min)
	h = WgHash.fold_var(h, enemy_groups_max)
	h = WgHash.fold_var(h, scale_groups_with_size)
	return h
