class_name ZonePlan
extends RefCounted
## A Zone where the seeded Zone order put it: a contiguous stretch of its Biome's route, carrying its
## authored quotas with it.

var id := &""
var biome := &""
var resource: ZoneResource
## Its place in the Biome's Zone order. The Spawn zone is always 0.
var order := 0
## Its route Rooms are the Biome route's [route_start, route_end()).
var route_start := 0
## Exactly resource.room_count Rooms: its route Rooms in order, then its set pieces and off-route
## Rooms.
var rooms: Array[RoomPlan] = []


func route_end() -> int:
	return route_start + resource.route_rooms
