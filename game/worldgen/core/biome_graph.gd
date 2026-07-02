class_name BiomeGraph
## Output of Layer 2 (spec §10.2), one per biome cell, cached forever (spec §11). Pure data.
## `units` are in canonical order (top-left slot, row-major); `slot_to_unit` maps each of the
## BIOME_SIZE_SLOTS² local slots to the index of the unit that covers it.
extends RefCounted

var biome_coord: Vector2i
var units: Array = []                       ## of RoomSpec, canonical order
var slot_to_unit: PackedInt32Array = []     ## size == size_slots², indexed local_y * size + local_x
var size_slots: int = 0                     ## BIOME_SIZE_SLOTS (row stride of slot_to_unit)


## The unit covering a biome-local slot coordinate.
func unit_at(local_slot: Vector2i) -> RoomSpec:
	return units[slot_to_unit[local_slot.y * size_slots + local_slot.x]]
