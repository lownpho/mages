class_name GenConfig
## The whole authored configuration for the new world generator (spec §3, §4.4, §10.4). Every
## §3 constant is an @export so it can be tuned in the inspector and saved as a .tres; the
## content registries (biomes, room types, adjacency) hang off it. compute_hash() folds all of
## it into CONFIG_HASH, which is mixed into every generation seed (spec §4.1) — so a saved
## world_seed only reproduces its world under the same content, and diverges loudly otherwise.
extends Resource

@export var gen_version: int = 1   ## GEN_VERSION — bump on any algorithm change (spec §3)

@export_group("World shape (spec §3)")
@export var ROOM_SLOT_SIZE: int = 64                                ## tiles per room-slot side
@export var BIOME_SIZE_SLOTS: int = 9                               ## room slots per biome side
@export var WORLD_SIZE_BIOMES: Vector2i = Vector2i(4, 4)            ## biome cells per world side
@export var CHUNK_SIZE: int = 32                                    ## tiles per streaming chunk side
@export var DOOR_WIDTH: int = 3                                     ## tiles per door / carved corridor

@export_group("Graph shape (spec §3)")
@export_range(0.0, 1.0, 0.01) var P_LOOP: float = 0.25             ## keep-prob for non-tree edges
@export_range(0.0, 1.0, 0.01) var P_MERGE: float = 0.15            ## per-slot merge attempt prob
@export var BORDER_CROSSINGS: int = 2                               ## doors per shared biome border

@export_group("Interior (spec §3)")
@export var MAX_ROOM_RETRIES: int = 5                               ## interior attempts before fallback
@export var MAX_LAYOUT_RETRIES: int = 1000                         ## layout attempts before config error
@export_range(0.0, 1.0, 0.01) var MIN_FLOOR_RATIO: float = 0.20    ## min reachable-floor fraction
@export var SPAWN_OPENING_GUARD: int = 6                            ## min tiles a spawn sits from any opening (spec §9)

@export_group("Streaming (spec §3)")
@export var ROOM_CACHE_CAPACITY: int = 64                           ## LRU room interiors kept in memory
@export var PREFETCH_RADIUS: int = 2                               ## chunks pre-generated around camera

@export_group("Content registries")
@export var biomes: Array[BiomeDef] = []
@export var adjacency: AdjacencyRules = null
@export var room_types: Array[RoomTypeDef] = []

# Precomputed at prepare() from the float dials above; generation loops read only these ints
# (spec §4.3.3). Not exported — recomputed from source of truth every load.
var threshold_loop: int = 0
var threshold_merge: int = 0
var _cached_hash: int = 0
var _prepared: bool = false


## Precompute integer thresholds (loop, merge, per-biome openness) once at load. Idempotent.
func prepare() -> void:
	threshold_loop = WgHash.threshold(P_LOOP)
	threshold_merge = WgHash.threshold(P_MERGE)
	for b in biomes:
		if b != null:
			b.prepare()
	_cached_hash = _compute_hash_uncached()
	_prepared = true


## CONFIG_HASH (spec §4.4). Folds var_to_bytes() of every field in a FIXED, hand-written order
## — never property-list order — recursing into biomes, room types, adjacency, and their nested
## spawn/loot tables. Cached after prepare(); recomputed on demand otherwise.
func compute_hash() -> int:
	if _prepared:
		return _cached_hash
	return _compute_hash_uncached()


func _compute_hash_uncached() -> int:
	var h: int = 0
	# Constants (spec §3), fixed order.
	h = WgHash.fold_var(h, gen_version)
	h = WgHash.fold_var(h, ROOM_SLOT_SIZE)
	h = WgHash.fold_var(h, BIOME_SIZE_SLOTS)
	h = WgHash.fold_var(h, WORLD_SIZE_BIOMES)
	h = WgHash.fold_var(h, CHUNK_SIZE)
	h = WgHash.fold_var(h, DOOR_WIDTH)
	h = WgHash.fold_var(h, P_LOOP)
	h = WgHash.fold_var(h, P_MERGE)
	h = WgHash.fold_var(h, BORDER_CROSSINGS)
	h = WgHash.fold_var(h, MAX_ROOM_RETRIES)
	h = WgHash.fold_var(h, MAX_LAYOUT_RETRIES)
	h = WgHash.fold_var(h, MIN_FLOOR_RATIO)
	h = WgHash.fold_var(h, SPAWN_OPENING_GUARD)
	h = WgHash.fold_var(h, ROOM_CACHE_CAPACITY)
	h = WgHash.fold_var(h, PREFETCH_RADIUS)
	# Content registries (spec §4.4), fixed order.
	for b in biomes:
		h = b.hash_fold(h)
	for rt in room_types:
		h = rt.hash_fold(h)
	if adjacency != null:
		h = adjacency.hash_fold(h)
	return h


## Look up a biome by id (nil if absent). Read-only convenience; safe outside RNG loops.
func biome_by_id(bid: StringName) -> BiomeDef:
	for b in biomes:
		if b != null and b.id == bid:
			return b
	return null


## Look up a room type by id (nil if absent).
func room_type_by_id(rid: StringName) -> RoomTypeDef:
	for rt in room_types:
		if rt != null and rt.id == rid:
			return rt
	return null
