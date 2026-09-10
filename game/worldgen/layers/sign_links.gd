class_name SignLinks
## The run's tip signs. A sign stands only in an EMPTY room — a room type with no enemies to spawn
## and no features to place, like the small signpost rooms each biome carries for them (its spawn
## room aside: the player starts on that centre) — one to a room, on the room's centre tile. Per
## biome it shuffles the empty rooms and deals BiomeDef.signs out over them in turn, so every empty
## room holds a sign, every listed sign stands at least once and the rest repeat evenly. That needs
## at least one empty room per listed sign — the signpost quotas are sized for it; a shortfall warns
## and leaves the signs past it out. Rebuilt from (world_seed, config) on every load — nothing saved.
##
## One roll off NS_SIGNS per biome, [world_seed, NS_SIGNS, biome index]: a Fisher-Yates over the
## biome's empty rooms in canonical order, never a Dictionary.
##
## A sign naming a `reveal_room_type` is resolved here too, because only the links know the world's
## rooms: its copy in each room points at the nearest room of that type (see SignDef).
##
## The signs live on BiomeDef and, like the doors, are deliberately OUTSIDE CONFIG_HASH: editing a
## sign re-deals the signs, not the world. The rooms holding them are ordinary room types, though —
## adding or retuning those is a world change.
extends RefCounted

const _SIGN_SCENE: PackedScene = preload("res://worldgen/runtime/under_construction_sign.tscn")

var _signs: Dictionary = {}   ## origin_slot -> the SignDef standing in that room


static func build(world_spec: WorldSpec, config: GenConfig, world_seed: int,
		graphs: RoomGraph) -> SignLinks:
	var links := SignLinks.new()
	for i in world_spec.placements.size():
		var place: WorldSpec.BiomePlacement = world_spec.placements[i]
		var biome := config.biome_by_id(place.id)
		if biome == null or biome.signs.is_empty():
			continue
		var rooms := empty_rooms(graphs.get_biome_graph(world_spec, place.id, config), biome, config)
		if rooms.size() < biome.signs.size():
			push_warning("SignLinks: biome '%s' has %d empty rooms for %d signs — some never stand"
					% [place.id, rooms.size(), biome.signs.size()])
		var rng := config.rng_for([world_seed, WgHash.NS_SIGNS, i] as Array[int])
		for k in rooms.size():   # Fisher-Yates: the k-th sign dealt lands in a random unsigned room
			var j := rng.randi_range(k, rooms.size() - 1)
			var room: RoomSpec = rooms[j]
			rooms[j] = rooms[k]
			rooms[k] = room
			var tip: SignDef = biome.signs[k % biome.signs.size()]
			if tip.reveal_room_type != &"":
				tip = _pointed(tip, room, world_spec, config, graphs)
			links._signs[room.origin_slot] = tip
	return links


## A biome's empty rooms, in canonical order — every room a sign may stand in.
static func empty_rooms(graph: BiomeGraph, biome: BiomeDef, config: GenConfig) -> Array:
	var out: Array = []
	for u in graph.rooms:
		var rt := config.room_type_by_id(u.type_id)
		if rt != null and is_empty_room(rt) and rt.id != biome.spawn_room_type:
			out.append(u)
	return out


## True for a room type that places nothing of its own: no enemy pool (or no groups to fill it
## with) and no features.
static func is_empty_room(rt: RoomTypeDef) -> bool:
	return (rt.enemies.is_empty() or rt.enemy_groups_max <= 0) and rt.features.is_empty()


## A copy of `tip` pointing at the room of its reveal_room_type nearest `from` (centre to centre,
## in slots; the first in placement then canonical room order wins a tie), or `tip` itself when
## this world has no room of that type.
static func _pointed(tip: SignDef, from: RoomSpec, world_spec: WorldSpec, config: GenConfig,
		graphs: RoomGraph) -> SignDef:
	var here := Vector2(from.origin_slot) + Vector2(from.size_slots) * 0.5
	var best: RoomSpec = null
	var best_d := INF
	for place in world_spec.placements:
		for u in graphs.get_biome_graph(world_spec, place.id, config).rooms:
			if u.type_id != tip.reveal_room_type:
				continue
			var d := (Vector2(u.origin_slot) + Vector2(u.size_slots) * 0.5).distance_squared_to(here)
			if d < best_d:
				best_d = d
				best = u
	if best == null:
		return tip
	var copy: SignDef = tip.duplicate()
	copy.reveal_slot = best.origin_slot
	return copy


## The sign standing in a room, or null for a room without one.
func sign_at(origin_slot: Vector2i) -> SignDef:
	return _signs.get(origin_slot)


## Every sign room's origin slot, sorted (test/debug hook — deterministic to compare).
func slots() -> Array:
	var out: Array = _signs.keys()
	out.sort()
	return out


## Append this room's sign to its finished RoomOutput, on the room's centre tile (the nearest
## reachable one when the centre is blocked). A room without a sign is left alone.
func add_spawn(out: RoomOutput, spec: RoomSpec) -> void:
	var tip := sign_at(spec.origin_slot)
	if tip == null:
		return
	var tile := Population.feature_tile(out)
	if tile.x < 0:
		return
	out.spawns.append({"feature": _SIGN_SCENE, "feature_data": tip, "tile": tile})
