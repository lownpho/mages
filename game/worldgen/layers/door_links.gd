class_name DoorLinks
## The run's two-way warp doors. Per biome it picks a few ORDINARY rooms (never a pinned
## set-piece — boss, gate, rare, spawn) to hold a door, then shuffles EVERY door in the world
## into one list and pairs them up, so a link is as likely to cross into another biome as to
## stay home. Both ends are the same object seen from either side: walking into one puts you
## beside the other. Rebuilt from (world_seed, config) on every load — nothing is saved.
##
## THREE independent rolls, all off NS_DOORS: which rooms hold doors (one stream per biome,
## [world_seed, NS_DOORS, biome index]), who links to whom ([world_seed, NS_DOORS, PAIR_STREAM]),
## and nothing else — the tile is the deterministic room centre, so both ends resolve to the same
## tile whether the room is live or being probed as a warp destination. Draws are consumed over
## ARRAYS in canonical order, never a Dictionary.
##
## The door counts live on BiomeDef (doors_min/doors_max) and are deliberately OUTSIDE
## CONFIG_HASH, like every other feature-tier dial: retuning them re-rolls the doors, not the world.
extends RefCounted

const _PAIR_STREAM := -1   ## stream key for the global pairing; can't collide with a biome index

const _DOOR_SCENE: PackedScene = preload("res://worldgen/runtime/door.tscn")

## Fallback exit-tile search order, used when the arrival carries no heading: south first, so a
## player usually steps out facing the room rather than into the wall behind it.
const _NEIGHBOURS: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0),
]

var _rooms: Dictionary = {}     ## origin_slot -> RoomSpec, one per room holding a door
var _partner: Dictionary = {}   ## origin_slot -> twin's origin_slot (always symmetric)


static func build(world_spec: WorldSpec, config: GenConfig, world_seed: int,
		graphs: RoomGraph) -> DoorLinks:
	var links := DoorLinks.new()
	var doors: Array = []   # of RoomSpec: biome order, then pick order
	for i in world_spec.placements.size():
		var place: WorldSpec.BiomePlacement = world_spec.placements[i]
		var biome := config.biome_by_id(place.id)
		if biome == null or biome.doors_max <= 0:
			continue
		var pool := _eligible(graphs.get_biome_graph(world_spec, place.id, config), config)
		if pool.is_empty():
			continue
		var rng := config.rng_for([world_seed, WgHash.NS_DOORS, i] as Array[int])
		var n := mini(rng.randi_range(biome.doors_min, biome.doors_max), pool.size())
		for k in n:   # partial Fisher-Yates — pool[0..n) ends up as the picks, no rejection loop
			var j := rng.randi_range(k, pool.size() - 1)
			var swap: RoomSpec = pool[k]
			pool[k] = pool[j]
			pool[j] = swap
			doors.append(pool[k])

	# One shuffle over every door in the world, then pair neighbours: cross-biome links fall out
	# of the mix rather than being authored. An odd door out is simply never placed — a one-way
	# door is worse than no door — which can leave one biome a single door under its minimum.
	var prng := config.rng_for([world_seed, WgHash.NS_DOORS, _PAIR_STREAM] as Array[int])
	for k in range(doors.size() - 1, 0, -1):
		var j := prng.randi_range(0, k)
		var swap: RoomSpec = doors[k]
		doors[k] = doors[j]
		doors[j] = swap
	for k in range(0, doors.size() - 1, 2):
		var a: RoomSpec = doors[k]
		var b: RoomSpec = doors[k + 1]
		links._rooms[a.origin_slot] = a
		links._rooms[b.origin_slot] = b
		links._partner[a.origin_slot] = b.origin_slot
		links._partner[b.origin_slot] = a.origin_slot
	return links


## The twin's room origin slot, or Vector2i.MAX when this room holds no door.
func partner_of(origin_slot: Vector2i) -> Vector2i:
	return _partner.get(origin_slot, Vector2i.MAX)


## The RoomSpec of a room holding a door, or null.
func room_at(origin_slot: Vector2i) -> RoomSpec:
	return _rooms.get(origin_slot, null)


## Number of doors placed in the world (always even).
func count() -> int:
	return _partner.size()


## Every door's room origin slot, sorted (test/debug hook — deterministic to compare).
func slots() -> Array:
	var out: Array = _partner.keys()
	out.sort()
	return out


## Append this room's door to its finished RoomOutput; a room holding none is left alone.
## Called by the streamer right after Layers 3+4, so the door streams and re-places exactly
## like an authored RoomFeature.
func add_spawn(out: RoomOutput, spec: RoomSpec, config: GenConfig) -> void:
	var target: Vector2i = partner_of(spec.origin_slot)
	if target == Vector2i.MAX:
		return
	var tile := Population.feature_tile(out)
	if tile.x < 0:
		return
	var res := DoorResource.new()
	res.target_slot = target
	var dest: BiomeDef = config.biome_by_id(_rooms[target].biome_id)
	if dest != null:
		res.style = dest.door_style as Door.Style   # a door wears its DESTINATION's art, not its own biome's
	out.spawns.append({"feature": _DOOR_SCENE, "feature_data": res, "tile": tile})


## Where a warp arriving in this room lands: a reachable 4-neighbour of the door tile, so the
## player steps OUT of the twin instead of standing in it. `heading` is the direction they walked
## into the far door — they come out the OTHER side of this one, still moving the same way, so
## holding the same key walks them away from the door instead of back through it. A blocked
## heading falls back to the two sides, and only then to doubling back. (-1,-1) if the room has
## no reachable tile at all.
static func exit_tile(out: RoomOutput, heading := Vector2i.ZERO) -> Vector2i:
	var tile := Population.feature_tile(out)
	if tile.x < 0:
		return tile
	for d in _exit_order(heading):
		var n := tile + d
		if n.x < 0 or n.y < 0 or n.x >= out.width or n.y >= out.height:
			continue
		if out.reachability_map[n.y * out.width + n.x] == 1:
			return n
	return tile


## Straight on, then the two sides, then back the way they came.
static func _exit_order(heading: Vector2i) -> Array[Vector2i]:
	if heading == Vector2i.ZERO:
		return _NEIGHBOURS
	return [heading, Vector2i(-heading.y, heading.x), Vector2i(heading.y, -heading.x), -heading]


## Rooms a door may land in, canonical order: the biome's ordinary generated rooms. Pinned
## set-pieces (weight 0 — boss, gate, rare, spawn) and world-unique rooms are left alone, so a
## door never lands on top of an authored encounter or hands out a boss-room shortcut.
static func _eligible(graph: BiomeGraph, config: GenConfig) -> Array:
	var out: Array = []
	for u in graph.rooms:
		var rt := config.room_type_by_id(u.type_id)
		if rt == null or rt.weight <= 0 or rt.unique_scope != RoomTypeDef.UniqueScope.NONE:
			continue
		out.append(u)
	return out
