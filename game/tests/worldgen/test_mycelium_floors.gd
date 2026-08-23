extends Node
## Headless test for the mycelium dungeon's floors: every floor lays out exactly one up stair and
## one down stair, each carrying its door on a tile the player can step off, only the two ends of
## the ladder lead out of the dungeon — and every floor's own content pool is complete: each room
## type names enemies that exist, carries a budget it can spend, and puts puffcaps on the floor.
## Run:
##   godot --headless --path game res://tests/worldgen/test_mycelium_floors.tscn

const AMBIENT := &"puffcap"   ## the dungeon's terrain: every room lays a field of it


func _ready() -> void:
	var fails: Array[String] = []
	var config: GenConfig = load("res://world_content/mycelium_gen_config.tres")
	if not config.validate():
		fails.append("mycelium_gen_config does not validate")

	var seen_ids: Dictionary = {}   # membership only, never iterated
	for f in range(1, config.floors + 1):
		var cfg := DungeonFloors.config_for(config, f)
		if cfg == config:
			fails.append("floor %d has no config of its own" % f)
		if not cfg.validate():
			fails.append("floor %d's config does not validate" % f)
		_check_pools(cfg, f, fails, seen_ids)

		var seed_v := DungeonFloors.floor_seed(12345, f)
		var world := WorldLayout.build(seed_v, cfg)
		var graph := RoomGraph.build(world, cfg.starting_biome, cfg)
		for type_id in [cfg.stair_up_room, cfg.stair_down_room]:
			var found: Array = []
			for room in graph.rooms:
				if room.type_id == type_id:
					found.append(room)
			if found.size() != 1:
				fails.append("floor %d has %d '%s' rooms, want exactly 1" % [f, found.size(), type_id])
				continue
			var out := RoomBuilder.build(found[0], cfg, seed_v)
			var doors := 0
			for sp in out.spawns:
				if sp.has("feature"):
					doors += 1
			if doors != 1:
				fails.append("floor %d '%s' carries %d door features, want 1" % [f, type_id, doors])
			if DoorLinks.exit_tile(out).x < 0:
				fails.append("floor %d '%s' has no reachable tile to arrive on" % [f, type_id])
		_check_populated(graph, cfg, seed_v, f, fails)
		if f == config.floors:
			_check_boss_slots(graph, cfg, seed_v, fails)

	# The ladder: its two ends leave, everything between them steps one floor.
	if DungeonFloors.next_floor(config, 1, -1) != 0:
		fails.append("floor 1's up stair does not leave the dungeon")
	if DungeonFloors.next_floor(config, config.floors, 1) != 0:
		fails.append("the last floor's down stair does not leave the dungeon")
	if DungeonFloors.next_floor(config, 1, 1) != 2 \
			or DungeonFloors.next_floor(config, config.floors, -1) != config.floors - 1:
		fails.append("a middle stair does not step one floor")

	if fails.is_empty():
		print("ALL PASS")
	else:
		for f2 in fails:
			print("  FAIL: ", f2)
		print("FAILED: %d" % fails.size())
	get_tree().quit(0 if fails.is_empty() else 1)


## The last floor stands the combat lab's placeholder where each boss fight will be, placed as a
## room feature — so until the real scenes exist, the slots are walkable rather than empty.
func _check_boss_slots(graph: BiomeGraph, cfg: GenConfig, seed_v: int, fails: Array[String]) -> void:
	for type_id in [&"mycelium_boss", &"mycelium_mother"]:
		var placed := 0
		for room in graph.rooms:
			if room.type_id != type_id:
				continue
			placed += 1
			var dummies := 0
			for sp in RoomBuilder.build(room, cfg, seed_v).spawns:
				if sp.has("feature"):
					dummies += 1
			if dummies != 1:
				fails.append("'%s' stands %d dummies, want 1" % [type_id, dummies])
		if placed != 1:
			fails.append("the last floor placed '%s' %d times, want 1" % [type_id, placed])


## Static content: a pool that can spend its budget, enemies that exist, ambient caps everywhere.
func _check_pools(cfg: GenConfig, floor_n: int, fails: Array[String], seen_ids: Dictionary) -> void:
	for rt in cfg.room_types:
		var where := "floor %d '%s'" % [floor_n, rt.id]
		if rt.enemies.is_empty() or rt.enemy_groups_max < 1:
			fails.append("%s spawns nothing — every room in the dungeon is mined" % where)
			continue
		for entry in rt.enemies:
			var ids: Array[StringName] = []
			if entry.members.is_empty():
				ids.append(entry.enemy_id)
			else:
				for m in entry.members:
					ids.append(m.enemy_id)
			if not ids.has(AMBIENT):
				fails.append("%s has a group with no %s in it" % [where, AMBIENT])
			for eid in ids:
				if seen_ids.has(eid):
					continue
				seen_ids[eid] = true
				if not ResourceLoader.exists("res://characters/enemies/%s/%s.tscn" % [eid, eid]):
					fails.append("%s names enemy '%s', which has no scene" % [where, eid])


## End to end: build every room the floor laid out and confirm the caps actually land.
func _check_populated(graph: BiomeGraph, cfg: GenConfig, seed_v: int, floor_n: int,
		fails: Array[String]) -> void:
	var bare := 0
	for room in graph.rooms:
		var out := RoomBuilder.build(room, cfg, seed_v)
		var has_ambient := false
		for sp in out.spawns:
			if sp.get("enemy_id", &"") == AMBIENT:
				has_ambient = true
				break
		if not has_ambient:
			bare += 1
	if bare > 0:
		fails.append("floor %d built %d room(s) with no %s on the floor" % [floor_n, bare, AMBIENT])
