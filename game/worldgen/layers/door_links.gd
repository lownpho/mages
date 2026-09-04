class_name DoorLinks
## The run's ONE-WAY warp doors. Per biome it picks a few ORDINARY rooms (never a pinned
## set-piece — boss, gate, rare, spawn) to hold a door, then rolls each door a destination of its
## own out of EVERY ordinary room in the world. So a door always drops you in the same room for a
## given seed, somewhere else in the overworld, and that room is almost never one holding a door:
## doors are NOT chained. It is only chance when a landing happens to have a door of its own — the
## destination pool is every ordinary room, not the door rooms. A destination is as likely to sit
## in another biome as at home. Rebuilt from (world_seed, config) on every load — nothing is saved.
##
## Doors never leave the GenConfig they were built for — the overworld and each dungeon stream
## their own WorldSpec and so build their own DoorLinks. An overworld door can't land you in a
## dungeon; the stair/gate doors are the only way between the two, and they are separate machinery.
##
## THREE independent rolls, all off NS_DOORS: which rooms hold doors (one stream per biome,
## [world_seed, NS_DOORS, biome index]), where each one leads ([world_seed, NS_DOORS,
## DEST_STREAM]), and where an authored GATE door leads (one stream per gate room, keyed by its
## slot, so a gate resolves the same whichever order rooms stream in). The tile is the
## deterministic room centre, so a room resolves to the same tile whether it is live or being
## probed as a warp destination. Draws are consumed over ARRAYS in canonical order, never a
## Dictionary.
##
## The door counts live on BiomeDef (doors_min/doors_max) and are deliberately OUTSIDE
## CONFIG_HASH, like every other feature-tier dial: retuning them re-rolls the doors, not the world.
extends RefCounted

const _DEST_STREAM := -1   ## stream key for the global destination roll; can't collide with a biome index
const _GATE_STREAM := -2   ## stream key for an authored gate door's destination roll

const _DOOR_SCENE: PackedScene = preload("res://worldgen/runtime/door.tscn")

## Fallback exit-tile search order, used when the arrival carries no heading: south first, so a
## player usually steps out facing the room rather than into the wall behind it.
const _NEIGHBOURS: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0),
]

var _rooms: Dictionary = {}    ## origin_slot -> RoomSpec, for every room this map can name
var _target: Dictionary = {}   ## origin_slot -> the origin_slot it leads to (one way, never back)
var _pools: Dictionary = {}    ## biome id -> Array of eligible RoomSpec, canonical order
var _world_seed: int = 0


static func build(world_spec: WorldSpec, config: GenConfig, world_seed: int,
		graphs: RoomGraph) -> DoorLinks:
	var links := DoorLinks.new()
	links._world_seed = world_seed
	var doors: Array = []       # of RoomSpec: biome order, then pick order
	var everywhere: Array = []  # of RoomSpec: every ordinary room in the world, biome order
	for i in world_spec.placements.size():
		var place: WorldSpec.BiomePlacement = world_spec.placements[i]
		var biome := config.biome_by_id(place.id)
		if biome == null:
			continue
		# Canonical pool FIRST: the per-biome pick below shuffles its copy, and the destination
		# and gate rolls must not shift with it.
		var pool := _eligible(graphs.get_biome_graph(world_spec, place.id, config), config)
		if pool.is_empty():
			continue
		links._pools[place.id] = pool
		everywhere.append_array(pool)
		if biome.doors_max <= 0:
			continue
		var picks := pool.duplicate()
		var rng := config.rng_for([world_seed, WgHash.NS_DOORS, i] as Array[int])
		var n := mini(rng.randi_range(biome.doors_min, biome.doors_max), picks.size())
		for k in n:   # partial Fisher-Yates — picks[0..n) ends up as the picks, no rejection loop
			var j := rng.randi_range(k, picks.size() - 1)
			var swap: RoomSpec = picks[k]
			picks[k] = picks[j]
			picks[j] = swap
			doors.append(picks[k])

	# Each door rolls its own destination out of every ordinary room in the world — nothing pairs
	# them up and nothing chains them, so a landing has a door onward only by coincidence. Every
	# picked room keeps its door, so the biome minimums hold exactly. Two doors may share a
	# destination; that too is only chance.
	if doors.is_empty() or everywhere.size() < 2:
		return links   # nowhere to send anyone but home: no door is placed
	var prng := config.rng_for([world_seed, WgHash.NS_DOORS, _DEST_STREAM] as Array[int])
	for d in doors:
		var dest: RoomSpec = _pick_other(prng, everywhere, d)
		links._rooms[d.origin_slot] = d
		links._rooms[dest.origin_slot] = dest
		links._target[d.origin_slot] = dest.origin_slot
	return links


