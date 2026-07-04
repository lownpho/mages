extends Node
## Headless test for entity-spawner determinism (same seed → same live entity ids and
## positions around the player spawn), deterministic player spawn, and session defeated
## tracking (a killed enemy stays gone through despawn/respawn). Runs as a scene because it
## exercises real nodes. Run:
##   godot --headless --path game res://worldgen/tests/test_entity_spawner.tscn

const SEED := 777_003


func _ready() -> void:
	var fails: Array[String] = []
	var config: GenConfig = load("res://worldgen/content/gen_config.tres")

	# World A.
	var a := await _build_world(config, SEED)
	var spawn_a: Vector2 = a.streamer.find_spawn_position()
	if a.streamer.find_spawn_position() != spawn_a:
		fails.append("find_spawn_position not stable")
	var live_a: Dictionary = _snapshot(a.spawner, a.enemies)
	print("world A: %d live enemies at spawn" % live_a.size())
	if live_a.is_empty():
		fails.append("no enemies streamed in around the spawn — spawner dead?")

	# World B, same seed — identical ids AND positions.
	var b := await _build_world(config, SEED)
	if b.streamer.find_spawn_position() != spawn_a:
		fails.append("player spawn differs across worlds with the same seed")
	var live_b: Dictionary = _snapshot(b.spawner, b.enemies)
	if live_a != live_b:
		fails.append("live enemies differ across identical worlds (%d vs %d)" % [live_a.size(), live_b.size()])

	# Defeated tracking on world B: kill one enemy, reseed (despawn + respawn everything),
	# same seed → same world minus the corpse.
	var victim = null   # untyped: Creature properties accessed dynamically
	for e in b.enemies.get_children():
		victim = e
		break
	if victim == null:
		fails.append("no victim available for defeated-tracking test")
	else:
		var dead_eid: int = victim.get_meta("entity_id")
		victim.health = 0
		victim.die()
		await get_tree().process_frame
		await get_tree().process_frame
		if not b.spawner.defeated.has(dead_eid):
			fails.append("kill not recorded in defeated set")
		b.streamer.build_world(SEED)
		for _i in 30:
			await get_tree().process_frame
		var live_after: Dictionary = _snapshot(b.spawner, b.enemies)
		if live_after.has(dead_eid):
			fails.append("defeated enemy respawned")
		var expected := live_a.duplicate()
		expected.erase(dead_eid)
		if live_after != expected:
			fails.append("respawned world differs beyond the defeated enemy (%d vs %d)"
					% [live_after.size(), expected.size()])
		print("defeated tracking: enemy %d stayed dead through respawn" % dead_eid)
	if fails.is_empty():
		print("ALL PASS")
	else:
		for f in fails:
			print("  FAIL: ", f)
		print("FAILED: %d" % fails.size())
	get_tree().quit(0 if fails.is_empty() else 1)


## Build a streamer + spawner + target rig and let chunks stream in around the player spawn.
func _build_world(config: GenConfig, seed_value: int) -> Dictionary:
	var root := Node2D.new()
	add_child(root)
	var streamer := WorldStreamer.new()
	streamer.config = config
	root.add_child(streamer)
	var enemies := Node2D.new()
	root.add_child(enemies)
	var spawner := WgEntitySpawner.new()
	spawner.streamer = streamer
	spawner.enemies_parent = enemies
	root.add_child(spawner)
	# NOT in the "player" group — enemies stay idle for the test.
	var target := Node2D.new()
	root.add_child(target)

	streamer.build_world(seed_value)
	target.position = streamer.find_spawn_position()
	streamer.target = target
	for _i in 30:   # 3 chunk loads/frame; ~25 chunks around the spawn headless
		await get_tree().process_frame
	return {"root": root, "streamer": streamer, "spawner": spawner, "enemies": enemies}


## entity_id -> position snapshot of live enemies.
func _snapshot(_spawner: WgEntitySpawner, enemies: Node2D) -> Dictionary:
	var out := {}
	for e in enemies.get_children():
		if is_instance_valid(e) and e.has_meta("entity_id"):
			out[e.get_meta("entity_id")] = e.position
	return out
