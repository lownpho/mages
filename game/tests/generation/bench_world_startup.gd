extends Node
## Run-start benchmark for the World plan and every room graph, outside the test suite: plans and
## builds the shipped World (about 480 Rooms) at several seeds in one process and fails when the
## slowest seed exceeds the headless desktop threshold, a third of the 2 s web startup budget.
## Interiors on Continue are not built yet; they join this budget at cutover. Run by hand, alone:
##   godot --headless --path game res://tests/generation/bench_world_startup.tscn -- [seeds] [content folder]
## Results are recorded in .scratch/worldgen-rewrite-build/issues/03-generate-room-graphs-roles-and-sites.md.

const SHIPPED := "res://generation/world/"
const THRESHOLD_MS := 2000.0 / 3.0


func _ready() -> void:
	var count := 20
	var root := SHIPPED
	for arg in OS.get_cmdline_user_args():
		if arg.is_valid_int():
			count = arg.to_int()
		else:
			root = arg if arg.contains("://") else "res://" + arg
	var content := ContentLoader.load_content(root)
	if not content.is_valid():
		print(content.report())
		get_tree().quit(1)
		return
	print("Run-start bench: %s, %d Rooms, %d seeds, Godot %s headless" % [root, content.world_room_count(), count,
			Engine.get_version_info().string])
	var plan_ms: Array[float] = []
	var graph_ms: Array[float] = []
	var total_ms: Array[float] = []
	var attempts: Array[int] = []
	var cells := 0
	var failed := 0
	var worst := ""
	var worst_attempts := 0
	for n in count:
		var world_seed := 1000 + n * 7919
		var started := Time.get_ticks_usec()
		var plan := WorldPlanner.plan(content, world_seed)
		var planned := Time.get_ticks_usec()
		var graph := WorldGraph.build(plan)
		var built := Time.get_ticks_usec()
		if graph == null:
			failed += 1
			print("  seed %d: no World" % world_seed)
			continue
		plan_ms.append((planned - started) / 1000.0)
		graph_ms.append((built - planned) / 1000.0)
		total_ms.append((built - started) / 1000.0)
		cells += graph.cells.size()
		for coord in graph.cells:
			var cell := graph.cells[coord]
			attempts.append(cell.attempts)
			if cell.attempts > worst_attempts:
				worst_attempts = cell.attempts
				worst = "seed %d cell %s (%s, %d Rooms, %d on the route): %d attempts %s" % [world_seed, cell.cell.key,
						cell.cell.biome, cell.rooms.size(), cell.route().size(), cell.attempts, cell.failures]
	if total_ms.is_empty():
		get_tree().quit(1)
		return
	attempts.sort()
	print("  plan        %s" % _stats(plan_ms))
	print("  room graphs %s" % _stats(graph_ms))
	print("  total       %s  (threshold %.0f ms)" % [_stats(total_ms), THRESHOLD_MS])
	print("  %.1f macro cells per World; attempts per cell: median %d, p95 %d, max %d" % [float(cells) / total_ms.size(),
			attempts[attempts.size() / 2], attempts[mini(attempts.size() - 1, int(attempts.size() * 0.95))], attempts[-1]])
	print("  most attempts: %s" % worst)
	var slowest: float = total_ms.max()
	var passed := failed == 0 and slowest <= THRESHOLD_MS
	print("PASS" if passed else "FAIL: %d seeds built nothing, slowest %.1f ms" % [failed, slowest])
	get_tree().quit(0 if passed else 1)


static func _stats(samples: Array[float]) -> String:
	var sorted := samples.duplicate()
	sorted.sort()
	return "median %7.1f ms  p95 %7.1f ms  max %7.1f ms" % [sorted[sorted.size() / 2],
			sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))], sorted[-1]]
