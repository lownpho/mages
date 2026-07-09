class_name WorldSpec
## Output of Layer 1. A plain RefCounted (NOT a Resource) — it is recomputed
## from (world_seed, config) every load, never saved. Holds the biome placement rects (from the
## bottom-left skyline packer), the world-unique room homes, and a lazy accessor for border
## contracts.
extends RefCounted

# Side constants. World-space directions; the
# room-graph layer reuses these. Order is fixed — a change bumps GEN_VERSION.
enum { SIDE_NORTH = 0, SIDE_EAST = 1, SIDE_SOUTH = 2, SIDE_WEST = 3 }

var world_seed: int = 0
var grid_w: int = 0                      ## == config.world_width_cells
var grid_h: int = 0                      ## packed height (max skyline after packing)
var biome_grid: Array[StringName] = []   ## row-major, size grid_w*grid_h; &"" = unclaimed (sealed)
var placements: Array = []               ## of BiomePlacement, one per biome, in config.biomes order
var unique_rooms: Array = []             ## of UniqueRoom
var config: GenConfig = null             ## source config (for dims + contract recompute)

var _contract_cache: Dictionary = {}     ## read-through cache; never iterated during generation


## One biome's placement on the world grid, in macro-cells.
class BiomePlacement extends RefCounted:
	var id: StringName
	var rect: Rect2i   ## macro-cells, world cell coords

	func _init(i := &"", r := Rect2i()) -> void:
		id = i
		rect = r


## One world-unique room home, addressed directly by its world slot — the owning biome is
## recovered via biome_at_slot() when needed, so there is no separate biome/local-slot pair.
class UniqueRoom extends RefCounted:
	var type_id: StringName
	var world_slot: Vector2i

	func _init(t := &"", ws := Vector2i.ZERO) -> void:
		type_id = t
		world_slot = ws


## Biome id at a biome-cell (macro-cell) coordinate; &"" if out of range or unclaimed.
func biome_at(cell: Vector2i) -> StringName:
	if cell.x < 0 or cell.y < 0 or cell.x >= grid_w or cell.y >= grid_h:
		return &""
	return biome_grid[cell.y * grid_w + cell.x]


## This biome's placement, or null if it wasn't placed (should not happen for a validated config).
func placement_for(bid: StringName) -> BiomePlacement:
	for p in placements:
		if p.id == bid:
			return p
	return null


## Macro-cell coordinate containing a world-space room slot (component-wise integer division).
func cell_of_slot(slot: Vector2i) -> Vector2i:
	return slot / config.biome_slots


## Biome id at a world-space room slot; &"" if unclaimed.
func biome_at_slot(slot: Vector2i) -> StringName:
	return biome_at(cell_of_slot(slot))


## This biome's region origin, in world-space room slots.
func region_origin_slot(bid: StringName) -> Vector2i:
	return placement_for(bid).rect.position * config.biome_slots


## This biome's region size, in room slots.
func region_size_slots(bid: StringName) -> Vector2i:
	return placement_for(bid).rect.size * config.biome_slots


## Border contract between two adjacent biome cells. Symmetric in a/b; cached.
## Returns Array[BorderContracts.Crossing].
func get_contract(a: Vector2i, b: Vector2i) -> Array:
	var key := "%d,%d-%d,%d" % [mini(a.x, b.x), mini(a.y, b.y), maxi(a.x, b.x), maxi(a.y, b.y)]
	if _contract_cache.has(key):
		return _contract_cache[key]
	var c := BorderContracts.get_contract(world_seed, config, a, b)
	_contract_cache[key] = c
	return c
