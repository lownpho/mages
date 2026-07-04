class_name WorldSpec
## Output of Layer 1. A plain RefCounted (NOT a Resource) — it is recomputed
## from (world_seed, config) every load, never saved. Holds the biome placement grid, the
## world-unique room homes, and a lazy accessor for border contracts.
extends RefCounted

# Side constants. World-space directions; the
# room-graph layer reuses these. Order is fixed — a change bumps GEN_VERSION.
enum { SIDE_NORTH = 0, SIDE_EAST = 1, SIDE_SOUTH = 2, SIDE_WEST = 3 }

var world_seed: int = 0
var grid_w: int = 0
var grid_h: int = 0
var biome_grid: Array[StringName] = []   ## row-major, size grid_w*grid_h
var unique_rooms: Array = []             ## of UniqueRoom
var config: GenConfig = null             ## source config (for dims + contract recompute)

var _contract_cache: Dictionary = {}     ## read-through cache; never iterated during generation


## One world-unique room home. Lightweight typed object rather than a raw Dict so
## callers can iterate the list without touching a Dictionary.
class UniqueRoom extends RefCounted:
	var type_id: StringName
	var biome_coord: Vector2i   ## which biome cell hosts it
	var local_slot: Vector2i    ## slot coord within that biome (interior only)

	func _init(t := &"", bc := Vector2i.ZERO, ls := Vector2i.ZERO) -> void:
		type_id = t
		biome_coord = bc
		local_slot = ls


## Biome id at a biome-cell coordinate; &"" if out of range.
func biome_at(biome_coord: Vector2i) -> StringName:
	if biome_coord.x < 0 or biome_coord.y < 0 or biome_coord.x >= grid_w or biome_coord.y >= grid_h:
		return &""
	return biome_grid[biome_coord.y * grid_w + biome_coord.x]


## Border contract between two adjacent biome cells. Symmetric in a/b; cached.
## Returns Array[BorderContracts.Crossing].
func get_contract(a: Vector2i, b: Vector2i) -> Array:
	var key := "%d,%d-%d,%d" % [mini(a.x, b.x), mini(a.y, b.y), maxi(a.x, b.x), maxi(a.y, b.y)]
	if _contract_cache.has(key):
		return _contract_cache[key]
	var c := BorderContracts.get_contract(world_seed, config, a, b)
	_contract_cache[key] = c
	return c


## Which of a world-space slot's four sides face the world's outer edge. The world
## occupies slots [0, grid_w*biome_slots) × [0, grid_h*biome_slots); a side is an edge
## side iff the slot sits on that perimeter. Returns an Array[int] of SIDE_* constants (empty for
## interior slots). Callers seal these sides CLOSED with no door.
func is_world_edge_slot(slot: Vector2i) -> Array[int]:
	var sides: Array[int] = []
	var s := config.biome_slots
	var max_x := grid_w * s - 1
	var max_y := grid_h * s - 1
	if slot.y == 0:
		sides.append(SIDE_NORTH)
	if slot.x == max_x:
		sides.append(SIDE_EAST)
	if slot.y == max_y:
		sides.append(SIDE_SOUTH)
	if slot.x == 0:
		sides.append(SIDE_WEST)
	return sides
