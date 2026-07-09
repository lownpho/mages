class_name RoomOutput
## Output of Layer 3+4 for one room, LRU-cached by the streamer. The canonical
## fields are origin_slot / tile_grid / reachability_map / spawns; width,
## height, protected_map and the id fields are implementation extras (debug views +
## generator input). Post-repair (RoomBuilder), every FLOOR/DECOR_FLOOR tile is reachable and
## reachability_map.count(1) >= min_reachable_floor_ratio * width * height.
extends RefCounted

var origin_slot: Vector2i                     ## the room's top-left world slot (cache key)
var width: int = 0                            ## tiles
var height: int = 0                           ## tiles
var tile_grid: PackedByteArray                ## RoomBuilder.FLOOR/WALL/BLOCKER/DECOR_FLOOR, y*width+x
var protected_map: PackedByteArray            ## parallel 0/1 mask
var reachability_map: PackedByteArray         ## 0/1 per tile, flood-filled from center
var spawns: Array = []                        ## data only; populated by Layer 4
var type_id: StringName
var biome_id: StringName
