class_name BiomeGraph
## Output of Layer 2, one per BIOME (which may span several macro-cells), cached forever.
## Pure data. `rooms` are in canonical order (top-left slot, row-major); `slot_to_room` maps
## each region-local slot to the index of the room that covers it.
extends RefCounted

var biome_id: StringName                    ## cache key — one graph per placed biome
var origin_slot: Vector2i                   ## region origin in WORLD slots
var size_slots: Vector2i                    ## region size in slots (w, h)
var rooms: Array = []                       ## of RoomSpec, canonical order
var slot_to_room: PackedInt32Array = []     ## size == size_slots.x * size_slots.y, stride size_slots.x


## The room covering a region-local slot coordinate (local = world_slot - origin_slot).
func room_at(local_slot: Vector2i) -> RoomSpec:
	return rooms[slot_to_room[local_slot.y * size_slots.x + local_slot.x]]
