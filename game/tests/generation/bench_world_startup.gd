extends Node
## Run-start benchmark, outside the test suite: New and Continue on the shipped World (about 480
## Rooms) through the real World scene, at several seeds in one process. It fails when either, until
## the player can move, passes the headless desktop threshold, a third of the 2 s web startup budget.
##
##   New       the World plan and every room graph (the title backdrop's work, which New reuses), then
##             the World's own start: the spawn's chunks, encounters, Objects, the Map and the first save.
##   Continue  the World planning the saved seed itself, with every Room of the World discovered, so
##             its bounded warm-up of discovered interiors runs in full.
##
## Both then allow one loading frame. Timings come from the World's own build timings, which exclude
## the debug layer that only non-web debug builds attach. Run by hand, alone:
##   godot --headless --path game res://tests/generation/bench_world_startup.tscn -- [seeds]
## Results are recorded in .scratch/worldgen-rewrite-build/issues/11-cut-over-gameplay-and-verify-performance.md.

const SHIPPED := "res://generation/world/"
const WORLD := "res://scenes/world.tscn"
const SAVE := "user://bench_world_startup_save.cfg"
const THRESHOLD_MS := 2000.0 / 3.0


func _ready() -> void:
	var count := 5
	for arg in OS.get_cmdline_user_args():
		if arg.is_valid_int():
			count = arg.to_int()
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	get_window().size = Vector2i(1920, 1080)
	var debug_state := {}
	for key in DebugState.keys("world_debug"):
		debug_state[key] = DebugState.get_value("world_debug", key)
	DebugState.set_value("world_debug", "fly", false)
	GameState.save_path = SAVE
	var content := ContentLoader.load_content(SHIPPED)
	if not content.is_valid():
		print(content.report())
		get_tree().quit(1)
		return
	print("Run-start bench: %s, %d Rooms, %d seeds, Godot %s headless" % [SHIPPED, content.world_room_count(), count,
			Engine.get_version_info().string])
	var new_ms: Array[float] = []
	var continue_ms: Array[float] = []
	for n in count:
		var world_seed := 1000 + n * 7919
		# New: the backdrop's plan, then entering the World with it.
		var started := Time.get_ticks_usec()
		var graph := WorldGraph.build(WorldPlanner.plan(content, world_seed))
		var planned_ms := (Time.get_ticks_usec() - started) / 1000.0
		GameState.new_game(0, graph)
		var world: Node2D = load(WORLD).instantiate()
		add_child(world)
		var frame_ms := await _loading_frame()
		var entry: Dictionary = world._build_timings
		var new_total: float = planned_ms + entry.spawn_ms + frame_ms
		new_ms.append(new_total)

		# Continue with the whole World discovered.
		for room in world._graph.room_list:
			GlobalMap.active.entered_rooms[room.key()] = true
		GameState.persist()
		world.queue_free()
		await get_tree().process_frame
		GlobalMap.reset()
		GameState.active_seed = 0
		GameState.continue_game()
		world = load(WORLD).instantiate()
		add_child(world)
		var continue_frame_ms := await _loading_frame()
		var resumed: Dictionary = world._build_timings
		var continue_total: float = resumed.total_ms + continue_frame_ms
		continue_ms.append(continue_total)
		print("  seed %d: New %.0f ms (plan+graphs %.0f, World %d, frame %.0f); Continue %.0f ms (plan %d, graphs %d, World %d, frame %.0f)" % [
				world_seed, new_total, planned_ms, entry.spawn_ms, frame_ms, continue_total, resumed.plan_ms,
				resumed.graphs_ms, resumed.spawn_ms, continue_frame_ms])
		world.queue_free()
		await get_tree().process_frame
		GameState.clear_save()
	GameState.save_path = GameState.SAVE_PATH
	for key in debug_state:
		DebugState.set_value("world_debug", key, debug_state[key])
	print("  New       %s  (threshold %.0f ms)" % [_stats(new_ms), THRESHOLD_MS])
	print("  Continue  %s  (threshold %.0f ms)" % [_stats(continue_ms), THRESHOLD_MS])
	var passed: bool = new_ms.max() <= THRESHOLD_MS and continue_ms.max() <= THRESHOLD_MS
	print("PASS" if passed else "FAIL: slowest New %.0f ms, slowest Continue %.0f ms" % [new_ms.max(), continue_ms.max()])
	get_tree().quit(0 if passed else 1)


## The frame after entering the World, until the player can move.
func _loading_frame() -> float:
	var started := Time.get_ticks_usec()
	await get_tree().process_frame
	return (Time.get_ticks_usec() - started) / 1000.0


static func _stats(samples: Array[float]) -> String:
	var sorted := samples.duplicate()
	sorted.sort()
	return "median %6.0f ms  p95 %6.0f ms  max %6.0f ms" % [sorted[sorted.size() / 2],
			sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))], sorted[-1]]
