class_name BiomePlan
extends RefCounted
## A Biome in the World plan: its seeded Zone order, its stretch of macro cells, its route, every Room
## it owns and, for a Side biome, the parent route Room it attaches to.

var id := &""
var resource: BiomeResource
## The Ideal-path Biome a Side biome attaches to; &"" on the Ideal path.
var parent := &""
## In seeded order, the Spawn zone first.
var zones: Array[ZonePlan] = []
## Its macro cells in route order, each bordering the one before. A Side biome's first cell borders
## its attachment's cell.
var cells: Array[Vector2i] = []
## Its route Rooms in order: its stretch of the Ideal path, or its Side route.
var route: Array[RoomPlan] = []
## Every Room it owns, the sum of its Zones' room_count: route Rooms first.
var rooms: Array[RoomPlan] = []
## Its Boss's set piece, joining its final Zone's route near the end.
var boss: RoomPlan
## Challenge at its first route Room: the previous Biome's exit (0 for the first), or a Side biome's
## attachment's. It rises to resource.exit_challenge at the last.
var entry_challenge := 0
## A Side biome's parent route Room. One ordinary Passage is reserved between it and route[0]; the
## Side biome has no other way in. null on the Ideal path.
var attachment: RoomPlan


func is_side() -> bool:
	return parent != &""


func zone(zone_id: StringName) -> ZonePlan:
	for plan in zones:
		if plan.id == zone_id:
			return plan
	return null