## A room from `pool` that is not `self_room`, in one draw: pick over the pool minus one, and let
## the room we must skip stand in for the last entry. No rejection loop, so the stream stays
## aligned however the pool falls.
static func _pick_other(rng: RandomNumberGenerator, pool: Array, self_room: RoomSpec) -> RoomSpec:
	var i := rng.randi_range(0, pool.size() - 2)
	var hit: RoomSpec = pool[i]
	return pool[pool.size() - 1] if hit == self_room else hit


## The room origin slot this door leads to, or Vector2i.MAX when this room holds no door. One
## way: the room it names is an ordinary room somewhere else in the world, and has no door back.
func target_of(origin_slot: Vector2i) -> Vector2i:
	return _target.get(origin_slot, Vector2i.MAX)


## The RoomSpec of a room this map names — one holding a door, or one a door leads to. null
## otherwise.
func room_at(origin_slot: Vector2i) -> RoomSpec:
	return _rooms.get(origin_slot, null)


## Number of doors placed in the world.
func count() -> int:
	return _target.size()


## Every door's room origin slot, sorted (test/debug hook — deterministic to compare).
func slots() -> Array:
	var out: Array = _target.keys()
	out.sort()
	return out


## Append this room's rolled door to its finished RoomOutput and point any authored GATE door it
## carries at a real room; a room with neither is left alone. Called by the streamer right after
## Layers 3+4, so a door streams and re-places exactly like an authored RoomFeature.
func add_spawn(out: RoomOutput, spec: RoomSpec, config: GenConfig) -> void:
	_resolve_gates(out, spec, config)
	var target: Vector2i = target_of(spec.origin_slot)
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


## An authored door whose DoorResource names a `target_biome` is a GATE: a fixed one-way way into
## that biome, placed by hand in a set-piece room rather than rolled like the others. It gets a
## destination the same way a rolled door does — an ordinary room in that biome, the same one for
## a given seed — resolved here because only DoorLinks knows the world's rooms. The authored
## resource is shared by every room of the type, so the patched copy is a duplicate. A gate whose
## biome is absent from this world names nothing and is dropped, rather than left as a dead door.
func _resolve_gates(out: RoomOutput, spec: RoomSpec, config: GenConfig) -> void:
	for i in range(out.spawns.size() - 1, -1, -1):
		var res = out.spawns[i].get("feature_data")
		if not (res is DoorResource) or res.target_biome == &"" \
				or res.target_slot != Vector2i.MAX:
			continue
		var pool: Array = _pools.get(res.target_biome, [])
		if pool.is_empty():
			out.spawns.remove_at(i)
			continue
		var rng := config.rng_for([_world_seed, WgHash.NS_DOORS, _GATE_STREAM,
				spec.origin_slot.x, spec.origin_slot.y] as Array[int])
		var dest: RoomSpec = pool[rng.randi_range(0, pool.size() - 1)]
		var fixed: DoorResource = res.duplicate()
		fixed.target_slot = dest.origin_slot
		_rooms[dest.origin_slot] = dest
		out.spawns[i]["feature_data"] = fixed


## Where a warp arriving in this room lands: a reachable 4-neighbour of the room's centre tile —
## which is also where a door sits in the rare case this room has one, so an arrival never lands
## standing in a door. `heading` is the direction they walked into the door they came from — they
## come out still moving the same way, so holding the same key walks them clear. A blocked heading
## falls back to the two sides, and only then to doubling back. (-1,-1) if the room has no
## reachable tile at all.
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


## Rooms a door may sit in, and rooms a door may land you in — the same pool, in canonical order:
## the biome's ordinary generated rooms. Pinned set-pieces (weight 0 — boss, gate, rare, spawn)
## and world-unique rooms are left alone, so a door never sits on, or drops you into, an authored
## encounter or hands out a boss-room shortcut.
static func _eligible(graph: BiomeGraph, config: GenConfig) -> Array:
	var out: Array = []
	for u in graph.rooms:
		var rt := config.room_type_by_id(u.type_id)
		if rt == null or rt.weight <= 0 or rt.unique_scope != RoomTypeDef.UniqueScope.NONE:
			continue
		out.append(u)
	return out
