extends Node
## Headless test for Group E sub-area placement + area trails. Pure logic.
##   godot --headless --path game overworld/tests/test_areas.tscn
## Over many seeds asserts: every biome's `required` area types appear ≥1×; instance counts track
## `weight` (glade grove>clearing, deepwood den>thicket); every area-cell centre is reachable by a
## trail flood from spawn; area_at is stable + identical on re-setup; area_at is null off-world.

const GRAPH_PATH := "res://overworld/world_graph.tres"

const SEEDS := 40             # coverage / weight / determinism (cheap)
const REACH_SEEDS := 6        # reachability flood (bounded; is_trail is O(corridors), ~25s/seed)
const FLOOD_BUDGET := 1_200_000


func _ready() -> void:
	var fails: Array[String] = []
	var graph: WorldGraph = load(GRAPH_PATH)
	if graph == null:
		_report(["could not load " + GRAPH_PATH])
		return

	var n_nodes := graph.nodes.size()
	# Aggregate instance counts across seeds: {biome_id: {type_id: count}}.
	var counts: Dictionary = {}

	for s in SEEDS:
		var seed := 7000 + s * 4099
		var macro = MacroMap.new()
		macro.setup(seed, graph)

		for node in n_nodes:
			var biome: Resource = graph.nodes[node].biome
			var instances: Array = macro.area_instances(node)

			# 1. Required coverage: each required type in this biome appears ≥1×.
			var present: Dictionary = {}
			for inst in instances:
				present[inst.type.type_id] = true
				var per: Dictionary = counts.get(biome.id, {})
				per[inst.type.type_id] = per.get(inst.type.type_id, 0) + 1
				counts[biome.id] = per
			for a in biome.area_set:
				if a != null and a.required and not present.has(a.type_id):
					fails.append("seed %d biome '%s': required area '%s' missing" % [seed, biome.id, a.type_id])

		# 4. area_at stable across calls + identical on re-setup.
		var macro2 = MacroMap.new()
		macro2.setup(seed, graph)
		for t in _sample_tiles(macro.biome_center(graph.start_index)):
			var v: Resource = macro.area_at(t)
			if v != macro.area_at(t):
				fails.append("seed %d: area_at not stable at %s" % [seed, t])
			if v != macro2.area_at(t):
				fails.append("seed %d: area_at differs on re-setup at %s" % [seed, t])

		if fails.size() > 20:
			break

	# 2. Weight tracking: higher-weight types get more instances on average.
	var glade: Dictionary = counts.get(&"glade", {})
	var deep: Dictionary = counts.get(&"deepwood", {})
	print("glade totals over %d seeds: grove=%d clearing=%d" % [SEEDS, glade.get(&"grove", 0), glade.get(&"clearing", 0)])
	print("deepwood totals over %d seeds: den=%d thicket=%d" % [SEEDS, deep.get(&"den", 0), deep.get(&"thicket", 0)])
	if glade.get(&"grove", 0) <= glade.get(&"clearing", 0):
		fails.append("weight: glade grove (w2.0) not > clearing (w1.0)")
	if deep.get(&"den", 0) <= deep.get(&"thicket", 0):
		fails.append("weight: deepwood den (w1.5) not > thicket (w1.0)")

	# 3. Reachability: flood is_trail from spawn centre; every area-cell centre must be reached.
	for s in REACH_SEEDS:
		var seed := 313 + s * 9173
		var macro = MacroMap.new()
		macro.setup(seed, graph)
		# Targets = every area-cell centre; flood stops early once all are found (only on success).
		var targets: Dictionary = {}
		for node in n_nodes:
			for inst in macro.area_instances(node):
				targets[inst.center] = node
		var _t0 := Time.get_ticks_msec()
		var visited := _flood(macro, macro.biome_center(graph.start_index), targets)
		print("  reach seed %d: flooded %d tiles in %d ms (targets %d)" % [seed, visited.size(), Time.get_ticks_msec() - _t0, targets.size()])
		if visited.size() >= FLOOD_BUDGET:
			fails.append("seed %d: reach flood hit budget %d — trails may be unbounded" % [seed, visited.size()])
		for c in targets:
			if not visited.has(c):
				fails.append("seed %d: area-cell centre %s (biome %d) not reached by trail flood" % [seed, c, targets[c]])
		if fails.size() > 20:
			break

	# 5. area_at off-world → null.
	var macro3 = MacroMap.new()
	macro3.setup(999, graph)
	var far := Vector2i(200000, 200000)
	if macro3.in_world(far):
		fails.append("test setup: %s unexpectedly in-world" % far)
	elif macro3.area_at(far) != null:
		fails.append("area_at off-world (%s) returned non-null" % far)

	_report(fails)


func _report(fails: Array[String]) -> void:
	print("RESULT: ", "PASS" if fails.is_empty() else "FAIL " + str(fails))
	get_tree().quit(1 if not fails.is_empty() else 0)


# 4-connected flood over is_trail tiles, bounded to in_world and a tile budget. Stops early once
# every tile in `targets` has been visited (a success short-circuit; failure still runs to budget).
func _flood(macro, start: Vector2i, targets: Dictionary) -> Dictionary:
	var visited := {}
	if not macro.is_trail(start):
		return visited
	var stack: Array[Vector2i] = [start]
	visited[start] = true
	var remaining := targets.size()
	if targets.has(start):
		remaining -= 1
	const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not stack.is_empty() and visited.size() < FLOOD_BUDGET and remaining > 0:
		var t: Vector2i = stack.pop_back()
		for d in DIRS:
			var n: Vector2i = t + d
			if not visited.has(n) and macro.in_world(n) and macro.is_trail(n):
				visited[n] = true
				if targets.has(n):
					remaining -= 1
				stack.append(n)
	return visited


# Tiles spanning the spawn biome cell (mix of area-cells) to compare area_at between runs.
func _sample_tiles(center: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [center]
	for dy in range(-600, 601, 120):
		for dx in range(-600, 601, 120):
			out.append(center + Vector2i(dx, dy))
	return out
