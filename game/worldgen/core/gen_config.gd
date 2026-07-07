class_name GenConfig
## The whole authored configuration for the world generator. Every dial is an @export so it
## can be tuned in the inspector and saved as a .tres; the content
## registries (biomes, room types, adjacency) hang off it. compute_hash() folds the
## world-affecting fields into CONFIG_HASH, which is mixed into every generation seed
## — so a saved world_seed only reproduces its world under the same content, and
## diverges loudly otherwise. Runtime dials (streaming, retry caps) are deliberately NOT
## hashed: they cannot change the generated world, so tuning them must not re-roll it.
extends Resource

@export var gen_version: int = 7   ## GEN_VERSION — bump on any algorithm change

@export_group("World shape")
@export var room_slot_tiles: int = 64        ## tiles per room-slot side
@export var biome_slots: int = 9             ## room slots per biome side
@export var world_width_biomes: int = 4      ## biome cells per row; rows = biomes.size() / width
@export var door_width_tiles: int = 3        ## tiles per door / carved corridor

@export_group("Graph shape")
@export_range(0.0, 1.0, 0.01) var extra_connection_chance: float = 0.25  ## keep-prob for non-tree edges (loops)
@export_range(0.0, 1.0, 0.01) var room_merge_chance: float = 0.15        ## per-slot merge attempt prob
@export_range(0.0, 1.0, 0.01) var big_merge_chance: float = 0.0          ## P(a merge hit tries 3-slot shapes first)
@export var doors_per_biome_border: int = 2                              ## crossings per shared biome border

@export_group("Interior")
@export var max_room_retries: int = 5                                    ## interior attempts before fallback
@export_range(0.0, 1.0, 0.01) var min_reachable_floor_ratio: float = 0.20  ## validation floor fraction
@export var spawn_min_dist_from_doors: int = 6                           ## tiles between a spawn and any opening
@export var wall_extra_depth: int = 2                                    ## max extra wall rings of shell noise (0 = straight shell)
@export var wall_outer_erode: int = 0                                    ## max tiles the clearing-facing wall edge recedes (0 = straight outer edge); void-facing world edges never erode
@export var wall_noise_period: int = 4                                   ## tiles between wall-noise lattice samples
@export var corner_radius: int = 3                                       ## room-corner rounding radius, varied ±1 per corner (0 = square)
@export var wall_inset_max: int = 0                                      ## max per-side base wall inset, hashed per room side — asymmetric margins so rooms stop filling their slots evenly

@export_group("Well-known ids")
@export var starting_biome: StringName = &"glade"           ## hosts the player spawn; presentation fallback

@export_group("Runtime (not hashed — cannot affect the generated world)")
@export var chunk_tiles: int = 32              ## tiles per streaming chunk side (a view, not content)
@export var max_layout_retries: int = 1000     ## layout attempts before config error
@export var room_cache_capacity: int = 64      ## LRU room interiors kept in memory
@export var prefetch_radius_chunks: int = 2    ## chunks pre-generated around the camera

@export_group("Content registries")
@export var biomes: Array[BiomeDef] = []
@export var adjacency: AdjacencyRules = null
@export var room_types: Array[RoomTypeDef] = []

# CONFIG_HASH is cached on first use — the config must not be mutated once generation has
# started (tests that probe hash sensitivity mutate a duplicate(true), which starts uncached).
var _cached_hash: int = 0
var _hash_valid: bool = false


func world_height_biomes() -> int:
	@warning_ignore("integer_division")
	return biomes.size() / maxi(world_width_biomes, 1)


## Content sanity for the one structural invariant code can't default away: the biome list
## must tile the world grid exactly (every biome appears exactly once). Loud, not an assert.
func validate() -> bool:
	if biomes.is_empty() or world_width_biomes < 1:
		push_error("GenConfig: need at least one biome and world_width_biomes >= 1")
		return false
	if biomes.size() % world_width_biomes != 0:
		push_error("GenConfig: %d biomes don't fill a width-%d grid (each biome appears exactly once — add/remove biomes or change world_width_biomes)"
				% [biomes.size(), world_width_biomes])
		return false
	# Every biome needs its own fallback room (an owned, registered type) — it is what a room
	# becomes when a tier fill finds nothing, so a missing one would leave rooms untyped.
	for b in biomes:
		var fb := room_type_by_id(b.fallback_room_type)
		if fb == null or fb.biome != b.id:
			push_error("GenConfig: biome '%s' fallback room type '%s' missing or not owned by it"
					% [b.id, b.fallback_room_type])
			return false
	return true


## CONFIG_HASH. Folds var_to_bytes() of every world-affecting field in a FIXED,
## hand-written order — never property-list order — recursing into biomes, room types,
## adjacency, and their nested spawn tables. Cached after the first call.
func compute_hash() -> int:
	if not _hash_valid:
		_cached_hash = _compute_hash_uncached()
		_hash_valid = true
	return _cached_hash


## Derive a seed from an ordered parts list under this config.
## parts[0] is always world_seed, parts[1] a WgHash.NS_* namespace constant.
func seed_for(parts: Array[int]) -> int:
	return WgHash.seed_for(gen_version, compute_hash(), parts)


## The one sanctioned way to make a per-unit generation RNG.
func rng_for(parts: Array[int]) -> RandomNumberGenerator:
	return WgHash.rng(seed_for(parts))


func _compute_hash_uncached() -> int:
	var h: int = 0
	# World-affecting constants, fixed order.
	h = WgHash.fold_var(h, gen_version)
	h = WgHash.fold_var(h, room_slot_tiles)
	h = WgHash.fold_var(h, biome_slots)
	h = WgHash.fold_var(h, world_width_biomes)
	h = WgHash.fold_var(h, door_width_tiles)
	h = WgHash.fold_var(h, extra_connection_chance)
	h = WgHash.fold_var(h, room_merge_chance)
	h = WgHash.fold_var(h, big_merge_chance)
	h = WgHash.fold_var(h, doors_per_biome_border)
	h = WgHash.fold_var(h, max_room_retries)
	h = WgHash.fold_var(h, min_reachable_floor_ratio)
	h = WgHash.fold_var(h, spawn_min_dist_from_doors)
	h = WgHash.fold_var(h, wall_extra_depth)
	h = WgHash.fold_var(h, wall_outer_erode)
	h = WgHash.fold_var(h, wall_noise_period)
	h = WgHash.fold_var(h, corner_radius)
	h = WgHash.fold_var(h, wall_inset_max)
	h = WgHash.fold_var(h, starting_biome)
	# Content registries, fixed order.
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


## A biome's room roster: the registered types it owns, in REGISTRY order (the canonical
## iteration order for L2's placement draws — authored, deterministic).
func rooms_for_biome(bid: StringName) -> Array[RoomTypeDef]:
	var out: Array[RoomTypeDef] = []
	for rt in room_types:
		if rt != null and rt.biome == bid:
			out.append(rt)
	return out
