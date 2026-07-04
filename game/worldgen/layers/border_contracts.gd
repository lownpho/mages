class_name BorderContracts
## Border contracts: the deterministic shared decision between two adjacent biome
## cells. Pure static function — no state, callable lazily from either side. The seed is
## symmetric in (A,B) via coordinate-wise min/max, so both neighbours compute the
## identical crossings in any generation order.
extends RefCounted


## One door crossing on a shared biome border. Lightweight object, not a Dict.
class Crossing extends RefCounted:
	var slot_index: int    ## which slot along the border [0, biome_slots)
	var tile_offset: int   ## door offset within the slot's shared wall
	var width: int         ## door_width_tiles

	func _init(si := 0, off := 0, w := 0) -> void:
		slot_index = si
		tile_offset = off
		width = w


## doors_per_biome_border distinct slot indices (ascending) each with a door offset.
## RNG consumption order is fixed: draw all distinct slot indices first (partial Fisher-Yates),
## sort ascending, then draw one offset per crossing in ascending-slot order.
static func get_contract(world_seed: int, config: GenConfig, biome_a: Vector2i, biome_b: Vector2i) -> Array:
	var rng := config.rng_for([
		world_seed, WgHash.NS_BORDER,
		mini(biome_a.x, biome_b.x), mini(biome_a.y, biome_b.y),
		maxi(biome_a.x, biome_b.x), maxi(biome_a.y, biome_b.y),
	] as Array[int])

	var n := config.biome_slots
	var count := mini(config.doors_per_biome_border, n)

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
	var hi := config.room_slot_tiles - config.door_width_tiles - 2
	var out: Array = []
	for si in slots:
		out.append(Crossing.new(si, rng.randi_range(lo, hi), config.door_width_tiles))
	return out
