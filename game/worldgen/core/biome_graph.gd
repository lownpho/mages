class_name BiomeGraph
## Output of Layer 2, one per biome cell, cached forever. Pure data.
## `rooms` are in canonical order (top-left slot, row-major); `slot_to_room` maps each of the
## biome_slots² local slots to the index of the room that covers it.
extends RefCounted

var biome_coord: Vector2i
var rooms: Array = []                       ## of RoomSpec, canonical order
var slot_to_room: PackedInt32Array = []     ## size == size_slots², indexed local_y * size + local_x
var size_slots: int = 0                     ## config.biome_slots (row stride of slot_to_room)


## The room covering a biome-local slot coordinate.
func room_at(local_slot: Vector2i) -> RoomSpec:
	return rooms[slot_to_room[local_slot.y * size_slots + local_slot.x]]
