extends Node
## Headless test for the mycelium dungeon's floors: every floor lays out exactly one up stair and
## one down stair, each carrying its door on a tile the player can step off, and only the two ends
## of the ladder lead out of the dungeon. Run:
##   godot --headless --path game res://tests/worldgen/test_mycelium_floors.tscn


func _ready() -> void:
	var fails: Array[String] = []
	var config: GenConfig = load("res://world_content/mycelium_gen_config.tres")
	if not config.validate():
		fails.append("mycelium_gen_config does not validate")

	for f in range(1, config.floors + 1):
		var seed_v := DungeonFloors.floor_seed(12345, f)
		var world := WorldLayout.build(seed_v, config)
		var graph := RoomGraph.build(world, config.starting_biome, config)
		for type_id in [config.stair_up_room, config.stair_down_room]:
			var found: Array = []
			for room in graph.rooms:
				if room.type_id == type_id:
					found.append(room)
			if found.size() != 1:
				fails.append("floor %d has %d '%s' rooms, want exactly 1" % [f, found.size(), type_id])
				continue
			var out := RoomBuilder.build(found[0], config, seed_v)
			var doors := 0
			for sp in out.spawns:
				if sp.has("feature"):
					doors += 1
			if doors != 1:
				fails.append("floor %d '%s' carries %d door features, want 1" % [f, type_id, doors])
			if DoorLinks.exit_tile(out).x < 0:
				fails.append("floor %d '%s' has no reachable tile to arrive on" % [f, type_id])

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
