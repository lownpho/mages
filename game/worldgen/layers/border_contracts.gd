class_name BorderContracts
## Border contracts (spec §6): the deterministic shared decision between two adjacent biome
## cells. Pure static function — no state, callable lazily from either side. The seed is
## symmetric in (A,B) via coordinate-wise min/max (spec §4.1), so both neighbours compute the
## identical crossings in any generation order.
extends RefCounted


## One door crossing on a shared biome border (spec §6). Lightweight object, not a Dict.
class Crossing extends RefCounted:
	var slot_index: int    ## which slot along the border [0, BIOME_SIZE_SLOTS)
	var tile_offset: int   ## door offset within the slot's shared wall
	var width: int         ## DOOR_WIDTH

	func _init(si := 0, off := 0, w := 0) -> void:
		slot_index = si
		tile_offset = off
		width = w


## BORDER_CROSSINGS distinct slot indices (ascending) each with a door offset (spec §6).
## RNG consumption order is fixed: draw all distinct slot indices first (partial Fisher-Yates),
## sort ascending, then draw one offset per crossing in ascending-slot order.
static func get_contract(world_seed: int, config: GenConfig, biome_a: Vector2i, biome_b: Vector2i) -> Array:
	var parts: Array[int] = [
		world_seed, WgHash.NS_BORDER,
		mini(biome_a.x, biome_b.x), mini(biome_a.y, biome_b.y),
		maxi(biome_a.x, biome_b.x), maxi(biome_a.y, biome_b.y),
	]
	var rng := WgHash.rng(WgHash.seed_for(config.gen_version, config.compute_hash(), parts))

	var n := config.BIOME_SIZE_SLOTS
	var count := mini(config.BORDER_CROSSINGS, n)

	# Distinct slot indices via partial Fisher-Yates over [0, n): pick the first `count`.
	var pool: Array[int] = []
	for i in n:
		pool.append(i)
	for i in count:
		var j := rng.randi_range(i, n - 1)
		var t := pool[i]
		pool[i] = pool[j]
		pool[j] = t
	var slots: Array[int] = pool.slice(0, count)
	slots.sort()

	var lo := 2
	var hi := config.ROOM_SLOT_SIZE - config.DOOR_WIDTH - 2
	var out: Array = []
	for si in slots:
		out.append(Crossing.new(si, rng.randi_range(lo, hi), config.DOOR_WIDTH))
	return out
