class_name DungeonFloors
## A dungeon is one GenConfig generated once per floor: `GenConfig.floors` deep, a seed apiece,
## walked through the two stair rooms it names. Everything about that is here — the scene playing
## the dungeon and the worldgen debug tool browsing it ask the same three questions, so neither
## has to know the other exists.
extends RefCounted


## The floor a stair leads to, or 0 for "out of the dungeon" — the two ends of the ladder, which
## the caller answers however it can (the game leaves for the overworld; the tool goes back to the
## world the gate was in).
static func next_floor(config: GenConfig, current: int, delta: int) -> int:
	var n := current + delta
	return n if n >= 1 and n <= config.floors else 0


## The config a floor generates from: `GenConfig.floor_configs` indexed by depth, falling back to
## the dungeon's own config. One floor is one content pool, which is how the descent introduces
## rooms as it goes without a second generator or a floor-aware layer.
static func config_for(config: GenConfig, n: int) -> GenConfig:
	if n >= 1 and n <= config.floor_configs.size() and config.floor_configs[n - 1] != null:
		return config.floor_configs[n - 1]
	return config


## A floor's world seed. Derived from the RUN seed rather than the floor above, so floor N is the
## same floor every time you walk back onto it.
static func floor_seed(run_seed: int, n: int) -> int:
	return WgHash.splitmix64(run_seed ^ WgHash.splitmix64(n))


## Where a player arriving by a stair lands: beside it, never on it — the rule a warp door's far
## end follows, so they step out of the stairwell instead of standing in it. Falls back to the
## floor's own spawn if that room somehow carries no reachable tile.
static func stair_position(streamer: WorldStreamer, room_type: StringName) -> Vector2:
	for room in streamer.biome_graph(streamer.config.starting_biome).rooms:
		if room.type_id != room_type:
			continue
		var tile := DoorLinks.exit_tile(streamer.get_room_output(room))
		if tile.x < 0:
			break
		var wt: Vector2i = room.origin_slot * streamer.config.room_slot_tiles + tile
		return (Vector2(wt) + Vector2(0.5, 0.5)) * GameConstants.PX_PER_TILE
	return streamer.find_spawn_position()
