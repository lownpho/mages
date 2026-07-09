class_name GenConfig
## The whole authored configuration for the world generator. Every dial is an @export so it
## can be tuned in the inspector and saved as a .tres; the content
## registries (biomes, room types, adjacency) hang off it. compute_hash() folds the
## world-affecting fields into CONFIG_HASH, which is mixed into every generation seed
## — so a saved world_seed only reproduces its world under the same content, and
## diverges loudly otherwise. Runtime dials (streaming, retry caps) are deliberately NOT
## hashed: they cannot change the generated world, so tuning them must not re-roll it.
extends Resource

@export var gen_version: int = 8   ## GEN_VERSION — bump on any algorithm change

@export_group("World shape")
@export var room_slot_tiles: int = 64        ## tiles per room-slot side
@export var biome_slots: int = 9             ## room slots per macro-cell side
@export var world_width_cells: int = 4       ## macro-cells per row; world height comes from the packer
@export var door_width_tiles: int = 3        ## tiles per door / carved corridor

@export_group("Graph shape")
@export_range(0.0, 1.0, 0.01) var extra_connection_chance: float = 0.25  ## keep-prob for non-tree edges (loops)
@export_range(0.0, 1.0, 0.01) var bsp_stop_chance: float = 0.35          ## P(a rect already within bsp_max_leaf_slots stops splitting — bigger rooms)
@export var bsp_max_leaf_slots := Vector2i(3, 3)                         ## max room size in slots; larger rects always split
@export var doors_per_biome_border: int = 2                              ## crossings per shared macro-cell border

@export_group("Interior")
@export var pocket_seal_max_tiles: int = 12                              ## repair: unreachable pockets up to this size are sealed, larger ones get corridor-connected
@export_range(0.0, 1.0, 0.01) var min_reachable_floor_ratio: float = 0.20  ## repair erodes walls until this reachable fraction holds
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


## Content sanity for structural invariants code can't default away: unique ids, valid
## references, feasible sizes (the BSP demand carving and the packer rely on these to be
## total functions — validate() failing loudly at load is what lets generation never fail).
func validate() -> bool:
	if biomes.is_empty() or world_width_cells < 1:
		push_error("GenConfig: need at least one biome and world_width_cells >= 1")
		return false
	if door_width_tiles + 4 > room_slot_tiles:
		push_error("GenConfig: room_slot_tiles (%d) too small for door_width_tiles (%d) + 4 margin"
				% [room_slot_tiles, door_width_tiles])
		return false
	var biome_ids: Dictionary = {}   # membership only, never iterated
	for b in biomes:
		if b == null or b.id == &"":
			push_error("GenConfig: null or id-less biome in the registry")
			return false
		if biome_ids.has(b.id):
			push_error("GenConfig: duplicate biome id '%s'" % b.id)
			return false
		biome_ids[b.id] = true
		if b.size_cells.x < 1 or b.size_cells.y < 1:
			push_error("GenConfig: biome '%s' size_cells must be at least 1x1" % b.id)
			return false
		if b.size_cells.x > world_width_cells:
			push_error("GenConfig: biome '%s' is %d cells wide but the world is only %d"
					% [b.id, b.size_cells.x, world_width_cells])
			return false
	var type_ids: Dictionary = {}   # membership only, never iterated
	for rt in room_types:
		if rt == null or rt.id == &"":
			push_error("GenConfig: null or id-less room type in the registry")
			return false
		if type_ids.has(rt.id):
			push_error("GenConfig: duplicate room type id '%s'" % rt.id)
			return false
		type_ids[rt.id] = true
		if rt.unique_scope == RoomTypeDef.UniqueScope.NONE and not biome_ids.has(rt.biome):
			push_error("GenConfig: room type '%s' names unregistered biome '%s'" % [rt.id, rt.biome])
			return false
		if rt.min_size_slots.x < 1 or rt.min_size_slots.y < 1 \
				or rt.min_size_slots.x > rt.max_size_slots.x or rt.min_size_slots.y > rt.max_size_slots.y:
			push_error("GenConfig: room type '%s' size window %s..%s is invalid"
					% [rt.id, rt.min_size_slots, rt.max_size_slots])
			return false
	# Per biome: the fallback room must exist, be owned, and accept any size (it is what a room
	# becomes when a tier fill finds nothing); quota demands must fit the region by area and
	# by dimension, or the BSP demand carving could not be total.
	for b in biomes:
		var fb := room_type_by_id(b.fallback_room_type)
		if fb == null or fb.biome != b.id:
			push_error("GenConfig: biome '%s' fallback room type '%s' missing or not owned by it"
					% [b.id, b.fallback_room_type])
			return false
		if fb.min_size_slots != Vector2i.ONE:
			push_error("GenConfig: biome '%s' fallback room type '%s' must accept any size (min_size_slots 1x1)"
					% [b.id, b.fallback_room_type])
			return false
		var region := b.size_cells * biome_slots   # region size in slots
		var demand_area := 0
		for rt in rooms_for_biome(b.id):
			var d := rt.min_size_slots
			var fits := (d.x <= region.x and d.y <= region.y) or (d.y <= region.x and d.x <= region.y)
			if rt.min_per_biome > 0 and not fits:
				push_error("GenConfig: room type '%s' demands %s slots but biome '%s' is only %s"
						% [rt.id, d, b.id, region])
				return false
			demand_area += rt.min_per_biome * d.x * d.y
		if demand_area > region.x * region.y:
			push_error("GenConfig: biome '%s' quota demands cover %d slots but the region only has %d"
					% [b.id, demand_area, region.x * region.y])
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
	h = WgHash.fold_var(h, world_width_cells)
	h = WgHash.fold_var(h, door_width_tiles)
	h = WgHash.fold_var(h, extra_connection_chance)
	h = WgHash.fold_var(h, bsp_stop_chance)
	h = WgHash.fold_var(h, bsp_max_leaf_slots)
	h = WgHash.fold_var(h, doors_per_biome_border)
	h = WgHash.fold_var(h, pocket_seal_max_tiles)
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
